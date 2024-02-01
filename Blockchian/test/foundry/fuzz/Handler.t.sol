// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.19;

// import {Test} from "../../../lib/forge-std/src/Test.sol";
// import {console} from "../../../lib/forge-std/src/console.sol";
// import {BorrowingTest} from "../../../contracts/TestContracts/CopyBorrowing.sol";
// import {Treasury} from "../../../contracts/Core_logic/Treasury.sol";
// import {CDSTest} from "../../../contracts/TestContracts/CopyCDS.sol";
// import {TrinityStablecoin} from "../../../contracts/Token/Trinity_ERC20.sol";
// import {ProtocolToken} from "../../../contracts/Token/Protocol_Token.sol";
// import {USDT} from "../../../contracts/TestContracts/CopyUsdt.sol";

// contract Handler is Test{
//     BorrowingTest borrow;
//     CDSTest cds;
//     TrinityStablecoin tsc;
//     Treasury treasury;
//     ProtocolToken pToken;
//     USDT usdt;
//     uint256 MAX_DEPOSIT = type(uint64).max;

//     address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

//     constructor(
//         BorrowingTest _borrow,
//         CDSTest _cds,
//         Treasury _treasury,
//         TrinityStablecoin _tsc,
//         ProtocolToken _pToken,
//         USDT _usdt
//     )
//     {
//         borrow = _borrow;
//         cds = _cds;
//         tsc = _tsc;
//         treasury = _treasury;
//         pToken = _pToken;
//         usdt = _usdt;
//     }

//     function depositBorrowing(uint256 amount) public {
//         vm.deal(msg.sender,type(uint256).max);
//         amount = bound(amount,0,MAX_DEPOSIT);
//         if(amount == 0){
//             return;
//         }
//         uint128 price = uint128(borrow.getUSDValue());
//         uint64 strikePrice = uint64((price * 10)/100);
//         vm.startPrank(msg.sender);
//         borrow.depositTokens{value: amount}(price,uint64(block.timestamp),strikePrice);
//         vm.stopPrank();
//     }

//     function withdrawBorrowing1(uint256 index) public{
//         vm.startPrank(msg.sender);
//         (uint64 maxIndex,) = treasury.getBorrowing(msg.sender,uint64(index));
//         index = bound(index,0,maxIndex);
//         if(index == 0){
//             return;
//         }
//         uint64 price = uint64(borrow.getUSDValue());
//         uint256 tokenBalance = tsc.balanceOf(msg.sender);
//         tsc.approve(address(treasury),tokenBalance);
//         tsc.approve(address(borrow),tokenBalance);
//         borrow.withDraw(msg.sender,uint64(index),price,uint64(block.timestamp));
//         vm.stopPrank();
//     }

//     function withdrawBorrowing2(uint256 index) public{
//         vm.startPrank(msg.sender);
//         (uint64 maxIndex,) = treasury.getBorrowing(msg.sender,uint64(index));
//         index = bound(index,0,maxIndex);
//         if(index == 0){
//             return;
//         }
//         uint64 price = uint64(borrow.getUSDValue());
//         uint256 tokenBalance = tsc.balanceOf(msg.sender);
//         tsc.approve(address(treasury),tokenBalance);
//         tsc.approve(address(borrow),tokenBalance);
//         borrow.withDraw(msg.sender,uint64(index),price,uint64(block.timestamp));
//         uint256 pTokenBalance = pToken.balanceOf(msg.sender);
//         cds.approval(address(borrow),(tokenBalance));
//         pToken.approve(address(borrow),pTokenBalance);
//         borrow.withDraw(msg.sender,uint64(index),price,uint64(block.timestamp));
//         vm.stopPrank();
//     }

//     function depositCDS(uint256 amount) public {
//         vm.deal(msg.sender,type(uint256).max);

//         uint128 price = uint128(borrow.getUSDValue());
//         vm.startPrank(msg.sender);
//         uint64 strikePrice = uint64((price * 10)/100);
//         borrow.depositTokens{value: MAX_DEPOSIT}(price,uint64(block.timestamp),strikePrice);

//         uint128 tokenBalance = uint128(tsc.balanceOf(msg.sender));
//         tsc.approve(address(cds),tokenBalance);

//         amount = bound(amount,1,tokenBalance);
//         cds.deposit(uint128(amount),true,uint128(amount));
//         vm.stopPrank();
//     }

//     function withdrawCDS(uint256 index) public{
//         vm.startPrank(msg.sender);
//         (,uint64 maxIndex) = cds.getCDSDepositDetails(msg.sender,uint64(index));
//         index = bound(index,0,maxIndex);
//         if(index == 0){
//             return;
//         }
//         uint256 tokenBalance = tsc.balanceOf(address(treasury));
//         cds.withdraw(uint64(index));
//         vm.stopPrank();
//     }
// }