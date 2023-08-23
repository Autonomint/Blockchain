// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

interface ITreasury{
        function deposit(address user,uint64 _ethPrice,uint64 _depositTime) external payable returns(bool);
        function depositToAave() external;
        function withdrawFromAave(uint64 index,uint256 amount) external;
        function depositToCompound() external;
        function withdrawFromCompound(uint64 index) external;
        function getBalanceInTreasury() external view returns(uint256);
        function noOfBorrowers() external returns(uint128);

        //function getUserAccountData (address user) external view returns();

        event Deposit(address indexed user,uint256 amount);
        event Withdraw(address indexed user,uint256 amount);
        event DepositToAave(uint256 amount);
        event WithdrawFromAave(uint256 amount);
}