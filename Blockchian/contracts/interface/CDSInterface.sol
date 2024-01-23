// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.18;

interface CDSInterface {

    struct CdsAccountDetails {
        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 withdrawedTime;
        uint128 withdrawedAmount;
        bool withdrawed;
        uint128 depositPrice;
        uint128 depositValue;
        bool optedLiquidation;
        uint128 profits; 
    }

    struct LiquidationInfo{
        uint128 liquidationAmount;
        uint128 profits;
        uint128 ethAmount;
        uint256 availableLiquidationAmount;
    }
    function pause() external;
    function unpause() external;
    function deposit(uint256 _amount, uint128 _timeStamp) external;
    function withdraw(address _to, uint96 _index, uint64 _withdrawTime) external;
    function withdraw_fee(address _to, uint96 _amount) external;
    function totalCdsDepositedAmount() external view returns(uint128);
    function amountAvailableToBorrow() external returns(uint128);
    function updateAmountAvailabletoBorrow(uint128 _updatedCdsPercentage) external;
    function approval(address _address, uint _amount) external;
    function cdsCount() external returns(uint256);
    function totalAvailableLiquidationAmount() external returns(uint256);

    function calculateCumulativeRate(uint128 fees) external returns(uint128);

    function getCDSDepositDetails(address depositor,uint64 index) external view returns(CdsAccountDetails memory);
    function updateTotalAvailableLiquidationAmount(uint256 amount) external;
    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external;
    function updateTotalCdsDepositedAmount(uint128 _amount) external;
}