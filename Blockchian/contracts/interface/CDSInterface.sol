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
    function omniChainCDSTotalCdsDepositedAmount() external view returns(uint256);
    function totalAvailableLiquidationAmount() external returns(uint256);
    function omniChainCDSTotalAvailableLiquidationAmount() external view returns(uint256);
    function quote(
        uint32 _dstEid,
        FunctionToDo _functionToDo,
        uint256 optionsFeesToGetFromOtherChain,
        uint256 cdsAmountToGetFromOtherChain,
        uint256 liqAmountToGetFromOtherChain,
        LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        bytes memory _options,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);

    function callLzSendFromExternal(
        uint32 _dstEid,
        FunctionToDo functionToDo,
        uint256 optionsFeesToGetFromOtherChain,
        uint256 cdsAmountToGetFromOtherChain,
        uint256 liqAmountToGetFromOtherChain,
        LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        MessagingFee memory fee,
        bytes memory _options
    ) external payable returns (MessagingReceipt memory receipt);

    function calculateCumulativeRate(uint128 fees) external payable;

    function getCDSDepositDetails(address depositor,uint64 index) external view returns(CdsAccountDetails memory,uint64);
    function updateTotalAvailableLiquidationAmount(uint256 amount) external;
    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external;
    function updateTotalCdsDepositedAmount(uint128 _amount) external;
    function updateTotalCdsDepositedAmountWithOptionFees(uint128 _amount) external;

    
    event Deposit(uint256 depositedUSDa,uint64 index,uint128 liquidationAmount,uint256 normalizedAmount,uint128 depositVal);
    event Withdraw(uint256 withdrewUSDa,uint128 withdrawETH);
}