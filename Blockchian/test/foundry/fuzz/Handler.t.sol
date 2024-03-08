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

contract Handler is Test{
    BorrowingTest borrow;
    CDSTest cds;
    TestAMINTStablecoin amint;
    Treasury treasury;
    TestABONDToken abond;
    TestUSDT usdt;
    uint256 MAX_DEPOSIT = type(uint128).max;
    uint256 public amintMintedManually;

    address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

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

    function depositBorrowing(uint256 amount,uint128 ethPrice,uint16 strikePricePercent) public {
        vm.deal(msg.sender,type(uint256).max);
        amount = bound(amount,0,MAX_DEPOSIT);
        ethPrice = uint128(bound(ethPrice,0,type(uint24).max));
        strikePricePercent = uint16(bound(strikePricePercent,0,type(uint8).max));

        if(ethPrice == 0){
            return;
        }

        if(strikePricePercent == 0 || strikePricePercent > 4){
            return;
        }

        if(amount == 0 || amount < 1e13){
            return;
        }

        uint64 strikePrice = uint64(ethPrice + (ethPrice * ((strikePricePercent*5) + 5))/100);
        depositCDS(uint128((((amount * ethPrice)/1e12)*21)/100),ethPrice);
        vm.startPrank(msg.sender);
        borrow.depositTokens{value: amount}(
            ethPrice,
            uint64(block.timestamp),
            IOptions.StrikePrice(strikePricePercent),
            strikePrice,
            50622665);
        vm.stopPrank();
    }

    // function withdrawBorrowing(uint256 index) public{
    //     vm.startPrank(msg.sender);
    //     (,,,,uint64 maxIndex) = treasury.borrowing(msg.sender);
    //     index = bound(index,0,maxIndex);
    //     if(index == 0){
    //         return;
    //     }
    //     uint64 price = uint64(borrow.getUSDValue());
    //     uint256 tokenBalance = amint.balanceOf(msg.sender);
    //     amint.approve(address(borrow),tokenBalance);
    //     borrow.withDraw(msg.sender,uint64(index),price,uint64(block.timestamp));
    //     vm.stopPrank();
    // }

    function depositCDS(uint128 amount,uint128 ethPrice) public {
        vm.startPrank(msg.sender);

        amount = uint128(bound(amount,0,type(uint64).max));
        ethPrice = uint128(bound(ethPrice,0,type(uint24).max));
        if(ethPrice == 0){
            return;
        }
        if(amount == 0){
            return;
        }

        uint128 usdtToDeposit = amount;
        uint128 amintToDeposit;
        uint256 liquidationAmount = (amount*50)/100;
        if((cds.usdtAmountDepositedTillNow() + usdtToDeposit) >= cds.usdtLimit()){
            amintToDeposit = (amount * 80)/100;
            usdtToDeposit = amount - amintToDeposit;
        }else{
            usdtToDeposit = amount;
            amintToDeposit = 0;
        }

        usdt.mint(msg.sender,usdtToDeposit);
        usdt.approve(address(cds),usdtToDeposit);

        amint.mint(msg.sender,amintToDeposit);
        amintMintedManually += amintToDeposit * 1e12;
        amint.approve(address(cds),amintToDeposit);

        cds.deposit(usdtToDeposit,amintToDeposit,true,uint128(liquidationAmount),ethPrice);

        vm.stopPrank();
    }

    function withdrawCDS(uint64 index,uint128 ethPrice) public{
        vm.startPrank(msg.sender);

        (uint64 maxIndex,) = cds.cdsDetails(msg.sender);
        index = uint64(bound(index,0,maxIndex));
        ethPrice = uint128(bound(ethPrice,0,type(uint24).max));

        if(ethPrice == 0){
            return;
        }
        if(index == 0){
            return;
        }

        cds.withdraw(index,ethPrice);

        vm.stopPrank();
    }
}