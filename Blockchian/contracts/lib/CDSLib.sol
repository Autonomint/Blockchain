// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.20;

import "../interface/ITreasury.sol";
import "../interface/IAmint.sol";
import "../interface/IBorrowing.sol";
import "../interface/CDSInterface.sol";
import "hardhat/console.sol";


library CDSLib {

    uint128 constant PRECISION = 1e12;
    uint128 constant RATIO_PRECISION = 1e4;

    function calculateValue(
        uint128 _price,
        uint256 totalCdsDepositedAmount,
        uint128 lastEthPrice,
        uint128 fallbackEthPrice,
        uint256  vaultBal
    ) public pure returns(CDSInterface.CalculateValueResult memory) {
        uint128 _amount = 1000;
        uint128 priceDiff;
        uint128 value;
        bool gains;

        if(totalCdsDepositedAmount == 0){
            value = 0;
            gains = true;
        }else{
            if(_price != lastEthPrice){
                // If the current eth price is higher than last eth price,then it is gains
                if(_price > lastEthPrice){
                    priceDiff = _price - lastEthPrice;
                    gains = true;    
                }else{
                    priceDiff = lastEthPrice - _price;
                    gains = false;
                }
            }
            else{
                // If the current eth price is higher than fallback eth price,then it is gains
                if(_price > fallbackEthPrice){
                    priceDiff = _price - fallbackEthPrice;
                    gains = true;   
                }else{
                    priceDiff = fallbackEthPrice - _price;
                    gains = false;
                }
            }
            // console.log("_amount",_amount);
            // console.log("vaultBal",vaultBal);
            // console.log("priceDiff",priceDiff);
            // console.log("totalCdsDepositedAmount",totalCdsDepositedAmount);

            value = uint128((_amount * vaultBal * priceDiff * 1e6) / (PRECISION * totalCdsDepositedAmount));
            // console.log("value",value);
        }
        return CDSInterface.CalculateValueResult(value,gains);
    }

    function getOptionsFeesProportions(
        uint256 optionsFees,
        uint256 _totalCdsDepositedAmount,
        uint256 _totalGlobalCdsDepositedAmount,
        uint256 _totalCdsDepositedAmountWithOptionFees,
        uint256 _totalGlobalCdsDepositedAmountWithOptionFees
    ) internal pure returns (uint256){
        uint256 otherChainCDSAmount = _totalGlobalCdsDepositedAmount - _totalCdsDepositedAmount;

        uint256 totalOptionFeesInOtherChain = _totalGlobalCdsDepositedAmountWithOptionFees
                - _totalCdsDepositedAmountWithOptionFees - otherChainCDSAmount;

        uint256 totalOptionFeesInThisChain = _totalCdsDepositedAmountWithOptionFees - _totalCdsDepositedAmount; 

        uint256 share = (otherChainCDSAmount * 1e10)/_totalGlobalCdsDepositedAmount;
        uint256 optionsfeesToGet = (optionsFees * share)/1e10;
        uint256 optionsFeesRemaining = optionsFees - optionsfeesToGet;

        if(totalOptionFeesInOtherChain == 0){
            optionsfeesToGet = 0;
        }else{
            if(totalOptionFeesInOtherChain < optionsfeesToGet) {
                optionsfeesToGet = totalOptionFeesInOtherChain;
            }else{
                if(totalOptionFeesInOtherChain > optionsfeesToGet && totalOptionFeesInThisChain < optionsFeesRemaining){
                    optionsfeesToGet += optionsFeesRemaining - totalOptionFeesInThisChain;
                }else{
                    optionsfeesToGet = optionsfeesToGet;
                }
            }
        }
        return optionsfeesToGet;
    }

    function setCumulativeValue(
        uint128 _value,
        bool _gains,
        bool _cumulativeValueSign,
        uint128 _cumulativeValue) internal pure returns(bool,uint128){
        if(_gains){
            // If the cumulativeValue is positive
            if(_cumulativeValueSign){
                // Add value to cumulativeValue
                _cumulativeValue += _value;
            }else{
                // if the cumulative value is greater than value 
                if(_cumulativeValue > _value){
                    // Remains in negative
                    _cumulativeValue -= _value;
                }else{
                    // Going to postive since value is higher than cumulative value
                    _cumulativeValue = _value - _cumulativeValue;
                    _cumulativeValueSign = true;
                }
            }
        }else{
            // If cumulative value is in positive
            if(_cumulativeValueSign){
                if(_cumulativeValue > _value){
                    // Cumulative value remains in positive
                    _cumulativeValue -= _value;
                }else{
                    // Going to negative since value is higher than cumulative value
                    _cumulativeValue = _value - _cumulativeValue;
                    _cumulativeValueSign = false;
                }
            }else{
                // Cumulative value is in negative
                _cumulativeValue += _value;
            }
        }

        return (_cumulativeValueSign, _cumulativeValue);
    }

    function calculateCumulativeRate(
        uint128 _fees,
        uint256 _totalCdsDepositedAmount,
        uint256 _totalCdsDepositedAmountWithOptionFees,
        uint256 _totalGlobalCdsDepositedAmountWithOptionFees,
        uint128 _lastCumulativeRate,
        uint128 _noOfBorrowers
    ) internal pure returns(uint256,uint256,uint128){

        require(_fees != 0,"Fees should not be zero");
        if(_totalCdsDepositedAmount > 0){
            _totalCdsDepositedAmountWithOptionFees += _fees;
        }
        _totalGlobalCdsDepositedAmountWithOptionFees += _fees;
        uint128 netCDSPoolValue = uint128(_totalGlobalCdsDepositedAmountWithOptionFees);
        uint128 percentageChange = (_fees * PRECISION)/netCDSPoolValue;
        uint128 currentCumulativeRate;
        if(_noOfBorrowers == 0){
            currentCumulativeRate = (1 * PRECISION) + percentageChange;
            _lastCumulativeRate = currentCumulativeRate;
        }else{
            currentCumulativeRate = _lastCumulativeRate * ((1 * PRECISION) + percentageChange);
            _lastCumulativeRate = (currentCumulativeRate/PRECISION);
        }

        return (_totalCdsDepositedAmountWithOptionFees,_totalGlobalCdsDepositedAmountWithOptionFees,_lastCumulativeRate);
    }
}