// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "../../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../../lib/forge-std/src/StdInvariant.sol";
import {console} from "../../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../../contracts/TestContracts/CopyCDS.sol";
import {Options} from "../../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../../contracts/Core_logic/multiSign.sol";
import {TestUSDaStablecoin} from "../../../contracts/TestContracts/CopyUSDa.sol";
import {TestABONDToken} from "../../../contracts/TestContracts/Copy_Abond_Token.sol";
import {TestUSDT} from "../../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "../../../scripts/script/HelperConfig.s.sol";
import {DeployBorrowing} from "../../../scripts/script/DeployBorrowing.s.sol";
import {Handler} from "./Handler.t.sol";
import {Handler1} from "./Handler1.t.sol";
import {IBorrowing} from "../../../contracts/interface/IBorrowing.sol";
import {CDSInterface} from "../../../contracts/interface/CDSInterface.sol";
import {ITreasury} from "../../../contracts/interface/ITreasury.sol";

import {IWrappedTokenGatewayV3} from "../../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
import {CometMainInterface} from "../../../contracts/interface/CometMainInterface.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract InvariantTest is StdInvariant,Test {
    DeployBorrowing deployer;
    DeployBorrowing.Contracts contractsA;
    DeployBorrowing.Contracts contractsB;
    Handler handler;
    Handler1 handler1;
    address ethUsdPriceFeed;

    address public USER = makeAddr("user");
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public owner1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address public cometAddress = 0xA17581A9E3356d9A858b789D68B4d866e593aE94; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    uint8[] functions = [0,1,2,3,4,5,6,7,8,9];
    uint32 eidA = 1;
    uint32 eidB = 2;
    uint32 eidC = 3;

    uint256 public ETH_AMOUNT = 1 ether;
    uint256 public STARTING_ETH_BALANCE = 100 ether;
    using OptionsBuilder for bytes;
    bytes options;
    MessagingFee borrowFee;
    MessagingFee cdsFee;
    MessagingFee treasuryFee;

    function setUp() public {
        deployer = new DeployBorrowing();
        (contractsA,contractsB) = deployer.run();
        (ethUsdPriceFeed,) = contractsA.config.activeNetworkConfig();
        handler = new Handler(contractsA,contractsB);
        handler1 = new Handler1(contractsA,contractsB);

        vm.startPrank(owner1);
        contractsA.multiSign.approveSetterFunction(functions);
        contractsB.multiSign.approveSetterFunction(functions);
        vm.stopPrank();

        vm.startPrank(owner);
        contractsA.borrow.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        contractsA.borrow.setTreasury(address(contractsA.treasury));
        contractsA.borrow.setOptions(address(contractsA.option));
        contractsA.borrow.setBorrowLiquidation(address(contractsA.borrowLiquidation));
        contractsA.borrow.setLTV(80);
        contractsA.borrow.setBondRatio(4);
        contractsA.borrow.setAPR(1000000001547125957863212449);
        contractsA.borrow.setDstEid(2);

        contractsA.cds.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        contractsA.cds.setTreasury(address(contractsA.treasury));
        contractsA.cds.setBorrowingContract(address(contractsA.borrow));
        contractsA.cds.setBorrowLiquidation(address(contractsA.borrowLiquidation));
        contractsA.cds.setUSDaLimit(80);
        contractsA.cds.setUsdtLimit(20000000000);
        contractsA.cds.setDstEid(2);
        contractsA.borrow.calculateCumulativeRate();

        contractsB.borrow.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        contractsB.borrow.setTreasury(address(contractsB.treasury));
        contractsB.borrow.setOptions(address(contractsB.option));
        contractsB.borrow.setBorrowLiquidation(address(contractsB.borrowLiquidation));
        contractsB.borrow.setLTV(80);
        contractsB.borrow.setBondRatio(4);
        contractsB.borrow.setAPR(1000000001547125957863212449);
        contractsB.borrow.setDstEid(1);

        contractsB.cds.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        contractsB.cds.setTreasury(address(contractsB.treasury));
        contractsB.cds.setBorrowingContract(address(contractsB.borrow));
        contractsB.cds.setBorrowLiquidation(address(contractsB.borrowLiquidation));
        contractsB.cds.setUSDaLimit(80);
        contractsB.cds.setUsdtLimit(20000000000);
        contractsB.cds.setDstEid(1);
        contractsB.borrow.calculateCumulativeRate();
        
        vm.stopPrank();

        vm.deal(USER,STARTING_ETH_BALANCE);
        vm.deal(owner,STARTING_ETH_BALANCE);
        targetContract(address(handler1));
    }

    function invariant_ProtocolMustHaveMoreValueThanSupply() public view{
        uint256 totalSupply = contractsA.usda.totalSupply() + contractsB.usda.totalSupply();
        uint256 totalDepositedEth = (address(contractsA.treasury)).balance + (address(contractsB.treasury)).balance;
        uint256 totalEthValue = totalDepositedEth * contractsA.borrow.getUSDValue();
        uint256 usdtInCds = contractsA.usdt.balanceOf(address(contractsA.treasury)) + contractsB.usdt.balanceOf(address(contractsB.treasury));
        uint256 totalBacked = (totalEthValue / 1e2) + (usdtInCds * 1e12);
        console.log("ETH VALUE",totalBacked);
        console.log("TOTAL SUPPLY",(totalSupply * 1e12));
        assert(totalBacked >= (totalSupply * 1e12));
    }
}