// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        // Reset any prank state
        vm.stopPrank();

        config = new HelperConfig();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        address testOwner = address(this);
        dsc = new DecentralizedStableCoin(testOwner);

        // Deploy DSCEngine
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        dsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.prank(testOwner);
        dsc.transferOwnership(address(dsce));
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //constructor test
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;


    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine_tokenAddressAndPriceFeedEngineMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }


    function testgetTokenAmountFromUsd() public{
        uint256 usdAmount = 100 ether;
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(amountWeth, expectedWeth);
    }




    // Price tests
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_needMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_TokenNotAllowed.selector);
        dsce.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL ,expectedDepositAmount);
    }
    

    //checking the DSC address
    function testRevertsIfDscAddressIsZero() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
    
        vm.expectRevert(DSCEngine.DSCEngine_InvalidDscAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(0));
    }


    function testConstructorSetsTokenAndPriceFeedCorrectlyIndirect() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
    
        DSCEngine newDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; // 15 ETH * $2000
        uint256 actualUsd = newDsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(newDsce), AMOUNT_COLLATERAL);
        newDsce.depositCollateral(weth, AMOUNT_COLLATERAL); // Should succeed if weth is allowed
        vm.stopPrank();
    
        (, uint256 collateralValueInUsd) = newDsce.getAccountInformation(USER);
        uint256 expectedDepositAmount = newDsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function testRevertsIfTransferFromFails() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        vm.mockCall(
            weth,
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(dsce), AMOUNT_COLLATERAL),
            abi.encode(false)
        );
        
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }


    //Verifies that depositing WETH twice correctly accumulates in s_collateralDeposited (e.g., total WETH deposited is AMOUNT_COLLATERAL * 2).
    function testMintDscWithSufficientCollateral() public depositedCollateral {
        uint256 amountDscToMint = 1000e18;
        vm.startPrank(USER);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();
    
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountDscToMint);
    }


}