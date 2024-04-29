const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers,upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { BorrowLib } from "../typechain-types";
import { Contract, ContractFactory } from 'ethers'
import { Options } from '@layerzerolabs/lz-v2-utilities'

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
        const TokenA = await upgrades.deployProxy(AmintStablecoin,[
            "Test AMINT TOKEN",
            "TAMINT",
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'});

        const TokenB = await upgrades.deployProxy(AmintStablecoin,[
            "Test AMINT TOKEN",
            "TAMINT",
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'});

        const ABONDToken = await ethers.getContractFactory("TestABONDToken");
        const abondTokenA = await upgrades.deployProxy(ABONDToken, {kind:'uups'});
        const abondTokenB = await upgrades.deployProxy(ABONDToken, {kind:'uups'});

        const MultiSign = await ethers.getContractFactory("MultiSign");
        const multiSignA = await upgrades.deployProxy(MultiSign,[[await owner.getAddress(),await owner1.getAddress(),await owner2.getAddress()],2],{initializer:'initialize'},{kind:'uups'});
        const multiSignB = await upgrades.deployProxy(MultiSign,[[await owner.getAddress(),await owner1.getAddress(),await owner2.getAddress()],2],{initializer:'initialize'},{kind:'uups'});

        const USDTToken = await ethers.getContractFactory("TestUSDT");
        const usdtA = await upgrades.deployProxy(USDTToken, {kind:'uups'});
        const usdtB = await upgrades.deployProxy(USDTToken, {kind:'uups'});

        const MockPriceFeed = await ethers.getContractFactory("MockV3Aggregator");
        const mockPriceFeedA = await MockPriceFeed.deploy(8,100000000000);
        const mockPriceFeedB = await MockPriceFeed.deploy(8,100000000000);

        const priceFeedAddressMainnetA = await mockPriceFeedA.getAddress();
        const priceFeedAddressMainnetB = await mockPriceFeedB.getAddress();


        const CDS = await ethers.getContractFactory("CDSTest");
        const CDSContractA = await upgrades.deployProxy(CDS,[
            await TokenA.getAddress(),
            priceFeedAddressMainnetA,
            await usdtA.getAddress(),
            await multiSignA.getAddress(),
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'})

        const CDSContractB = await upgrades.deployProxy(CDS,[
            await TokenB.getAddress(),
            priceFeedAddressMainnetB,
            await usdtB.getAddress(),
            await multiSignB.getAddress(),
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'})

        const borrowLibFactory = await ethers.getContractFactory("BorrowLib");
        const borrowLib = await borrowLibFactory.deploy();

        const Borrowing = await ethers.getContractFactory("BorrowingTest",{
            libraries: {
                BorrowLib:await borrowLib.getAddress()
            }
        });

        const BorrowingContractA = await upgrades.deployProxy(Borrowing,[
            await TokenA.getAddress(),
            await CDSContractA.getAddress(),
            await abondTokenA.getAddress(),
            await multiSignA.getAddress(),
            priceFeedAddressMainnetA,
            1,
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'});

        const BorrowingContractB = await upgrades.deployProxy(Borrowing,[
            await TokenB.getAddress(),
            await CDSContractB.getAddress(),
            await abondTokenB.getAddress(),
            await multiSignB.getAddress(),
            priceFeedAddressMainnetB,
            1,
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'});

        const Treasury = await ethers.getContractFactory("Treasury");
        const treasuryA = await upgrades.deployProxy(Treasury,[
            await BorrowingContractA.getAddress(),
            await TokenA.getAddress(),
            await abondTokenA.getAddress(),
            await CDSContractA.getAddress(),
            wethGatewayMainnet,
            cometMainnet,
            aavePoolAddressMainnet,
            aTokenAddressMainnet,
            await usdtA.getAddress(),
            wethAddressMainnet,
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize'},{kind:'uups'});

        const treasuryB = await upgrades.deployProxy(Treasury,[
            await BorrowingContractB.getAddress(),
            await TokenB.getAddress(),
            await abondTokenB.getAddress(),
            await CDSContractB.getAddress(),
            wethGatewayMainnet,
            cometMainnet,
            aavePoolAddressMainnet,
            aTokenAddressMainnet,
            await usdtB.getAddress(),
            wethAddressMainnet,
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize'},{kind:'uups'});

        const Option = await ethers.getContractFactory("Options");
        const optionsA = await upgrades.deployProxy(Option,[await treasuryA.getAddress(),await CDSContractA.getAddress(),await BorrowingContractA.getAddress()],{initializer:'initialize'},{kind:'uups'});
        const optionsB = await upgrades.deployProxy(Option,[await treasuryB.getAddress(),await CDSContractB.getAddress(),await BorrowingContractB.getAddress()],{initializer:'initialize'},{kind:'uups'});

        await BorrowingContractA.setDstEid(eidB);
        await BorrowingContractB.setDstEid(eidA);

        await CDSContractA.setDstEid(eidB);
        await CDSContractB.setDstEid(eidA);

        await treasuryA.setDstEid(eidB);
        await treasuryB.setDstEid(eidA);

        await TokenA.setDstEid(eidB);
        await TokenB.setDstEid(eidA);

        await mockEndpointV2B.setDestLzEndpoint(await TokenA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await TokenB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await abondTokenA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await abondTokenB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await multiSignA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await multiSignB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await usdtA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await usdtB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await CDSContractA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await CDSContractB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await BorrowingContractA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await BorrowingContractB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await treasuryA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await treasuryB.getAddress(), mockEndpointV2B.getAddress())

        await mockEndpointV2B.setDestLzEndpoint(await optionsA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await optionsB.getAddress(), mockEndpointV2B.getAddress())

        await BorrowingContractA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await BorrowingContractB.getAddress(), 32))
        await BorrowingContractB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await BorrowingContractA.getAddress(), 32))

        await CDSContractA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await CDSContractB.getAddress(), 32))
        await CDSContractB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await CDSContractA.getAddress(), 32))

        await treasuryA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await treasuryB.getAddress(), 32))
        await treasuryB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await treasuryA.getAddress(), 32))

        await TokenA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await TokenB.getAddress(), 32))
        await TokenB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await TokenA.getAddress(), 32))

        await abondTokenA.setBorrowingContract(await BorrowingContractA.getAddress());
        await abondTokenB.setBorrowingContract(await BorrowingContractB.getAddress());

        await multiSignA.connect(owner).approveSetterFunction([0,1,4,5,6,7,8,9,10]);
        await multiSignA.connect(owner1).approveSetterFunction([0,1,4,5,6,7,8,9,10]);
        await multiSignB.connect(owner).approveSetterFunction([0,1,4,5,6,7,8,9,10]);
        await multiSignB.connect(owner1).approveSetterFunction([0,1,4,5,6,7,8,9,10]);

        await BorrowingContractA.connect(owner).setAdmin(owner.getAddress());
        await BorrowingContractB.connect(owner).setAdmin(owner.getAddress());

        await CDSContractA.connect(owner).setAdmin(owner.getAddress());
        await CDSContractB.connect(owner).setAdmin(owner.getAddress());

        await BorrowingContractA.connect(owner).setTreasury(await treasuryA.getAddress());
        await BorrowingContractA.connect(owner).setOptions(await optionsA.getAddress());
        await BorrowingContractA.connect(owner).setLTV(80);
        await BorrowingContractA.connect(owner).setBondRatio(4);
        await BorrowingContractA.connect(owner).setAPR(BigInt("1000000001547125957863212449"));

        await BorrowingContractB.connect(owner).setTreasury(await treasuryB.getAddress());
        await BorrowingContractB.connect(owner).setOptions(await optionsB.getAddress());
        await BorrowingContractB.connect(owner).setLTV(80);
        await BorrowingContractB.connect(owner).setBondRatio(4);
        await BorrowingContractB.connect(owner).setAPR(BigInt("1000000001547125957863212449"));

        await CDSContractA.connect(owner).setTreasury(await treasuryA.getAddress());
        await CDSContractA.connect(owner).setBorrowingContract(await BorrowingContractA.getAddress());
        await CDSContractA.connect(owner).setAmintLimit(80);
        await CDSContractA.connect(owner).setUsdtLimit(20000000000);

        await CDSContractB.connect(owner).setTreasury(await treasuryB.getAddress());
        await CDSContractB.connect(owner).setBorrowingContract(await BorrowingContractB.getAddress());
        await CDSContractB.connect(owner).setAmintLimit(80);
        await CDSContractB.connect(owner).setUsdtLimit(20000000000);

        await BorrowingContractA.calculateCumulativeRate();
        await BorrowingContractB.calculateCumulativeRate();

        const provider = new ethers.JsonRpcProvider(INFURA_URL_MAINNET);
        const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",provider);

        const aToken = new ethers.Contract(aTokenAddressMainnet,aTokenABI,signer);
        const cETH = new ethers.Contract(cometMainnet,cETH_ABI,signer);

        return {
            TokenA,abondTokenA,usdtA,
            CDSContractA,BorrowingContractA,
            treasuryA,optionsA,multiSignA,

            TokenB,abondTokenB,usdtB,
            CDSContractB,BorrowingContractB,
            treasuryB,optionsB,multiSignB,

            owner,user1,user2,user3,
            provider,signer,
        }
    }

    describe("Should deposit ETH and mint Trinity",function(){
        it("Should deposit ETH",async function(){
            const {BorrowingContract,CDSContract,usdt,user1} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);

            const options = "0x00030100110100000000000000000000000000030d40";
            let nativeFee = 0
            ;[nativeFee] = await CDSContract.quote(eidB, [5,10,15,20,25,30],options, false)

            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});
            await user1.sendTransaction({
                to: await BorrowingContract.getAddress(),
                value: ethers.parseEther("1")
              });
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("50")});
        })

        it.only("Should deposit ETH",async function(){
            const {
                BorrowingContractA,BorrowingContractB,
                CDSContractA,CDSContractB,
                usdtA,usdtB,
                treasuryA,treasuryB
            } = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = "0x00030100110100000000000000000000000000030d40";

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, [5,10,15,20,25,30],options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            console.log(await CDSContractA.omniChainCDS());
            console.log(await CDSContractB.omniChainCDS());

            await usdtB.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtB.connect(user1).approve(CDSContractB.getAddress(),10000000000);
            await CDSContractB.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            console.log(await CDSContractA.omniChainCDS());
            console.log(await CDSContractB.omniChainCDS());

            await BorrowingContractA.connect(user2).send(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("50")})
            const tx1 = await BorrowingContractA.omniChainBorrowing();
            const tx2 = await BorrowingContractB.omniChainBorrowing();

            const tx3 = await treasuryA.omniChainTreasury();
            const tx4 = await treasuryB.omniChainTreasury();

            console.log(tx1)
            console.log(tx2);
        })

        it("Should transfer amint from src to dst ",async function(){
            const {Token,TokenA} = await loadFixture(deployer);
            const initialAmount = ethers.parseEther('100')
            await Token.mint(await user1.getAddress(), initialAmount)
    
            const tokensToSend = ethers.parseEther('1')
    
            // Defining extra message execution options for the send operation
            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
    
            const sendParam = [
                eidB,
                ethers.zeroPadValue(await user2.getAddress(), 32),
                tokensToSend,
                tokensToSend,
                options,
                '0x',
                '0x',
            ]
    
            // Fetching the native fee for the token send operation
            const [nativeFee] = await Token.quoteSend(sendParam, false)

            console.log("SRC TOTAL SUPPLY BEFORE SEND", await Token.totalSupply());
            console.log("DST TOTAL SUPPLY BEFORE SEND", await TokenA.totalSupply());
    
            // Executing the send operation from myOFTA contract
            await Token.connect(user1).send(sendParam, [nativeFee, 0], await user1.getAddress(), { value: nativeFee })
    
            // Fetching the final token balances of ownerA and ownerB
            const finalBalance = await Token.balanceOf(await user1.getAddress())
            const finalBalanceA = await TokenA.balanceOf(await user2.getAddress())

            console.log("USER1 BALANCE IN SRC AFTER SEND", finalBalance);
            console.log("USER2 BALANCE IN DST AFTER SEND", finalBalanceA);

            console.log("SRC TOTAL SUPPLY AFTER SEND", await Token.totalSupply());
            console.log("DST TOTAL SUPPLY AFTER SEND", await TokenA.totalSupply());
    
        })
    })
})
