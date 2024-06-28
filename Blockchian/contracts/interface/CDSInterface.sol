// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

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
        uint256 burnedUSDaInRedeem;
        uint128 lastCumulativeRate;
    }

    enum FunctionToDo { DUMMY, UPDATE_GLOBAL, UPDATE_INDIVIDUAL }

    function totalCdsDepositedAmount() external view returns(uint256);
    function totalAvailableLiquidationAmount() external returns(uint256);

    function calculateCumulativeRate(uint128 fees) external returns(uint128);

    function getCDSDepositDetails(address depositor,uint64 index) external view returns(CdsAccountDetails memory,uint64);
    function updateTotalAvailableLiquidationAmount(uint256 amount) external;
    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external;
    function updateTotalCdsDepositedAmount(uint128 _amount) external;
    function updateTotalCdsDepositedAmountWithOptionFees(uint128 _amount) external;

    
    event Deposit(
        address user,
        uint64 index,
        uint128 depositedUSDa,
        uint128 depositedUSDT,
        uint256 depositedTime,
        uint128 ethPriceAtDeposit,
        uint128 lockingPeriod,
        uint128 liquidationAmount,
        bool optedForLiquidation
    );
    event Withdraw(
        address user,
        uint64 index,
        uint256 withdrawUSDa,
        uint256 withdrawTime,
        uint128 withdrawETH,
        uint128 ethPriceAtWithdraw,
        uint256 optionsFees,
        uint256 optionsFeesWithdrawn
    );
}