const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers,upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import {
    wethGateway,
    priceFeedAddress,
    aTokenAddress,
    aavePoolAddress,
    cEther
    } from "./utils/index"


describe("Testing contracts ", function(){

    let owner: any;
    let owner1: any;
    let owner2: any;
    let user1: any;
    let user2: any;
    let user3: any;
    const ethVolatility = 50622665;
    
    async function deployer(){
        [owner,owner1,owner2,user1,user2,user3] = await ethers.getSigners();

        const AmintStablecoin = await ethers.getContractFactory("TestAMINTStablecoin");
        const Token = await upgrades.deployProxy(AmintStablecoin, {kind:'uups'});

        const ABONDToken = await ethers.getContractFactory("TestABONDToken");
        const abondToken = await upgrades.deployProxy(ABONDToken, {kind:'uups'});

        const MultiSign = await ethers.getContractFactory("MultiSign");
        const multiSign = await upgrades.deployProxy(MultiSign,[[await owner.getAddress(),await owner1.getAddress(),await owner2.getAddress()],2],{initializer:'initialize'},{kind:'uups'});

        const USDTToken = await ethers.getContractFactory("TestUSDT");
        const usdt = await upgrades.deployProxy(USDTToken, {kind:'uups'});

        const CDS = await ethers.getContractFactory("CDSTest");
        const CDSContract = await upgrades.deployProxy(CDS,[await Token.getAddress(),priceFeedAddress,await usdt.getAddress(),await multiSign.getAddress()],{initializer:'initialize'},{kind:'uups'})

        const Borrowing = await ethers.getContractFactory("BorrowingTest");
        const BorrowingContract = await upgrades.deployProxy(Borrowing,[await Token.getAddress(),await CDSContract.getAddress(),await abondToken.getAddress(),await multiSign.getAddress(),priceFeedAddress,1],{initializer:'initialize'},{kind:'uups'});

        const Treasury = await ethers.getContractFactory("Treasury");
        const treasury = await upgrades.deployProxy(Treasury,[await BorrowingContract.getAddress(),await Token.getAddress(),await CDSContract.getAddress(),wethGateway,cEther,aavePoolAddress,aTokenAddress,await usdt.getAddress()],{initializer:'initialize'},{kind:'uups'});

        const Option = await ethers.getContractFactory("Options");
        const options = await upgrades.deployProxy(Option,[await treasury.getAddress(),await CDSContract.getAddress(),await BorrowingContract.getAddress()],{initializer:'initialize'},{kind:'uups'});
        
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
        
        return {Token,abondToken,usdt,CDSContract,BorrowingContract,treasury,options,multiSign,owner,user1,user2,user3}
    }
    
    describe("Minting tokens and transfering tokens", async function(){

        it("Should check Trinity Token contract & Owner of contracts",async () => {
            const{CDSContract,Token} = await loadFixture(deployer);
            expect(await CDSContract.amint()).to.be.equal(await Token.getAddress());
            expect(await CDSContract.owner()).to.be.equal(await owner.getAddress());
            expect(await Token.owner()).to.be.equal(await owner.getAddress());
        })

        it("Should Mint token", async function() {
            const{Token} = await loadFixture(deployer);
            await Token.mint(owner.getAddress(),ethers.parseEther("1"));
            expect(await Token.balanceOf(owner.getAddress())).to.be.equal(ethers.parseEther("1"));
        })

        it("should deposit USDT into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),10000000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),10000000000);

            expect(await usdt.allowance(owner.getAddress(),CDSContract.getAddress())).to.be.equal(10000000000);

            await CDSContract.connect(owner).deposit(10000000000,0,true,10000000000);
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(10000000000);

            let tx = await CDSContract.cdsDetails(owner.getAddress());
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(1);
        })

        it("should deposit USDT and AMINT into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),30000000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),30000000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.getAddress(),800000000)
            await Token.connect(owner).approve(CDSContract.getAddress(),800000000);

            await CDSContract.connect(owner).deposit(200000000,800000000,true,1000000000);
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(21000000000);

            let tx = await CDSContract.cdsDetails(owner.getAddress());
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(2);
        })

    })

    describe("Checking revert conditions", function(){

        it("should revert if Liquidation amount can't greater than deposited amount", async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).deposit(3000000000,700000000,true,ethers.parseEther("5000"))).to.be.revertedWith("Liquidation amount can't greater than deposited amount");
        })

        it("should revert if 0 USDT deposit into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),10000000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),10000000000);

            expect(await usdt.allowance(owner.getAddress(),CDSContract.getAddress())).to.be.equal(10000000000);

            await expect(CDSContract.deposit(0,ethers.parseEther("1"),true,ethers.parseEther("0.5"))).to.be.revertedWith("100% of amount must be USDT");
        })

        it("should revert if USDT deposit into CDS is greater than 20%", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),30000000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),30000000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.getAddress(),700000000)
            await Token.connect(owner).approve(CDSContract.getAddress(),700000000);

            await expect(CDSContract.connect(owner).deposit(3000000000,700000000,true,500000000)).to.be.revertedWith("Required AMINT amount not met");
        })

        it("should revert if Insufficient AMINT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),30000000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),30000000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.getAddress(),70000000)
            await Token.connect(owner).approve(CDSContract.getAddress(),70000000);

            await expect(CDSContract.connect(owner).deposit(200000000,800000000,true,500000000)).to.be.revertedWith("Insufficient AMINT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),20100000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),20100000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.getAddress(),800000000)
            await Token.connect(owner).approve(CDSContract.getAddress(),800000000);

            await expect(CDSContract.connect(owner).deposit(200000000,800000000,true,500000000)).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.getAddress(),10000000000);
            await usdt.connect(owner).approve(CDSContract.getAddress(),10000000000);

            expect(await usdt.allowance(owner.getAddress(),CDSContract.getAddress())).to.be.equal(10000000000);

            await expect(CDSContract.deposit(20000000000,0,true,10000000000)).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("Should revert if zero balance is deposited in CDS",async () => {
            const {CDSContract} = await loadFixture(deployer);
            await expect( CDSContract.connect(user1).deposit(0,0,true,ethers.parseEther("1"))).to.be.revertedWith("Deposit amount should not be zero");
        })

        // it("Should revert if Insufficient allowance",async () => {
        //     const {CDSContract,Token} = await loadFixture(deployer);
        //     await Token.mint(user1.getAddress(),ethers.parseEther("1"));
        //     await Token.connect(user1).approve(CDSContract.getAddress(),ethers.parseEther("0.5"));
        //     await await expect( CDSContract.connect(user1).deposit(ethers.parseEther("1"),true,ethers.parseEther("0.5"))).to.be.revertedWith("Insufficient allowance");
        // })

        // it("Should revert with insufficient balance ",async () => {
        //     const {CDSContract} = await loadFixture(deployer);
        //     await await expect( CDSContract.connect(user1).deposit(ethers.parseEther("1"),true,ethers.parseEther("0.5"))).to.be.revertedWith("Insufficient balance with msg.sender")
        // })

        it("Should revert if Input address is invalid",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setBorrowingContract(ethers.ZeroAddress)).to.be.revertedWith("Input address is invalid");
            await expect( CDSContract.connect(owner).setBorrowingContract(user1.getAddress())).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the index is not valid",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).withdraw(1)).to.be.revertedWith("user doesn't have the specified index");
        })

        it("Should revert if the caller is not owner for setTreasury",async function(){
            const {CDSContract,treasury} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setTreasury(treasury.getAddress())).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the caller is not owner for setWithdrawTimeLimit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setWithdrawTimeLimit(1000)).to.be.revertedWith("Caller is not an admin");
        })

        // it("Should revert if the caller is not owner for approval",async function(){
        //     const {CDSContract} = await loadFixture(deployer);
        //     await expect(CDSContract.connect(user1).approval(CDSContract.getAddress(),1000)).to.be.revertedWith("Ownable: caller is not the owner");
        // })

        it("Should revert if the caller is not owner for setBorrowingContract",async function(){
            const {BorrowingContract,CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setBorrowingContract(BorrowingContract.getAddress())).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the Treasury address is zero",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).setTreasury(ethers.ZeroAddress)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the Treasury address is not contract address",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).setTreasury(user2.getAddress())).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the zero sec is given in setWithdrawTimeLimit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).setWithdrawTimeLimit(0)).to.be.revertedWith("Withdraw time limit can't be zero");
        })
    })

    describe("Should update variables correctly",function(){
        // it("Should update lastEthPrice correctly",async function(){
        //     const {CDSContract} = await loadFixture(deployer);
        //     // await CDSContract.updateLastEthPrice(1500);
        //     await expect (await CDSContract.fallbackEthPrice()).to.be.equal(await CDSContract.fallbackEthPrice());     
        //     await expect (await CDSContract.lastEthPrice()).to.be.equal(1500);     
        // })
        it("Should update borrowing correctly",async function(){
            const {BorrowingContract,CDSContract} = await loadFixture(deployer);
            await CDSContract.connect(owner).setBorrowingContract(BorrowingContract.getAddress());
            expect (await CDSContract.borrowingContract()).to.be.equal(await BorrowingContract.getAddress());     
        })
        it("Should update treasury correctly",async function(){
            const {treasury,CDSContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([7]);
            await multiSign.connect(owner1).approveSetterFunction([7]);
            await CDSContract.connect(owner).setTreasury(treasury.getAddress());
            expect (await CDSContract.treasuryAddress()).to.be.equal(await treasury.getAddress());     
        })
        it("Should update withdrawTime correctly",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([3]);
            await multiSign.connect(owner1).approveSetterFunction([3]);
            await CDSContract.connect(owner).setWithdrawTimeLimit(1500);
            expect (await CDSContract.withdrawTimeLimit()).to.be.equal(1500);     
        })
    })

    describe("To check CDS withdrawl function",function(){
        it("Should withdraw from cds",async () => {
            const {BorrowingContract,CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.mint(user2.getAddress(),20000000000)
            await usdt.mint(user1.getAddress(),50000000000)
            await usdt.connect(user2).approve(CDSContract.getAddress(),20000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),50000000000);

            await CDSContract.connect(user2).deposit(12000000000,0,true,12000000000);
            await CDSContract.connect(user1).deposit(2000000000,0,true,1500000000);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            await BorrowingContract.connect(owner).liquidate(user1.getAddress(),1,80000);
            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should withdraw from cds",async () => {
            const {CDSContract,usdt} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.getAddress(),30000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),30000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,false,0);

            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should revert Not enough fund in CDS",async () => {
            const {CDSContract,usdt,BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.getAddress(),2000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),2000000000);
            await CDSContract.connect(user1).deposit(100000000,0,false,0);
            await CDSContract.connect(user1).deposit(1001000000,0,false,0);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("5")});

            await CDSContract.connect(user1).withdraw(1);
            await expect(CDSContract.connect(user1).withdraw(2)).to.be.revertedWith("Not enough fund in CDS");
        })

        it("Should revert Already withdrawn",async () => {
            const {CDSContract,usdt} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.getAddress(),30000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),30000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            await CDSContract.connect(user1).withdraw(1);
            const tx =  CDSContract.connect(user1).withdraw(1);
            await expect(tx).to.be.revertedWith("Already withdrawn");
        })
        // it("Should calculate cumulative rate correctly",async () =>{
        //     const {CDSContract,BorrowingContract,Token} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await usdt.mint(owner.getAddress(),30000000000);
        //     await usdt.connect(owner).approve(CDSContract.getAddress(),30000000000);

        //     await Token.mint(user1.getAddress(),4000000000);
        //     await Token.connect(user1).approve(CDSContract.getAddress(),4000000000);

        //     await CDSContract.deposit(20000000000,0,true,10000000000);
        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.parseEther("2")});

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));
        // })

        // it("Should withdraw with fees",async () =>{
        //     const {CDSContract,BorrowingContract,Token,treasury} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await usdt.mint(owner.getAddress(),30000000000);
        //     await usdt.connect(owner).approve(CDSContract.getAddress(),30000000000);

        //     await Token.mint(user1.getAddress(),ethers.parseEther("4000"));
        //     await Token.connect(user1).approve(CDSContract.getAddress(),ethers.parseEther("4000"));

        //     await CDSContract.deposit(20000000000,0,true,10000000000);

        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.parseEther("1")});
        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.parseEther("1")});
            
        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.parseEther("60"));

        //     await BorrowingContract.liquidate(user1.getAddress(),2,80000);

        //     await CDSContract.connect(user1).withdraw(1);
        // })

        it("Should revert cannot withdraw before the withdraw time limit",async () => {
            const {CDSContract,usdt,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([3]);
            await multiSign.connect(owner1).approveSetterFunction([3]);
            await CDSContract.connect(owner).setWithdrawTimeLimit(1000);
            await usdt.connect(user1).mint(user1.getAddress(),30000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),30000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            const tx = CDSContract.connect(user1).withdraw(1);
            await expect(tx).to.be.revertedWith("cannot withdraw before the withdraw time limit");
        })
    })

    describe("To check cdsAmountToReturn function",function(){
        // it("Should calculate cdsAmountToReturn ",async function(){
        //     const {CDSContract,Token} = await loadFixture(deployer);

        //     await usdt.mint(user1.getAddress(),20000000000);
        //     await usdt.connect(user1).approve(CDSContract.getAddress(),20000000000);

        //     await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);
        //     const ethPrice = await CDSContract.lastEthPrice();
        //     await CDSContract.connect(user1).cdsAmountToReturn(user1.getAddress(),1,ethPrice);
        // })
    })

    describe("Should redeem USDT correctly",function(){
        it("Should redeem USDT correctly",async function(){
            const {CDSContract,BorrowingContract,Token,treasury,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.getAddress(),20000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),20000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.getAddress(),800000000);
            await Token.connect(owner).approve(CDSContract.getAddress(),800000000);

            await CDSContract.connect(owner).redeemUSDT(800000000,1500,1000);

            expect(await Token.totalSupply()).to.be.equal(20000000000);
            expect(await usdt.balanceOf(owner.getAddress())).to.be.equal(1200000000);
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContract} = await loadFixture(deployer);

            const tx = CDSContract.connect(owner).redeemUSDT(0,1500,1000);
            await expect(tx).to.be.revertedWith("Amount should not be zero");
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContract,Token} = await loadFixture(deployer);
            await Token.mint(owner.getAddress(),80000000);

            const tx = CDSContract.connect(owner).redeemUSDT(800000000,1500,1000);
            await expect(tx).to.be.revertedWith("Insufficient balance");
        })

        it("Should revert if Amint limit can't be zero",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setAmintLimit(0)).to.be.revertedWith("Amint limit can't be zero");
        })

        it("Should revert if the caller is not owner for setAmintLImit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setAmintLimit(10)).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if USDT limit can't be zero",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setUsdtLimit(0)).to.be.revertedWith("USDT limit can't be zero");
        })

        it("Should revert if the caller is not owner for setUsdtLImit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setUsdtLimit(1000)).to.be.revertedWith("Caller is not an admin");
        })

        // it("Should revert Fees should not be zero",async function(){
        //     const {CDSContract} = await loadFixture(deployer);
        //     await expect(CDSContract.connect(user1).calculateCumulativeRate(0)).to.be.revertedWith("Fees should not be zero");
        // })
    })

    describe("Should calculate value correctly",function(){
        it("Should calculate value for no deposit in borrowing",async function(){
            const {CDSContract,BorrowingContract,Token,treasury,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.getAddress(),20000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),20000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);
        })

        it("Should calculate value for no deposit in borrowing and 2 deposit in cds",async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.getAddress(),20000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),20000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            await Token.mint(user2.getAddress(),4000000000);
            await Token.connect(user2).approve(CDSContract.getAddress(),4000000000);
            await CDSContract.connect(user2).deposit(0,4000000000,true,4000000000);

            await CDSContract.connect(user1).withdraw(1);
        })

        // it("Should calculate value for 1 deposit in borrowing",async function(){
        //     const {CDSContract,usdt} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await usdt.mint(user1.getAddress(),20000000000);
        //     await usdt.connect(user1).approve(CDSContract.getAddress(),20000000000);
        //     await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

        //     const ethPrice = await BorrowingContract.getUSDValue();
        //     await BorrowingContract.connect(user2).depositTokens(ethPrice,timeStamp,1,256785,ethVolatility,{value: ethers.parseEther("2")});

        //     await Token.mint(user3.getAddress(),4000000000);
        //     await Token.connect(user3).approve(CDSContract.getAddress(),4000000000);
        //     await CDSContract.connect(user3).deposit(0,4000000000,true,4000000000);

        //     await BorrowingContract.connect(user2).depositTokens(ethPrice,timeStamp,1,256785,ethVolatility,{value: ethers.parseEther("2")});

        //     await CDSContract.connect(user1).withdraw(1);
        //     await CDSContract.connect(user3).withdraw(1);

        //     await Token.connect(user1).transfer(user2.getAddress(),21);
        //     await Token.connect(user2).approve(BorrowingContract.getAddress(),await Token.balanceOf(user2.getAddress()));
        //     await BorrowingContract.connect(user2).withDraw(user2.getAddress(),1,256885,timeStamp,4);


        //     await abondToken.connect(user2).approve(BorrowingContract.getAddress(),await abondToken.balanceOf(user2.getAddress()));
        //     await BorrowingContract.connect(user2).withDraw(user2.getAddress(),1,ethPrice,timeStamp,4);
        // })

        // it("Should calculate cumulative value",async function(){
        //     const {CDSContract} = await loadFixture(deployer);
        //     await CDSContract.setCumulativeValue(4636363636,true);
        //     await CDSContract.setCumulativeValue(4333333333,true);
        //     await CDSContract.setCumulativeValue(4076923077,true);
        //     await CDSContract.setCumulativeValue(3857142857,true);
        //     await CDSContract.setCumulativeValue(3666666667,false);
        //     await CDSContract.setCumulativeValue(3500000000,false);
        //     await CDSContract.setCumulativeValue(3352941176,false);
        //     await CDSContract.setCumulativeValue(3222222222,false);
        //     await CDSContract.setCumulativeValue(15526315790,false);
        //     await CDSContract.setCumulativeValue(3000000000,true);

        //     expect(await CDSContract.cumulativeValue()).to.be.equal(9364382952);
        //     expect(await CDSContract.cumulativeValueSign()).to.be.equal(false);
        // })

    //     it("Should calculate value correctly during deposit and withdraw",async function(){
    //         const {CDSContract,BorrowingContract,usdt} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.mint(user1.getAddress(),20000000000);
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),20000000000);

    //         // await CDSContract.connect(user1).deposit(270425,20000000000,0,true,10000000000);
    //         // await BorrowingContract.connect(user2).depositTokens(270425,timeStamp,1,250000,ethVolatility,{value: ethers.parseEther("2")});
    //         await CDSContract.connect(user1).deposit(100000,10000000000,0,true,10000000000);
    //         await CDSContract.connect(user1).deposit(100000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("51")});
    //         await CDSContract.connect(user1).deposit(101000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(101000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         await CDSContract.connect(user1).deposit(102000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(102000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         await CDSContract.connect(user1).deposit(103000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(103000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         // await CDSContract.connect(user1).withdraw(103000,2);
    //         await CDSContract.connect(user1).deposit(104000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(104000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         //await CDSContract.connect(user1).withdraw(104000,3);
    //         await CDSContract.connect(user1).deposit(103000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(103000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         await CDSContract.connect(user1).deposit(102000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(102000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         await CDSContract.connect(user1).deposit(101000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(101000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         await CDSContract.connect(user1).deposit(100000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
    //         await CDSContract.connect(user1).deposit(95000,1000000000,0,true,1000000000);
    //         await BorrowingContract.connect(user2).depositTokens(95000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

    //         // await CDSContract.withdraw();


    //         console.log(await CDSContract.cumulativeValue());
    //         console.log(await CDSContract.cumulativeValueSign());

    //         // await Token.mint(user2.getAddress(),4000000000);
    //         // await Token.connect(user2).approve(CDSContract.getAddress(),4000000000);
    //         // await CDSContract.connect(user2).deposit(290425,0,4000000000,true,4000000000);
    //         // // console.log(await CDSContract.cumulativeValue());

    //         // await CDSContract.connect(user1).withdraw(230425,1);
    //         // console.log(await CDSContract.cumulativeValue());

    //     })
    })
})