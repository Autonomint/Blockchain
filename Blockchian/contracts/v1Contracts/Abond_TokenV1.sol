// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

contract ABONDToken {
    
    mapping(address => bool) internal whitelist;
    address internal borrowingContract;
}
