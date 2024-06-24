//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TestUSDaStablecoin} from "../../contracts/TestContracts/CopyUSDa.sol";
import {TestABONDToken} from "../../contracts/TestContracts/Copy_Abond_Token.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../contracts/Core_logic/multiSign.sol";
import {TestUSDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {EndpointV2Mock} from "../../contracts/TestContracts/EndpointV2Mock.sol";
import {BorrowLiquidation} from "../../contracts/Core_logic/borrowLiquidation.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBorrowing is Script {

    struct Contracts {
        TestUSDaStablecoin usda;
        TestABONDToken abond;
        TestUSDT usdt;
        BorrowingTest borrow;
        Treasury treasury;
        CDSTest cds;
        MultiSign multiSign;
        Options option;
        BorrowLiquidation borrowLiquidation;
        HelperConfig config;
    }

    TestUSDaStablecoin usda;
    TestABONDToken abond;
    TestUSDT usdt;
    Options option;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    MultiSign multiSign;
    BorrowLiquidation borrowLiquidation;
    EndpointV2Mock endPointV2A;
    EndpointV2Mock endPointV2B;
    
    address public priceFeedAddress;
    address wethGatewayAddress = 0x893411580e590D62dDBca8a703d61Cc4A8c7b2b9; // 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
    address cEthAddress = 0xA17581A9E3356d9A858b789D68B4d866e593aE94; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address aavePoolAddress = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e; //0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    uint32 eidA = 1;
    uint32 eidB = 2;

    address[] owners = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
        ];

    uint8[] functions = [0,1,2,3,4,5,6,7,8,9];

    function run() external returns (Contracts memory,Contracts memory){
        HelperConfig config = new HelperConfig();
        (address ethUsdPriceFeed, uint256 deployerKey) = config.activeNetworkConfig();
        priceFeedAddress = ethUsdPriceFeed;
        
        vm.startBroadcast(deployerKey);
        usda = new TestUSDaStablecoin();
        abond = new TestABONDToken();
        multiSign = new MultiSign();
        usdt = new TestUSDT();
        cds = new CDSTest();
        borrow = new BorrowingTest();
        treasury = new Treasury();
        option = new Options();
        borrowLiquidation = new BorrowLiquidation();
        endPointV2A = new EndpointV2Mock(eidA);

        usda.initialize(address(endPointV2A),owners[0]);
        abond.initialize();
        multiSign.initialize(owners,2);
        usdt.initialize(address(endPointV2A),owners[0]);
        cds.initialize(address(usda),priceFeedAddress,address(usdt),address(multiSign),address(endPointV2A),owners[0]);
        borrow.initialize(address(usda),address(cds),address(abond),address(multiSign),priceFeedAddress,11155111,address(endPointV2A),owners[0]);
        borrowLiquidation.initialize(address(borrow),address(cds),address(usda));
        treasury.initialize(
            address(borrow),
            address(usda),
            address(abond),
            address(cds),
            address(borrowLiquidation),
            address(usdt),
            address(endPointV2A),
            owners[0]);
        option.initialize(address(treasury),address(cds),address(borrow));

        Contracts memory contractsA = Contracts(usda,abond,usdt,borrow,treasury,cds,multiSign,option,borrowLiquidation,config);

        usda = new TestUSDaStablecoin();
        abond = new TestABONDToken();
        multiSign = new MultiSign();
        usdt = new TestUSDT();
        cds = new CDSTest();
        borrow = new BorrowingTest();
        treasury = new Treasury();
        option = new Options();
        borrowLiquidation = new BorrowLiquidation();
        endPointV2B = new EndpointV2Mock(eidB);

        usda.initialize(address(endPointV2B),owners[0]);
        abond.initialize();
        multiSign.initialize(owners,2);
        usdt.initialize(address(endPointV2B),owners[0]);
        cds.initialize(address(usda),priceFeedAddress,address(usdt),address(multiSign),address(endPointV2B),owners[0]);
        borrow.initialize(address(usda),address(cds),address(abond),address(multiSign),priceFeedAddress,11155111,address(endPointV2B),owners[0]);
        borrowLiquidation.initialize(address(borrow),address(cds),address(usda));
        treasury.initialize(
            address(borrow),
            address(usda),
            address(abond),
            address(cds),
            address(borrowLiquidation),
            address(usdt),
            address(endPointV2B),
            owners[0]);
        option.initialize(address(treasury),address(cds),address(borrow));
        Contracts memory contractsB = Contracts(usda,abond,usdt,borrow,treasury,cds,multiSign,option,borrowLiquidation,config);

        endPointV2A.setDestLzEndpoint(address(contractsB.usda),address(endPointV2B));
        endPointV2A.setDestLzEndpoint(address(contractsB.usdt),address(endPointV2B));
        endPointV2A.setDestLzEndpoint(address(contractsB.multiSign),address(endPointV2B));
        endPointV2A.setDestLzEndpoint(address(contractsB.cds),address(endPointV2B));
        endPointV2A.setDestLzEndpoint(address(contractsB.borrow),address(endPointV2B));
        endPointV2A.setDestLzEndpoint(address(contractsB.treasury),address(endPointV2B));
        endPointV2A.setDestLzEndpoint(address(contractsB.option),address(endPointV2B));

        endPointV2B.setDestLzEndpoint(address(contractsA.usda),address(endPointV2A));
        endPointV2B.setDestLzEndpoint(address(contractsA.usdt),address(endPointV2A));
        endPointV2B.setDestLzEndpoint(address(contractsA.multiSign),address(endPointV2A));
        endPointV2B.setDestLzEndpoint(address(contractsA.cds),address(endPointV2A));
        endPointV2B.setDestLzEndpoint(address(contractsA.borrow),address(endPointV2A));
        endPointV2B.setDestLzEndpoint(address(contractsA.treasury),address(endPointV2A));
        endPointV2B.setDestLzEndpoint(address(contractsA.option),address(endPointV2A));

        contractsA.usda.setPeer(eidB,bytes32(uint256(uint160(address(contractsB.usda)))));
        contractsA.usdt.setPeer(eidB,bytes32(uint256(uint160(address(contractsB.usdt)))));
        contractsA.cds.setPeer(eidB,bytes32(uint256(uint160(address(contractsB.cds)))));
        contractsA.borrow.setPeer(eidB,bytes32(uint256(uint160(address(contractsB.borrow)))));
        contractsA.treasury.setPeer(eidB,bytes32(uint256(uint160(address(contractsB.treasury)))));

        contractsB.usda.setPeer(eidA,bytes32(uint256(uint160(address(contractsA.usda)))));
        contractsB.usdt.setPeer(eidA,bytes32(uint256(uint160(address(contractsA.usdt)))));
        contractsB.cds.setPeer(eidA,bytes32(uint256(uint160(address(contractsA.cds)))));
        contractsB.borrow.setPeer(eidA,bytes32(uint256(uint160(address(contractsA.borrow)))));
        contractsB.treasury.setPeer(eidA,bytes32(uint256(uint160(address(contractsA.treasury)))));

        contractsA.abond.setBorrowingContract(address(contractsA.borrow));
        contractsB.abond.setBorrowingContract(address(contractsB.borrow));

        contractsA.treasury.setExternalProtocolAddresses(wethGatewayAddress,cEthAddress,aavePoolAddress,aTokenAddress,wethAddress);
        contractsB.treasury.setExternalProtocolAddresses(wethGatewayAddress,cEthAddress,aavePoolAddress,aTokenAddress,wethAddress);

        contractsA.treasury.setDstTreasuryAddress(address(contractsB.treasury));
        contractsB.treasury.setDstTreasuryAddress(address(contractsA.treasury));

        contractsA.borrowLiquidation.setTreasury(address(contractsA.treasury));
        contractsB.borrowLiquidation.setTreasury(address(contractsB.treasury));

        contractsA.usda.setDstEid(eidB);
        contractsA.usdt.setDstEid(eidB);
        contractsA.treasury.setDstEid(eidB);

        contractsB.usda.setDstEid(eidA);
        contractsB.usdt.setDstEid(eidA);
        contractsB.treasury.setDstEid(eidA);
        contractsA.multiSign.approveSetterFunction(functions);
        contractsB.multiSign.approveSetterFunction(functions);

        vm.stopBroadcast();
        return(contractsA,contractsB);
    }
}