// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.18;

interface CDSInterface {
    function deposit(uint256 _amount, uint128 _timeStamp) external;
    function withdraw(address _to, uint96 _index, uint64 _withdrawTime) external;
    function withdraw_fee(address _to, uint96 _amount) external;
    function totalCdsDepositedAmount() external returns(uint128);
    function amountAvailableToBorrow() external returns(uint128);
    function updateAmountAvailabletoBorrow(uint128 _updatedCdsPercentage) external;
    function approval(address _address, uint _amount) external;
    function cdsCount() external returns(uint256);
}