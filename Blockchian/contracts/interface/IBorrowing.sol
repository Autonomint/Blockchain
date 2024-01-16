// SPDX-License-Identifier: unlicensed

pragma solidity ^0.8.18;

interface IBorrowing{
    function transferToken(address _borrower, uint64 borrowerIndex) external;
    function getUSDValue() external view returns(uint256);
    function noOfLiquidations() external view returns(uint128);
    function updateLastEthVaultValue(uint256 _amount) external;
}