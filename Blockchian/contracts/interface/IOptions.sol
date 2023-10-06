// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

interface IOptions{
    function withdrawOption(uint128 depositedAmount,uint128 strikePrice,uint64 ethPrice) external pure returns(uint128);
}