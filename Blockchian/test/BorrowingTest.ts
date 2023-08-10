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

        await BorrowingContract.initializeTreasury(treasury.address);
        
        [owner, user1, user2] = await ethers.getSigners();
        return {Token,pToken,CDSContract,BorrowingContract,treasury,owner,user1,user2}
    }

        it.only("Should deposit ETH",async function(){
            const {BorrowingContract,treasury,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
            console.log("Trinity supply",await Token.totalSupply());
        })

})