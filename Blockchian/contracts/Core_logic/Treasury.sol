// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable{
    receive() external payable {}
}