const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers } from "hardhat";
import { Contract,utils,providers,Wallet, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { Borrowing, CDS, TrinityStablecoin, ProtocolToken, Treasury} from "../typechain-types";
import {
    wethGateway,
    priceFeedAddress,
    aTokenAddress,
    aavePoolAddress,
    cEther,
    INFURA_URL,
    aTokenABI,
    cETH_ABI,
    } from "./index";

describe("Borrowing Contract",function(){

    let CDSContract : CDS;
    let BorrowingContract : Borrowing;
    let Token : TrinityStablecoin;
    let pToken : ProtocolToken;
    let treasury : Treasury;
    let owner: any;
    let user1: any;
    let user2: any;


    async function deployer(){
        const TrinityStablecoin = await ethers.getContractFactory("TrinityStablecoin");
        Token = await TrinityStablecoin.deploy();

        const ProtocolToken = await ethers.getContractFactory("ProtocolToken");
        pToken = await ProtocolToken.deploy();

        const CDS = await ethers.getContractFactory("CDS");
        CDSContract = await CDS.deploy(Token.address);

        const Borrowing = await ethers.getContractFactory("Borrowing");
        BorrowingContract = await Borrowing.deploy(Token.address,CDSContract.address,pToken.address,priceFeedAddress);

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(BorrowingContract.address,wethGateway,cEther,aavePoolAddress,aTokenAddress);

        await BorrowingContract.initializeTreasury(treasury.address);
        await BorrowingContract.setLTV(80);

        const provider = new ethers.providers.JsonRpcProvider(INFURA_URL);
        const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",provider);

        const aToken = new ethers.Contract(aTokenAddress,aTokenABI,signer);
        const cETH = new ethers.Contract(cEther,cETH_ABI,signer);

        [owner,user1,user2] = await ethers.getSigners();

        return {Token,pToken,CDSContract,BorrowingContract,treasury,aToken,cETH,owner,user1,user2,provider}
    }

    describe("Should deposit ETH and mint Trinity",function(){
        it("Should deposit ETH",async function(){
            const {BorrowingContract,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            expect(await Token.totalSupply()).to.be.equal(ethers.utils.parseEther("800"));
        })
    })

    describe("Should get the ETH/USD price",function(){
        it("Should get ETH/USD price",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = await BorrowingContract.getUSDValue();
            console.log("ETH/USD",tx);
        })
    })

    describe("Should revert errors",function(){
        it("Should revert if zero eth is deposited",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const tx =  BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("0")});
            expect(tx).to.be.revertedWith("Cannot deposit zero tokens");
        })

        it("Should revert if LTV set to zero value before providing loans",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await BorrowingContract.setLTV(0);          
            const timeStamp = await time.latest();
            const tx =  BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith("LTV must be set to non-zero value before providing loans");
        })

        it("Should revert if called by other than borrowing contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const tx =  treasury.connect(user1).deposit(user1.address,1000,timeStamp,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");    
        })

        it("Should return if the address is invalid",async function(){
            const {treasury} = await loadFixture(deployer);
            expect(treasury.setBorrowingContract(user1.address)).to.be.revertedWith("Input address is invalid");
        })
    })

    describe("Should update all state changes correctly",function(){
        it("Should update deposited amount",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            const tx = await treasury.borrowing(user1.address);
            expect(tx[0]).to.be.equal(ethers.utils.parseEther("1"))
        })

        it.only("Should update depositedAmount correctly if deposited multiple times",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("3")});                    
            const tx = await treasury.borrowing(user1.address);
            console.log(tx);
            console.log(await treasury.depositDetails());
            expect(tx[0]).to.be.equal(ethers.utils.parseEther("6"))
        })

        it("Should update hasDeposited or not",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            const tx = await treasury.borrowing(user1.address);
            expect(tx[3]).to.be.equal(true);
        })

        it("Should update borrowerIndex",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            const tx = await treasury.borrowing(user1.address);
            expect(tx[4]).to.be.equal(1);
        })

        it("Should update borrowerIndex correctly if deposited multiple times",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("3")});                    
            const tx = await treasury.borrowing(user1.address);
            expect(tx[4]).to.be.equal(3);
        })

        it("Should update totalVolumeOfBorrowersinUSD",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("2")});
            expect(await treasury.totalVolumeOfBorrowersinUSD()).to.be.equal(ethers.utils.parseEther("2000"));
        })

        it("Should update totalVolumeOfBorrowersinUSD if multiple users deposit in different ethPrice",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user2).depositTokens(1500,timeStamp,{value: ethers.utils.parseEther("2")});
            expect(await treasury.totalVolumeOfBorrowersinUSD()).to.be.equal(ethers.utils.parseEther("5000"));
        })

        it("Should update totalVolumeOfBorrowersinWei",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user2).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("3")});          
            expect(await treasury.totalVolumeOfBorrowersinWei()).to.be.equal(ethers.utils.parseEther("5"));
        })
    })

})