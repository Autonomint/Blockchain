const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { Borrowing, CDS, TrinityStablecoin, ProtocolToken, Treasury} from "../typechain-types";

describe("Borrowing Contract",function(){

    let CDSContract : CDS;
    let BorrowingContract : Borrowing;
    let Token : TrinityStablecoin;
    let pToken : ProtocolToken;
    let treasury : Treasury;
    let owner: any;
    let user1: any;
    let user2: any;

    let wethGateway = "0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C";
    let cEther = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
    let priceFeedAddress = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";

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
        treasury = await Treasury.deploy(Token.address,wethGateway,cEther);
        await treasury.transferOwnership(BorrowingContract.address);

        await BorrowingContract.initializeTreasury(treasury.address);
        await BorrowingContract.setLTV(80);
        
        [owner, user1, user2] = await ethers.getSigners();
        return {Token,pToken,CDSContract,BorrowingContract,treasury,owner,user1,user2}
    }

    describe("Should deposit ETH and mint Trinity",function(){
        it("Should deposit ETH",async function(){
            const {BorrowingContract,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            expect(await Token.totalSupply()).to.be.equal(ethers.utils.parseEther("800"));
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
            const tx =  BorrowingContract.depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith("LTV must be set to non-zero value before providing loans");
        })
    })

})