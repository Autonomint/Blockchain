// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.20;

import { State, IABONDToken } from "../interface/IAbond.sol";
import "../interface/ITreasury.sol";
import "../interface/IAmint.sol";
import "../interface/IBorrowing.sol";
import "hardhat/console.sol";


library BorrowLib {

    uint128 constant PRECISION = 1e6;
    uint128 constant CUMULATIVE_PRECISION = 1e7;
    uint128 constant RATIO_PRECISION = 1e4;
    uint128 constant RATE_PRECISION = 1e27;
    uint128 constant AMINT_PRECISION = 1e12;

    function calculateRatio(
        uint256 _amount,
        uint currentEthPrice,
        uint128 lastEthprice,
        uint128 noOfBorrowers,
        uint256 latestTotalCDSPool,
        IBorrowing.OmniChainBorrowingData memory previousData) public pure returns(uint64, IBorrowing.OmniChainBorrowingData memory){

        uint256 netPLCdsPool;

        // Calculate net P/L of CDS Pool
        if(currentEthPrice > lastEthprice){
            netPLCdsPool = (currentEthPrice - lastEthprice) * noOfBorrowers;
        }else{
            netPLCdsPool = (lastEthprice - currentEthPrice) * noOfBorrowers;
        }

        uint256 currentEthVaultValue;
        uint256 currentCDSPoolValue;
        
        // OmniChainBorrowingData memory previousData = omniChainBorrowing;
 
        // Check it is the first deposit
        if(noOfBorrowers == 0){

            // Calculate the ethVault value
            // lastEthVaultValue = _amount * currentEthPrice;
            previousData.ethVaultValue = _amount * currentEthPrice;
            // Set the currentEthVaultValue to lastEthVaultValue for next deposit
            currentEthVaultValue = previousData.ethVaultValue;

            // Get the total amount in CDS
            // lastTotalCDSPool = cds.totalCdsDepositedAmount();
            previousData.totalCDSPool = latestTotalCDSPool;

            if (currentEthPrice >= lastEthprice){
                currentCDSPoolValue = previousData.totalCDSPool + netPLCdsPool;
            }else{
                currentCDSPoolValue = previousData.totalCDSPool - netPLCdsPool;
            }

            // Set the currentCDSPoolValue to lastCDSPoolValue for next deposit
            currentCDSPoolValue = currentCDSPoolValue * AMINT_PRECISION;
            previousData.cdsPoolValue = currentCDSPoolValue;

        }else{

            currentEthVaultValue = previousData.ethVaultValue + (_amount * currentEthPrice);
            previousData.ethVaultValue = currentEthVaultValue;


            if(currentEthPrice >= lastEthprice){
                if(latestTotalCDSPool > previousData.totalCDSPool){
                    previousData.cdsPoolValue = previousData.cdsPoolValue + (
                        latestTotalCDSPool - previousData.totalCDSPool) + netPLCdsPool;  
                }else{
                    previousData.cdsPoolValue = previousData.cdsPoolValue - (
                        previousData.totalCDSPool - latestTotalCDSPool) + netPLCdsPool;
                }
            }else{
                if(latestTotalCDSPool > previousData.totalCDSPool){
                    previousData.cdsPoolValue = previousData.cdsPoolValue + (
                        latestTotalCDSPool - previousData.totalCDSPool) - netPLCdsPool;  
                }else{
                    previousData.cdsPoolValue = previousData.cdsPoolValue - (
                        previousData.totalCDSPool - latestTotalCDSPool) - netPLCdsPool;
                }
            }

            previousData.totalCDSPool = latestTotalCDSPool;
            currentCDSPoolValue = previousData.cdsPoolValue * AMINT_PRECISION;
        }

        // Calculate ratio by dividing currentEthVaultValue by currentCDSPoolValue,
        // since it may return in decimals we multiply it by 1e6
        uint64 ratio = uint64((currentCDSPoolValue * CUMULATIVE_PRECISION)/currentEthVaultValue);
        return (ratio, previousData);
    }

    function calculateCumulativeRate(
        uint128 noOfBorrowers,
        uint256 ratePerSec,
        uint128 lastEventTime,
        uint256 lastCumulativeRate
    ) public view returns (uint256) {
        uint256 currentCumulativeRate;

        if (noOfBorrowers == 0) {
            currentCumulativeRate = ratePerSec;
        } else {
            uint256 timeInterval = uint128(block.timestamp) - lastEventTime;
            currentCumulativeRate = lastCumulativeRate * _rpow(ratePerSec, timeInterval, RATE_PRECISION);
            currentCumulativeRate = currentCumulativeRate / RATE_PRECISION;
        }
        return currentCumulativeRate;
    }

    function tokensToLend(uint256 depositedAmont, uint128 ethPrice, uint8 LTV) public pure returns(uint256){
        uint256 tokens = (depositedAmont * ethPrice * LTV) / (AMINT_PRECISION * RATIO_PRECISION);
        return tokens;
    }

    function getAbondYields(
        address user,
        uint128 aBondAmount,
        address abondAddress,
        address treasuryAddress
    ) public view returns(uint128,uint256,uint256){
        require(aBondAmount > 0,"Abond amount should not be zero");
        
        IABONDToken abond = IABONDToken(abondAddress);
        State memory userState = abond.userStates(user);
        require(aBondAmount <= userState.aBondBalance,"You don't have enough aBonds");

        ITreasury treasury = ITreasury(treasuryAddress);

        uint256 redeemableAmount = treasury.calculateYieldsForExternalProtocol(user,aBondAmount);
        uint128 depositedAmount = (aBondAmount * userState.ethBacked)/1e18;

        uint128 amintToAbondRatioLiq = uint64(treasury.amintGainedFromLiquidation() * BorrowLib.RATE_PRECISION/ abond.totalSupply());
        uint256 amintToTransfer = (amintToAbondRatioLiq * aBondAmount) / BorrowLib.RATE_PRECISION;

        return (depositedAmount,redeemableAmount,amintToTransfer);
    }

    function redeemYields(
        address user,
        uint128 aBondAmount,
        address amintAddress,
        address abondAddress,
        address treasuryAddress
    ) public returns(uint256){

        require(aBondAmount > 0,"Abond amount should not be zero");
        IABONDToken abond = IABONDToken(abondAddress);

        State memory userState = abond.userStates(user);
        require(aBondAmount <= userState.aBondBalance,"You don't have enough aBonds");

        ITreasury treasury = ITreasury(treasuryAddress);
        uint128 amintToAbondRatio = uint128(treasury.abondAmintPool() * BorrowLib.RATE_PRECISION/ abond.totalSupply());
        uint256 amintToBurn = (amintToAbondRatio * aBondAmount) / BorrowLib.RATE_PRECISION;
        treasury.updateAbondAmintPool(amintToBurn,false);

        uint128 amintToAbondRatioLiq = uint128(treasury.amintGainedFromLiquidation() * BorrowLib.RATE_PRECISION/ abond.totalSupply());
        uint256 amintToTransfer = (amintToAbondRatioLiq * aBondAmount) / BorrowLib.RATE_PRECISION;
        treasury.updateAmintGainedFromLiquidation(amintToTransfer,false);

        //Burn the amint from treasury
        treasury.approveAmint(address(this),(amintToBurn + amintToTransfer));

        IAMINT amint = IAMINT(amintAddress);
        bool burned = amint.burnFromUser(address(treasury),amintToBurn);
        if(!burned){
            revert ('Borrowing_RedeemBurnFailed');
        }
        
        if(amintToTransfer > 0){
            bool transferred = amint.transferFrom(address(treasury),user,amintToTransfer);
            if(!transferred){
                revert ('Borrowing_RedeemTransferFailed');
            }
        }
        
        uint256 withdrawAmount = treasury.withdrawFromExternalProtocol(user,aBondAmount);

        //Burn the abond from user
        bool success = abond.burnFromUser(msg.sender,aBondAmount);
        if(!success){
            revert ('Borrowing_RedeemBurnFailed');
        }
        return withdrawAmount;
    }

    function _rpow(uint x, uint n, uint b) internal pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
}
