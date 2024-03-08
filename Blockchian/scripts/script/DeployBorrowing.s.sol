//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TestAMINTStablecoin} from "../../contracts/TestContracts/CopyAmint.sol";
import {TestABONDToken} from "../../contracts/TestContracts/Copy_Abond_Token.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../contracts/Core_logic/multiSign.sol";
import {TestUSDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBorrowing is Script {

    struct Contracts {
        TestAMINTStablecoin amint;
        TestABONDToken abond;
        TestUSDT usdt;
        BorrowingTest borrow;
        Treasury treasury;
        CDSTest cds;
        MultiSign multiSign;
        Options option;
        HelperConfig config;
    }

    TestAMINTStablecoin amint;
    TestABONDToken abond;
    TestUSDT usdt;
    Options option;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    MultiSign multiSign;
    address public priceFeedAddress;
    address wethGatewayAddress = 0x893411580e590D62dDBca8a703d61Cc4A8c7b2b9; // 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
    address cEthAddress = 0xA17581A9E3356d9A858b789D68B4d866e593aE94; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address aavePoolAddress = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e; //0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    address[] owners = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
        ];

    uint8[] functions = [0,1,2,3,4,5,6,7,8,9,10];

    function run() external returns (Contracts memory){
        HelperConfig config = new HelperConfig();
        (address ethUsdPriceFeed, uint256 deployerKey) = config.activeNetworkConfig();
        priceFeedAddress = ethUsdPriceFeed;
        
        vm.startBroadcast(deployerKey);
        amint = new TestAMINTStablecoin();
        abond = new TestABONDToken();
        multiSign = new MultiSign();
        usdt = new TestUSDT();
        cds = new CDSTest();
        borrow = new BorrowingTest();
        treasury = new Treasury();
        option = new Options();

        amint.initialize();
        abond.initialize();
        multiSign.initialize(owners,2);
        usdt.initialize();
        cds.initialize(address(amint),priceFeedAddress,address(usdt),address(multiSign));
        borrow.initialize(address(amint),address(cds),address(abond),address(multiSign),priceFeedAddress,11155111);
        treasury.initialize(
            address(borrow),
            address(amint),
            address(abond),
            address(cds),
            wethGatewayAddress,cEthAddress,aavePoolAddress,aTokenAddress,address(usdt),wethAddress);
        option.initialize(address(treasury),address(cds),address(borrow));

        multiSign.approveSetterFunction(functions);

        vm.stopBroadcast();
        return(Contracts(amint,abond,usdt,borrow,treasury,cds,multiSign,option,config));
    }
}