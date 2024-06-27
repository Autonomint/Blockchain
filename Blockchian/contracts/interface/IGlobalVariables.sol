// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import "../interface/CDSInterface.sol";
interface IGlobalVariables{

    struct OmniChainData {
        uint256  normalizedAmount;
        uint256  ethVaultValue;
        uint256  cdsPoolValue;
        uint256  totalCDSPool;
        uint256  ethRemainingInWithdraw;
        uint256  ethValueRemainingInWithdraw;
        uint128  noOfLiquidations;
        uint64   nonce;

        uint64  cdsCount;
        uint256 totalCdsDepositedAmount;
        uint256 totalCdsDepositedAmountWithOptionFees;
        uint256 totalAvailableLiquidationAmount;
        uint256 usdtAmountDepositedTillNow;
        uint256 burnedUSDaInRedeem;
        uint128 lastCumulativeRate;

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

    enum FunctionToDo { DUMMY, UPDATE_GLOBAL, UPDATE_INDIVIDUAL , TOKEN_TRANSFER, NATIVE_TRANSFER, BOTH_TRANSFER}
    
    function getOmniChainData() external view returns(OmniChainData memory);

    function setOmniChainData(OmniChainData memory _omniChainData) external;
    function oftOrNativeReceiveFromOtherChains(
        FunctionToDo _functionToDo,
        USDaOftTransferData memory _oftTransferData,
        NativeTokenTransferData memory _nativeTokenTransferData,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt);


    function quote(
        FunctionToDo _functionToDo,
        bytes memory _options,
        bool _payInLzToken
    ) external view returns(MessagingFee memory fee);

    function send(        
        FunctionToDo _functionToDo,
        MessagingFee memory _fee,
        bytes memory _options,
        address refundAddress
    ) external payable returns (MessagingReceipt memory receipt);

    function sendForLiquidation(        
        FunctionToDo _functionToDo,
        uint128 _liqIndex,
        CDSInterface.LiquidationInfo memory _liquidationInfo,
        MessagingFee memory _fee,
        bytes memory _options,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt);
}