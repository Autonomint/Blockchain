// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

interface IMultiSign{

    enum SetterFunctions{
        SetLTV,
        SetAPR,
        SetWithdrawTimeLimitBorrow,
        SetWithdrawTimeLimitCDS,
        SetAdminBorrow,
        SetAdminCDS,
        SetTreasuryBorrow,
        SetTreasuryCDS,
        SetBondRatio,
        SetAmintLimit,
        SetUsdtLimit
    }
    enum Functions{
        BorrowingDeposit,
        BorrowingWithdraw,
        Liquidation,
        SetAPR,
        CDSDeposit,
        CDSWithdraw,
        RedeemUSDT
    }
    
    function functionState(Functions) external returns(bool);
    function executeSetterFunction(SetterFunctions _function) external returns (bool);
}