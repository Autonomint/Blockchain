// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

    struct RatioInputData{
        uint128 noOfBorrowers;
        uint256 lastEthVaultValue;
        uint256 lastCDSPoolValue;
        uint256 lastTotalCDSPool;
        uint256 latestTotalCDSPool;
        uint256 _amount;
        uint128 lastEthprice;
        uint128 currentEthPrice;
    }

    struct RatioReturnData{
        uint256 lastEthVaultValue;
        uint256 lastCDSPoolValue;
        uint256 lastTotalCDSPool;
        uint64 ratio;
    }

interface IBorrowing{

    function pause() external;
    function unpause() external;
    function transferToken(address _borrower, uint64 borrowerIndex) external;
    function getUSDValue() external view returns(uint256);
    function noOfLiquidations() external view returns(uint128);
    function lastEthVaultValue() external view returns(uint256);
    function lastCDSPoolValue() external view returns(uint256);


    function updateLastEthVaultValue(uint256 _amount) external;
    function calculateRatio(uint256 _amount,uint currentEthPrice) external returns(uint64);

}