// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

interface CDSInterface {

    struct CdsAccountDetails {
        uint64 depositedTime;
        uint256 depositedAmount;
        uint64 withdrawedTime;
        uint256 withdrawedAmount;
        bool withdrawed;
        uint128 depositPrice;
        uint128 depositValue;
        bool depositValueSign;
        bool optedLiquidation;
        uint128 InitialLiquidationAmount;
        uint128 liquidationAmount;
        uint128 liquidationindex;
        uint256 normalizedAmount;
    }

    struct CdsDetails {
        uint64 index;
        bool hasDeposited;
        mapping ( uint64 => CdsAccountDetails) cdsAccountDetails;
    }
    
    struct CalculateValueResult{
        uint128 currentValue;
        bool gains;
    }

    struct LiquidationInfo{
        uint128 liquidationAmount;
        uint128 profits;
        uint128 ethAmount;
        uint256 availableLiquidationAmount;
    }

    struct OmniChainCDSData {
        uint64  cdsCount;
        uint256 totalCdsDepositedAmount;
        uint256 totalCdsDepositedAmountWithOptionFees;
        uint256 totalAvailableLiquidationAmount;
        uint256 usdtAmountDepositedTillNow;
        uint256 burnedAmintInRedeem;
    }

    function totalCdsDepositedAmount() external view returns(uint256);
    function totalAvailableLiquidationAmount() external returns(uint256);

    function calculateCumulativeRate(uint128 fees) external;

    function getCDSDepositDetails(address depositor,uint64 index) external view returns(CdsAccountDetails memory,uint64);
    function updateTotalAvailableLiquidationAmount(uint256 amount) external;
    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external;
    function updateTotalCdsDepositedAmount(uint128 _amount) external;
    function updateTotalCdsDepositedAmountWithOptionFees(uint128 _amount) external;

    
    event Deposit(uint256 depositedAmint,uint64 index,uint128 liquidationAmount,uint256 normalizedAmount,uint128 depositVal);
    event Withdraw(uint256 withdrewAmint,uint128 withdrawETH);
}