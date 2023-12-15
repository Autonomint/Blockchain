// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TrinityStablecoin} from "../../contracts/Token/Trinity_ERC20.sol";
import {ProtocolToken} from "../../contracts/Token/Protocol_Token.sol";
import {HelperConfig} from "../../scripts/script/HelperConfig.s.sol";
import {DeployBorrowing} from "../../scripts/script/DeployBorrowing.s.sol";

import {IWrappedTokenGatewayV3} from "../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
import {ICEther} from "../../contracts/interface/ICEther.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract BorrowTest is Test {
    DeployBorrowing deployer;
    TrinityStablecoin tsc;
    ProtocolToken pToken;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    HelperConfig config;

    address ethUsdPriceFeed;
    address wethAddress = 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
    address cEthAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    IWrappedTokenGatewayV3 wethGateway;
    ICEther cEther;
    // IPoolAddressesProvider public aaveProvider;
    // IPool public aave;
    address public USER = makeAddr("user");
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public ETH_AMOUNT = 1 ether;
    uint256 public STARTING_ETH_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployBorrowing();
        (tsc,pToken,borrow,treasury,cds,config) = deployer.run();
        (ethUsdPriceFeed,) = config.activeNetworkConfig();

        wethGateway = IWrappedTokenGatewayV3(wethAddress);
        cEther = ICEther(cEthAddress);
        vm.startPrank(owner);
        borrow.initializeTreasury(address(treasury));
        borrow.setLTV(80);
        vm.stopPrank();

        vm.deal(USER,STARTING_ETH_BALANCE);
    }

    function testGetUsdValue() public {
        uint256 expectedUsd = 1000e2;
        uint256 actualUsd = borrow.getUSDValue();
        assertEq(expectedUsd, actualUsd);
    }

    function testCanDepositETH(uint128 data) public{
        
        vm.startPrank(USER);
        borrow.depositTokens{value: ETH_AMOUNT}(data,uint64(block.timestamp));
        uint256 expectedAmount = 800 ether;
        uint256 actualAmount = tsc.balanceOf(USER); 
        assertEq(expectedAmount,actualAmount);
        vm.stopPrank();
    }
}
