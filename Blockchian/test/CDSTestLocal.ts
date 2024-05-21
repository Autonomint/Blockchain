const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers,upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { BorrowLib } from "../typechain-types";
import { Contract, ContractFactory, ZeroAddress } from 'ethers'
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

        const USDaStablecoin = await ethers.getContractFactory("TestUSDaStablecoin");
        const TokenA = await upgrades.deployProxy(USDaStablecoin,[
            "Test USDa TOKEN",
            "TUSDa",
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'});

        const TokenB = await upgrades.deployProxy(USDaStablecoin,[
            "Test USDa TOKEN",
            "TUSDa",
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()],{initializer:'initialize'},{kind:'uups'});

        const ABONDToken = await ethers.getContractFactory("TestABONDToken");
        const abondTokenA = await upgrades.deployProxy(ABONDToken, {initializer: 'initialize'}, {kind:'uups'});
        const abondTokenB = await upgrades.deployProxy(ABONDToken, {initializer: 'initialize'}, {kind:'uups'});

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


        const BorrowLiq = await ethers.getContractFactory("BorrowLiquidation",{
            libraries: {
                BorrowLib:await borrowLib.getAddress()
            }
        });

        const BorrowingLiquidationA = await upgrades.deployProxy(BorrowLiq,[
            await BorrowingContractA.getAddress(),
            await CDSContractA.getAddress(),
            await TokenA.getAddress(),
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'}); 

        const BorrowingLiquidationB = await upgrades.deployProxy(BorrowLiq,[
            await BorrowingContractB.getAddress(),
            await CDSContractB.getAddress(),
            await TokenB.getAddress(),
        ],{initializer:'initialize',
            unsafeAllowLinkedLibraries:true
        },{kind:'uups'}); 

        const Treasury = await ethers.getContractFactory("Treasury");
        const treasuryA = await upgrades.deployProxy(Treasury,[
            await BorrowingContractA.getAddress(),
            await TokenA.getAddress(),
            await abondTokenA.getAddress(),
            await CDSContractA.getAddress(),
            await BorrowingLiquidationA.getAddress(),
            await usdtA.getAddress(),
            await mockEndpointV2A.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize'},{kind:'uups'});

        const treasuryB = await upgrades.deployProxy(Treasury,[
            await BorrowingContractB.getAddress(),
            await TokenB.getAddress(),
            await abondTokenB.getAddress(),
            await CDSContractB.getAddress(),
            await BorrowingLiquidationB.getAddress(),
            await usdtB.getAddress(),
            await mockEndpointV2B.getAddress(),
            await owner.getAddress()
        ],{initializer:'initialize'},{kind:'uups'});

        const Option = await ethers.getContractFactory("Options");
        const optionsA = await upgrades.deployProxy(Option,[await treasuryA.getAddress(),await CDSContractA.getAddress(),await BorrowingContractA.getAddress()],{initializer:'initialize'},{kind:'uups'});
        const optionsB = await upgrades.deployProxy(Option,[await treasuryB.getAddress(),await CDSContractB.getAddress(),await BorrowingContractB.getAddress()],{initializer:'initialize'},{kind:'uups'});

        await mockEndpointV2B.setDestLzEndpoint(await TokenA.getAddress(), mockEndpointV2A.getAddress())
        await mockEndpointV2A.setDestLzEndpoint(await TokenB.getAddress(), mockEndpointV2B.getAddress())

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

        await usdtA.connect(owner).setPeer(eidB, ethers.zeroPadValue(await usdtB.getAddress(), 32))
        await usdtB.connect(owner).setPeer(eidA, ethers.zeroPadValue(await usdtA.getAddress(), 32))

        await abondTokenA.setBorrowingContract(await BorrowingContractA.getAddress());
        await abondTokenB.setBorrowingContract(await BorrowingContractB.getAddress());

        await multiSignA.connect(owner).approveSetterFunction([0,1,3,4,5,6,7,8,9]);
        await multiSignA.connect(owner1).approveSetterFunction([0,1,3,4,5,6,7,8,9]);
        await multiSignB.connect(owner).approveSetterFunction([0,1,3,4,5,6,7,8,9]);
        await multiSignB.connect(owner1).approveSetterFunction([0,1,3,4,5,6,7,8,9]);

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

        await usdtA.setDstEid(eidB);
        await usdtB.setDstEid(eidA);

        await BorrowingContractA.connect(owner).setTreasury(await treasuryA.getAddress());
        await BorrowingContractA.connect(owner).setOptions(await optionsA.getAddress());
        await BorrowingContractA.connect(owner).setBorrowLiquidation(await BorrowingLiquidationA.getAddress());
        await BorrowingContractA.connect(owner).setLTV(80);
        await BorrowingContractA.connect(owner).setBondRatio(4);
        await BorrowingContractA.connect(owner).setAPR(BigInt("1000000001547125957863212449"));

        await BorrowingContractB.connect(owner).setTreasury(await treasuryB.getAddress());
        await BorrowingContractB.connect(owner).setOptions(await optionsB.getAddress());
        await BorrowingContractB.connect(owner).setBorrowLiquidation(await BorrowingLiquidationB.getAddress());
        await BorrowingContractB.connect(owner).setLTV(80);
        await BorrowingContractB.connect(owner).setBondRatio(4);
        await BorrowingContractB.connect(owner).setAPR(BigInt("1000000001547125957863212449"));

        await BorrowingLiquidationA.connect(owner).setTreasury(await treasuryA.getAddress());
        await BorrowingLiquidationB.connect(owner).setTreasury(await treasuryB.getAddress());

        await CDSContractA.connect(owner).setTreasury(await treasuryA.getAddress());
        await CDSContractA.connect(owner).setBorrowingContract(await BorrowingContractA.getAddress());
        await CDSContractA.connect(owner).setBorrowLiquidation(await BorrowingLiquidationA.getAddress());
        await CDSContractA.connect(owner).setUSDaLimit(80);
        await CDSContractA.connect(owner).setUsdtLimit(20000000000);

        await CDSContractB.connect(owner).setTreasury(await treasuryB.getAddress());
        await CDSContractB.connect(owner).setBorrowingContract(await BorrowingContractB.getAddress());
        await CDSContractB.connect(owner).setBorrowLiquidation(await BorrowingLiquidationB.getAddress());
        await CDSContractB.connect(owner).setUSDaLimit(80);
        await CDSContractB.connect(owner).setUsdtLimit(20000000000);

        await BorrowingContractA.calculateCumulativeRate();
        await BorrowingContractB.calculateCumulativeRate();

        await treasuryA.connect(owner).setDstTreasuryAddress(await treasuryB.getAddress());
        await treasuryA.connect(owner).setExternalProtocolAddresses(
            wethGatewayMainnet,
            cometMainnet,
            aavePoolAddressMainnet,
            aTokenAddressMainnet,
            wethAddressMainnet,
        )

        await treasuryB.connect(owner).setDstTreasuryAddress(await treasuryA.getAddress());
        await treasuryB.connect(owner).setExternalProtocolAddresses(
            wethGatewayMainnet,
            cometMainnet,
            aavePoolAddressMainnet,
            aTokenAddressMainnet,
            wethAddressMainnet,
        )

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

    describe("Minting tokens and transfering tokens", async function(){

        it("Should check Trinity Token contract & Owner of contracts",async () => {
            const{CDSContractA,TokenA} = await loadFixture(deployer);
            expect(await CDSContractA.usda()).to.be.equal(await TokenA.getAddress());
            expect(await CDSContractA.owner()).to.be.equal(await owner.getAddress());
            expect(await TokenA.owner()).to.be.equal(await owner.getAddress());
        })

        it("Should Mint token", async function() {
            const{TokenA} = await loadFixture(deployer);
            await TokenA.mint(owner.getAddress(),ethers.parseEther("1"));
            expect(await TokenA.balanceOf(owner.getAddress())).to.be.equal(ethers.parseEther("1"));
        })

        it("should deposit USDT into CDS",async function(){
            const {CDSContractA,CDSContractB,usdtA,usdtB} = await loadFixture(deployer);

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = "0x00030100110100000000000000000000000000030d40";

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0,options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            await usdtB.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtB.connect(user1).approve(CDSContractB.getAddress(),10000000000);
            await CDSContractB.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});
            
            expect(await CDSContractB.totalCdsDepositedAmount()).to.be.equal(10000000000);

            let tx = await CDSContractB.cdsDetails(user1.getAddress());
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(1);
        })

        it("should deposit USDT and USDa into CDS", async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),30000000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),30000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0,options, false)

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

    describe("Checking revert conditions", function(){

        it("should revert if Liquidation amount can't greater than deposited amount", async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(owner).deposit(3000000000,700000000,true,ethers.parseEther("5000"))).to.be.revertedWith("Liquidation amount can't greater than deposited amount");
        })

        it("should revert if 0 USDT deposit into CDS", async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),10000000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),10000000000);

            expect(await usdtA.allowance(owner.getAddress(),CDSContractA.getAddress())).to.be.equal(10000000000);

            await expect(CDSContractA.deposit(0,ethers.parseEther("1"),true,ethers.parseEther("0.5"))).to.be.revertedWith("100% of amount must be USDT");
        })

        it("should revert if USDT deposit into CDS is greater than 20%", async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),30000000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),30000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.deposit(20000000000,0,true,10000000000,{ value: nativeFee.toString()});

            await TokenA.mint(owner.getAddress(),700000000)
            await TokenA.connect(owner).approve(CDSContractA.getAddress(),700000000);

            await expect(CDSContractA.connect(owner).deposit(3000000000,700000000,true,500000000,{ value: nativeFee.toString()})).to.be.revertedWith("Required USDa amount not met");
        })

        it("should revert if Insufficient USDa balance with msg.sender", async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),30000000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),30000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.deposit(20000000000,0,true,10000000000,{ value: nativeFee.toString()});

            await TokenA.mint(owner.getAddress(),70000000)
            await TokenA.connect(owner).approve(CDSContractA.getAddress(),70000000);

            await expect(CDSContractA.connect(owner).deposit(200000000,800000000,true,500000000,{ value: nativeFee.toString()})).to.be.revertedWith("Insufficient USDa balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),20100000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),20100000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.deposit(20000000000,0,true,10000000000,{ value: nativeFee.toString()});

            await TokenA.mint(owner.getAddress(),800000000)
            await TokenA.connect(owner).approve(CDSContractA.getAddress(),800000000);


            await expect(CDSContractA.connect(owner).deposit(200000000,800000000,true,500000000,{ value: nativeFee.toString()})).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContractA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(owner.getAddress(),10000000000);
            await usdtA.connect(owner).approve(CDSContractA.getAddress(),10000000000);

            expect(await usdtA.allowance(owner.getAddress(),CDSContractA.getAddress())).to.be.equal(10000000000);

            await expect(CDSContractA.deposit(20000000000,0,true,10000000000)).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("Should revert if zero balance is deposited in CDS",async () => {
            const {CDSContractA} = await loadFixture(deployer);
            await expect( CDSContractA.connect(user1).deposit(0,0,true,ethers.parseEther("1"))).to.be.revertedWith("Deposit amount should not be zero");
        })

        it("Should revert if Input address is invalid",async () => {
            const {CDSContractA} = await loadFixture(deployer);  
            await expect( CDSContractA.connect(owner).setBorrowingContract(ethers.ZeroAddress)).to.be.revertedWith("Input address is invalid");
            await expect( CDSContractA.connect(owner).setBorrowingContract(user1.getAddress())).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the index is not valid",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(user1).withdraw(1)).to.be.revertedWith("user doesn't have the specified index");
        })

        it("Should revert if the caller is not owner for setTreasury",async function(){
            const {CDSContractA,treasuryA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(user1).setTreasury(treasuryA.getAddress())).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the caller is not owner for setWithdrawTimeLimit",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(user1).setWithdrawTimeLimit(1000)).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the caller is not owner for setBorrowingContract",async function(){
            const {BorrowingContractA,CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(user1).setBorrowingContract(BorrowingContractA.getAddress())).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the Treasury address is zero",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(owner).setTreasury(ZeroAddress)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the Treasury address is not contract address",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(owner).setTreasury(user2.getAddress())).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the zero sec is given in setWithdrawTimeLimit",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(owner).setWithdrawTimeLimit(0)).to.be.revertedWith("Withdraw time limit can't be zero");
        })

        it("Should revert if USDa limit can't be zero",async () => {
            const {CDSContractA} = await loadFixture(deployer);  
            await expect( CDSContractA.connect(owner).setUSDaLimit(0)).to.be.revertedWith("USDa limit can't be zero");
        })

        it("Should revert if the caller is not owner for setUSDaLImit",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(user1).setUSDaLimit(10)).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if USDT limit can't be zero",async () => {
            const {CDSContractA} = await loadFixture(deployer);  
            await expect( CDSContractA.connect(owner).setUsdtLimit(0)).to.be.revertedWith("USDT limit can't be zero");
        })

        it("Should revert if the caller is not owner for setUsdtLImit",async function(){
            const {CDSContractA} = await loadFixture(deployer);
            await expect(CDSContractA.connect(user1).setUsdtLimit(1000)).to.be.revertedWith("Caller is not an admin");
        })
    })

    describe("Should update variables correctly",function(){
        it("Should update treasury correctly",async function(){
            const {treasuryA,CDSContractA,multiSignA} = await loadFixture(deployer);
            await multiSignA.connect(owner).approveSetterFunction([6]);
            await multiSignA.connect(owner1).approveSetterFunction([6]);
            await CDSContractA.connect(owner).setTreasury(treasuryA.getAddress());
            expect (await CDSContractA.treasuryAddress()).to.be.equal(await treasuryA.getAddress());     
        })
        it("Should update withdrawTime correctly",async function(){
            const {CDSContractA,multiSignA} = await loadFixture(deployer);
            await multiSignA.connect(owner).approveSetterFunction([2]);
            await multiSignA.connect(owner1).approveSetterFunction([2]);
            await CDSContractA.connect(owner).setWithdrawTimeLimit(1500);
            expect (await CDSContractA.withdrawTimeLimit()).to.be.equal(1500);     
        })
    })

    describe("To check CDS withdrawl function",function(){
        it("Should withdraw from cds,both chains have cds amount and eth deposit",async () => {
            const {BorrowingContractB,BorrowingContractA,CDSContractA,CDSContractB,usdtA,usdtB,treasuryB} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdtA.mint(user2.getAddress(),20000000000)
            await usdtA.mint(user1.getAddress(),50000000000)
            await usdtA.connect(user2).approve(CDSContractA.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),50000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.connect(user2).deposit(12000000000,0,true,12000000000, { value: nativeFee.toString()});

            await usdtB.mint(user2.getAddress(),20000000000)
            await usdtB.mint(user1.getAddress(),50000000000)
            await usdtB.connect(user2).approve(CDSContractB.getAddress(),20000000000);
            await usdtB.connect(user1).approve(CDSContractB.getAddress(),50000000000);

            await CDSContractB.connect(user1).deposit(2000000000,0,true,1500000000, { value: nativeFee.toString()});

            const depositAmount = ethers.parseEther("1");

            let nativeFee1 = 0
            ;[nativeFee1] = await BorrowingContractB.quote(eidA, [5,10,15,20,25,30,35,40],options, false)
            let nativeFee2 = 0
            ;[nativeFee2] = await treasuryB.quote(eidA, 1, [ZeroAddress,0],[ZeroAddress,0],options, false)
            
            await BorrowingContractB.connect(user1).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            await BorrowingContractA.connect(user2).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})

            // const sendParam = [
            //     eidB,
            //     ethers.zeroPadValue(await treasuryB.getAddress(), 32),
            //     ethers.parseEther("0.002"),
            //     ethers.parseEther("0.002"),
            //     Options.newOptions().addExecutorLzReceiveOption(60000, 0),
            //     '0x',
            //     '0x',
            // ]

            // let nativeFee3 = 0
            // ;[nativeFee3] = await TokenA.quoteSend(sendParam, false)

            // const optionsA = Options.newOptions().addExecutorLzReceiveOption(250000, 0).addExecutorNativeDropOption(
            //     nativeFee3, 
            //     ethers.zeroPadValue(await treasuryB.getAddress(), 32).toString()
            // ).toHex().toString();
            
            const optionsA = Options.newOptions().addExecutorLzReceiveOption(600000, 0).toHex().toString()
            let nativeFee2a = 0
            ;[nativeFee2a] = await treasuryB.quote(eidA, 2, [ZeroAddress,0],[ZeroAddress,0],optionsA, false)

            await CDSContractA.connect(user2).withdraw(1, { value: nativeFee + nativeFee2a});
        })

        it("Should withdraw from cds,both chains have cds amount and one chain have eth deposit",async () => {
            const {BorrowingContractB,CDSContractA,CDSContractB,usdtA,usdtB,treasuryB} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdtA.mint(user2.getAddress(),20000000000)
            await usdtA.mint(user1.getAddress(),50000000000)
            await usdtA.connect(user2).approve(CDSContractA.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),50000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.connect(user2).deposit(12000000000,0,true,12000000000, { value: nativeFee.toString()});

            await usdtB.mint(user2.getAddress(),20000000000)
            await usdtB.mint(user1.getAddress(),50000000000)
            await usdtB.connect(user2).approve(CDSContractB.getAddress(),20000000000);
            await usdtB.connect(user1).approve(CDSContractB.getAddress(),50000000000);

            await CDSContractB.connect(user1).deposit(2000000000,0,true,1500000000, { value: nativeFee.toString()});

            const depositAmount = ethers.parseEther("1");

            let nativeFee1 = 0
            ;[nativeFee1] = await BorrowingContractB.quote(eidA, [5,10,15,20,25,30,35,40],options, false)
            let nativeFee2 = 0
            ;[nativeFee2] = await treasuryB.quote(eidA, 1, [ZeroAddress,0],[ZeroAddress,0],options, false)
            
            await BorrowingContractB.connect(user1).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            
            const optionsA = Options.newOptions().addExecutorLzReceiveOption(600000, 0).toHex().toString()
            let nativeFee2a = 0
            ;[nativeFee2a] = await treasuryB.quote(eidA, 1, [ZeroAddress,0], [ZeroAddress,0], optionsA, false)

            await CDSContractA.connect(user2).withdraw(1, { value: nativeFee + nativeFee2a});
        })

        it("Should withdraw from cds,one chain have cds amount and both chains have eth deposit",async () => {
            const {BorrowingContractB,BorrowingContractA,CDSContractA,usdtA,treasuryB} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdtA.mint(user2.getAddress(),20000000000)
            await usdtA.mint(user1.getAddress(),50000000000)
            await usdtA.connect(user2).approve(CDSContractA.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),50000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0,options, false)

            await CDSContractA.connect(user2).deposit(12000000000,0,true,12000000000, { value: nativeFee.toString()});

            const depositAmount = ethers.parseEther("1");;

            let nativeFee1 = 0
            ;[nativeFee1] = await BorrowingContractB.quote(eidA, [5,10,15,20,25,30,35,40], options, false)
            let nativeFee2 = 0
            ;[nativeFee2] = await treasuryB.quote(eidA,1, [ZeroAddress,0],[ZeroAddress,0],options, false)
            
            await BorrowingContractB.connect(user1).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            await BorrowingContractB.connect(user2).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            await BorrowingContractA.connect(user2).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            
            const optionsA = Options.newOptions().addExecutorLzReceiveOption(600000, 0).toHex().toString()
            let nativeFee2a = 0
            ;[nativeFee2a] = await treasuryB.quote(eidA, 2, [ZeroAddress,0],[ZeroAddress,0],optionsA, false)

            const tx = CDSContractA.connect(user2).withdraw(1, { value: nativeFee + nativeFee2a});
            await expect(tx).to.be.revertedWith("CDS: Not enough fund in CDS")

        })

        it("Should withdraw from cds,one chain have cds amount and one chain have eth deposit",async () => {
            const {BorrowingContractB,CDSContractA,usdtA,treasuryB} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdtA.mint(user2.getAddress(),20000000000)
            await usdtA.mint(user1.getAddress(),50000000000)
            await usdtA.connect(user2).approve(CDSContractA.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),50000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.connect(user2).deposit(12000000000,0,true,12000000000, { value: nativeFee.toString()});

            const depositAmount = ethers.parseEther("1");

            let nativeFee1 = 0
            ;[nativeFee1] = await BorrowingContractB.quote(eidA, [5,10,15,20,25,30,35,40], options, false)
            let nativeFee2 = 0
            ;[nativeFee2] = await treasuryB.quote(eidA, 2, [ZeroAddress,0],[ZeroAddress,0],options, false)
            
            await BorrowingContractB.connect(user1).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            await BorrowingContractB.connect(user2).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})

            await BorrowingContractB.connect(user2).depositTokens(
                100000,
                timeStamp,
                1,
                110000,
                ethVolatility,
                depositAmount,
                {value: (depositAmount + BigInt(nativeFee1) + BigInt(nativeFee2) + BigInt(nativeFee))})
            
            const optionsA = Options.newOptions().addExecutorLzReceiveOption(600000, 0).toHex().toString()
            let nativeFee2a = 0
            ;[nativeFee2a] = await treasuryB.quote(eidA, 2, [ZeroAddress,0],[ZeroAddress,0],optionsA, false)

            await BorrowingContractB.connect(owner).liquidate(
                await user2.getAddress(),
                1,
                80000,
                {value: (nativeFee1 + nativeFee2a + nativeFee).toString()})

            await CDSContractA.connect(user2).withdraw(1, { value: nativeFee + nativeFee2a});
            // await expect(tx).to.be.revertedWith("CDS: Not enough fund in CDS")
        })

        it("Should withdraw from cds",async () => {
            const {CDSContractA,usdtA} = await loadFixture(deployer);

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0,options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            await CDSContractA.connect(user1).withdraw(1, { value: nativeFee.toString()});
        })

        it("Should revert Already withdrawn",async () => {
            const {CDSContractA,usdtA} = await loadFixture(deployer);

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0,options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            await CDSContractA.connect(user1).withdraw(1, { value: nativeFee.toString()});
            const tx =  CDSContractA.connect(user1).withdraw(1, { value: nativeFee.toString()});
            await expect(tx).to.be.revertedWith("Already withdrawn");
        })

        it("Should revert cannot withdraw before the withdraw time limit",async () => {
            const {CDSContractA,usdtA,multiSignA} = await loadFixture(deployer);

            await multiSignA.connect(owner).approveSetterFunction([2]);
            await multiSignA.connect(owner1).approveSetterFunction([2]);
            await CDSContractA.connect(owner).setWithdrawTimeLimit(1000);

            await usdtA.connect(user1).mint(user1.getAddress(),10000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),10000000000);
            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()

            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB,1,123,123,123,[0,0,0,0],0,options, false)
            await CDSContractA.connect(user1).deposit(10000000000,0,true,10000000000, { value: nativeFee.toString()});

            const tx =  CDSContractA.connect(user1).withdraw(1, { value: nativeFee.toString()});
            await expect(tx).to.be.revertedWith("cannot withdraw before the withdraw time limit");
        })
    })

    describe("Should redeem USDT correctly",function(){
        it("Should redeem USDT correctly",async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(user1.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),20000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            await CDSContractA.connect(user1).deposit(20000000000,0,true,10000000000,{ value: nativeFee.toString()});

            await TokenA.mint(owner.getAddress(),800000000);
            await TokenA.connect(owner).approve(CDSContractA.getAddress(),800000000);

            await CDSContractA.connect(owner).redeemUSDT(800000000,1500,1000,{ value: nativeFee.toString()});

            expect(await TokenA.totalSupply()).to.be.equal(20000000000);
            expect(await usdtA.balanceOf(owner.getAddress())).to.be.equal(1200000000);
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContractA} = await loadFixture(deployer);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            const tx = CDSContractA.connect(owner).redeemUSDT(0,1500,1000,{ value: nativeFee.toString()});
            await expect(tx).to.be.revertedWith("Amount should not be zero");
        })

        it("Should revert Insufficient USDa balance",async function(){
            const {CDSContractA,TokenA} = await loadFixture(deployer);
            await TokenA.mint(owner.getAddress(),80000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)

            const tx = CDSContractA.connect(owner).redeemUSDT(800000000,1500,1000,{ value: nativeFee.toString()});
            await expect(tx).to.be.revertedWith("Insufficient balance");
        })
    })

    describe("Should calculate value correctly",function(){
        it("Should calculate value for no deposit in borrowing",async function(){
            const {CDSContractA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(user1.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),20000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)
            await CDSContractA.connect(user1).deposit(20000000000,0,true,10000000000,{ value: nativeFee.toString()});
        })

        it("Should calculate value for no deposit in borrowing and 2 deposit in cds",async function(){
            const {CDSContractA,TokenA,usdtA} = await loadFixture(deployer);
            await usdtA.mint(user1.getAddress(),20000000000);
            await usdtA.connect(user1).approve(CDSContractA.getAddress(),20000000000);

            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex().toString()
            let nativeFee = 0
            ;[nativeFee] = await CDSContractA.quote(eidB, 1, 123,123,123,[0,0,0,0],0, options, false)
            await CDSContractA.connect(user1).deposit(20000000000,0,true,10000000000,{ value: nativeFee.toString()});

            await TokenA.mint(user2.getAddress(),4000000000);
            await TokenA.connect(user2).approve(CDSContractA.getAddress(),4000000000);
            await CDSContractA.connect(user2).deposit(0,4000000000,true,4000000000,{ value: nativeFee.toString()});

            await CDSContractA.connect(user1).withdraw(1,{ value: nativeFee.toString()});
        })
    })
})
