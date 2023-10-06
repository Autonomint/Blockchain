// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "hardhat/console.sol";

contract Options{

    function depositOption(uint8 percent) external {}

    function withdrawOption(uint128 depositedAmount,uint128 strikePrice,uint64 ethPrice) external pure returns(uint128){
        require(depositedAmount != 0 && strikePrice != 0 && ethPrice != 0,"Zero inputs in options");
        uint64 currentEthPrice = ethPrice;
        uint128 currentEthValue = depositedAmount * currentEthPrice;
        uint128 ethToReturn;
        require(currentEthValue >= strikePrice);
        if(currentEthValue > strikePrice){
            ethToReturn = (depositedAmount * (currentEthPrice- strikePrice))/currentEthPrice;
        }else{
            ethToReturn = 0;
        }
        return ethToReturn;
    }
}