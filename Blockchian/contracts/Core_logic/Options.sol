// SPDX-License-Identifier: unlicensed

pragma solidity ^0.8.18;

import "../interface/ITreasury.sol";
import "../interface/CDSInterface.sol";

import "hardhat/console.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Options{

    AggregatorV3Interface internal priceFeed; //ETH USD pricefeed address
    uint256 private currentEMA;
    uint256 private constant smoothingFactor = 2;
    uint256 private index = 0; // To track the oldest variance
    uint256[30] private variances;
    uint256 PRECISION = 1e18;
    uint256 ETH_PRICE_PRECISION = 1e6;
    uint256 OPTION_PRICE_PRECISION = 1e5;

    // enum for different strike price percentages
    enum StrikePrice{FIVE,TEN,FIFTEEN,TWENTY,TWENTY_FIVE}

    ITreasury treasury;
    CDSInterface cds;

    constructor(address _priceFeed, address _treasuryAddress, address _cdsAddress) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        treasury = ITreasury(_treasuryAddress);
        cds = CDSInterface(_cdsAddress);
    }

    /**
     * calculate eth price gains for user
     * @param depositedAmount eth amount to be deposit
     * @param strikePrice strikePrice,not percent, price
     * @param ethPrice eth price
     */
    function withdrawOption(uint128 depositedAmount,uint128 strikePrice,uint64 ethPrice) external pure returns(uint128){
        require(depositedAmount != 0 && strikePrice != 0 && ethPrice != 0,"Zero inputs in options");
        uint64 currentEthPrice = ethPrice;
        uint128 currentEthValue = depositedAmount * currentEthPrice;
        uint128 ethToReturn;
        require(currentEthValue >= strikePrice);
        if(currentEthValue > strikePrice){
            ethToReturn = (currentEthValue - strikePrice)/currentEthPrice;
        }else{
            ethToReturn = 0;
        }
        return ethToReturn;
    }

    // Chainlink function to get the latest Ethereum price
    function getLatestPrice() public view returns (uint) {
        (
            ,int price,,,
        ) = priceFeed.latestRoundData();
        return (uint(price)/ETH_PRICE_PRECISION);
    }

    // Function to update EMA daily
    function updateDailyEMA() external {
        uint latestPrice = getLatestPrice();
        uint256 latestPriceUint = uint256(latestPrice);

        // Update EMA
        if (index < 30) {
            currentEMA = (currentEMA * index + latestPriceUint) / (index + 1); // Simple average for initial values
        } else {
            uint256 k = smoothingFactor / (31);
            currentEMA = latestPriceUint * k + currentEMA * (1 - k);
        }

        // Calculate and store variance
        uint256 deviation = latestPriceUint > currentEMA ? latestPriceUint - currentEMA : currentEMA - latestPriceUint;
        variances[index % 30] = deviation * deviation;
        
        index++;
    }

    // Function to calculate the standard deviation
    function calculateStandardDeviation() external view returns (uint256) {
        uint256 sum = 0;
        uint256 count = index < 30 ? index : 30; // Use all available variances

        for (uint256 i = 0; i < count; i++) {
            sum += variances[i];
        }

        uint256 meanVariance = sum / count;
        return sqrt(meanVariance);
    }

    // Function to calculate option price
    function calculateOptionPrice(uint128 _ethPrice,uint256 _ethVolatility,uint256 _amount,StrikePrice _strikePrice) public view returns (uint256) {
        //uint256 a = calculateStandardDeviation(); 
        uint256 a = _ethVolatility;
        uint256 ethPrice = _ethPrice;/*getLatestPrice();*/
        uint256 E = (treasury.totalVolumeOfBorrowersAmountinUSD() + (_amount * ethPrice));
        uint256 cdsVault = cds.totalCdsDepositedAmount();

        require(E != 0, "Treasury balance is zero");
        require(cdsVault != 0, "CDS Vault is zero");

        uint256 b = (cdsVault * 1e2)/ E;
        uint256 baseOptionPrice = ((sqrt(10 * a * ethPrice))*PRECISION)/OPTION_PRICE_PRECISION + (3 * PRECISION / b); // 1e18 is used to handle division precision

        uint256 optionPrice;
        // Calculate option fees based on strike price chose by user
        if(_strikePrice == StrikePrice.FIVE){
            // constant has extra 1e3 and volatility have 1e8
            optionPrice = baseOptionPrice + (400 * OPTION_PRICE_PRECISION * baseOptionPrice)/(3*a);
        }else if(_strikePrice == StrikePrice.TEN){
            optionPrice = baseOptionPrice + (100 * OPTION_PRICE_PRECISION * baseOptionPrice)/(3*a);
        }else if(_strikePrice == StrikePrice.FIFTEEN){
            optionPrice = baseOptionPrice + (50 * OPTION_PRICE_PRECISION * baseOptionPrice)/(3*a);
        }else if(_strikePrice == StrikePrice.TWENTY){
            optionPrice = baseOptionPrice + (10 * OPTION_PRICE_PRECISION * baseOptionPrice)/(3*a);
        }else if(_strikePrice == StrikePrice.TWENTY_FIVE){
            optionPrice = baseOptionPrice + (5 * OPTION_PRICE_PRECISION * baseOptionPrice)/(3*a);
        }else{
            revert("Incorrect Strike Price");
        }
        // console.log((optionPrice * _amount)/PRECISION);
        return (optionPrice * _amount)/PRECISION;
    }

    // Provided square root function
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}