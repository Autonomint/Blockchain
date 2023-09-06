// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

interface ITreasury{

        struct DepositDetails{
                uint64 depositedTime;
                uint128 depositedAmount;
                uint64 downsidePercentage;
                uint128 ethPriceAtDeposit;
                uint128 borrowedAmount;
                uint128 normalizedAmount;
                uint8 withdrawNo;
                bool withdrawed;
                uint128 withdrawAmount;
                bool liquidated;
                uint64 ethPriceAtWithdraw;
                uint64 withdrawTime;
                uint128 pTokensAmount;
        }

        function deposit(address user,uint128 _ethPrice,uint64 _depositTime) external payable returns(bool,uint64);
        function withdraw(address borrower,address toAddress,uint256 _amount,uint64 index) external;
        function depositToAave() external;
        function withdrawFromAave(uint64 index,uint256 amount) external;
        function depositToCompound() external;
        function withdrawFromCompound(uint64 index) external;
        function getBalanceInTreasury() external view returns(uint256);

        function noOfBorrowers() external returns(uint128);
        function totalInterest() external returns(uint256);

        function updateHasBorrowed(address borrower,bool _bool) external;
        function updateTotalDepositedAmount(address borrower,uint128 amount) external;
        function updateTotalBorrowedAmount(address borrower,uint256 amount) external;
        function updateTotalPTokensIncrease(address borrower,uint128 amount) external;
        function updateTotalPTokensDecrease(address borrower,uint128 amount) external;


        function updateBorrowedAmount(address borrower,uint64 index,uint128 amount ) external;
        function updateNormalizedAmount(address borrower,uint64 index,uint128 amount) external;
        function updateWithdrawed(address borrower,uint64 index,bool _bool) external;
        function updateDepositedAmount(address borrower,uint64 index,uint128 amount) external;
        function updateethPriceAtWithdraw(address borrower,uint64 index,uint64 price) external;
        function updateWithdrawTime(address borrower,uint64 index,uint64 time) external;
        function updateWithdrawNo(address borrower,uint64 index,uint8 no) external;
        function updatePTokensAmount(address borrower,uint64 index,uint128 amount) external;

        function updateTotalInterest(uint _amount) external;

        function getBorrowing(address depositor,uint64 index) external view returns(uint64,DepositDetails memory);

        event Deposit(address indexed user,uint256 amount);
        event Withdraw(address indexed user,uint256 amount);
        event DepositToAave(uint256 amount);
        event WithdrawFromAave(uint256 amount);
}