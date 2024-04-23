// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "../interface/IBorrowing.sol";

interface IBorrowOApp{

    function send(
        uint32 _dstEid,
        IBorrowing.OmniChainBorrowingData memory _message,
        uint8[] memory indices,
        MessagingFee memory fee,
        bytes memory _options
    ) external payable returns (MessagingReceipt memory receipt);

    function quote(
        uint32 _dstEid,
        IBorrowing.OmniChainBorrowingData memory _message,
        uint8[] memory indices,
        bytes memory _options,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external;
}