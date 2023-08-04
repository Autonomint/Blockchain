// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

interface IBorrowing{
    function getUSDValue() internal view returns(uint256);
}