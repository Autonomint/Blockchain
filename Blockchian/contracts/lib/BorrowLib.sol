// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.20;

import { State, IABONDToken } from "../interface/IAbond.sol";
import "../interface/ITreasury.sol";
import "../interface/IUSDa.sol";
import "../interface/IBorrowing.sol";
import "../interface/IGlobalVariables.sol";
import "hardhat/console.sol";


library BorrowLib {

    uint128 constant PRECISION = 1e6;
    uint128 constant CUMULATIVE_PRECISION = 1e7;
    uint128 constant RATIO_PRECISION = 1e4;
    uint128 constant RATE_PRECISION = 1e27;
    uint128 constant USDA_PRECISION = 1e12;
    uint128 constant LIQ_AMOUNT_PRECISION = 1e10;

    string  public constant name = "Autonomint USD";
    string  public constant version = "1";
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 allowedAmount,bool allowed,uint256 expiry)");

    function calculateHalfValue(uint256 amount) public pure returns(uint128){
        return uint128((amount * 50)/100);
    }

    function calculateNormAmount(
        uint256 amount,
        uint256 cumulativeRate
    ) public pure returns(uint256){
        return (amount * RATE_PRECISION)/cumulativeRate;
    }

    function calculateDebtAmount(
        uint256 amount,
        uint256 cumulativeRate
    ) public pure returns(uint256){
        return (amount * cumulativeRate)/RATE_PRECISION;
    }

    function calculateEthPriceRatio(
        uint128 depositEthPrice, 
        uint128 currentEthPrice
    ) public pure returns(uint128){
        return (currentEthPrice * 10000)/depositEthPrice;
    }

    function calculateDiscountedETH(
        uint256 amount,
        uint128 ethPrice
    ) public pure returns(uint256){
        return ((((80*calculateHalfValue(amount))/100)*ethPrice)/100)/USDA_PRECISION;
    }

    function calculateReturnToAbond(
        uint128 depositedAmount,
        uint128 depositEthPrice,
        uint128 returnToTreasury
    ) public pure returns(uint128){
        return (((((depositedAmount * depositEthPrice)/USDA_PRECISION)/100) - returnToTreasury) * 10)/100;
    }
    
    function calculateRatio(
        uint256 _amount,
        uint currentEthPrice,
        uint128 lastEthprice,
        uint128 noOfBorrowers,
        uint256 latestTotalCDSPool,
        IGlobalVariables.OmniChainData memory previousData
    ) public pure returns(uint64, IGlobalVariables.OmniChainData memory){

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
            previousData.cdsPoolValue = currentCDSPoolValue;
            currentCDSPoolValue = currentCDSPoolValue * USDA_PRECISION;

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
            currentCDSPoolValue = previousData.cdsPoolValue * USDA_PRECISION;
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

    function tokensToLend(
        uint256 depositedAmont, 
        uint128 ethPrice, 
        uint8 LTV
    ) public pure returns(uint256){
        uint256 tokens = (depositedAmont * ethPrice * LTV) / (USDA_PRECISION * RATIO_PRECISION);
        return tokens;
    }

    function abondToMint(
        uint256 _amount, 
        uint64 _bondRatio
    ) public pure returns(uint128 amount){
        amount = (uint128(_amount) * USDA_PRECISION)/_bondRatio;
    }

    function calculateBaseToMultiply(uint32 usdaPrice) public pure returns (uint16 baseToMultiply){
        if(usdaPrice < 9500){
            baseToMultiply = 50;
        }else if(usdaPrice < 9700 && usdaPrice >= 9500){
            baseToMultiply = 30;
        }else if(usdaPrice < 9800 && usdaPrice >= 9700){
            baseToMultiply = 20;
        }else if(usdaPrice < 9900 && usdaPrice >= 9800){
            baseToMultiply = 15;
        }else if(usdaPrice < 10100 && usdaPrice >= 9900){
            baseToMultiply = 10;
        }else if(usdaPrice < 10200 && usdaPrice >= 10100){
            baseToMultiply = 8;
        }else if(usdaPrice < 10500 && usdaPrice >= 10200){
            baseToMultiply = 5;
        }else{
            baseToMultiply = 1;
        }
    }

    function calculateNewAPRToUpdate(uint32 usdaPrice) public pure returns(uint128 newAPR){
        require(usdaPrice != 0, "Invalid USDa price");
        uint32 newBorrowingFeesRate = 5 * calculateBaseToMultiply(usdaPrice);
        if(newBorrowingFeesRate == 250){
            newAPR = 1000000007075835619725814915;
        }else if (newBorrowingFeesRate == 150){
            newAPR = 1000000004431822129783699001;
        }else if(newBorrowingFeesRate == 100){
            newAPR = 1000000003022265980097387650;
        }else if(newBorrowingFeesRate == 75){
            newAPR = 1000000002293273137447730714;
        }else if(newBorrowingFeesRate == 50){
            newAPR = 1000000001547125957863212448;
        }else if(newBorrowingFeesRate == 40){
            newAPR = 1000000001243680656318820312;
        }else if(newBorrowingFeesRate == 25){
            newAPR = 1000000000782997609082909351;
        }else if(newBorrowingFeesRate == 5){
            newAPR = 1000000000158153903837946257;
        }
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

        uint128 usdaToAbondRatioLiq = uint64(treasury.usdaGainedFromLiquidation() * RATE_PRECISION/ abond.totalSupply());
        uint256 usdaToTransfer = (usdaToAbondRatioLiq * aBondAmount) / RATE_PRECISION;

        return (depositedAmount,redeemableAmount,usdaToTransfer);
    }

    function getLiquidationAmountProportions(
        uint256 _liqAmount,
        uint256 _totalCdsDepositedAmount,
        uint256 _totalGlobalCdsDepositedAmount,
        uint256 _totalAvailableLiqAmount,
        uint256 _totalGlobalAvailableLiqAmountAmount
    ) public pure returns (uint256){

        uint256 otherChainCDSAmount = _totalGlobalCdsDepositedAmount - _totalCdsDepositedAmount;

        uint256 totalAvailableLiqAmountInOtherChain = _totalGlobalAvailableLiqAmountAmount - _totalAvailableLiqAmount;

        uint256 share = (otherChainCDSAmount * LIQ_AMOUNT_PRECISION)/_totalGlobalCdsDepositedAmount;
        uint256 liqAmountToGet = (_liqAmount * share)/LIQ_AMOUNT_PRECISION;
        uint256 liqAmountRemaining = _liqAmount - liqAmountToGet;

        if(totalAvailableLiqAmountInOtherChain == 0){
            liqAmountToGet = 0;
        }else{
            if(totalAvailableLiqAmountInOtherChain < liqAmountToGet) {
                liqAmountToGet = totalAvailableLiqAmountInOtherChain;
            }else{
                if(totalAvailableLiqAmountInOtherChain > liqAmountToGet && _totalAvailableLiqAmount < liqAmountRemaining){
                    liqAmountToGet += liqAmountRemaining - _totalAvailableLiqAmount;
                }else{
                    liqAmountToGet = liqAmountToGet;
                }
            }
        }
        return liqAmountToGet;
    }

    function getCdsProfitsProportions(
        uint128 _liqAmount,
        uint128 _liqAmountToGetFromOtherChain,
        uint128 _cdsProfits
    ) public pure returns (uint128){

        uint128 share = (_liqAmountToGetFromOtherChain * LIQ_AMOUNT_PRECISION)/_liqAmount;
        uint128 cdsProfitsForOtherChain = (_cdsProfits * share)/LIQ_AMOUNT_PRECISION;

        return cdsProfitsForOtherChain;
    }

    function redeemYields(
        address user,
        uint128 aBondAmount,
        address usdaAddress,
        address abondAddress,
        address treasuryAddress
    ) public returns(uint256){

        require(aBondAmount > 0,"Abond amount should not be zero");
        IABONDToken abond = IABONDToken(abondAddress);

        State memory userState = abond.userStates(user);
        require(aBondAmount <= userState.aBondBalance,"You don't have enough aBonds");

        ITreasury treasury = ITreasury(treasuryAddress);
        uint128 usdaToAbondRatio = uint128(treasury.abondUSDaPool() * RATE_PRECISION/ abond.totalSupply());
        uint256 usdaToBurn = (usdaToAbondRatio * aBondAmount) / RATE_PRECISION;
        treasury.updateAbondUSDaPool(usdaToBurn,false);

        uint128 usdaToAbondRatioLiq = uint128(treasury.usdaGainedFromLiquidation() * RATE_PRECISION/ abond.totalSupply());
        uint256 usdaToTransfer = (usdaToAbondRatioLiq * aBondAmount) / RATE_PRECISION;
        treasury.updateUSDaGainedFromLiquidation(usdaToTransfer,false);

        //Burn the usda from treasury
        treasury.approveUSDa(address(this),(usdaToBurn + usdaToTransfer));

        IUSDa usda = IUSDa(usdaAddress);
        bool burned = usda.burnFromUser(address(treasury),usdaToBurn);
        if(!burned){
            revert ('Borrowing_RedeemBurnFailed');
        }
        
        if(usdaToTransfer > 0){
            bool transferred = usda.transferFrom(address(treasury),user,usdaToTransfer);
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

    function _rpow(uint x, uint n, uint b) public pure returns (uint z) {
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
