// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

interface IOptions{
    enum StrikePrice{FIVE,TEN,FIFTEEN,TWENTY,TWENTY_FIVE}
    function calculateStrikePriceGains(uint128 depositedAmount,uint128 strikePrice,uint64 ethPrice) external pure returns(uint128);
    function calculateOptionPrice(uint128 _ethPrice,uint256 _ethVolatility,uint256 _amount,StrikePrice _strikePrice) external returns (uint256);

}