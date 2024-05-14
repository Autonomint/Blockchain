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
        uint64  externalProtocolCount;
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
        uint256  abondAmintPool;
        uint256  ethProfitsOfLiquidators;
        uint256  interestFromExternalProtocolDuringLiquidation;
        uint256  amintGainedFromLiquidation;
    }

    struct AmintOftTransferData {
        address recipient;
        uint256 tokensToSend;
    }

    enum Protocol{Aave,Compound}
    enum FunctionToDo { DUMMY, UPDATE, TRANSFER }

        function deposit(
            uint256 _depositingAmount,
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
        function approveAmint(address _address, uint _amount) external;
        function approveUsdt(address _address, uint _amount) external;
        function transferEthToCdsLiquidators(address borrower,uint128 amount) external;


        function noOfBorrowers() external view returns(uint128);
        function ethProfitsOfLiquidators() external view returns(uint256);
        function abondAmintPool() external view returns(uint256);
        function amintGainedFromLiquidation() external view returns(uint256);
        function totalVolumeOfBorrowersAmountinWei() external view returns(uint256);
        function totalVolumeOfBorrowersAmountinUSD() external view returns(uint256);
        function omniChainTreasuryNoOfBorrowers() external view returns(uint128);
        function omniChainTreasuryTotalVolumeOfBorrowersAmountinWei() external view returns(uint256);
        function omniChainTreasuryTotalVolumeOfBorrowersAmountinUSD() external view returns(uint256);
        function omniChainTreasuryEthProfitsOfLiquidators() external view returns(uint256);

        function quote(
            uint32 _dstEid,
            FunctionToDo _functionToDo,
            AmintOftTransferData memory _oftTransferData,
            bytes memory _options,
            bool _payInLzToken
        ) external view returns (MessagingFee memory fee);

        function oftReceiveFromOtherChains(
            FunctionToDo _functionToDo,
            AmintOftTransferData memory _oftTransferData
        ) external payable returns (MessagingReceipt memory receipt);

        function updateHasBorrowed(address borrower,bool _bool) external;
        function updateTotalDepositedAmount(address borrower,uint128 amount) external;
        function updateTotalBorrowedAmount(address borrower,uint256 amount) external;

        function getBorrowing(address depositor,uint64 index) external view returns(GetBorrowingResult memory);
        function getExternalProtocolCumulativeRate(bool maximum) external view  returns(uint128);
        function updateDepositDetails(address depositor,uint64 index,DepositDetails memory depositDetail) external;
        function updateTotalInterest(uint256 _amount) external;
        function updateTotalInterestFromLiquidation(uint256 _amount) external;
        function updateAbondAmintPool(uint256 amount,bool operation) external;
        function updateAmintGainedFromLiquidation(uint256 amount,bool operation) external;
        function updateEthProfitsOfLiquidators(uint256 amount,bool operation) external;
        function updateInterestFromExternalProtocol(uint256 amount) external;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint64 count,uint256 amount);
    event WithdrawFromAave(uint64 count,uint256 amount);
    event DepositToCompound(uint64 count,uint256 amount);
    event WithdrawFromCompound(uint64 count,uint256 amount);
}