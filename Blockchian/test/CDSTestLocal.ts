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

describe("CDS Contract",function(){

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
        const abondTokenA = await upgrades.deployProxy(ABONDToken,[
            "Test ABOND Token",
            "TABOND",
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()],{initializer: 'initialize'}, {kind:'uups'});
        const abondTokenB = await upgrades.deployProxy(ABONDToken,[
            "Test ABOND Token",
            "TABOND",
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()],{initializer: 'initialize'}, {kind:'uups'});

        const MultiSign = await ethers.getContractFactory("MultiSign");
        const multiSignA = await upgrades.deployProxy(MultiSign,[[await owner.getAddress(),await owner1.getAddress(),await owner2.getAddress()],2],{initializer:'initialize'},{kind:'uups'});
        const multiSignB = await upgrades.deployProxy(MultiSign,[[await owner.getAddress(),await owner1.getAddress(),await owner2.getAddress()],2],{initializer:'initialize'},{kind:'uups'});

        const USDTToken = await ethers.getContractFactory("TestUSDT");
        const usdtA = await upgrades.deployProxy(USDTToken,[
            "Test Tether",
            "TUSDT",
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'});
        const usdtB = await upgrades.deployProxy(USDTToken,[
            "Test Tether",
            "TUSDT",
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'});

        const MockPriceFeed = await ethers.getContractFactory("MockV3Aggregator");
        const mockPriceFeedA = await MockPriceFeed.deploy(8,100000000000);
        const mockPriceFeedB = await MockPriceFeed.deploy(8,100000000000);

        const priceFeedAddressMainnetA = await mockPriceFeedA.getAddress();
        const priceFeedAddressMainnetB = await mockPriceFeedB.getAddress();


        const cdsLibFactory = await ethers.getContractFactory("CDSLib");
        const cdsLib = await cdsLibFactory.deploy();

        const CDS = await ethers.getContractFactory("CDSTest",{
            libraries: {
                CDSLib:await cdsLib.getAddress()
            }
        });
        const CDSContractA = await upgrades.deployProxy(CDS,[
            await TokenA.getAddress(),
            priceFeedAddressMainnetA,
            await usdtA.getAddress(),
            await multiSignA.getAddress(),
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'})

        const CDSContractB = await upgrades.deployProxy(CDS,[
            await TokenB.getAddress(),
            priceFeedAddressMainnetB,
            await usdtB.getAddress(),
            await multiSignB.getAddress(),
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'})

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

        await abondTokenA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await abondTokenB.getAddress(), 32))
        await abondTokenB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await abondTokenA.getAddress(), 32))

        await usdtA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await usdtB.getAddress(), 32))
        await usdtB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await usdtA.getAddress(), 32))

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

        await BorrowingContractA.setDstEid(eidB);
        await BorrowingContractB.setDstEid(eidA);

        await CDSContractA.setDstEid(eidB);
        await CDSContractB.setDstEid(eidA);

        await treasuryA.setDstEid(eidB);
        await treasuryB.setDstEid(eidA);

        await TokenA.setDstEid(eidB);
        await TokenB.setDstEid(eidA);

        await abondTokenA.setDstEid(eidB);
        await abondTokenB.setDstEid(eidA);

        await usdtA.setDstEid(eidB);
        await usdtB.setDstEid(eidA);

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

    describe("should deposit into CDS",function(){

        it("should deposit USDT into CDS",async function(){
            const {
                CDSContractA,CDSContractB,
                usdtA,usdtB
            } = await loadFixture(deployer);

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = "0x00030100110100000000000000000000000000030d40";

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, [5,10,15,20,25,30,35],options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            await usdtB.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtB.connect(user1).approve(CDSContractB.getAddress(),10000000000);
            await CDSContractB.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});
            
            expect(await CDSContractB.totalCdsDepositedAmount()).to.be.equal(10000000000);

            let tx = await CDSContractB.cdsDetails(user1.getAddress());
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(1);
        })

        it("should deposit USDT and AMINT into CDS", async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),30000000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),30000000000);

            const options = "0x00030100110100000000000000000000000000030d40";

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, [5,10,15,20,25,30,35],options, false)

            await CDSContractA.deposit(20000000000,0,true,10000000000, { value: nativeFee.toString()});

            await TokenA.mint(owner.getAddress(),800000000)
            await TokenA.connect(owner).approve(CDSContractA.getAddress(),800000000);

            await CDSContractA.connect(owner).deposit(200000000,800000000,true,1000000000, { value: nativeFee.toString()});
            expect(await CDSContractA.totalCdsDepositedAmount()).to.be.equal(21000000000);

            let tx = await CDSContractA.cdsDetails(owner.getAddress());
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(2);
        })
    })

    describe("To check CDS withdrawl function",function(){
        it("Should withdraw from cds",async () => {
            const {BorrowingContractA,CDSContractA,usdtA,treasuryA} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdtA.mint(user2.getAddress(),20000000000)
            await usdtA.mint(user1.getAddress(),50000000000)
            await usdtA.connect(user2).approve(CDSContractA.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),50000000000);

            const options = "0x00030100110100000000000000000000000000030d40";

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, [5,10,15,20,25,30,35],options, false)

            await CDSContractA.connect(user2).deposit(12000000000,0,true,12000000000, { value: nativeFee.toString()});
            await CDSContractA.connect(user1).deposit(2000000000,0,true,1500000000, { value: nativeFee.toString()});

            const depositAmount = ethers.parseEther("1");
            const coder = ethers.AbiCoder.defaultAbiCoder();
            const callDataDeposit = coder.encode([            
                "uint64",
                "uint64",
                "uint256",
                "uint64",
                "uint64",
                "uint256",
                "address",
                'uint64'
            ],[
                100000,
                timeStamp,
                depositAmount,
                1,
                110000,
                ethVolatility,
                await user1.getAddress(),
                1
            ]);

            let nativeFee1 = 0
            ;[nativeFee1] = await BorrowingContractA.quote(eidB, [5,10,15,20,25,30,35,40],[], options, false)
            let nativeFee2 = 0
            ;[nativeFee2] = await treasuryA.quote(eidB, [5,10,15,20,25,30,35,40,45], options, false)

            await BorrowingContractA.connect(user1).send(1, callDataDeposit, {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2))})
            await BorrowingContractA.connect(user2).send(1, callDataDeposit, {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2))})

            const callDataLiquidate = coder.encode([            
                "uint64",
                "uint64",
                "uint256",
                "uint64",
                "uint64",
                "uint256",
                "address",
                'uint64'
            ],[
                80000,
                timeStamp,
                depositAmount,
                1,
                110000,
                ethVolatility,
                await user1.getAddress(),
                1
            ]);
            await BorrowingContractA.connect(owner).send(3, callDataLiquidate, {value: (nativeFee1 + nativeFee2).toString()})
            await CDSContractA.connect(user1).withdraw(1, { value: nativeFee.toString()});
        })

        it("Should withdraw from cds",async () => {
            const {CDSContractA,usdtA} = await loadFixture(deployer);

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = "0x00030100110100000000000000000000000000030d40";

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, [5,10,15,20,25,30,35],options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            await CDSContractA.connect(user1).withdraw(1, { value: nativeFee.toString()});
        })
    })
})
