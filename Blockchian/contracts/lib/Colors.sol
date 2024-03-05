// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity ^0.8.0;

import {State} from "../interface/IAbond.sol";

library Colors {

    error InvalidUser();
    error InvalidCumulativeRate();
    error InvalidEthBacked();
    error InsufficientBalance();
    error InvalidAmount();

    function _credit(
        State memory _fromState,
        State memory _toState,
        uint64 _amount
    ) internal pure returns(State memory){

        // increment the balance
        _toState.cumulativeRate = _calculateCumulativeRate(_amount, _toState.aBondBalance, _fromState.cumulativeRate, _toState.cumulativeRate);
        _toState.ethBacked = _calculateEthBacked(_amount, _toState.aBondBalance, _fromState.ethBacked, _toState.ethBacked);
        _toState.aBondBalance += _amount;

        return _toState;
    }

    function _debit(
        State memory _fromState,
        uint64 _amount
    ) internal pure returns(State memory) {

        uint64 balance = _fromState.aBondBalance;
        
        require(balance < _amount,"InsufficientBalance");
 
        _fromState.aBondBalance = balance - _amount;

        if(_fromState.aBondBalance == 0){
            _fromState.cumulativeRate = 0;
            _fromState.ethBacked = 0;
        }
        return _fromState;
    }

    function _calculateCumulativeRate(uint64 _balanceA, uint64 _balanceB, uint128 _crA, uint128 _crB) internal pure returns(uint128){
        if (_balanceA == 0) revert InsufficientBalance();
        if (_crA == 0) revert InvalidCumulativeRate();
        uint128 currentCumulativeRate;
        currentCumulativeRate = ((_balanceA * _crA)+(_balanceB * _crB))/(_balanceA + _balanceB); 
        return currentCumulativeRate;
    }

    function _calculateEthBacked(uint64 _balanceA, uint64 _balanceB, uint128 _ethBackedA, uint128 _ethBackedB) internal pure returns(uint128){
        if (_balanceA == 0) revert InsufficientBalance();
        if (_ethBackedA == 0) revert InvalidEthBacked();
        uint128 currentEthBacked;
        currentEthBacked = ((_balanceA * _ethBackedA)+(_balanceB * _ethBackedB))/(_balanceA + _balanceB); 
        return currentEthBacked;
    }
}
