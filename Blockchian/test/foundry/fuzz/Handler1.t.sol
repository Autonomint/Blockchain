// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "../../../lib/forge-std/src/Test.sol";
import {console} from "../../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../../contracts/TestContracts/CopyCDS.sol";
import {Options} from "../../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../../contracts/Core_logic/multiSign.sol";
import {TestUSDaStablecoin} from "../../../contracts/TestContracts/CopyUSDa.sol";
import {TestABONDToken} from "../../../contracts/TestContracts/Copy_Abond_Token.sol";
import {TestUSDT} from "../../../contracts/TestContracts/CopyUsdt.sol";
import {ITreasury} from "../../../contracts/interface/ITreasury.sol";
import {IOptions} from "../../../contracts/interface/IOptions.sol";
import {DeployBorrowing} from "../../../scripts/script/DeployBorrowing.s.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IBorrowing} from "../../../contracts/interface/IBorrowing.sol";
import {CDSInterface} from "../../../contracts/interface/CDSInterface.sol";

contract Handler1 is Test{
    DeployBorrowing.Contracts contractsA;
    DeployBorrowing.Contracts contractsB;
    uint256 MAX_DEPOSIT = type(uint96).max;
    uint public withdrawCalled;

    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public user = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    using OptionsBuilder for bytes;
    bytes options;
    bytes options2;
    MessagingFee borrowFee;
    MessagingFee cdsFee;
    MessagingFee treasuryFee;
    MessagingFee treasuryFee2;
    uint32 eidA = 1;
    uint32 eidB = 2;
    uint32 eidC = 3;

    constructor(
        DeployBorrowing.Contracts memory _contractsA,
        DeployBorrowing.Contracts memory _contractsB)
    {
        contractsA = _contractsA;
        contractsB = _contractsB;
        feeSetup();
    }

    function feeSetup() internal {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        options2 = OptionsBuilder.newOptions().addExecutorLzReceiveOption(600000, 0);

        borrowFee = contractsA.borrow.quote(
            eidB, 
            IBorrowing.OmniChainBorrowingData(5,10,15,20,25,30,35,40), 
            options, 
            false);
        cdsFee =  contractsA.cds.quote(
            eidB, 
            CDSInterface.FunctionToDo(1), 
            123, 123, 123, 
            CDSInterface.LiquidationInfo(0,0,0,0), 0, 
            options, 
            false);
        treasuryFee = contractsA.treasury.quote(
            eidB, 
            ITreasury.FunctionToDo(1), 
            ITreasury.USDaOftTransferData(address(0),0), 
            ITreasury.NativeTokenTransferData(address(0),0), 
            options, 
            false);
        treasuryFee2 = contractsA.treasury.quote(
            eidB, 
            ITreasury.FunctionToDo(2), 
            ITreasury.USDaOftTransferData(address(0),0), 
            ITreasury.NativeTokenTransferData(address(0),0), 
            options2, 
            false);
    }

    // function depositBorrowingA(uint128 amount,uint8 strikePricePercent) public { 
    //     if(contractsA.cds.omniChainCDSTotalCdsDepositedAmount() == 0){
    //         return;
    //     }
    //     vm.deal(user,type(uint128).max);
    //     amount = uint128(bound(amount,0,MAX_DEPOSIT));
    //     uint64 ethPrice = uint64(contractsA.borrow.getUSDValue());
    //     strikePricePercent = uint8(bound(strikePricePercent,0,type(uint8).max));


    //     if(strikePricePercent == 0 || strikePricePercent > 4){
    //         return;
    //     }

    //     if(amount == 0 || amount < 1e13){
    //         return;
    //     }

    //     uint64 ratio = contractsA.borrow.calculateRatio(amount,ethPrice);

    //     if(ratio < 20000){
    //         return;
    //     }
    //     uint64 strikePrice = uint64(ethPrice + (ethPrice * ((strikePricePercent*5) + 5))/100);

    //     // depositCDS(uint128((((amount * ethPrice)/1e12)*25)/100),ethPrice);
    //     vm.startPrank(user);
    //     contractsA.borrow.depositTokens{value: (amount+cdsFee.nativeFee+borrowFee.nativeFee+treasuryFee.nativeFee)}(
    //         ethPrice,
    //         uint64(block.timestamp),
    //         IOptions.StrikePrice(strikePricePercent),
    //         strikePrice,
    //         50622665,
    //         amount);
    //     vm.stopPrank();
    // }

    // function depositBorrowingB(uint128 amount,uint8 strikePricePercent) public { 
    //     if(contractsB.cds.omniChainCDSTotalCdsDepositedAmount() == 0){
    //         return;
    //     }
    //     vm.deal(user,type(uint128).max);
    //     amount = uint128(bound(amount,0,MAX_DEPOSIT));
    //     uint64 ethPrice = uint64(contractsB.borrow.getUSDValue());
    //     strikePricePercent = uint8(bound(strikePricePercent,0,type(uint8).max));


    //     if(strikePricePercent == 0 || strikePricePercent > 4){
    //         return;
    //     }

    //     if(amount == 0 || amount < 1e13){
    //         return;
    //     }

    //     uint64 ratio = contractsB.borrow.calculateRatio(amount,ethPrice);

    //     if(ratio < 20000){
    //         return;
    //     }
    //     uint64 strikePrice = uint64(ethPrice + (ethPrice * ((strikePricePercent*5) + 5))/100);

    //     // depositCDS(uint128((((amount * ethPrice)/1e12)*25)/100),ethPrice);
    //     vm.startPrank(user);
    //     contractsB.borrow.depositTokens{value: (amount+cdsFee.nativeFee+borrowFee.nativeFee+treasuryFee.nativeFee)}(
    //         ethPrice,
    //         uint64(block.timestamp),
    //         IOptions.StrikePrice(strikePricePercent),
    //         strikePrice,
    //         50622665,
    //         amount);
    //     vm.stopPrank();
    // }

    // function withdrawBorrowingA(uint64 index) public{
    //     (,,,,uint64 maxIndex) = contractsA.treasury.borrowing(user);
    //     index = uint64(bound(index,0,maxIndex));
    //     uint64 ethPrice = uint64(contractsA.borrow.getUSDValue());

    //     if(index == 0){
    //         return;
    //     }

    //     Treasury.GetBorrowingResult memory getBorrowingResult = contractsA.treasury.getBorrowing(user,index);
    //     Treasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

    //     if(depositDetail.withdrawed){
    //         return;
    //     }

    //     if(depositDetail.liquidated){
    //         return;
    //     }
    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 216000);

    //     uint256 currentCumulativeRate = contractsA.borrow.calculateCumulativeRate();
    //     uint256 tokenBalance = contractsA.usda.balanceOf(user);

    //     if((currentCumulativeRate*depositDetail.normalizedAmount)/1e27 > tokenBalance){
    //         return;
    //     }

    //     vm.startPrank(user);
    //     contractsA.usda.approve(address(contractsA.borrow),tokenBalance);
    //     vm.deal(user,borrowFee.nativeFee + treasuryFee.nativeFee);
    //     contractsA.borrow.withDraw{value:(borrowFee.nativeFee + treasuryFee.nativeFee)}(user,index,ethPrice,uint64(block.timestamp));
    //     vm.stopPrank();
    // }

    // function withdrawBorrowingB(uint64 index) public{
    //     (,,,,uint64 maxIndex) = contractsB.treasury.borrowing(user);
    //     index = uint64(bound(index,0,maxIndex));
    //     uint64 ethPrice = uint64(contractsB.borrow.getUSDValue());

    //     if(index == 0){
    //         return;
    //     }

    //     Treasury.GetBorrowingResult memory getBorrowingResult = contractsB.treasury.getBorrowing(user,index);
    //     Treasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

    //     if(depositDetail.withdrawed){
    //         return;
    //     }

    //     if(depositDetail.liquidated){
    //         return;
    //     }
    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 216000);

    //     uint256 currentCumulativeRate = contractsB.borrow.calculateCumulativeRate();
    //     uint256 tokenBalance = contractsB.usda.balanceOf(user);

    //     if((currentCumulativeRate*depositDetail.normalizedAmount)/1e27 > tokenBalance){
    //         return;
    //     }

    //     vm.startPrank(user);
    //     contractsB.usda.approve(address(contractsB.borrow),tokenBalance);
    //     vm.deal(user,borrowFee.nativeFee + treasuryFee.nativeFee);
    //     contractsB.borrow.withDraw{value:(borrowFee.nativeFee + treasuryFee.nativeFee)}(user,index,ethPrice,uint64(block.timestamp));
    //     vm.stopPrank();
    // }

    // function depositCDSA(uint128 usdtToDeposit,uint128 usdaToDeposit,uint64 ethPrice) public {

    //     usdtToDeposit = uint128(bound(usdtToDeposit,0,type(uint64).max));
    //     usdaToDeposit = uint128(bound(usdaToDeposit,0,type(uint64).max));

    //     ethPrice = uint64(bound(ethPrice,0,type(uint24).max));
    //     if(ethPrice <= 3500){
    //         return;
    //     }

    //     if(usdaToDeposit == 0){
    //         return;
    //     }

    //     if(usdtToDeposit == 0 || usdtToDeposit > 20000000000){
    //         return;
    //     }

    //     if((contractsA.cds.usdtAmountDepositedTillNow() + usdtToDeposit) > contractsA.cds.usdtLimit()){
    //         return;
    //     }    

    //     if((contractsA.cds.usdtAmountDepositedTillNow() + usdtToDeposit) <= contractsA.cds.usdtLimit()){
    //         usdaToDeposit = 0;
    //     }    

    //     if((contractsA.cds.usdtAmountDepositedTillNow()) == contractsA.cds.usdtLimit()){
    //         usdaToDeposit = (usdaToDeposit * 80)/100;
    //         usdtToDeposit = (usdaToDeposit * 20)/100;
    //     }

    //     if((usdaToDeposit + usdtToDeposit) < 100000000){
    //         return;
    //     }

    //     uint256 liquidationAmount = ((usdaToDeposit + usdtToDeposit) * 50)/100;

    //     if(contractsA.usda.balanceOf(user) < usdaToDeposit){
    //         return;
    //     }
    //     vm.startPrank(user);

    //     contractsA.usdt.mint(user,usdtToDeposit);
    //     contractsA.usdt.approve(address(contractsA.cds),usdtToDeposit);
    //     contractsA.usda.approve(address(contractsA.cds),usdaToDeposit);
    //     vm.deal(user,cdsFee.nativeFee);
    //     contractsA.cds.deposit{value:cdsFee.nativeFee}(usdtToDeposit,usdaToDeposit,true,uint128(liquidationAmount),ethPrice);

    //     vm.stopPrank();
    // }

    // function depositCDSB(uint128 usdtToDeposit,uint128 usdaToDeposit,uint64 ethPrice) public {

    //     usdtToDeposit = uint128(bound(usdtToDeposit,0,type(uint64).max));
    //     usdaToDeposit = uint128(bound(usdaToDeposit,0,type(uint64).max));

    //     ethPrice = uint64(bound(ethPrice,0,type(uint24).max));
    //     if(ethPrice <= 3500){
    //         return;
    //     }

    //     if(usdaToDeposit == 0){
    //         return;
    //     }

    //     if(usdtToDeposit == 0 || usdtToDeposit > 20000000000){
    //         return;
    //     }

    //     if((contractsB.cds.usdtAmountDepositedTillNow() + usdtToDeposit) > contractsB.cds.usdtLimit()){
    //         return;
    //     }    

    //     if((contractsB.cds.usdtAmountDepositedTillNow() + usdtToDeposit) <= contractsB.cds.usdtLimit()){
    //         usdaToDeposit = 0;
    //     }    

    //     if((contractsB.cds.usdtAmountDepositedTillNow()) == contractsB.cds.usdtLimit()){
    //         usdaToDeposit = (usdaToDeposit * 80)/100;
    //         usdtToDeposit = (usdaToDeposit * 20)/100;
    //     }

    //     if((usdaToDeposit + usdtToDeposit) < 100000000){
    //         return;
    //     }

    //     uint256 liquidationAmount = ((usdaToDeposit + usdtToDeposit) * 50)/100;

    //     if(contractsB.usda.balanceOf(user) < usdaToDeposit){
    //         return;
    //     }
    //     vm.startPrank(user);

    //     contractsB.usdt.mint(user,usdtToDeposit);
    //     contractsB.usdt.approve(address(contractsB.cds),usdtToDeposit);
    //     contractsB.usda.approve(address(contractsB.cds),usdaToDeposit);
    //     vm.deal(user,cdsFee.nativeFee);
    //     contractsB.cds.deposit{value:cdsFee.nativeFee}(usdtToDeposit,usdaToDeposit,true,uint128(liquidationAmount),ethPrice);

    //     vm.stopPrank();
    // }

    // function withdrawCDSA(uint64 index,uint64 ethPrice) public{
    //     (uint64 maxIndex,) = contractsA.cds.cdsDetails(user);
    //     index = uint64(bound(index,0,maxIndex));
    //     ethPrice = uint64(bound(ethPrice,0,type(uint24).max));

    //     if(ethPrice <= 3500 || ethPrice > (contractsA.cds.lastEthPrice() * 5)/100){
    //         return;
    //     }
    //     if(index == 0){
    //         return;
    //     }

    //     (CDSInterface.CdsAccountDetails memory accDetails,) = contractsA.cds.getCDSDepositDetails(user,index);

    //     if(accDetails.withdrawed){
    //         return;
    //     }
    //     if(contractsA.cds.omniChainCDSTotalCdsDepositedAmount() >= accDetails.depositedAmount){
    //         if((contractsA.cds.omniChainCDSTotalCdsDepositedAmount() - accDetails.depositedAmount) == 0){
    //             return;
    //         }
    //     }

    //     vm.startPrank(user);
    //     vm.deal(user,cdsFee.nativeFee + treasuryFee2.nativeFee);
    //     contractsA.cds.withdraw{value: cdsFee.nativeFee + treasuryFee2.nativeFee}(index,ethPrice);

    //     vm.stopPrank();
    // }

    // function withdrawCDSB(uint64 index,uint64 ethPrice) public{
    //     (uint64 maxIndex,) = contractsB.cds.cdsDetails(user);
    //     index = uint64(bound(index,0,maxIndex));
    //     ethPrice = uint64(bound(ethPrice,0,type(uint24).max));

    //     if(ethPrice <= 3500 || ethPrice > (contractsB.cds.lastEthPrice() * 5)/100){
    //         return;
    //     }
    //     if(index == 0){
    //         return;
    //     }

    //     (CDSInterface.CdsAccountDetails memory accDetails,) = contractsB.cds.getCDSDepositDetails(user,index);

    //     if(accDetails.withdrawed){
    //         return;
    //     }
    //     if(contractsB.cds.omniChainCDSTotalCdsDepositedAmount() >= accDetails.depositedAmount){
    //         if((contractsB.cds.omniChainCDSTotalCdsDepositedAmount() - accDetails.depositedAmount) == 0){
    //             return;
    //         }
    //     }
    //     vm.startPrank(user);
    //     vm.deal(user,cdsFee.nativeFee + treasuryFee2.nativeFee);
    //     contractsB.cds.withdraw{value: cdsFee.nativeFee + treasuryFee2.nativeFee}(index,ethPrice);

    //     vm.stopPrank();
    // }

    // function liquidationA(uint64 index,uint64 ethPrice) public{
    //     (,,,,uint64 maxIndex) = contractsA.treasury.borrowing(user);
    //     index = uint64(bound(index,0,maxIndex));
    //     ethPrice = uint64(bound(ethPrice,0,type(uint24).max));

    //     if(ethPrice == 0){
    //         return;
    //     }
    //     if(index == 0){
    //         return;
    //     }

    //     ITreasury.GetBorrowingResult memory getBorrowingResult = contractsA.treasury.getBorrowing(user,index);
    //     ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

    //     if(depositDetail.liquidated){
    //         return;
    //     }

    //     if(ethPrice > ((depositDetail.ethPriceAtDeposit * 80)/100)){
    //         return;
    //     }
    //     if((ethPrice * depositDetail.depositedAmount) > contractsA.cds.omniChainCDSTotalAvailableLiquidationAmount()){
    //         return;
    //     }
    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 216000);

    //     vm.startPrank(owner);
    //     vm.deal(owner,cdsFee.nativeFee + borrowFee.nativeFee + treasuryFee2.nativeFee);
    //     contractsA.borrow.liquidate{value: cdsFee.nativeFee + borrowFee.nativeFee + treasuryFee2.nativeFee}(user,index,ethPrice);
    //     vm.stopPrank();
    // }

    // function liquidationB(uint64 index,uint64 ethPrice) public{
    //     (,,,,uint64 maxIndex) = contractsB.treasury.borrowing(user);
    //     index = uint64(bound(index,0,maxIndex));
    //     ethPrice = uint64(bound(ethPrice,0,type(uint24).max));

    //     if(ethPrice == 0){
    //         return;
    //     }
    //     if(index == 0){
    //         return;
    //     }

    //     ITreasury.GetBorrowingResult memory getBorrowingResult = contractsB.treasury.getBorrowing(user,index);
    //     ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

    //     if(depositDetail.liquidated){
    //         return;
    //     }

    //     if(ethPrice > ((depositDetail.ethPriceAtDeposit * 80)/100)){
    //         return;
    //     }
    //     if((ethPrice * depositDetail.depositedAmount) > contractsA.cds.omniChainCDSTotalAvailableLiquidationAmount()){
    //         return;
    //     }
    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 216000);

    //     vm.startPrank(owner);
    //     vm.deal(owner,cdsFee.nativeFee + borrowFee.nativeFee + treasuryFee2.nativeFee);
    //     contractsB.borrow.liquidate{value: cdsFee.nativeFee + borrowFee.nativeFee + treasuryFee2.nativeFee}(user,index,ethPrice);
    //     vm.stopPrank();
    // }
}