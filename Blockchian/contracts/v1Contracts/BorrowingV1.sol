// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/CDSInterface.sol";
import "../interface/IUSDa.sol";
import "../interface/IAbond.sol";
import "../interface/ITreasury.sol";
import "../interface/IOptions.sol";
import "../interface/IMultiSign.sol";
import "hardhat/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Borrowing {

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
        uint128  noOfLiquidations;
        uint256  ethRemainingInWithdraw;
        uint256  ethValueRemainingInWithdraw;
        uint64 nonce;
    }

    IUSDa        internal usda; // our stablecoin
    CDSInterface internal cds;
    IABONDToken  internal abond; // abond stablecoin
    ITreasury    internal treasury;
    IOptions     internal options; // options contract interface
    IMultiSign   internal multiSign;

    uint256 internal _downSideProtectionLimit;
    address internal treasuryAddress; // treasury contract address
    address internal cdsAddress; // CDS contract address
    address internal admin; // admin address
    uint8   internal LTV; // LTV is a percentage eg LTV = 60 is 60%, must be divided by 100 in calculations
    uint8   internal APY; 
    uint256 internal totalNormalizedAmount; // total normalized amount in protocol
    address internal priceFeedAddress; // ETH USD pricefeed address
    uint128 internal lastEthprice; // previous eth price
    uint256 internal lastEthVaultValue; // previous eth vault value
    uint256 internal lastCDSPoolValue; // previous CDS pool value
    uint256 internal lastTotalCDSPool;
    uint256 public   lastCumulativeRate; // previous cumulative rate
    uint128 internal lastEventTime;
    uint128 internal noOfLiquidations; // total number of liquidation happened till now
    uint64  internal withdrawTimeLimit; // withdraw time limit
    uint128 internal ratePerSec;
    uint64  internal bondRatio;

    string  internal constant name = "USDa Stablecoin";
    string  internal constant version = "1";
    bytes32 internal DOMAIN_SEPARATOR;
    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 allowedAmount,bool allowed,uint256 expiry)");

    uint128 internal PRECISION; // ETH price precision
    uint128 internal CUMULATIVE_PRECISION;
    uint128 internal RATIO_PRECISION;
    uint128 internal RATE_PRECISION;
    uint128 internal USDa_PRECISION;

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