// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";



/* 
 * @author: Abhilov Gupta
 * 
 * This system is designed to be as minimal as possible, and have the token maintain a 1 token == $1 peg.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 */

contract DSCEngine is ReentrancyGuard {
    //Errors
    error DSCEngine_needMoreThanZero();
    error DSCEngine_tokenAddressAndPriceFeedEngineMustBeSameLength();
    error DSCEngine_TokenNotAllowed();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();



    //State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;


    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;


    DecentralizedStableCoin private immutable i_dsc;
    

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);



    //Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_needMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        //USD price-fees
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_tokenAddressAndPriceFeedEngineMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
    * @param tokenCollateralAddress : the address of the token to deposit as collateral
    * @param amoutCollateral The amount of collateral to deposit
    * @param amountDscToMint the amount of decentralized stablecoin to mint
    * 
    * 
    */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
       depositCollateral(tokenCollateralAddress, amountCollateral);
       mintDsc(amountDscToMint);
    }

    /*
     * @notice follows CEI
     * @param tokenCollateralAddress : the address of token to deposit as collateral
     * @param amountCollateral : the amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
         revert DSCEngine_TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    } 

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral the amount of collateral to redeem 
     * @param amountDscToBurn the amount of DSC to burn
     * This function burns DSC and redeems underlying collateral
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
       burnDsc(amountDscToBurn);
       redeemCollateral(tokenCollateralAddress, amountCollateral);
       //redeemCollateral already checks with Health-factor
    }

    //for redeem collateral:
    // 1. Your health factor will be over one.
    // DRY: Don't repeat yourself

    //CEI: Check, Effects, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant{
      // 100 - 1000 (revert)
        s_collateralDeposited(msg.sender)[tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, amountCollateral, tokenCollateralAddress);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if(!success){
           revert  DSCEngine__TransferFailed();
        }
    }
    
    /**
     * 
     * @param amountDscToMint : the amount of the centralized stable coin to mint
     * @notice : they must have more collateral value that minimum threshold
     */

    //check if the collateral value > DSC amount,checking: price-feeds, value
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much, then revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
        s_DSCMinted[msg.sender] -=amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender); //I do not think this will ever hit...
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    //Private and internal view functions

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
      totalDscMinted = s_DSCMinted[user];
      collateralValueInUsd = getAccountCollateralValue(user);
    }

    //returns how close to liquidation a user is 
    //if a user go below 1, then they can be liquified
    function _healthFactor(address user) private view returns(uint256){
       //we need :  1.  total DSC minted,  2. total collateral VALUE

       (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
       //return (collateralValueInUsd / totalDscMinted); //it will return the collateral value
       uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
       //1000 ETH * 50 = 50,000 / 100 = 500
       return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view{
       //1. check healthfactor
       //2. Revert if they do not have a good health factor
       uint256 userHealthFactor = _healthFactor(user);
       if(userHealthFactor < MIN_HEALTH_FACTOR){
           revert DSCEngine_BreaksHealthFactor(userHealthFactor);
       }
      
    }



    //public & external functions
    function getAccountCollateralValue(address user) public view returns (uint256 tokenCollateralValueInUsd){
      //loop through each collateral token, get the amount they deposited , and map to 
      //the price to get the USD value
      for(uint256 i=0;i< s_collateralTokens.length; i++){
         address token = s_collateralTokens[i];
         uint256 amount = s_collateralDeposited[user][token];
         tokenCollateralValueInUsd += getUsdValue(token, amount);
      }
      return tokenCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        //1 ETH = $1000
        //the return value from CL will be 100 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; //(1000 * 1e8 * (1e10)) * 1000 * 1e18;
    } 
}
