// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interface/IUSDa.sol";
import "../interface/IBorrowing.sol";
import "../interface/AaveInterfaces/IWETHGateway.sol";
import "../interface/AaveInterfaces/IPoolAddressesProvider.sol";
import "../interface/CometMainInterface.sol";
import "hardhat/console.sol";

contract TreasuryV1 {

    error Treasury_ZeroDeposit();
    error Treasury_ZeroWithdraw();
    error Treasury_AavePoolAddressZero();
    error Treasury_AaveDepositAndMintFailed();
    error Treasury_AaveWithdrawFailed();
    error Treasury_CompoundDepositAndMintFailed();
    error Treasury_CompoundWithdrawFailed();
    error Treasury_EthTransferToCdsLiquidatorFailed();
    error Treasury_WithdrawExternalProtocolInterestFailed();

    //Depositor's Details for each depsoit.
    struct DepositDetails{
        uint64  depositedTime;
        uint128 depositedAmount;
        uint128 depositedAmountUsdValue;
        uint64  downsidePercentage;
        uint128 ethPriceAtDeposit;
        uint128 borrowedAmount;
        uint128 normalizedAmount;
        bool    withdrawed;
        uint128 withdrawAmount;
        bool    liquidated;
        uint64  ethPriceAtWithdraw;
        uint64  withdrawTime;
        uint128 aBondTokensAmount;
        uint128 strikePrice;
        uint128 optionFees;
    }

    //Borrower Details
    struct BorrowerDetails {
        uint256 depositedAmount;
        mapping(uint64 => DepositDetails) depositDetails;
        uint256 totalBorrowedAmount;
        bool    hasBorrowed;
        bool    hasDeposited;
        uint64  borrowerIndex;
    }

    //Each Deposit to Aave/Compound
    struct EachDepositToProtocol{
        uint64  depositedTime;
        uint128 depositedAmount;
        uint128 ethPriceAtDeposit;
        uint256 depositedUsdValue;
        uint128 tokensCredited;

        bool    withdrawed;
        uint128 ethPriceAtWithdraw;
        uint64  withdrawTime;
        uint256 withdrawedUsdValue;
        uint128 interestGained;
        uint256 discountedPrice;
    }

    //Total Deposit to Aave/Compound
    struct ProtocolDeposit{
        mapping (uint64 => EachDepositToProtocol) eachDepositToProtocol;
        uint64  depositIndex;
        uint256 depositedAmount;
        uint256 totalCreditedTokens;
        uint256 depositedUsdValue;
        uint256 cumulativeRate;       
    }

    struct DepositResult{
        bool hasDeposited;
        uint64 borrowerIndex;
    }

    struct GetBorrowingResult{
        uint64 totalIndex;
        DepositDetails depositDetails;
    }

    struct OmniChainTreasuryData {
        uint256  totalVolumeOfBorrowersAmountinWei;
        uint256  totalVolumeOfBorrowersAmountinUSD;
        uint128  noOfBorrowers;
        uint256  totalInterest;
        uint256  totalInterestFromLiquidation;
        uint256  abondUSDaPool;
        uint256  ethProfitsOfLiquidators;
        uint256  interestFromExternalProtocolDuringLiquidation;
        uint256  usdaGainedFromLiquidation;
    }

    struct USDaOftTransferData {
        address recipient;
        uint256 tokensToSend;
    }

    struct NativeTokenTransferData{
        address recipient;
        uint256 nativeTokensToSend;
    }

    enum Protocol{Aave,Compound}
    enum FunctionToDo { DUMMY, UPDATE, TOKEN_TRANSFER, NATIVE_TRANSFER, BOTH_TRANSFER}

    IBorrowing  internal borrow;
    IUSDa      internal usda;
    IWrappedTokenGatewayV3          internal wethGateway; // Weth gateway is used to deposit eth in  and withdraw from aave
    IPoolAddressesProvider   internal aavePoolAddressProvider; // To get the current pool  address in Aave
    IERC20  internal usdt;
    IERC20 internal aToken; // aave token contract
    CometMainInterface internal comet; // To deposit in and withdraw eth from compound

    address internal borrowingContract;
    address internal cdsContract;  
    address internal compoundAddress;
    address internal aaveWETH;        //wethGateway Address for Approve

    // Get depositor details by address
    mapping(address depositor => BorrowerDetails) public borrowing;
    //Get external protocol deposit details by protocol name (enum)
    mapping(Protocol => ProtocolDeposit) internal protocolDeposit;
    uint256 public totalVolumeOfBorrowersAmountinWei;
    //eth vault value
    uint256 public totalVolumeOfBorrowersAmountinUSD;
    uint128 public noOfBorrowers;
    uint256 internal totalInterest;
    uint256 internal totalInterestFromLiquidation;
    uint256 public abondUSDaPool;
    uint256 internal ethProfitsOfLiquidators;
    uint256 internal interestFromExternalProtocolDuringLiquidation;

    //no of times deposited in external protocol(always 1 ahead) 
    uint64 internal externalProtocolDepositCount;
    uint256 internal PRECISION;
    uint256 internal CUMULATIVE_PRECISION;

    // Eth depsoited in particular index
    mapping(uint256=>uint256) externalProtocolCountTotalValue;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint64 count,uint256 amount);
    event WithdrawFromAave(uint64 count,uint256 amount);
    event DepositToCompound(uint64 count,uint256 amount);
    event WithdrawFromCompound(uint64 count,uint256 amount);

}