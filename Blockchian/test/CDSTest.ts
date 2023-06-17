import { expect } from "chai";
import { ethers, network } from "hardhat";
import type { Wallet } from "ethers";
import {CDS,Borrowing,TrinityStablecoin} from "../typechain-types";
import { time } from'@nomicfoundation/hardhat-network-helpers';
import { ChildProcess } from "child_process";
import { token } from "../typechain-types/contracts";


describe("Testing contracts ", function(){

    let CDSContract : CDS;
    let BorrowingContract : Borrowing;
    let Token : TrinityStablecoin;
    let owner: any;
    let user1: any;
    let user2: any;
    
    before(async () => {
    const TrinityStablecoin = await ethers.getContractFactory("TrinityStablecoin");
    Token = await TrinityStablecoin.deploy();

    const CDS = await ethers.getContractFactory("CDS");
    CDSContract = await CDS.deploy(Token.address);

    const Borrowing = await ethers.getContractFactory("Borrowing");
    BorrowingContract = await Borrowing.deploy(Token.address,CDSContract.address);

    [owner, user1, user2] = await ethers.getSigners();
    })
    
    describe("Minting tokens and transfering tokens", async function(){
        it("Should check Trinity Token contract & Owner of contracts",async () => {
            expect(await CDSContract.Trinity_token()).to.be.equal(Token.address);
            expect(await CDSContract.owner()).to.be.equal(owner.address);
            expect(await Token.owner()).to.be.equal(owner.address);
        })

        it("Should Mint token", async function() {
          console.log("Owner",owner.address);    
          await Token.mint(owner.address,10000000000000);
          expect( (await (Token.balanceOf(owner.address))).toNumber()).to.be.equal(10000000000000);
        })

        it("should deposit trinity into CDS", async function(){
            await Token.approve(CDSContract.address,10000000000000);
            expect( (await (Token.allowance(owner.address,CDSContract.address))).toNumber()).to.be.equal(10000000000000);
            const timestamp = await time.latest();
            await CDSContract.deposit(10000000000000,timestamp);
            //console.log(await CDSContract.amountAvailableToBorrow())
            expect((await (CDSContract.totalCdsDepositedAmount())).toNumber()).to.be.equal(10000000000000);
            let tx = await CDSContract.cdsDetails(owner.address);
            expect(await tx.hasDeposited).to.be.equal(true);
            expect((await tx.index).toNumber()).to.be.equal(1);
            
        })

        it("should deposit ether for Trinity",async () => {
            await BorrowingContract.setLTV(100);
            const timestamp = await time.latest();
            await BorrowingContract.depositTokens(200,timestamp,20,0,{value: ethers.utils.parseEther("0.000005")});
            expect(await BorrowingContract.totalVolumeOfBorrowersinWei()).to.be.equal(ethers.utils.parseEther("0.000005"));
        })
        
    })

    describe("Checking revert conditions", function(){
        it("Should revert if zero balance is deposited in CDS",async () => {
            await Token.mint(user1.address,10000000000000);
            await Token.connect(user1).approve(CDSContract.address,10000000000000);
            const timestamp = await time.latest();
            await expect( CDSContract.connect(user1).deposit(0,timestamp)).to.be.revertedWith("Deposit amount should not be zero");
        })

        it("Should revert with insufficient balance ",async () => {
            const timestamp = await time.latest();
            
           await expect( CDSContract.connect(user1).deposit(1000000000000000,timestamp)).to.be.revertedWith("Insufficient balance with msg.sender")
        })

        it("Should revert if zero Rth are deposited in Borrowing contract",async () => {
            const timestamp = await time.latest();
            await expect((BorrowingContract.depositTokens(200,timestamp,20,0,{value: ethers.utils.parseEther("0.0")}))).to.be.revertedWith("Cannot deposit zero tokens");
        })

        it("should revert with Doesnt have enough value in cds",async () => {
            const timestamp = await time.latest();
            await  expect((  BorrowingContract.depositTokens(200,timestamp,200,0,{value: ethers.utils.parseEther("2.0")}))).to.be.revertedWith("Doesnt have enough value in cds");
        })

        it("should revert with 'LTV must be set to non-zero value before providing loans'",async () => {
            const timestamp = await time.latest();
            await BorrowingContract.setLTV(0);
            await  expect((BorrowingContract.connect(user2).depositTokens(200,timestamp,20,0,{value: ethers.utils.parseEther("0.000005")}))).to.be.revertedWith("LTV must be set to non-zero value before providing loans");
        })
    })

    describe.only("To check CDS withdrawl function",function(){
        it("Should withdraw from cds",async () => {
            await BorrowingContract.setLTV(100);
            //console.log(await Token.balanceOf(user1.address))
            await Token.mint(user1.address,10000000000000);
            console.log("Bal",Token.balanceOf(user1.address));
            await Token.connect(user1).approve(CDSContract.address,10000000000);
            const timestamp = await time.latest();
            await  CDSContract.connect(user1).deposit(1000,timestamp);
            await BorrowingContract.connect(user2).depositTokens(100,timestamp,20,0,{value: ethers.utils.parseEther("0.000000000000002500")});
           let x =  await CDSContract.connect(user1).withdraw(user1.address,1,1,timestamp);
           console.log(x);

        })
    })
})