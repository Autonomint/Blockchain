// SPDX-License-Identifier: unlicensed

pragma solidity ^0.8.18;

interface IMultiSign{
    function approve() external;
    function execute() external returns (bool);
}