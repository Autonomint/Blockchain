// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "../interface/ITreasury.sol";
import "../interface/CDSInterface.sol";
import "../interface/IBorrowing.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Options {

    // uint256 internal currentEMA;
    // uint256 internal constant smoothingFactor = 2;
    // uint256 internal index = 0; // To track the oldest variance
    // uint256[30] internal variances;
    uint256 internal PRECISION;
    uint256 internal ETH_PRICE_PRECISION;
    uint256 internal OPTION_PRICE_PRECISION;
    uint128 internal USDA_PRECISION;

    // enum for different strike price percentages
    enum StrikePrice{FIVE,TEN,FIFTEEN,TWENTY,TWENTY_FIVE}

    ITreasury treasury;
    CDSInterface cds;
    IBorrowing borrowing;
    AggregatorV3Interface internal priceFeed; //ETH USD pricefeed address

}