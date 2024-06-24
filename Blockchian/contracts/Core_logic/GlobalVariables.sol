// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "hardhat/console.sol";

import "../interface/IUSDa.sol";
import "../interface/CDSInterface.sol";
import "../interface/IGlobalVariables.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

contract GlobalVariables is IGlobalVariables,Initializable,UUPSUpgradeable,ReentrancyGuardUpgradeable,OApp {

    using OptionsBuilder for bytes;
    IUSDa private usda;
    CDSInterface private cds;
    address private dstTreasuryAddress;
    uint32 private dstEid;
    OmniChainData private omniChainData; //! omniChainData contains global data(all chains)

    function initialize(
        address _usda,
        address _cds,
        address _endpoint,
        address _delegate
    ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __oAppinit(_endpoint, _delegate);
        usda = IUSDa(_usda);
        cds = CDSInterface(_cds);
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    function getOmniChainData() public view returns(OmniChainData memory){
        return omniChainData;
    }

    function setOmniChainData(OmniChainData memory _omniChainData) public{
        omniChainData = _omniChainData;
    }

    function setDstEid(uint32 _eid) public onlyOwner{
        dstEid = _eid;
    }

    function oftOrNativeReceiveFromOtherChains(
        FunctionToDo _functionToDo,
        USDaOftTransferData memory _oftTransferData,
        NativeTokenTransferData memory _nativeTokenTransferData
    ) external payable returns (MessagingReceipt memory receipt) {

        bytes memory _payload = abi.encode(
            _functionToDo, 
            omniChainData, 
            _oftTransferData,
            _nativeTokenTransferData);

        MessagingFee memory _fee;
        bytes memory _options;

        if(_functionToDo == FunctionToDo.TOKEN_TRANSFER || _functionToDo == FunctionToDo.BOTH_TRANSFER){

            //! getting options since,the src don't know the dst state
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(60000, 0);

            SendParam memory _sendParam = SendParam(
                dstEid,
                bytes32(uint256(uint160(_oftTransferData.recipient))),
                _oftTransferData.tokensToSend,
                _oftTransferData.tokensToSend,
                options,
                '0x',
                '0x'
            );
            MessagingFee memory fee = usda.quoteSend( _sendParam, false);

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(350000, 0).addExecutorNativeDropOption(
                uint128(fee.nativeFee), 
                bytes32(uint256(uint160(dstTreasuryAddress)))
            );

        }else if(_functionToDo == FunctionToDo.NATIVE_TRANSFER){
            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(260000, 0);
        }

        _fee = quoteInternal(
                dstEid, 
                _functionToDo, 
                0,
                0,
                0,
                CDSInterface.LiquidationInfo(0,0,0,0),
                0,
                _oftTransferData,
                _nativeTokenTransferData,
                _options, 
                false);

        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(dstEid, _payload, _options, _fee, payable(msg.sender));
    }

    function sendInternal(        
        uint32 _dstEid,
        FunctionToDo functionToDo,
        uint256 optionsFeesToGetFromOtherChain,
        uint256 cdsAmountToGetFromOtherChain,
        uint256 liqAmountToGetFromOtherChain,
        CDSInterface.LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        MessagingFee memory _fee,
        bytes memory _options,
        address refundAddress
    ) internal returns (MessagingReceipt memory receipt) {

        //! encoding the message 
        bytes memory _payload = abi.encode(
            functionToDo,
            optionsFeesToGetFromOtherChain,
            cdsAmountToGetFromOtherChain,
            liqAmountToGetFromOtherChain,
            liquidationInfo,
            liqIndex,
            USDaOftTransferData(address(0), 0),
            NativeTokenTransferData(address(0), 0),
            omniChainData);
        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(_dstEid, _payload, _options, _fee, payable(refundAddress));
    }

    function quoteInternal(
        uint32 _dstEid,
        FunctionToDo functionToDo,
        uint256 optionsFeesToGetFromOtherChain,
        uint256 cdsAmountToGetFromOtherChain,
        uint256 liqAmountToGetFromOtherChain,
        CDSInterface.LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        USDaOftTransferData memory _oftTransferData,
        NativeTokenTransferData memory _nativeTokenTransferData,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {

        bytes memory payload = abi.encode(
            functionToDo,
            optionsFeesToGetFromOtherChain,
            cdsAmountToGetFromOtherChain,
            liqAmountToGetFromOtherChain,
            liquidationInfo,
            liqIndex,
            _oftTransferData,
            _nativeTokenTransferData,
            omniChainData);

        fee = _quote( _dstEid, payload, _options, _payInLzToken);
    }

    function quote(
        FunctionToDo _functionToDo,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns(MessagingFee memory fee){
        return quoteInternal(
            dstEid, 
            _functionToDo,
            0,0,0,
            CDSInterface.LiquidationInfo(0,0,0,0),
            0,
            USDaOftTransferData(address(0),0),
            NativeTokenTransferData(address(0),0),
            _options,
            _payInLzToken);
    }

    function send(        
        FunctionToDo _functionToDo,
        MessagingFee memory _fee,
        bytes memory _options,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt){
        return sendInternal(
            dstEid,
            _functionToDo,
            0,0,0,
            CDSInterface.LiquidationInfo(0,0,0,0),
            0,
            _fee,
            _options,
            _refundAddress
        );
    }


    /**
     * @dev function to receive data from src
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override{

        //! Decoding the message from src
        (FunctionToDo functionToDo,
        uint256 optionsFeesToRemove,
        uint256 cdsAmountToRemove,
        uint256 liqAmountToRemove,
        CDSInterface.LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        USDaOftTransferData memory oftTransferData,
        NativeTokenTransferData memory nativeTokenTransferData,
        OmniChainData memory message
        ) = abi.decode(payload, (
            FunctionToDo,
            uint256,
            uint256,
            uint256,
            CDSInterface.LiquidationInfo,
            uint128,
            USDaOftTransferData,
            NativeTokenTransferData,
            OmniChainData
        ));
        bytes memory _options;
        MessagingFee memory _fee;

        if(functionToDo == FunctionToDo.TOKEN_TRANSFER){
            //! getting options since,the src don't know the dst state
            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(60000, 0);

            SendParam memory _sendParam = SendParam(
                dstEid,
                bytes32(uint256(uint160(oftTransferData.recipient))),
                oftTransferData.tokensToSend,
                oftTransferData.tokensToSend,
                _options,
                '0x',
                '0x'
            );
            _fee = usda.quoteSend( _sendParam, false);

            usda.send{ value: _fee.nativeFee}( _sendParam, _fee, address(this));

        }else if(functionToDo == FunctionToDo.NATIVE_TRANSFER){

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(260000, 0).addExecutorNativeDropOption(
                uint128(nativeTokenTransferData.nativeTokensToSend), 
                bytes32(uint256(uint160(nativeTokenTransferData.recipient)))
            );

            bytes memory _payload = abi.encode(
                FunctionToDo(1), 
                omniChainData, 
                USDaOftTransferData(address(0),0),
                NativeTokenTransferData(address(0), 0));

        _fee = quoteInternal(
                dstEid, 
                FunctionToDo(1), 
                0,
                0,
                0,
                CDSInterface.LiquidationInfo(0,0,0,0),
                0,
                USDaOftTransferData(address(0),0),
                NativeTokenTransferData(address(0), 0),
                _options, 
                false);

            _lzSend(dstEid, _payload, _options, _fee, payable(msg.sender));

        }else if(functionToDo == FunctionToDo.BOTH_TRANSFER){

            // _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(60000, 0);

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(260000, 0).addExecutorNativeDropOption(
                uint128(nativeTokenTransferData.nativeTokensToSend), 
                bytes32(uint256(uint160(nativeTokenTransferData.recipient)))
            );

            SendParam memory _sendParam = SendParam(
                dstEid,
                bytes32(uint256(uint160(oftTransferData.recipient))),
                oftTransferData.tokensToSend,
                oftTransferData.tokensToSend,
                _options,
                '0x',
                '0x'
            );
            _fee = usda.quoteSend( _sendParam, false);

            usda.send{ value: _fee.nativeFee}( _sendParam, _fee, address(this));

        }else if(functionToDo == FunctionToDo.UPDATE_INDIVIDUAL){
            cds.updateTotalCdsDepositedAmountWithOptionFees(uint128(optionsFeesToRemove));
            cds.updateTotalCdsDepositedAmount(uint128(cdsAmountToRemove));
            cds.updateTotalAvailableLiquidationAmount(liqAmountToRemove);
            cds.updateLiquidationInfo(liqIndex, liquidationInfo);
        }

        omniChainData = message;

    }

}