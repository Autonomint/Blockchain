// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.20;

import { State, IABONDToken } from "../interface/IAbond.sol";
import "../interface/ITreasury.sol";
import "../interface/IUSDa.sol";

library TreasuryLib {
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
        uint256  abondUSDaPool;
        uint256  ethProfitsOfLiquidators;
        uint256  interestFromExternalProtocolDuringLiquidation;
        uint256  usdaGainedFromLiquidation;
    }

    enum Protocol{Aave,Compound}

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint64 count,uint256 amount);
    event WithdrawFromAave(uint64 count,uint256 amount);
    event DepositToCompound(uint64 count,uint256 amount);
    event WithdrawFromCompound(uint64 count,uint256 amount);
}