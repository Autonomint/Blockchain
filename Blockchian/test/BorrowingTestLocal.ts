const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers,upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { BorrowLib } from "../typechain-types";
import { Contract, ContractFactory } from 'ethers'

import {
    wethGatewayMainnet,wethGatewaySepolia,
    //priceFeedAddressMainnet,priceFeedAddressSepolia,
    aTokenAddressMainnet,aTokenAddressSepolia,
    aavePoolAddressMainnet,aavePoolAddressSepolia,
    cometMainnet,cometSepolia,
    INFURA_URL_MAINNET,INFURA_URL_SEPOLIA,
    aTokenABI,
    cETH_ABI,
    wethAddressMainnet,wethAddressSepolia,
    endPointAddressMainnet,endPointAddressPolygon,
    } from "./utils/index"

describe("Borrowing Contract",function(){

    let owner: any;
    let owner1: any;
    let owner2: any;
    let user1: any;
    let user2: any;
    let user3: any;
    const eidA = 1
    const eidB = 2
    const ethVolatility = 50622665;


    async function deployer(){
        [owner,owner1,owner2,user1,user2,user3] = await ethers.getSigners();

        const EndpointV2Mock = await ethers.getContractFactory('EndpointV2Mock')
        const mockEndpointV2A = await EndpointV2Mock.deploy(eidA)
        const mockEndpointV2B = await EndpointV2Mock.deploy(eidB)

        const AmintStablecoin = await ethers.getContractFactory("TestAMINTStablecoin");
        const Token = await upgrades.deployProxy(AmintStablecoin, {kind:'uups'});

        const ABONDToken = await ethers.getContractFactory("TestABONDToken");
        const abondToken = await upgrades.deployProxy(ABONDToken, {kind:'uups'});

        const MultiSign = await ethers.getContractFactory("MultiSign");
        const multiSign = await upgrades.deployProxy(MultiSign,[[await owner.getAddress(),await owner1.getAddress(),await owner2.getAddress()],2],{initializer:'initialize'},{kind:'uups'});

        const USDTToken = await ethers.getContractFactory("TestUSDT");
        const usdt = await upgrades.deployProxy(USDTToken, {kind:'uups'});

        const MockPriceFeed = await ethers.getContractFactory("MockV3Aggregator");
        const mockPriceFeed = await MockPriceFeed.deploy(8,100000000000);
        const priceFeedAddressMainnet = await mockPriceFeed.getAddress();

        const CDS = await ethers.getContractFactory("CDSTest");
        const CDSContract = await upgrades.deployProxy(CDS,[
            await Token.getAddress(),
            priceFeedAddressMainnet,
            await usdt.getAddress(),
            await multiSign.getAddress(),
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'})

        const borrowLibFactory = await ethers.getContractFactory("BorrowLib");
        const borrowLib = await borrowLibFactory.deploy();

        const Borrowing = await ethers.getContractFactory("BorrowingTest",{
            libraries: {
                BorrowLib:await borrowLib.getAddress()
            }
        });

        // const BorrowOApp = await ethers.getContractFactory("BorrowOApp");

        const BorrowingContract = await upgrades.deployProxy(Borrowing,[
            await Token.getAddress(),
            await CDSContract.getAddress(),
            await abondToken.getAddress(),
            await multiSign.getAddress(),
            priceFeedAddressMainnet,
            1,
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'});

        // const BorrowingContractOAPP1 = await upgrades.deployProxy(BorrowOApp,[
        //     await BorrowingContract.getAddress(),
        //     await mockEndpointV2A.getAddress(),
        //     await owner.getAddress()
        // ],{initializer:'initialize',
        //     unsafeAllowLinkedLibraries:true
        // },{kind:'uups'});

        const BorrowingContractA = await upgrades.deployProxy(Borrowing,[
            await Token.getAddress(),
            await CDSContract.getAddress(),
            await abondToken.getAddress(),
            await multiSign.getAddress(),
            priceFeedAddressMainnet,
            1,
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'});

        // const BorrowingContractOAPP2 = await upgrades.deployProxy(BorrowOApp,[
        //     await BorrowingContractA.getAddress(),
        //     await mockEndpointV2B.getAddress(),
        //     await owner.getAddress()
        // ],{initializer:'initialize',
        //     unsafeAllowLinkedLibraries:true
        // },{kind:'uups'});

        const Treasury = await ethers.getContractFactory("Treasury");
        const treasury = await upgrades.deployProxy(Treasury,[
            await BorrowingContract.getAddress(),
            await Token.getAddress(),
            await abondToken.getAddress(),
            await CDSContract.getAddress(),
            wethGatewayMainnet,
            cometMainnet,
            aavePoolAddressMainnet,
            aTokenAddressMainnet,
            await usdt.getAddress(),
            wethAddressMainnet,
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()
            ],{initializer:'initialize'},{kind:'uups'});

        const Option = await ethers.getContractFactory("Options");
        const options = await upgrades.deployProxy(Option,[await treasury.getAddress(),await CDSContract.getAddress(),await BorrowingContract.getAddress()],{initializer:'initialize'},{kind:'uups'});

        // await BorrowingContract.setBorrowOApp(await BorrowingContractOAPP1.getAddress());
        // await BorrowingContractA.setBorrowOApp(await BorrowingContractOAPP2.getAddress());
        await BorrowingContract.setDstEid(eidB);
        await BorrowingContractA.setDstEid(eidA);

        await mockEndpointV2A.setDestLzEndpoint(await BorrowingContractA.getAddress(), mockEndpointV2B.getAddress())
        await mockEndpointV2B.setDestLzEndpoint(await BorrowingContract.getAddress(), mockEndpointV2A.getAddress())
        // await BorrowingContractOAPP1.connect(owner).setPeer(eidB, ethers.zeroPadValue(await BorrowingContractOAPP2.getAddress(), 32))
        // await BorrowingContractOAPP2.connect(owner).setPeer(eidA, ethers.zeroPadValue(await BorrowingContractOAPP1.getAddress(), 32))

        await BorrowingContract.connect(owner).setPeer(eidB, ethers.zeroPadValue(await BorrowingContractA.getAddress(), 32))
        await BorrowingContractA.connect(owner).setPeer(eidA, ethers.zeroPadValue(await BorrowingContract.getAddress(), 32))

        await abondToken.setBorrowingContract(await BorrowingContract.getAddress());
        await multiSign.connect(owner).approveSetterFunction([0,1,4,5,6,7,8,9,10]);
        await multiSign.connect(owner1).approveSetterFunction([0,1,4,5,6,7,8,9,10]);

        await BorrowingContract.connect(owner).setAdmin(owner.getAddress());
        
        await CDSContract.connect(owner).setAdmin(owner.getAddress());

        await BorrowingContract.connect(owner).setTreasury(await treasury.getAddress());
        await BorrowingContract.connect(owner).setOptions(await options.getAddress());
        await BorrowingContract.connect(owner).setLTV(80);
        await BorrowingContract.connect(owner).setBondRatio(4);
        await BorrowingContract.connect(owner).setAPR(BigInt("1000000001547125957863212449"));

        await CDSContract.connect(owner).setTreasury(await treasury.getAddress());
        await CDSContract.connect(owner).setBorrowingContract(await BorrowingContract.getAddress());
        await CDSContract.connect(owner).setAmintLimit(80);
        await CDSContract.connect(owner).setUsdtLimit(20000000000);

        await BorrowingContract.calculateCumulativeRate();
        
        const provider = new ethers.JsonRpcProvider(INFURA_URL_MAINNET);
        const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",provider);

        const aToken = new ethers.Contract(aTokenAddressMainnet,aTokenABI,signer);
        const cETH = new ethers.Contract(cometMainnet,cETH_ABI,signer);

        return {Token,abondToken,usdt,CDSContract,BorrowingContract,treasury,options,multiSign,owner,user1,user2,user3,provider,signer}
    }

    describe("Should deposit ETH and mint Trinity",function(){
        it("Should deposit ETH",async function(){
            const {BorrowingContract,CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("50")});
        })

        // it("Should deposit ETH",async function(){
        //     const {BorrowingContractOAPP1} = await loadFixture(deployer);

        //     const options = "0x00030100110100000000000000000000000000030d40";
        //     // Define native fee and quote for the message send operation
        //     let nativeFee = 0
        //     ;[nativeFee] = await BorrowingContractOAPP1.quote(eidB, [5,10,15,20,25,30,35,40],[], options, false)

        //     // Execute send operation from myOAppA
        //     await BorrowingContractOAPP1.send(eidB, [5,10,15,20,25,30,35,40],[], options, { value: nativeFee.toString() })
        // })
        
        // it("Should deposit ETH",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);

        //     const options = "0x00030100110100000000000000000000000000030d40";
        //     // Define native fee and quote for the message send operation
        //     let nativeFee = 0
        //     ;[nativeFee] = await BorrowingContract.quote(eidB, [5,10,15,20,25,30,35,40],[1,2], options, false)

        //     console.log(nativeFee);

        //     // Execute send operation from myOAppA
        //     await BorrowingContract.send(eidB,[5,10,15,20,25,30,35,40],[1,2],[nativeFee,0], options, { value: nativeFee.toString() })
        // })

        // it("Should deposit ETH",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);


        //     // Call the deposit function with 1 ETH
        //     const depositSelector = BorrowingContract.interface.functions.deposit.selector; // Get selector again
        //     const depositValue = ethers.parseEther("1"); // Convert ETH value to wei
        //     const depositTx = await BorrowingContract.connect(owner).sendTransaction({
        //         to: BorrowingContract.address,
        //         value: depositValue,
        //         data: depositSelector, // Only function selector for deposit
        //     });

        //     console.log("Deposit Tx Hash:", depositTx.hash);
        //     await depositTx.wait();
        // })
    })
})
