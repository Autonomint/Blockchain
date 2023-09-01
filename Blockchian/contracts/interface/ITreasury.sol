// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

interface ITreasury{
        function deposit(address user,uint128 _ethPrice,uint64 _depositTime) external payable returns(bool,uint64);
        function withdraw(address toAddress,uint256 _amount) external;
        function depositToAave() external;
        function withdrawFromAave(uint64 index,uint256 amount) external;
        function depositToCompound() external;
        function withdrawFromCompound(uint64 index) external;
        function getBalanceInTreasury() external view returns(uint256);

        function noOfBorrowers() external returns(uint128);
        function totalVolumeOfBorrowersAmountinWei() external returns(uint256);
        function totalVolumeOfBorrowersAmountinUSD() external returns(uint256);
        function totalInterest() external returns(uint256);

        event Deposit(address indexed user,uint256 amount);
        event Withdraw(address indexed user,uint256 amount);
        event DepositToAave(uint256 amount);
        event WithdrawFromAave(uint256 amount);
}