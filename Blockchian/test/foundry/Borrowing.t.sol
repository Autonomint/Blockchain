// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../contracts/Core_logic/multiSign.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TestUSDaStablecoin} from "../../contracts/TestContracts/CopyUSDa.sol";
import {TestABONDToken} from "../../contracts/TestContracts/Copy_Abond_Token.sol";
import {TestUSDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "../../scripts/script/HelperConfig.s.sol";
import {DeployBorrowing} from "../../scripts/script/DeployBorrowing.s.sol";

import {IWrappedTokenGatewayV3} from "../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
import {IPoolAddressesProvider} from "../../contracts/interface/AaveInterfaces/IPoolAddressesProvider.sol";
import {ILendingPoolAddressesProvider} from "../../contracts/interface/AaveInterfaces/ILendingPoolAddressesProvider.sol";
import {IPool} from "../../contracts/interface/AaveInterfaces/IPool.sol";
import {State} from "../../contracts/interface/IAbond.sol";

import {CometMainInterface} from "../../contracts/interface/CometMainInterface.sol";
import {IOptions} from "../../contracts/interface/IOptions.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract BorrowTest is Test {
    DeployBorrowing deployer;
    DeployBorrowing.Contracts contractsA;
    DeployBorrowing.Contracts contractsB;

    address ethUsdPriceFeed;

    address public USER = makeAddr("user");
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public owner1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address public cometAddress = 0xA17581A9E3356d9A858b789D68B4d866e593aE94; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    uint8[] functions = [0,1,2,3,4,5,6,7,8,9];

    uint256 public ETH_AMOUNT = 1 ether;
    uint256 public STARTING_ETH_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployBorrowing();
        (contractsA,contractsB) = deployer.run();
        (ethUsdPriceFeed,) = contractsA.config.activeNetworkConfig();

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

        contractsB.cds.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        contractsB.cds.setTreasury(address(contractsB.treasury));
        contractsB.cds.setBorrowingContract(address(contractsB.borrow));
        contractsB.cds.setBorrowLiquidation(address(contractsB.borrowLiquidation));
        contractsB.cds.setUSDaLimit(80);
        contractsB.cds.setUsdtLimit(20000000000);
        contractsB.cds.setDstEid(1);
        contractsB.borrow.calculateCumulativeRate();

        contractsB.borrow.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        contractsB.borrow.setTreasury(address(contractsB.treasury));
        contractsB.borrow.setOptions(address(contractsB.option));
        contractsB.borrow.setBorrowLiquidation(address(contractsB.borrowLiquidation));
        contractsB.borrow.setLTV(80);
        contractsB.borrow.setBondRatio(4);
        contractsB.borrow.setAPR(1000000001547125957863212449);
        contractsB.borrow.setDstEid(2);

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
    }

    // modifier depositInCds {
    //     vm.startPrank(USER);
    //     contractsA.usdt.mint(address(USER),30000000000);
    //     uint256 usdtBalance = contractsA.usdt.balanceOf(address(USER));
    //     contractsA.usdt.approve(address(contractsA.cds),usdtBalance);
    //     contractsA.cds.deposit(uint128(usdtBalance),0,true,uint128(usdtBalance/2));
    //     vm.stopPrank();
    //     _;
    // }

    // modifier depositETH {
    //     vm.startPrank(USER);
    //     contractsA.usdt.mint(address(USER),20000000000);
    //     uint256 usdtBalance = contractsA.usdt.balanceOf(address(USER));
    //     contractsA.usdt.approve(address(contractsA.cds),usdtBalance);
    //     contractsA.cds.deposit(uint128(usdtBalance),0,true,uint128(usdtBalance/2));
    //     contractsA.borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     vm.stopPrank();
    //     _;
    // }

    function testGetUsdValue() public {
        uint256 expectedUsd = 1000e2;
        uint256 actualUsd = contractsA.borrow.getUSDValue();
        assertEq(expectedUsd, actualUsd);
    }

    // function testCanDepositEth() public depositInCds{
    //     vm.startPrank(USER);
    //     contractsA.borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     uint256 expectedAmount = ((800*1e6) - contractsA.option.calculateOptionPrice(100000,50622665,ETH_AMOUNT,Options.StrikePrice.TEN));
    //     uint256 actualAmount = contractsA.usda.balanceOf(USER); 
    //     assertEq(expectedAmount,actualAmount);
    //     vm.stopPrank();
    // }

    // function testUserCantWithdrawDirectlyFromAave() public depositETH{
    //     vm.startPrank(USER);
    //     console.log("USER BALANCE AFTER DEPOSIT",USER.balance);
    //     vm.warp(block.timestamp + 360000000);

    //     uint256 balance = IERC20(aTokenAddress).balanceOf(address(USER));
    //     address poolAddress = ILendingPoolAddressesProvider(0x5E52dEc931FFb32f609681B8438A51c675cc232d/*0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e*/).getLendingPool();

    //     IERC20(aTokenAddress).approve(address(wethGateway),balance);
    //     wethGateway.withdrawETH(poolAddress,balance,address(USER));

    //     console.log("USER BALANCE AFTER AAVE WITHDRAW",USER.balance);
    //     vm.stopPrank();
    // }

    // function testUserCantWithdrawDirectlyFromCompound() public depositETH{
    //     vm.startPrank(USER);
    //     vm.roll(block.number + 100);
    //     console.log("USER BALANCE AFTER DEPOSIT",USER.balance);
    //     console.log("TREASURY BALANCE AFTER DEPOSIT",contractsA.treasury.getBalanceInTreasury());

    //     uint256 balance = cEther.balanceOf(address(contractsA.treasury));
    //     console.log(balance);
    //     contractsA.treasury.compoundWithdraw(balance);

    //     cEther.redeem(balance);
    //     console.log("USER BALANCE AFTER COMPOUND WITHDRAW",USER.balance);
    //     console.log("TREASURY BALANCE AFTER COMPOUND WITHDRAW",contractsA.treasury.getBalanceInTreasury());
    //     console.log(cEther.balanceOfUnderlying(address(USER)));
    //     vm.stopPrank();
    // }

    // function testUserCanDepositAndWithdraw() public depositETH{
    //     vm.startPrank(USER);
    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 216000);

    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.mint(address(USER),10000000);
    //     uint256 usdaBalance = contractsA.usda.balanceOf(address(USER));

    //     contractsA.usda.approve(address(contractsA.borrow),usdaBalance);
    //     contractsA.borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));

    //     assertEq(address(USER).balance, STARTING_ETH_BALANCE - 5e17);

    //     vm.stopPrank();
    // }

    // function testUserCanRedeemAbond() public depositETH{
    //     vm.startPrank(USER);

    //     vm.warp(block.timestamp + 2592000);

    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.mint(address(USER),10000000);
    //     uint256 usdaBalance = contractsA.usda.balanceOf(address(USER));

    //     contractsA.usda.approve(address(contractsA.borrow),usdaBalance);
    //     contractsA.borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));

    //     contractsA.borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

    //     vm.warp(block.timestamp + 2592000);

    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.mint(address(USER),10000000);

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),2,99900,uint64(block.timestamp));

    //     uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(address(contractsA.treasury));
    //     uint256 cETHbalance = CometMainInterface(cometAddress).balanceOf(address(contractsA.treasury));

    //     uint256 abondBalance = contractsA.abond.balanceOf(address(USER));
    //     contractsA.abond.approve(address(contractsA.borrow), abondBalance);
    //     uint256 withdrawAmount = contractsA.borrow.redeemYields(address(USER),uint128(abondBalance));

    //     assert((aTokenBalance + cETHbalance - withdrawAmount) <= 1e14);

    //     vm.stopPrank();
    // }

    // function testAbondDataAreStoringCorrectlyForMultipleIndex() public depositETH{
    //     vm.startPrank(USER);

    //     vm.warp(block.timestamp + 2592000);
    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.mint(address(USER),10000000000);

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));

    //     (uint256 cR1,uint128 ethBacked1,uint128 aBondAmount1) = contractsA.abond.userStates(address(USER));

    //     contractsA.borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

    //     (uint256 cR2,uint128 ethBacked2,) = contractsA.abond.userStatesAtDeposits(address(USER),2);

    //     vm.warp(block.timestamp + 2592000);
    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),2,99000,uint64(block.timestamp));

    //     (uint256 cR3,uint128 ethBacked3,uint128 aBondAmount3) = contractsA.abond.userStates(address(USER));

    //     assertEq(((aBondAmount1 * cR1) + ((aBondAmount3 - aBondAmount1) * cR2))/aBondAmount3,cR3);
    //     assertEq(((aBondAmount1 * ethBacked1) + ((aBondAmount3 - aBondAmount1) * ((ethBacked2 * 1e18)/(aBondAmount3 - aBondAmount1))))/aBondAmount3,ethBacked3);

    //     vm.stopPrank();
    // }

    // function testAbondDataAreStoringCorrectlyForOneTransfer() public depositETH{
    //     vm.startPrank(USER);
    //     (uint256 cR1d,uint128 ethBacked1d,uint128 abondBalance1d) = contractsA.abond.userStatesAtDeposits(address(USER),1);

    //     vm.warp(block.timestamp + 2592000);
    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.mint(address(USER),10000000);

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));
    //     (uint256 cR1w,uint128 ethBacked1w,uint128 abondBalance1w) = contractsA.abond.userStates(address(USER));

    //     contractsA.borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     (uint256 cR2d,uint128 ethBacked2d,uint128 abondBalance2d) = contractsA.abond.userStatesAtDeposits(address(USER),2);

    //     vm.warp(block.timestamp + 2592000);
    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),2,99000,uint64(block.timestamp));
    //     (uint256 cR2w,uint128 ethBacked2w,uint128 abondBalance2w) = contractsA.abond.userStates(address(USER));

    //     contractsA.abond.transfer(owner,(contractsA.abond.balanceOf(address(USER)) * 50)/100);

    //     (uint256 cR1,uint128 ethBacked1,uint128 aBondAmount1) = contractsA.abond.userStates(address(USER));
    //     (uint256 cR2,uint128 ethBacked2,uint128 aBondAmount2) = contractsA.abond.userStates(owner);

    //     assertEq(cR2,cR1);
    //     assertEq(aBondAmount1,aBondAmount2);
    //     assertEq(ethBacked1,ethBacked2);

    //     vm.stopPrank();
    // }

    // function testAbondDataAreStoringCorrectlyForMultipleTransfers() public depositETH{
    //     vm.startPrank(USER);
    //     (uint256 cR1d,uint128 ethBacked1d,uint128 abondBalance1d) = contractsA.abond.userStatesAtDeposits(address(USER),1);

    //     vm.warp(block.timestamp + 2592000);
    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.mint(address(USER),10000000);

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));
    //     (uint256 cR1w,uint128 ethBacked1w,uint128 abondBalance1w) = contractsA.abond.userStates(address(USER));

    //     contractsA.borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     (uint256 cR2d,uint128 ethBacked2d,uint128 abondBalance2d) = contractsA.abond.userStatesAtDeposits(address(USER),2);

    //     vm.warp(block.timestamp + 2592000);
    //     contractsA.borrow.calculateCumulativeRate();

    //     contractsA.usda.approve(address(contractsA.borrow),contractsA.usda.balanceOf(address(USER)));
    //     contractsA.borrow.withDraw(address(USER),2,100000,uint64(block.timestamp));
    //     (uint256 cR2w,uint128 ethBacked2w,uint128 abondBalance2w) = contractsA.abond.userStates(address(USER));

    //     // console.log("CR 1D",cR1d);
    //     // console.log("EB 1D",ethBacked1d);
    //     // console.log("AB 1D",abondBalance1d);

    //     // console.log("CR 1W",cR1w);
    //     // console.log("EB 1W",ethBacked1w);
    //     // console.log("AB 1W",abondBalance1w);

    //     // console.log("CR 2D",cR2d);
    //     // console.log("EB 2D",ethBacked2d);
    //     // console.log("AB 2D",abondBalance2d);

    //     // console.log("CR 2W",cR2w);
    //     // console.log("EB 2W",ethBacked2w);
    //     // console.log("AB 2W",abondBalance2w);

    //     contractsA.abond.transfer(owner,(contractsA.abond.balanceOf(address(USER)) * 50)/100);
    //     vm.warp(block.timestamp + 2592000);

    //     (uint256 cR1,uint128 ethBacked1,uint128 aBondAmount1) = contractsA.abond.userStates(address(USER));
    //     (uint256 cR2,uint128 ethBacked2,uint128 aBondAmount2) = contractsA.abond.userStates(owner);

    //     // console.log("CR o",cR2);
    //     // console.log("EB o",ethBacked2);
    //     // console.log("AB o",aBondAmount2);

    //     uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(address(contractsA.treasury));
    //     uint256 cETHbalance = CometMainInterface(cometAddress).balanceOf(address(contractsA.treasury));

    //     contractsA.abond.approve(address(contractsA.borrow), aBondAmount1);
    //     uint256 withdrawAmount1 = contractsA.borrow.redeemYields(address(USER),uint128(aBondAmount1));
    //     vm.stopPrank();

    //     vm.startPrank(owner);
    //     contractsA.abond.approve(address(contractsA.borrow), aBondAmount2);
    //     uint256 withdrawAmount2 = contractsA.borrow.redeemYields(owner,uint128(aBondAmount2));

    //     assertEq(cR1,cR2);
    //     assertEq(aBondAmount1,aBondAmount2);
    //     assertEq(ethBacked1,ethBacked2);

    //     vm.stopPrank();
    // }
}
