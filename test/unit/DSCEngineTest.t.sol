// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() public {
        // Reset any prank state
        vm.stopPrank();

        // Deploy contracts manually to control ownership
        config = new HelperConfig();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();

        // Deploy DecentralizedStableCoin with test contract as owner
        address testOwner = address(this);
        dsc = new DecentralizedStableCoin(testOwner);

        // Deploy DSCEngine
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        dsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // Transfer ownership of DecentralizedStableCoin to DSCEngine
        vm.prank(testOwner);
        dsc.transferOwnership(address(dsce));
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
}