//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {AMINTStablecoin} from "../../contracts/Token/Amint.sol";
import {ABONDToken} from "../../contracts/Token/Abond_Token.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../contracts/Core_logic/multiSign.sol";
import {TestUSDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBorrowing is Script {

    AMINTStablecoin tsc;
    ABONDToken pToken;
    TestUSDT usdt;
    Options option;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    MultiSign multiSign;
    address public priceFeedAddress;
    address wethAddress = 0x3bd3a20Ac9Ff1dda1D99C0dFCE6D65C4960B3627; // 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
    address cEthAddress = 0x64078a6189Bf45f80091c6Ff2fCEe1B15Ac8dbde; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address aavePoolAddress = 0x5E52dEc931FFb32f609681B8438A51c675cc232d; //0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address aTokenAddress = 0x22404B0e2a7067068AcdaDd8f9D586F834cCe2c5; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    address[] owners = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
        ];

    function run() external returns (AMINTStablecoin,ABONDToken,TestUSDT,BorrowingTest,Treasury,CDSTest,MultiSign,Options,HelperConfig){
        HelperConfig config = new HelperConfig();
        (address ethUsdPriceFeed,uint256 deployerKey) = config.activeNetworkConfig();

        priceFeedAddress = ethUsdPriceFeed;
        vm.startBroadcast(deployerKey);
        tsc = new AMINTStablecoin();
        pToken = new ABONDToken();
        usdt = new TestUSDT();
        multiSign = new MultiSign(owners,2);
        cds = new CDSTest(address(tsc),priceFeedAddress,address(usdt),address(multiSign));
        borrow = new BorrowingTest(address(tsc),address(cds),address(pToken),address(multiSign),priceFeedAddress,1);
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
        return(tsc,pToken,usdt,borrow,treasury,cds,multiSign,option,config);
    }
}