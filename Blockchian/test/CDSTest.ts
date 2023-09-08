import { expect } from "chai";
import { ethers, network } from "hardhat";
import type { Wallet } from "ethers";
import {Borrowing,Treasury,TrinityStablecoin,ProtocolToken,CDSTest} from "../typechain-types";
import { loadFixture,time } from'@nomicfoundation/hardhat-network-helpers';
import { ChildProcess } from "child_process";
import { token } from "../typechain-types/contracts";
import {
    wethGateway,
    priceFeedAddress,
    aTokenAddress,
    aavePoolAddress,
    cEther,
    } from "./utils/index"


describe("Testing contracts ", function(){

    let CDSContract : CDSTest;
    let BorrowingContract : Borrowing;
    let treasury : Treasury;
    let Token : TrinityStablecoin;
    let pToken : ProtocolToken;
    let owner: any;
    let user1: any;
    let user2: any;
    
    async function deployer(){
        const TrinityStablecoin = await ethers.getContractFactory("TrinityStablecoin");
        Token = await TrinityStablecoin.deploy();

        const ProtocolToken = await ethers.getContractFactory("ProtocolToken");
        pToken = await ProtocolToken.deploy();

        const CDS = await ethers.getContractFactory("CDSTest");
        CDSContract = await CDS.deploy(Token.address);

        const Borrowing = await ethers.getContractFactory("Borrowing");
        BorrowingContract = await Borrowing.deploy(Token.address,CDSContract.address,pToken.address,priceFeedAddress);

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(BorrowingContract.address,Token.address,CDSContract.address,wethGateway,cEther,aavePoolAddress,aTokenAddress);

        await BorrowingContract.initializeTreasury(treasury.address);
        await BorrowingContract.setLTV(80);
        await CDSContract.setTreasury(treasury.address);
        await CDSContract.setWithdrawTimeLimit(1000);

        [owner, user1, user2] = await ethers.getSigners();
        return {Token,pToken,CDSContract,BorrowingContract,treasury,owner,user1,user2}
    }
    
    describe("Minting tokens and transfering tokens", async function(){

        it("Should check Trinity Token contract & Owner of contracts",async () => {
            const{CDSContract,Token} = await loadFixture(deployer);
            expect(await CDSContract.Trinity_token()).to.be.equal(Token.address);
            expect(await CDSContract.owner()).to.be.equal(owner.address);
            expect(await Token.owner()).to.be.equal(owner.address);
        })

        it("Should Mint token", async function() {
            const{Token} = await loadFixture(deployer);
            console.log("Owner",owner.address);    
            await Token.mint(owner.address,ethers.utils.parseEther("1"));
            expect(await Token.balanceOf(owner.address)).to.be.equal(ethers.utils.parseEther("1"));
        })

        it("should deposit trinity into CDS", async function(){
            const {CDSContract,Token} = await loadFixture(deployer);
            await Token.mint(owner.address,ethers.utils.parseEther("1"));
            await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("1"));

            expect(await Token.allowance(owner.address,CDSContract.address)).to.be.equal(ethers.utils.parseEther("1"));

            await CDSContract.deposit(ethers.utils.parseEther("1"));
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(ethers.utils.parseEther("1"));

            let tx = await CDSContract.cdsDetails(owner.address);
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(1);
            
        })

    })

    describe("Checking revert conditions", function(){
        it("Should revert if zero balance is deposited in CDS",async () => {
            const {CDSContract} = await loadFixture(deployer);
            await expect( CDSContract.connect(user1).deposit(0)).to.be.revertedWith("Deposit amount should not be zero");
        })

        it("Should revert if Insufficient allowance",async () => {
            const {CDSContract,Token} = await loadFixture(deployer);
            await Token.mint(user1.address,ethers.utils.parseEther("1"));
            await Token.connect(user1).approve(CDSContract.address,ethers.utils.parseEther("0.5"));
            await expect( CDSContract.connect(user1).deposit(ethers.utils.parseEther("1"))).to.be.revertedWith("Insufficient allowance");
        })

        it("Should revert with insufficient balance ",async () => {
            const {CDSContract} = await loadFixture(deployer);
            await expect( CDSContract.connect(user1).deposit(ethers.utils.parseEther("1"))).to.be.revertedWith("Insufficient balance with msg.sender")
        })

        it("Should revert if Input address is invalid",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setBorrowingContract(ethers.constants.AddressZero)).to.be.revertedWith("Input address is invalid");
            await expect( CDSContract.connect(owner).setBorrowingContract(user1.address)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the index is not valid",async function(){
            const {CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(user1).withdraw(1)).to.be.revertedWith("user doesn't have the specified index");
        })

        it("Should revert if the caller is not owner for setTreasury",async function(){
            const {CDSContract,treasury} = await loadFixture(deployer);
            expect(CDSContract.connect(user1).setTreasury(treasury.address)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the caller is not owner for setWithdrawTimeLimit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(user1).setWithdrawTimeLimit(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the caller is not owner for approval",async function(){
            const {CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(user1).approval(CDSContract.address,1000)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the caller is not owner for setBorrowingContract",async function(){
            const {BorrowingContract,CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(user1).setBorrowingContract(BorrowingContract.address)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the Treasury address is zero",async function(){
            const {CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(owner).setTreasury(ethers.constants.AddressZero)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the Treasury address is not contract address",async function(){
            const {CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(owner).setTreasury(user2.address)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the zero sec is given in setWithdrawTimeLimit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            expect(CDSContract.connect(owner).setWithdrawTimeLimit(0)).to.be.revertedWith("Withdraw time limit can't be zero");
        })
    })

    describe("Should update variables correctly",function(){
        it("Should update lastEthPrice correctly",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await CDSContract.updateLastEthPrice(1500);
            expect (await CDSContract.fallbackEthPrice()).to.be.equal(await CDSContract.fallbackEthPrice());     
            expect (await CDSContract.lastEthPrice()).to.be.equal(1500);     
        })
        it("Should update borrowing correctly",async function(){
            const {BorrowingContract,CDSContract} = await loadFixture(deployer);
            await CDSContract.connect(owner).setBorrowingContract(BorrowingContract.address);
            expect (await CDSContract.borrowingContract()).to.be.equal(BorrowingContract.address);     
        })
        it("Should update treasury correctly",async function(){
            const {treasury,CDSContract} = await loadFixture(deployer);
            await CDSContract.connect(owner).setTreasury(treasury.address);
            expect (await CDSContract.treasuryAddress()).to.be.equal(treasury.address);     
        })
        it("Should update withdrawTime correctly",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await CDSContract.connect(owner).setWithdrawTimeLimit(1500);
            expect (await CDSContract.withdrawTimeLimit()).to.be.equal(1500);     
        })
    })

    describe("To check CDS withdrawl function",function(){
        it("Should withdraw from cds",async () => {
            const {CDSContract,treasury,Token} = await loadFixture(deployer);

            await Token.mint(user1.address,ethers.utils.parseEther("1000"));
            await Token.connect(user1).approve(CDSContract.address,ethers.utils.parseEther("1000"));
            
            const timestamp = await time.latest();
            console.log("BEFORE DEPOSIT TO CDS",await Token.balanceOf(user1.address));
            await CDSContract.connect(user1).deposit(ethers.utils.parseEther("1000"));
            console.log("AFTER DEPOSIT TO CDS",await Token.balanceOf(user1.address));

            await time.increase(1000);
            await CDSContract.approval(CDSContract.address,await Token.balanceOf(treasury.address));
            await CDSContract.connect(user1).withdraw(1);
            console.log("AFTER WITHDRAW FROM CDS",await Token.balanceOf(user1.address));
        })
    })
    // describe("To check cdsAmountToReturn function",function(){
    //     it("Should calculate cdsAmountToReturn ",async function(){
    //         const {CDSContract,Token} = await loadFixture(deployer);

    //         await Token.mint(owner.address,ethers.utils.parseEther("1"));
    //         await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("1"));

    //         await CDSContract.connect(owner).deposit(ethers.utils.parseEther("1"));
    //         const ethPrice = await CDSContract.lastEthPrice();
    //         const tx = await CDSContract.connect(user1).cdsAmountToReturn(user1.address,1,ethPrice);
    //         console.log(tx);
    //     })
    // })
})