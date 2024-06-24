// SPDX-License-Identifier: unlicensed

import "../interface/IOptions.sol";

pragma solidity 0.8.20;

interface IBorrowing{

    error Borrowing_DepositFailed();
    error Borrowing_GettingETHPriceFailed();
    error Borrowing_usdaMintFailed();
    error Borrowing_abondMintFailed();
    error Borrowing_WithdrawUSDaTransferFailed();
    error Borrowing_WithdrawEthTransferFailed();
    error Borrowing_WithdrawBurnFailed();
    error Borrowing_LiquidateBurnFailed();
    error Borrowing_LiquidateEthTransferToCdsFailed();
    
    enum DownsideProtectionLimitValue {
        // 0: deside Downside Protection limit by percentage of eth price in past 3 months
        ETH_PRICE_VOLUME,
        // 1: deside Downside Protection limit by CDS volume divided by borrower volume.
        CDS_VOLUME_BY_BORROWER_VOLUME
    }

    struct OmniChainBorrowingData {
        uint256  normalizedAmount;
        uint256  ethVaultValue;
        uint256  cdsPoolValue;
        uint256  totalCDSPool;
        uint256  ethRemainingInWithdraw;
        uint256  ethValueRemainingInWithdraw;
        uint128  noOfLiquidations;
        uint64 nonce;
    }

    function getUSDValue() external view returns(uint256);
    // function lastEthVaultValue() external view returns(uint256);
    // function lastCDSPoolValue() external view returns(uint256);

    function updateLastEthVaultValue(uint256 _amount) external;
    function calculateRatio(uint256 _amount,uint currentEthPrice) external returns(uint64);

    event Deposit(
        address user,
        uint64 index,
        uint256 depositedAmount,
        uint256 normalizedAmount,
        uint256 depositedTime,
        uint128 ethPrice,
        uint256 borrowAmount,
        uint64 strikePrice,
        uint256 optionsFees,
        IOptions.StrikePrice strikePricePercent
        );
    event Withdraw(
        address user,
        uint64 index,
        uint256 withdrawTime,
        uint128 withdrawAmount,
        uint128 noOfAbond,
        uint256 borrowDebt
    );
    event Liquidate(uint64 index,uint128 liquidationAmount,uint128 profits,uint128 ethAmount,uint256 availableLiquidationAmount);
}