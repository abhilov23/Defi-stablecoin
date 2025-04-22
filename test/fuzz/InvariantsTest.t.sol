//SPDX-License-Identifier: MIT

//Have out invariants

//what are our invariants


//1. The total supply of DSC should be less than the total value collateral
//2. Getter view functions should revert <- evergreen invariants



pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    address deployerAddress;

    function setUp() external {
        // Simulate being the deployer
        deployerAddress = address(this); // This test contract is acting as deployer
        deployer = new DeployDSC();
        
        (dsc, dsce, config) = deployer.run();
        (,,weth, wbtc,) = config.activeNetworkConfig();
        
        targetContract(address(dsce));

        // Transfer ownership from this contract to the DSCEngine
        if (dsc.owner() != address(dsce)) {
            vm.prank(deployerAddress); // `this` contract deployed DSC, so it should be owner
            dsc.transferOwnership(address(dsce));
        }
    }

    function invariant_protocolMustHaveMoreValueThanTotal() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

        console.log("WETH value:", wethValue);
        console.log("WBTC value:", wbtcValue);
        console.log("Total supply:", totalSupply);

        assert(wethValue + wbtcValue > totalSupply);
    }
}
