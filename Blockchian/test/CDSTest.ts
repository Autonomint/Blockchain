import { expect } from "chai";
import { ethers, network } from "hardhat";
import type { Wallet } from "ethers";
import {BorrowingTest,Treasury,AMINTStablecoin,ABONDToken,Options,CDSTest,USDT,MultiSign} from "../typechain-types";
import { loadFixture,time } from'@nomicfoundation/hardhat-network-helpers';
import { ChildProcess } from "child_process";
import { token } from "../typechain-types/contracts";
import {
    wethGateway,
    priceFeedAddress,
    aTokenAddress,
    aavePoolAddress,
    cEther,
    usdtTokenAddress
    } from "./utils/index"


describe("Testing contracts ", function(){

    let CDSContract : CDSTest;
    let BorrowingContract : BorrowingTest;
    let Token : AMINTStablecoin;
    let abondToken : ABONDToken;
    let usdt: USDT;
    let treasury : Treasury;
    let options : Options;
    let multiSign : MultiSign; 
    let owner: any;
    let owner1: any;
    let owner2: any;
    let user1: any;
    let user2: any;
    let user3: any;
    const ethVolatility = 50622665;
    
    async function deployer(){
        [owner,owner1,owner2,user1,user2,user3] = await ethers.getSigners();

        const AmintStablecoin = await ethers.getContractFactory("AMINTStablecoin");
        Token = await AmintStablecoin.deploy();

        const ABONDToken = await ethers.getContractFactory("ABONDToken");
        abondToken = await ABONDToken.deploy();

        const MultiSign = await ethers.getContractFactory("MultiSign");
        multiSign = await MultiSign.deploy([owner.address,owner1.address,owner2.address],2);

        const USDTToken = await ethers.getContractFactory("USDT");
        usdt = await USDTToken.deploy();

        const CDS = await ethers.getContractFactory("CDSTest");
        CDSContract = await CDS.deploy(Token.address,priceFeedAddress,usdt.address,multiSign.address);

        const Borrowing = await ethers.getContractFactory("BorrowingTest");
        BorrowingContract = await Borrowing.deploy(Token.address,CDSContract.address,abondToken.address,multiSign.address,priceFeedAddress,1);

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(BorrowingContract.address,Token.address,CDSContract.address,wethGateway,cEther,aavePoolAddress,aTokenAddress,usdt.address);

        const Option = await ethers.getContractFactory("Options");
        options = await Option.deploy(priceFeedAddress,treasury.address,CDSContract.address);

        await BorrowingContract.initializeTreasury(treasury.address);
        await BorrowingContract.setOptions(options.address);
        await BorrowingContract.setLTV(80);
        await CDSContract.setTreasury(treasury.address);
        await CDSContract.setBorrowingContract(BorrowingContract.address);
        await CDSContract.setAmintLimit(80);
        await CDSContract.setUsdtLimit(20000000000);

        await multiSign.connect(owner).approveSetAPR();
        await multiSign.connect(owner1).approveSetAPR();
        await BorrowingContract.setAPR(BigInt("1000000001547125957863212449"));
        await BorrowingContract.calculateCumulativeRate();

        await BorrowingContract.setAdmin(owner.address);
        return {Token,abondToken,usdt,CDSContract,BorrowingContract,treasury,owner,user1,user2,user3}
    }
    
    describe("Minting tokens and transfering tokens", async function(){

        it("Should check Trinity Token contract & Owner of contracts",async () => {
            const{CDSContract,Token} = await loadFixture(deployer);
            await expect(await CDSContract.amint()).to.be.equal(Token.address);
            await expect(await CDSContract.owner()).to.be.equal(owner.address);
            await expect(await Token.owner()).to.be.equal(owner.address);
        })

        it("Should Mint token", async function() {
            const{Token} = await loadFixture(deployer);
            await Token.mint(owner.address,ethers.utils.parseEther("1"));
            expect(await Token.balanceOf(owner.address)).to.be.equal(ethers.utils.parseEther("1"));
        })

        it("should deposit USDT into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,10000000000);
            await usdt.connect(owner).approve(CDSContract.address,10000000000);

            expect(await usdt.allowance(owner.address,CDSContract.address)).to.be.equal(10000000000);

            await CDSContract.connect(owner).deposit(10000000000,0,true,ethers.utils.parseEther("10000"));
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(ethers.utils.parseEther("10000"));

            let tx = await CDSContract.cdsDetails(owner.address);
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(1);
        })

        it("should deposit USDT and AMINT into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            await Token.mint(owner.address,ethers.utils.parseEther("800"))
            await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("800"));

            await CDSContract.connect(owner).deposit(200000000,ethers.utils.parseEther("800"),true,ethers.utils.parseEther("1000"));
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(ethers.utils.parseEther("21000"));

            let tx = await CDSContract.cdsDetails(owner.address);
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(2);
        })

    })

    describe("Checking revert conditions", function(){

        it("should revert if Liquidation amount can't greater than deposited amount", async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).deposit(3000000000,ethers.utils.parseEther("700"),true,ethers.utils.parseEther("5000"))).to.be.revertedWith("Liquidation amount can't greater than deposited amount");
        })

        it("should revert if 0 USDT deposit into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,10000000000);
            await usdt.connect(owner).approve(CDSContract.address,10000000000);

            expect(await usdt.allowance(owner.address,CDSContract.address)).to.be.equal(10000000000);

            await expect(CDSContract.deposit(0,ethers.utils.parseEther("1"),true,ethers.utils.parseEther("0.5"))).to.be.revertedWith("100% of amount must be USDT");
        })

        it("should revert if USDT deposit into CDS is greater than 20%", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            await Token.mint(owner.address,ethers.utils.parseEther("700"))
            await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("700"));

            await expect(CDSContract.connect(owner).deposit(3000000000,ethers.utils.parseEther("700"),true,ethers.utils.parseEther("500"))).to.be.revertedWith("Required AMINT amount not met");
        })

        it("should revert if Insufficient AMINT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            await Token.mint(owner.address,ethers.utils.parseEther("70"))
            await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("70"));

            await expect(CDSContract.connect(owner).deposit(200000000,ethers.utils.parseEther("800"),true,ethers.utils.parseEther("500"))).to.be.revertedWith("Insufficient AMINT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,20100000000);
            await usdt.connect(owner).approve(CDSContract.address,20100000000);

            await CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            await Token.mint(owner.address,ethers.utils.parseEther("800"))
            await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("800"));

            await expect(CDSContract.connect(owner).deposit(200000000,ethers.utils.parseEther("800"),true,ethers.utils.parseEther("500"))).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,10000000000);
            await usdt.connect(owner).approve(CDSContract.address,10000000000);

            expect(await usdt.allowance(owner.address,CDSContract.address)).to.be.equal(10000000000);

            await expect(CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"))).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("Should revert if zero balance is deposited in CDS",async () => {
            const {CDSContract} = await loadFixture(deployer);
            await expect( CDSContract.connect(user1).deposit(0,0,true,ethers.utils.parseEther("1"))).to.be.revertedWith("Deposit amount should not be zero");
        })

        // it("Should revert if Insufficient allowance",async () => {
        //     const {CDSContract,Token} = await loadFixture(deployer);
        //     await Token.mint(user1.address,ethers.utils.parseEther("1"));
        //     await Token.connect(user1).approve(CDSContract.address,ethers.utils.parseEther("0.5"));
        //     await await expect( CDSContract.connect(user1).deposit(ethers.utils.parseEther("1"),true,ethers.utils.parseEther("0.5"))).to.be.revertedWith("Insufficient allowance");
        // })

        // it("Should revert with insufficient balance ",async () => {
        //     const {CDSContract} = await loadFixture(deployer);
        //     await await expect( CDSContract.connect(user1).deposit(ethers.utils.parseEther("1"),true,ethers.utils.parseEther("0.5"))).to.be.revertedWith("Insufficient balance with msg.sender")
        // })

        it("Should revert if Input address is invalid",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setBorrowingContract(ethers.constants.AddressZero)).to.be.revertedWith("Input address is invalid");
            await expect( CDSContract.connect(owner).setBorrowingContract(user1.address)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the index is not valid",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).withdraw(1)).to.be.revertedWith("user doesn't have the specified index");
        })

        it("Should revert if the caller is not owner for setTreasury",async function(){
            const {CDSContract,treasury} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setTreasury(treasury.address)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the caller is not owner for setWithdrawTimeLimit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setWithdrawTimeLimit(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        // it("Should revert if the caller is not owner for approval",async function(){
        //     const {CDSContract} = await loadFixture(deployer);
        //     await expect(CDSContract.connect(user1).approval(CDSContract.address,1000)).to.be.revertedWith("Ownable: caller is not the owner");
        // })

        it("Should revert if the caller is not owner for setBorrowingContract",async function(){
            const {BorrowingContract,CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setBorrowingContract(BorrowingContract.address)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the Treasury address is zero",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).setTreasury(ethers.constants.AddressZero)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the Treasury address is not contract address",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).setTreasury(user2.address)).to.be.revertedWith("Input address is invalid");
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
            const {CDSContract,treasury,Token,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.mint(user2.address,20000000000)
            await usdt.mint(user1.address,50000000000)
            await usdt.connect(user2).approve(CDSContract.address,20000000000);
            await usdt.connect(user1).approve(CDSContract.address,50000000000);

            await CDSContract.connect(user2).deposit(12000000000,0,true,ethers.utils.parseEther("12000"));
            await CDSContract.connect(user1).deposit(2000000000,0,true,ethers.utils.parseEther("1500"));

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await BorrowingContract.connect(owner).liquidate(user1.address,1,80000);
            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should withdraw from cds",async () => {
            const {CDSContract,treasury,Token} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.address,30000000000);
            await usdt.connect(user1).approve(CDSContract.address,30000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,false,0);

            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should revert Already withdrawn",async () => {
            const {CDSContract,treasury,Token} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.address,30000000000);
            await usdt.connect(user1).approve(CDSContract.address,30000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            await CDSContract.connect(user1).withdraw(1);
            const tx =  CDSContract.connect(user1).withdraw(1);
            await expect(tx).to.be.revertedWith("Already withdrawn");
        })
        it("Should calculate cumulative rate correctly",async () =>{
            const {CDSContract,BorrowingContract,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await Token.mint(user1.address,ethers.utils.parseEther("4000"));
            await Token.connect(user1).approve(CDSContract.address,ethers.utils.parseEther("4000"));

            await CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            // await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));
            // await BorrowingContract.calculateCumulativeRate();
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.utils.parseEther("2")});

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));
        })

        it("Should withdraw with fees",async () =>{
            const {CDSContract,BorrowingContract,Token,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await Token.mint(user1.address,ethers.utils.parseEther("4000"));
            await Token.connect(user1).approve(CDSContract.address,ethers.utils.parseEther("4000"));

            await CDSContract.deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            // await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));
            // await BorrowingContract.calculateCumulativeRate();
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.utils.parseEther("1")});
            
            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await CDSContract.connect(user1).deposit(0,ethers.utils.parseEther("1000"),true,ethers.utils.parseEther("500"));
            await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

            await BorrowingContract.liquidate(user1.address,2,80000);

            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should revert cannot withdraw before the withdraw time limit",async () => {
            const {CDSContract,treasury,Token} = await loadFixture(deployer);

            await CDSContract.connect(owner).setWithdrawTimeLimit(1000);
            await usdt.connect(user1).mint(user1.address,30000000000);
            await usdt.connect(user1).approve(CDSContract.address,30000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            const tx = CDSContract.connect(user1).withdraw(1);
            await expect(tx).to.be.revertedWith("cannot withdraw before the withdraw time limit");
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

    describe("Should redeem USDT correctly",function(){
        it("Should redeem USDT correctly",async function(){
            const {CDSContract,BorrowingContract,Token,treasury,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.address,20000000000);
            await usdt.connect(user1).approve(CDSContract.address,20000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,ethers.utils.parseEther("10000"));

            await Token.mint(owner.address,ethers.utils.parseEther("800"))
            await Token.connect(owner).approve(CDSContract.address,ethers.utils.parseEther("800"));

            await CDSContract.connect(owner).redeemUSDT(ethers.utils.parseEther("800"),1500,1000);

            expect(await Token.balanceOf(owner.address)).to.be.equal(0);
            expect(await usdt.balanceOf(owner.address)).to.be.equal(1200000000);
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContract} = await loadFixture(deployer);

            const tx = CDSContract.connect(owner).redeemUSDT(0,1500,1000);
            await expect(tx).to.be.revertedWith("Amount should not be zero");
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await Token.mint(owner.address,ethers.utils.parseEther("80"));

            const tx = CDSContract.connect(owner).redeemUSDT(ethers.utils.parseEther("800"),1500,1000);
            await expect(tx).to.be.revertedWith("Insufficient balance");
        })

        it("Should revert if Amint limit can't be zero",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setAmintLimit(0)).to.be.revertedWith("Amint limit can't be zero");
        })

        it("Should revert if the caller is not owner for setAmintLImit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setAmintLimit(10)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if USDT limit can't be zero",async () => {
            const {CDSContract} = await loadFixture(deployer);  
            await expect( CDSContract.connect(owner).setUsdtLimit(0)).to.be.revertedWith("USDT limit can't be zero");
        })

        it("Should revert if the caller is not owner for setUsdtLImit",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).setUsdtLimit(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert Fees should not be zero",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(user1).calculateCumulativeRate(0)).to.be.revertedWith("Fees should not be zero");
        })


    })
})