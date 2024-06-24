// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
interface ITreasury{

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
        uint256  abondUSDaPool;
        uint256  ethProfitsOfLiquidators;
        uint256  usdaGainedFromLiquidation;
        uint256  totalInterestFromLiquidation;
        uint256  interestFromExternalProtocolDuringLiquidation;
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

        function deposit(
            address user,
            uint128 _ethPrice,
            uint64 _depositTime
        ) external payable returns(DepositResult memory);
        function withdraw(address borrower,address toAddress,uint256 _amount,uint64 index) external payable returns(bool);
        function withdrawFromExternalProtocol(address user, uint128 aBondAmount) external returns(uint256);

        // function depositToAave() external;
        // function withdrawFromAave(uint64 index) external;
        // function depositToCompound() external;
        // function withdrawFromCompound(uint64 index) external;
        // function withdrawFromCompoundByUser(address depositor,uint64 index) external returns(uint256);
        function calculateYieldsForExternalProtocol(address user,uint128 aBondAmount) external view returns (uint256);
        function getBalanceInTreasury() external view returns(uint256);
        function approveUSDa(address _address, uint _amount) external;
        function approveUsdt(address _address, uint _amount) external;
        function transferEthToCdsLiquidators(address borrower,uint128 amount) external;


        function noOfBorrowers() external view returns(uint128);
        function abondUSDaPool() external view returns(uint256);
        function usdaGainedFromLiquidation() external view returns(uint256);
        function totalVolumeOfBorrowersAmountinWei() external view returns(uint256);
        function totalVolumeOfBorrowersAmountinUSD() external view returns(uint256);

        function updateHasBorrowed(address borrower,bool _bool) external;
        function updateTotalDepositedAmount(address borrower,uint128 amount) external;
        function updateTotalBorrowedAmount(address borrower,uint256 amount) external;

        function getBorrowing(address depositor,uint64 index) external view returns(GetBorrowingResult memory);
        function getExternalProtocolCumulativeRate(bool maximum) external view  returns(uint128);
        function updateDepositDetails(address depositor,uint64 index,DepositDetails memory depositDetail) external;
        function updateTotalInterest(uint256 _amount) external;
        function updateTotalInterestFromLiquidation(uint256 _amount) external;
        function updateAbondUSDaPool(uint256 amount,bool operation) external;
        function updateUSDaGainedFromLiquidation(uint256 amount,bool operation) external;
        function updateEthProfitsOfLiquidators(uint256 amount,bool operation) external;
        function updateInterestFromExternalProtocol(uint256 amount) external;
        function updateUsdaCollectedFromCdsWithdraw(uint256 amount) external;
        function updateLiquidatedETHCollectedFromCdsWithdraw(uint256 amount) external;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint64 count,uint256 amount);
    event WithdrawFromAave(uint64 count,uint256 amount);
    event DepositToCompound(uint64 count,uint256 amount);
    event WithdrawFromCompound(uint64 count,uint256 amount);
}