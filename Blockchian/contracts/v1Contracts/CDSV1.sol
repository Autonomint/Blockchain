// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IUSDa.sol";
import "../interface/IBorrowing.sol";
import "../interface/CDSInterface.sol";
import "../interface/ITreasury.sol";
import "../interface/IMultiSign.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract CDSV1 {

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
    
    IUSDa      internal usda; // our stablecoin
    IBorrowing  internal borrowing; // Borrowing contract interface
    ITreasury   internal treasury; // Treasury contrcat interface
    AggregatorV3Interface internal dataFeed;
    IMultiSign  internal multiSign;
    IERC20      internal usdt; // USDT interface

    address internal admin; // admin address
    address internal borrowingContract; // borrowing contract address
    address internal treasuryAddress; // treasury contract address

    uint128 internal lastEthPrice;
    uint128 internal fallbackEthPrice;
    uint64  public cdsCount; // cds depositors count
    uint64  internal withdrawTimeLimit; // Fixed Time interval between deposit and withdraw
    uint256 public totalCdsDepositedAmount; // total amint and usdt deposited in cds
    uint256 internal totalCdsDepositedAmountWithOptionFees;
    uint256 public totalAvailableLiquidationAmount; // total deposited amint available for liquidation
    uint128 internal lastCumulativeRate; 
    uint8   public usdaLimit; // amint limit in percent
    uint64  public usdtLimit; // usdt limit in number
    uint256 public usdtAmountDepositedTillNow; // total usdt deposited till now
    uint256 internal burnedUSDaInRedeem;
    uint128 internal cumulativeValue;
    bool    internal cumulativeValueSign;
    uint128 private PRECISION;
    uint128 private RATIO_PRECISION;

    mapping (address => CdsDetails) public cdsDetails;

    // liquidations info based on liquidation numbers
    mapping (uint128 liquidationIndex => LiquidationInfo) internal omniChainCDSLiqIndexToInfo;

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
