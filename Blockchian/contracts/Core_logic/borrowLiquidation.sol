// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

import "../interface/ITreasury.sol";
import "../interface/IBorrowing.sol";
import "../interface/CDSInterface.sol";
import "../interface/IUSDa.sol";
import "../interface/IBorrowLiquidation.sol";

import { BorrowLib } from "../lib/BorrowLib.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract BorrowLiquidation is IBorrowLiquidation,Initializable,OwnableUpgradeable,UUPSUpgradeable,ReentrancyGuardUpgradeable{

    IBorrowing borrowing;
    ITreasury treasury;
    CDSInterface cds;
    IUSDa usda;

    using OptionsBuilder for bytes;

    function initialize(
        address _borrowing,
        address _cds,
        address _usda
    ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        borrowing = IBorrowing(_borrowing);
        cds = CDSInterface(_cds);
        usda = IUSDa(_usda);
    }

    function _authorizeUpgrade(address implementation) internal onlyOwner override{}

    modifier onlyBorrowingContract() {
        require( msg.sender == address(borrowing), "This function can only called by borrowing contract");
        _;
    }
    
    // Function to check if an address is a contract
    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
    return size > 0;
    }

    /**
     * @dev set Treasury contract
     * @param _treasury treasury contract address
     */

    function setTreasury(address _treasury) external onlyOwner{
        require(_treasury != address(0) && isContract(_treasury) != false, "Treasury must be contract address & can't be zero address");
        treasury = ITreasury(_treasury);
    }

    /**
     * @dev This function liquidate ETH which are below downside protection.
     * @param _user The address to whom to liquidate ETH.
     * @param _index Index of the borrow
     */

    function liquidateBorrowPosition(
        address _user,
        uint64 _index,
        uint64 _currentEthPrice,
        uint128 _globalNoOfLiquidations,
        uint256 _lastCumulativeRate,
        uint32 _dstEid
    ) external payable onlyBorrowingContract{

        // Get the borrower details
        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(_user,_index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
        require(!depositDetail.liquidated,"Already Liquidated");
        
        // uint256 externalProtocolInterest = treasury.withdrawFromExternalProtocol(borrower,10000); // + treasury.withdrawFromCompoundByUser(borrower,index);

        require(
            depositDetail.depositedAmount <= (
                treasury.omniChainTreasuryTotalVolumeOfBorrowersAmountinWei() - treasury.omniChainTreasuryEthProfitsOfLiquidators())
            ,"Not enough funds in treasury");

        // Check whether the position is eligible or not for liquidation
        uint128 ratio = BorrowLib.calculateEthPriceRatio(depositDetail.ethPriceAtDeposit,_currentEthPrice);
        require(ratio <= 8000,"You cannot liquidate, ratio is greater than 0.8");

        //Update the position to liquidated     
        depositDetail.liquidated = true;

        // Calculate borrower's debt 
        uint256 borrowerDebt = ((depositDetail.normalizedAmount * _lastCumulativeRate)/BorrowLib.RATE_PRECISION);
        uint128 returnToTreasury = uint128(borrowerDebt);

        // 20% to abond usda pool
        uint128 returnToAbond = BorrowLib.calculateReturnToAbond(
            depositDetail.depositedAmount,
            depositDetail.ethPriceAtDeposit, 
            returnToTreasury);
        treasury.updateAbondUSDaPool(returnToAbond,true);
        // CDS profits
        uint128 cdsProfits = (((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/BorrowLib.USDA_PRECISION)/100) - returnToTreasury - returnToAbond;
        uint128 liquidationAmountNeeded = returnToTreasury + returnToAbond;
        require(cds.omniChainCDSTotalAvailableLiquidationAmount() >= liquidationAmountNeeded,"Don't have enough USDa in CDS to liquidate");
        
        CDSInterface.LiquidationInfo memory liquidationInfo;
        liquidationInfo = CDSInterface.LiquidationInfo(
            liquidationAmountNeeded,
            cdsProfits,
            depositDetail.depositedAmount,
            cds.omniChainCDSTotalAvailableLiquidationAmount());

        uint256 liqAmountToGetFromOtherChain = BorrowLib.getLiquidationAmountProportions(
            liquidationAmountNeeded,
            cds.totalCdsDepositedAmount(),
            cds.omniChainCDSTotalCdsDepositedAmount(),
            cds.totalAvailableLiquidationAmount(),
            cds.omniChainCDSTotalAvailableLiquidationAmount()
        );

        uint128 cdsProfitsForOtherChain = BorrowLib.getCdsProfitsProportions(
            liquidationAmountNeeded,
            uint128(liqAmountToGetFromOtherChain),
            cdsProfits);

        uint128 cdsAmountToGetFromThisChain = (liquidationAmountNeeded - uint128(liqAmountToGetFromOtherChain)) - (cdsProfits - cdsProfitsForOtherChain);

        cds.updateLiquidationInfo(_globalNoOfLiquidations,liquidationInfo);
        cds.updateTotalCdsDepositedAmount(cdsAmountToGetFromThisChain);
        cds.updateTotalCdsDepositedAmountWithOptionFees(cdsAmountToGetFromThisChain);
        cds.updateTotalAvailableLiquidationAmount(cdsAmountToGetFromThisChain);
        treasury.updateEthProfitsOfLiquidators(depositDetail.depositedAmount,true);

        // Update totalInterestFromLiquidation
        uint256 totalInterestFromLiquidation = uint256(borrowerDebt - depositDetail.borrowedAmount);
        treasury.updateTotalInterestFromLiquidation(totalInterestFromLiquidation);
        treasury.updateDepositDetails(_user,_index,depositDetail);

        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        MessagingFee memory cdsLzFee = cds.quote(
            _dstEid, 
            CDSInterface.FunctionToDo(2), 
            liqAmountToGetFromOtherChain, 
            liqAmountToGetFromOtherChain, 
            liqAmountToGetFromOtherChain,
            liquidationInfo, 
            _globalNoOfLiquidations,  
            _options, 
            false);

        if(liqAmountToGetFromOtherChain > 0){
            treasury.oftOrNativeReceiveFromOtherChains{ value: msg.value - cdsLzFee.nativeFee}(
                ITreasury.FunctionToDo(2),
                ITreasury.USDaOftTransferData( address(treasury), liqAmountToGetFromOtherChain),
                ITreasury.NativeTokenTransferData(address(0), 0));
        }

        cds.callLzSendFromExternal{ value: cdsLzFee.nativeFee}(
            _dstEid,
            CDSInterface.FunctionToDo(2),
            liqAmountToGetFromOtherChain,
            liqAmountToGetFromOtherChain,
            liqAmountToGetFromOtherChain,
            liquidationInfo,
            _globalNoOfLiquidations,
            cdsLzFee,
            _options
        );

        // Burn the borrow amount
        treasury.approveUSDa(address(this),depositDetail.borrowedAmount);
        bool success = usda.burnFromUser(address(treasury), depositDetail.borrowedAmount);
        if(!success){
            revert BorrowLiquidation_LiquidateBurnFailed();
        }
        if(liqAmountToGetFromOtherChain == 0){
            (bool sent,) = payable(_user).call{value: msg.value - cdsLzFee.nativeFee}("");
            require(sent, "Failed to send Ether");
        }
        // Transfer ETH to CDS Pool
        emit Liquidate(_index,liquidationAmountNeeded,cdsProfits,depositDetail.depositedAmount,cds.totalAvailableLiquidationAmount());
    }
}