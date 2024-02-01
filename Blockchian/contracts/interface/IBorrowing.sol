// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.19;

interface IBorrowing{
    function pause() external;
    function unpause() external;
    function transferToken(address _borrower, uint64 borrowerIndex) external;
    function getUSDValue() external view returns(uint256);
    function noOfLiquidations() external view returns(uint128);
    function updateLastEthVaultValue(uint256 _amount) external;
    function calculateRatio(uint256 _amount,uint currentEthPrice) external returns(uint64);

}