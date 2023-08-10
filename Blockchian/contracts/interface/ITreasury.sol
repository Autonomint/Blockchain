// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

interface ITreasury{
        function deposit(address user,uint64 _ethPrice,uint64 _depositTime) external payable returns(uint64,bool);
        //function getUserAccountData (address user) external view returns();

        event Deposit(address indexed user,uint256 amount);
        event Withdraw(address indexed user,uint256 amount);
        event DepositToAave(uint256 amount);
        event WithdrawFromAave(uint256 amount);
}