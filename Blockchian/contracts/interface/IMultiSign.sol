// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.19;

interface IMultiSign{

    enum Functions{BorrowingDeposit,BorrowingWithdraw,Liquidation,SetAPR,CDSDeposit,CDSWithdraw,RedeemUSDT}
    function functionState(Functions) external returns(bool);
    function executeSetAPR() external returns (bool);
}