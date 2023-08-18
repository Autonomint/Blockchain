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

    describe("Should deposit and withdraw Eth in Aave",function(){
        it("Should revert if zero eth is deposited to Aave",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).depositToAaveProtocol();
            expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroDeposit");
        })

        it("Should deposit eth and mint aTokens",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("100")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();
        })

        it("Should revert if zero Eth withdraw from Compound",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).withdrawFromAaveProtocol(1,ethers.utils.parseEther("0"));
            expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroWithdraw");
        })

        it("Should withdraw eth from Aave",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("100")});
            console.log(await treasury.getBalanceInTreasury());

            await BorrowingContract.connect(owner).depositToAaveProtocol();
            console.log(await treasury.getBalanceInTreasury());

            await BorrowingContract.connect(owner).withdrawFromAaveProtocol(1,ethers.utils.parseEther("25"));
            console.log(await treasury.getBalanceInTreasury());
        })

        it("Should update deposit index correctly",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("100")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            await BorrowingContract.connect(owner).depositToAaveProtocol();

            const tx = await treasury.protocolDeposit(0);
            expect(tx[0]).to.be.equal(2);
        })

        it("Should update depositedAmount correctly",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("100")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            await BorrowingContract.connect(owner).depositToAaveProtocol();

            const tx = await treasury.protocolDeposit(0);
            expect(tx[1]).to.be.equal(ethers.utils.parseEther("43.75"));
        })
    })

})