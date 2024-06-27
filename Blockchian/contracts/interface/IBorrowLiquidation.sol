// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "./CDSInterface.sol";

interface IBorrowLiquidation{

    error BorrowLiquidation_LiquidateBurnFailed();

    function liquidateBorrowPosition(
        address _user,
        uint64 _index,
        uint64 _currentEthPrice,
        uint256 _lastCumulativeRate
    ) external payable returns(CDSInterface.LiquidationInfo memory);

    event Liquidate(uint64 index,uint128 liquidationAmount,uint128 profits,uint128 ethAmount,uint256 availableLiquidationAmount);

}