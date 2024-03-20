// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.20;

import { RatioReturnData } from "../interface/IBorrowing.sol";
library Colors {

    uint128 constant CUMULATIVE_PRECISION = 1e7;
    uint128 constant AMINT_PRECISION = 1e12;
    /**
     * @dev calculate the ratio of CDS Pool/Eth Vault
     * @param _amount amount to be depositing
     * @param currentEthPrice current eth price in usd
     */
    function calculateRatio(
        uint128 noOfBorrowers,
        uint256 lastEthVaultValue,
        uint256 lastCDSPoolValue,
        uint256 lastTotalCDSPool,
        uint256 latestTotalCDSPool,
        uint256 _amount,
        uint128 lastEthprice,
        uint128 currentEthPrice
    ) public pure returns(RatioReturnData memory){

        uint256 netPLCdsPool;

        // Calculate net P/L of CDS Pool
        if(currentEthPrice > lastEthprice){
            netPLCdsPool = (currentEthPrice - lastEthprice) * noOfBorrowers;
        }else{
            netPLCdsPool = (lastEthprice - currentEthPrice) * noOfBorrowers;
        }

        uint256 currentEthVaultValue;
        uint256 currentCDSPoolValue;
 
        // Check it is the first deposit
        if(noOfBorrowers == 0){

            // Calculate the ethVault value
            lastEthVaultValue = _amount * currentEthPrice;

            // Set the currentEthVaultValue to lastEthVaultValue for next deposit
            currentEthVaultValue = lastEthVaultValue;

            // Get the total amount in CDS
            lastTotalCDSPool = latestTotalCDSPool;

            if (currentEthPrice >= lastEthprice){
                lastCDSPoolValue = lastTotalCDSPool + netPLCdsPool;
            }else{
                lastCDSPoolValue = lastTotalCDSPool - netPLCdsPool;
            }

            // Set the currentCDSPoolValue to lastCDSPoolValue for next deposit
            currentCDSPoolValue = lastCDSPoolValue * AMINT_PRECISION;
        }else{

            currentEthVaultValue = lastEthVaultValue + (_amount * currentEthPrice);
            lastEthVaultValue = currentEthVaultValue;

            if(currentEthPrice >= lastEthprice){
                if(latestTotalCDSPool > lastTotalCDSPool){
                    lastCDSPoolValue = lastCDSPoolValue + (latestTotalCDSPool - lastTotalCDSPool) + netPLCdsPool;  
                }else{
                    lastCDSPoolValue = lastCDSPoolValue - (lastTotalCDSPool - latestTotalCDSPool) + netPLCdsPool;
                }
            }else{
                if(latestTotalCDSPool > lastTotalCDSPool){
                    lastCDSPoolValue = lastCDSPoolValue + (latestTotalCDSPool - lastTotalCDSPool) - netPLCdsPool;  
                }else{
                    lastCDSPoolValue = lastCDSPoolValue - (lastTotalCDSPool - latestTotalCDSPool) - netPLCdsPool;
                }
            }

            lastTotalCDSPool = latestTotalCDSPool;
            currentCDSPoolValue = lastCDSPoolValue * AMINT_PRECISION;
        }

        // Calculate ratio by dividing currentEthVaultValue by currentCDSPoolValue,
        // since it may return in decimals we multiply it by 1e6
        uint64 ratio = uint64((currentCDSPoolValue * CUMULATIVE_PRECISION)/currentEthVaultValue);

        return RatioReturnData(lastEthVaultValue,lastCDSPoolValue,lastTotalCDSPool,ratio);
    }
}
