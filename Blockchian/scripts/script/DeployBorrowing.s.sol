//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TrinityStablecoin} from "../../contracts/Token/Trinity_ERC20.sol";
import {ProtocolToken} from "../../contracts/Token/Protocol_Token.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {USDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBorrowing is Script {

    TrinityStablecoin tsc;
    ProtocolToken pToken;
    USDT usdt;
    Options option;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    address public priceFeedAddress;
    address wethAddress = 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
    address cEthAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address aavePoolAddress = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    function run() external returns (TrinityStablecoin,ProtocolToken,USDT,BorrowingTest,Treasury,CDSTest,HelperConfig){
        HelperConfig config = new HelperConfig();
        (address ethUsdPriceFeed,uint256 deployerKey) = config.activeNetworkConfig();

        priceFeedAddress = ethUsdPriceFeed;
        vm.startBroadcast(deployerKey);
        tsc = new TrinityStablecoin();
        pToken = new ProtocolToken();
        usdt = new USDT();
        cds = new CDSTest(address(tsc),priceFeedAddress,address(usdt));
        borrow = new BorrowingTest(address(tsc),address(cds),address(pToken),priceFeedAddress);
        treasury = new Treasury(address(borrow),address(tsc),address(cds),wethAddress,cEthAddress,aavePoolAddress,aTokenAddress,address(usdt));
        option = new Options(priceFeedAddress,address(treasury),address(cds));

        borrow.initializeTreasury(address(treasury));
        borrow.setOptions(address(option));
        borrow.setLTV(80);
        cds.setTreasury(address(treasury));
        cds.setBorrowingContract(address(borrow));
        cds.setAmintLimit(80);
        cds.setUsdtLimit(20000);
        borrow.calculateCumulativeRate();

        vm.stopBroadcast();
        return(tsc,pToken,usdt,borrow,treasury,cds,config);
    }
}