// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "hardhat/console.sol";

import "../interface/IUSDa.sol";
import "../interface/CDSInterface.sol";
import "../interface/IGlobalVariables.sol";
import "../interface/ITreasury.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

contract GlobalVariables is IGlobalVariables,Initializable,UUPSUpgradeable,ReentrancyGuardUpgradeable,OApp {

    using OptionsBuilder for bytes;
    IUSDa private usda;
    CDSInterface private cds;
    ITreasury private treasury;
    address private borrowing;
    address private borrowLiq;
    address private dstGlobalVariablesAddress;
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
    
    // Function to check if an address is a contract
    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    modifier onlyCoreContracts() {
        require( 
            msg.sender == borrowing ||  msg.sender == address(cds) || msg.sender == borrowLiq || msg.sender == address(treasury), 
            "This function can only called by Core contracts");
        _;
    }

    modifier onlyCDSOrBorrowLiq() {
        require( 
            msg.sender == address(cds) || msg.sender == borrowLiq, 
            "This function can only called by Core contracts");
        _;
    }

    function getOmniChainData() public view returns(OmniChainData memory){
        return omniChainData;
    }

    function setOmniChainData(OmniChainData memory _omniChainData) public onlyCoreContracts{
        omniChainData = _omniChainData;
    }

    function setDstEid(uint32 _eid) public onlyOwner{
        dstEid = _eid;
    }

    function setTreasury(address _treasury) public onlyOwner{
        require(_treasury != address(0) && isContract(_treasury) != false, 
            "Treasury address should not be zero address and must be contract address");
        treasury = ITreasury(_treasury);
    }

    function setBorrowing(address _borrow) public onlyOwner{
        require(_borrow != address(0) && isContract(_borrow) != false, 
            "Borrowing address should not be zero address and must be contract address");
        borrowing = _borrow;
    }

    function setBorrowLiq(address _borrowLiq) public onlyOwner{
        require(_borrowLiq != address(0) && isContract(_borrowLiq) != false, 
            "Borrow Liquidation address should not be zero address and must be contract address");
        borrowLiq = _borrowLiq;
    }

    function setDstGlobalVariablesAddress(address _globalVariables) public onlyOwner{
        require(_globalVariables != address(0) && isContract(_globalVariables) != false, 
            "Destination treasury address should not be zero address and must be contract address");
        dstGlobalVariablesAddress = _globalVariables;
    }

    function oftOrNativeReceiveFromOtherChains(
        FunctionToDo _functionToDo,
        USDaOftTransferData memory _oftTransferData,
        NativeTokenTransferData memory _nativeTokenTransferData,
        address _refundAddress
    ) external payable onlyCDSOrBorrowLiq returns (MessagingReceipt memory receipt) {

        bytes memory _payload = abi.encode(
                _functionToDo,
                _oftTransferData.tokensToSend,
                _oftTransferData.tokensToSend,
                _oftTransferData.tokensToSend,
                CDSInterface.LiquidationInfo(0,0,0,0),0, 
                _oftTransferData,
                _nativeTokenTransferData,
                omniChainData
            );

        MessagingFee memory _fee;
        MessagingFee memory feeForTokenTransfer;
        MessagingFee memory feeForNativeTransfer;
        bytes memory _options;
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
        feeForTokenTransfer = usda.quoteSend( _sendParam, false);

        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(280000, 0).addExecutorNativeDropOption(
                uint128(_nativeTokenTransferData.nativeTokensToSend), 
                bytes32(uint256(uint160(dstGlobalVariablesAddress))));

        feeForNativeTransfer = quote(FunctionToDo(1), options, false);

        if(_functionToDo == FunctionToDo.TOKEN_TRANSFER){

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(400000, 0).addExecutorNativeDropOption(
                uint128(feeForTokenTransfer.nativeFee), 
                bytes32(uint256(uint160(dstGlobalVariablesAddress)))
            );

        }else if(_functionToDo == FunctionToDo.NATIVE_TRANSFER){

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0).addExecutorNativeDropOption(
                uint128(feeForNativeTransfer.nativeFee), 
                bytes32(uint256(uint160(dstGlobalVariablesAddress)))
            );
        }else if(_functionToDo == FunctionToDo.BOTH_TRANSFER){

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(400000, 0).addExecutorNativeDropOption(
                // 104083014000000000,
                uint128(feeForTokenTransfer.nativeFee + (feeForNativeTransfer.nativeFee - _nativeTokenTransferData.nativeTokensToSend)),
                bytes32(uint256(uint160(dstGlobalVariablesAddress)))
            );
        }

        _fee = quoteInternal(
                dstEid, 
                _functionToDo, 
                _oftTransferData.tokensToSend,
                _oftTransferData.tokensToSend,
                _oftTransferData.tokensToSend,
                CDSInterface.LiquidationInfo(0,0,0,0),
                0,
                _oftTransferData,
                _nativeTokenTransferData,
                _options, 
                false);

        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(dstEid, _payload, _options, _fee, payable(_refundAddress));
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
    ) internal view returns (MessagingFee memory fee) {

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
    ) external payable onlyCoreContracts returns (MessagingReceipt memory receipt){
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

    function sendForLiquidation(        
        FunctionToDo _functionToDo,
        uint128 _liqIndex,
        CDSInterface.LiquidationInfo memory _liquidationInfo,
        MessagingFee memory _fee,
        bytes memory _options,
        address _refundAddress
    ) external payable onlyCoreContracts returns (MessagingReceipt memory receipt){
        return sendInternal(
            dstEid,
            _functionToDo,
            0,0,0,
            _liquidationInfo,
            _liqIndex,
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

            treasury.transferFundsToGlobal(oftTransferData.tokensToSend, 0);
            usda.send{ value: _fee.nativeFee}( _sendParam, _fee, address(this));

        }else if(functionToDo == FunctionToDo.NATIVE_TRANSFER || functionToDo == FunctionToDo.BOTH_TRANSFER){

            _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(280000, 0).addExecutorNativeDropOption(
                uint128(nativeTokenTransferData.nativeTokensToSend), 
                bytes32(uint256(uint160(nativeTokenTransferData.recipient)))
            );

                        // _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(60000, 0);


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

            treasury.transferFundsToGlobal(oftTransferData.tokensToSend,nativeTokenTransferData.nativeTokensToSend);
            usda.send{ value: _fee.nativeFee}( _sendParam, _fee, address(this));

        }
        cds.updateTotalCdsDepositedAmountWithOptionFees(uint128(optionsFeesToRemove));
        cds.updateTotalCdsDepositedAmount(uint128(cdsAmountToRemove));
        cds.updateTotalAvailableLiquidationAmount(liqAmountToRemove);
        cds.updateLiquidationInfo(liqIndex, liquidationInfo);

        omniChainData = message;

    }
    receive() external payable{}
}