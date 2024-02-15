// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

interface ITreasury{

    struct DepositDetails{
        uint64 depositedTime;
        uint128 depositedAmount;
        uint128 depositedAmountUsdValue;
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
        uint128 aBondTokensAmount;
        uint128 strikePrice;
        uint128 optionFees;
        uint256 burnedAmint;
        uint64 externalProtocolCount;
        uint256 discountedPrice;
        uint128 cTokensCredited;
    }

    struct DepositResult{
        bool hasDeposited;
        uint64 borrowerIndex;
    }

    struct GetBorrowingResult{
        uint64 totalIndex;
        DepositDetails depositDetails;
    }

        function deposit(address user,uint128 _ethPrice,uint64 _depositTime) external payable returns(DepositResult memory);
        function withdraw(address borrower,address toAddress,uint256 _amount,uint64 index) external returns(bool);
        // function depositToAave() external;
        // function withdrawFromAave(uint64 index) external;
        // function depositToCompound() external;
        // function withdrawFromCompound(uint64 index) external;
        function withdrawFromAaveByUser(address depositor,uint64 index) external returns(uint256);
        function withdrawFromCompoundByUser(address depositor,uint64 index) external returns(uint256);

        function getBalanceInTreasury() external view returns(uint256);
        function approveAmint(address _address, uint _amount) external;
        function approveUsdt(address _address, uint _amount) external;
        function transferEthToCdsLiquidators(address borrower,uint128 amount) external;


        function noOfBorrowers() external view returns(uint128);
        function ethProfitsOfLiquidators() external view returns(uint256);
        function totalVolumeOfBorrowersAmountinWei() external view returns(uint256);
        function totalVolumeOfBorrowersAmountinUSD() external view returns(uint256);

        function updateHasBorrowed(address borrower,bool _bool) external;
        function updateTotalDepositedAmount(address borrower,uint128 amount) external;
        function updateTotalBorrowedAmount(address borrower,uint256 amount) external;
        function updateTotalAbondTokensIncrease(address borrower,uint128 amount) external;
        function updateTotalAbondTokensDecrease(address borrower,uint128 amount) external;

        function getBorrowing(address depositor,uint64 index) external view returns(GetBorrowingResult memory);
        function updateDepositDetails(address depositor,uint64 index,DepositDetails memory depositDetail) external;
        function updateTotalInterest(uint256 _amount) external;
        function updateTotalInterestFromLiquidation(uint256 _amount) external;
        function updateAbondAmintPool(uint256 amount,bool operation) external;
        function updateEthProfitsOfLiquidators(uint256 amount,bool operation) external;
        function updateInterestFromExternalProtocol(uint256 amount) external;

        event Deposit(address indexed user,uint256 amount);
        event Withdraw(address indexed user,uint256 amount);
        event DepositToAave(uint256 amount);
        event WithdrawFromAave(uint256 amount);
}