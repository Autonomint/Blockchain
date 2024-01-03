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
            uint64 strikePrice;
            uint64 externalProtocolCount;
        }

        function deposit(address user,uint128 _ethPrice,uint64 _depositTime) external payable returns(bool,uint64);
        function withdraw(address borrower,address toAddress,uint256 _amount,uint64 index,uint64 ethPrice) external returns(bool);
        function depositToAave() external;
        function withdrawFromAave(uint64 index) external;
        function depositToCompound() external;
        function withdrawFromCompound(uint64 index) external;
        function getBalanceInTreasury() external view returns(uint256);
        function approveAmint(address _address, uint _amount) external;
        function approveUsdt(address _address, uint _amount) external;
        function transferEthToCdsLiquidators(address borrower,uint128 amount) external;


        function noOfBorrowers() external returns(uint128);
        function totalVolumeOfBorrowersAmountinUSD() external view returns(uint256);

        function updateHasBorrowed(address borrower,bool _bool) external;
        function updateTotalDepositedAmount(address borrower,uint128 amount) external;
        function updateTotalBorrowedAmount(address borrower,uint256 amount) external;
        function updateTotalPTokensIncrease(address borrower,uint128 amount) external;
        function updateTotalPTokensDecrease(address borrower,uint128 amount) external;

        function getBorrowing(address depositor,uint64 index) external view returns(uint64,DepositDetails memory);
        function updateDepositDetails(address depositor,uint64 index,DepositDetails memory depositDetail) external;
        function updateTotalInterest(uint _amount) external;
        function updateTotalInterestFromLiquidation(uint _amount) external;

        event Deposit(address indexed user,uint256 amount);
        event Withdraw(address indexed user,uint256 amount);
        event DepositToAave(uint256 amount);
        event WithdrawFromAave(uint256 amount);
}