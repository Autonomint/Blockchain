// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

interface IBorrowLiquidation{

    error BorrowLiquidation_LiquidateBurnFailed();

    function liquidateBorrowPosition(
        address _user,
        uint64 _index,
        uint64 _currentEthPrice,
        uint128 _globalNoOfLiquidations,
        uint256 _lastCumulativeRate
    ) external payable;

    event Liquidate(uint64 index,uint128 liquidationAmount,uint128 profits,uint128 ethAmount,uint256 availableLiquidationAmount);

}