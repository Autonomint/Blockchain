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
}