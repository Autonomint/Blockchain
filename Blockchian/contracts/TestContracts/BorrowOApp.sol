// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "../interface/IBorrowing.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/IBorrowing.sol";
import "hardhat/console.sol";

contract BorrowOApp is Initializable,UUPSUpgradeable,OApp {

    IBorrowing public borrowing;

    function initialize( 
        address _borrowing,
        address _endpoint,
        address _delegate
        ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __oAppinit(_endpoint, _delegate);
        borrowing = IBorrowing(_borrowing);
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    function send(
        uint32 _dstEid,
        IBorrowing.OmniChainBorrowingData memory _message,
        uint8[] memory indices,
        MessagingFee memory fee,
        bytes memory _options
    ) external payable returns (MessagingReceipt memory receipt) {
        console.log("2");
        bytes memory _payload = abi.encode(_message,indices);
        // console.log(fee.nativeFee);
        // console.log(fee.lzTokenFee);
        receipt = _lzSend(_dstEid, _payload, _options, fee, payable(msg.sender));
    }

    function quote(
        uint32 _dstEid,
        IBorrowing.OmniChainBorrowingData memory _message,
        uint8[] memory indices,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_message,indices);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {

        uint8[] memory index;

        IBorrowing.OmniChainBorrowingData memory data;

        (data,index) = abi.decode(payload, (IBorrowing.OmniChainBorrowingData, uint8[]));

        if(index.length > 0){
            // bytes memory _payload = abi.encode();
            // bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0);
            // MessagingFee memory fee = quote(dstEid, ,[], _options, false);
            // _lzSend(dstEid, _payload, _options, fee, payable(msg.sender));
        }else{
            borrowing.setLZReceive(data,index);
            // omniChainBorrowing.normalizedAmount = totalNormalizedAmount + data.normalizedAmount;
            // omniChainBorrowing.ethVaultValue = data.ethVaultValue;
            // omniChainBorrowing.cdsPoolValue = data.cdsPoolValue;
            // omniChainBorrowing.totalCDSPool = data.totalCDSPool;
            // omniChainBorrowing.noOfLiquidations = noOfLiquidations + data.noOfLiquidations;
            // omniChainBorrowing.ethRemainingInWithdraw = ethRemainingInWithdraw + data.ethRemainingInWithdraw;
            // omniChainBorrowing.ethValueRemainingInWithdraw = ethValueRemainingInWithdraw + data.ethValueRemainingInWithdraw;
            // nonce = data.nonce;
        }
    }
}
