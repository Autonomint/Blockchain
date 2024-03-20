// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "../../../lib/forge-std/src/Test.sol";
import {console} from "../../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../../contracts/TestContracts/CopyCDS.sol";
import {Options} from "../../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../../contracts/Core_logic/multiSign.sol";
import {TestAMINTStablecoin} from "../../../contracts/TestContracts/CopyAmint.sol";
import {TestABONDToken} from "../../../contracts/TestContracts/Copy_Abond_Token.sol";
import {TestUSDT} from "../../../contracts/TestContracts/CopyUsdt.sol";
import {ITreasury} from "../../../contracts/interface/ITreasury.sol";
import {IOptions} from "../../../contracts/interface/IOptions.sol";

contract Handler1 is Test{
    BorrowingTest borrow;
    CDSTest cds;
    TestAMINTStablecoin amint;
    Treasury treasury;
    TestABONDToken abond;
    TestUSDT usdt;
    uint256 MAX_DEPOSIT = type(uint96).max;
    uint public withdrawCalled;

    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public user = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    constructor(
        BorrowingTest _borrow,
        CDSTest _cds,
        Treasury _treasury,
        TestAMINTStablecoin _amint,
        TestABONDToken _abond,
        TestUSDT _usdt
    )
    {
        borrow = _borrow;
        cds = _cds;
        amint = _amint;
        treasury = _treasury;
        abond = _abond;
        usdt = _usdt;
    }

    function depositBorrowing(uint128 amount,uint8 strikePricePercent) public { 
        if(cds.totalCdsDepositedAmount() == 0){
            return;
        }
        vm.deal(user,type(uint128).max);
        amount = uint128(bound(amount,0,MAX_DEPOSIT));
        uint64 ethPrice = uint64(borrow.getUSDValue());
        strikePricePercent = uint8(bound(strikePricePercent,0,type(uint8).max));


        if(strikePricePercent == 0 || strikePricePercent > 4){
            return;
        }

        if(amount == 0 || amount < 1e13){
            return;
        }

        uint64 ratio = borrow.calculateRatio(amount,ethPrice);

        if(ratio < 20000){
            return;
        }
        uint64 strikePrice = uint64(ethPrice + (ethPrice * ((strikePricePercent*5) + 5))/100);

        // depositCDS(uint128((((amount * ethPrice)/1e12)*25)/100),ethPrice);
        vm.startPrank(user);
        borrow.depositTokens{value: amount}(
            ethPrice,
            uint64(block.timestamp),
            IOptions.StrikePrice(strikePricePercent),
            strikePrice,
            50622665);
        vm.stopPrank();
    }

    function withdrawBorrowing(uint64 index) public{
        (,,,,uint64 maxIndex) = treasury.borrowing(user);
        index = uint64(bound(index,0,maxIndex));
        uint64 ethPrice = uint64(borrow.getUSDValue());

        if(index == 0){
            return;
        }

        Treasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(user,index);
        Treasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

        if(depositDetail.withdrawed){
            return;
        }

        if(depositDetail.liquidated){
            return;
        }

        uint256 currentCumulativeRate = borrow.calculateCumulativeRate();
        uint256 tokenBalance = amint.balanceOf(user);

        if((currentCumulativeRate*depositDetail.normalizedAmount)/1e27 > tokenBalance){
            return;
        }

        vm.startPrank(user);
        amint.approve(address(borrow),tokenBalance);

        borrow.withDraw(user,index,ethPrice,uint64(block.timestamp));
        vm.stopPrank();
    }

    function depositCDS(uint128 usdtToDeposit,uint128 amintToDeposit,uint64 ethPrice) public {

        usdtToDeposit = uint128(bound(usdtToDeposit,0,type(uint64).max));
        amintToDeposit = uint128(bound(amintToDeposit,0,type(uint64).max));

        ethPrice = uint64(bound(ethPrice,0,type(uint24).max));
        if(ethPrice <= 3500){
            return;
        }

        if(amintToDeposit == 0){
            return;
        }

        if(usdtToDeposit == 0 || usdtToDeposit > 20000000000){
            return;
        }

        if((cds.usdtAmountDepositedTillNow() + usdtToDeposit) > cds.usdtLimit()){
            return;
        }    

        if((cds.usdtAmountDepositedTillNow() + usdtToDeposit) <= cds.usdtLimit()){
            amintToDeposit = 0;
        }    

        if((cds.usdtAmountDepositedTillNow()) == cds.usdtLimit()){
            amintToDeposit = (amintToDeposit * 80)/100;
            usdtToDeposit = (amintToDeposit * 20)/100;
        }

        if((amintToDeposit + usdtToDeposit) < 100000000){
            return;
        }

        uint256 liquidationAmount = ((amintToDeposit + usdtToDeposit) * 50)/100;

        if(amint.balanceOf(user) < amintToDeposit){
            return;
        }
        vm.startPrank(user);

        usdt.mint(user,usdtToDeposit);
        usdt.approve(address(cds),usdtToDeposit);
        amint.approve(address(cds),amintToDeposit);

        cds.deposit(usdtToDeposit,amintToDeposit,true,uint128(liquidationAmount),ethPrice);

        vm.stopPrank();
    }

    function withdrawCDS(uint64 index,uint64 ethPrice) public{
        (uint64 maxIndex,) = cds.cdsDetails(user);
        index = uint64(bound(index,0,maxIndex));
        ethPrice = uint64(bound(ethPrice,0,type(uint24).max));

        if(ethPrice <= 3500 || ethPrice > (cds.lastEthPrice() * 5)/100){
            return;
        }
        if(index == 0){
            return;
        }

        (CDSTest.CdsAccountDetails memory accDetails,) = cds.getCDSDepositDetails(user,index);

        if(accDetails.withdrawed){
            return;
        }
        vm.startPrank(user);

        cds.withdraw(index,ethPrice);

        vm.stopPrank();
    }

    function liquidation(uint64 index,uint64 ethPrice) public{
        (,,,,uint64 maxIndex) = treasury.borrowing(user);
        index = uint64(bound(index,0,maxIndex));
        ethPrice = uint64(bound(ethPrice,0,type(uint24).max));

        if(ethPrice == 0){
            return;
        }
        if(index == 0){
            return;
        }

        Treasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(user,index);
        Treasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

        if(depositDetail.liquidated){
            return;
        }

        if(ethPrice > ((depositDetail.ethPriceAtDeposit * 80)/100)){
            return;
        }
        vm.startPrank(owner);
        borrow.liquidate(user,index,ethPrice);
        vm.stopPrank();
    }
}