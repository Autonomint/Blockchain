import { expect } from "chai";
import { ethers} from "hardhat";
import {BorrowingTest,Treasury,AMINTStablecoin,ABONDToken,Options,CDSTest,TestUSDT,MultiSign} from "../typechain-types";
import { loadFixture,time } from'@nomicfoundation/hardhat-network-helpers';
import {
    wethGateway,
    priceFeedAddress,
    aTokenAddress,
    aavePoolAddress,
    cEther
    } from "./utils/index"


describe("Testing contracts ", function(){

    let CDSContract : CDSTest;
    let BorrowingContract : BorrowingTest;
    let Token : AMINTStablecoin;
    let abondToken : ABONDToken;
    let usdt: TestUSDT;
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

        const USDTToken = await ethers.getContractFactory("TestUSDT");
        usdt = await USDTToken.deploy();

        const CDS = await ethers.getContractFactory("CDSTest");
        CDSContract = await CDS.deploy(Token.address,priceFeedAddress,usdt.address,multiSign.address);

        const Borrowing = await ethers.getContractFactory("BorrowingTest");
        BorrowingContract = await Borrowing.deploy(Token.address,CDSContract.address,abondToken.address,multiSign.address,priceFeedAddress,1);

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(BorrowingContract.address,Token.address,CDSContract.address,wethGateway,cEther,aavePoolAddress,aTokenAddress,usdt.address);

        const Option = await ethers.getContractFactory("Options");
        options = await Option.deploy(priceFeedAddress,treasury.address,CDSContract.address,BorrowingContract.address);

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
            expect(await CDSContract.amint()).to.be.equal(Token.address);
            expect(await CDSContract.owner()).to.be.equal(owner.address);
            expect(await Token.owner()).to.be.equal(owner.address);
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

            await CDSContract.connect(owner).deposit(10000000000,0,true,10000000000);
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(10000000000);

            let tx = await CDSContract.cdsDetails(owner.address);
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(1);
        })

        it("should deposit USDT and AMINT into CDS", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.address,800000000)
            await Token.connect(owner).approve(CDSContract.address,800000000);

            await CDSContract.connect(owner).deposit(200000000,800000000,true,1000000000);
            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal(21000000000);

            let tx = await CDSContract.cdsDetails(owner.address);
            expect(tx.hasDeposited).to.be.equal(true);
            expect(tx.index).to.be.equal(2);
        })

    })

    describe("Checking revert conditions", function(){

        it("should revert if Liquidation amount can't greater than deposited amount", async function(){
            const {CDSContract} = await loadFixture(deployer);
            await expect(CDSContract.connect(owner).deposit(3000000000,700000000,true,ethers.utils.parseEther("5000"))).to.be.revertedWith("Liquidation amount can't greater than deposited amount");
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

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.address,700000000)
            await Token.connect(owner).approve(CDSContract.address,700000000);

            await expect(CDSContract.connect(owner).deposit(3000000000,700000000,true,500000000)).to.be.revertedWith("Required AMINT amount not met");
        })

        it("should revert if Insufficient AMINT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,30000000000);
            await usdt.connect(owner).approve(CDSContract.address,30000000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.address,70000000)
            await Token.connect(owner).approve(CDSContract.address,70000000);

            await expect(CDSContract.connect(owner).deposit(200000000,800000000,true,500000000)).to.be.revertedWith("Insufficient AMINT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,20100000000);
            await usdt.connect(owner).approve(CDSContract.address,20100000000);

            await CDSContract.deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.address,800000000)
            await Token.connect(owner).approve(CDSContract.address,800000000);

            await expect(CDSContract.connect(owner).deposit(200000000,800000000,true,500000000)).to.be.revertedWith("Insufficient USDT balance with msg.sender");
        })

        it("should revert Insufficient USDT balance with msg.sender", async function(){
            const {CDSContract,Token,usdt} = await loadFixture(deployer);
            await usdt.mint(owner.address,10000000000);
            await usdt.connect(owner).approve(CDSContract.address,10000000000);

            expect(await usdt.allowance(owner.address,CDSContract.address)).to.be.equal(10000000000);

            await expect(CDSContract.deposit(20000000000,0,true,10000000000)).to.be.revertedWith("Insufficient USDT balance with msg.sender");
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
            const {CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.mint(user2.address,20000000000)
            await usdt.mint(user1.address,50000000000)
            await usdt.connect(user2).approve(CDSContract.address,20000000000);
            await usdt.connect(user1).approve(CDSContract.address,50000000000);

            await CDSContract.connect(user2).deposit(12000000000,0,true,12000000000);
            await CDSContract.connect(user1).deposit(2000000000,0,true,1500000000);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await BorrowingContract.connect(owner).liquidate(user1.address,1,80000);
            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should withdraw from cds",async () => {
            const {CDSContract} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.address,30000000000);
            await usdt.connect(user1).approve(CDSContract.address,30000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,false,0);

            await CDSContract.connect(user1).withdraw(1);
        })

        it("Should revert Not enough fund in CDS",async () => {
            const {CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();


            await usdt.connect(user1).mint(user1.address,2000000000);
            await usdt.connect(user1).approve(CDSContract.address,2000000000);
            await CDSContract.connect(user1).deposit(100000000,0,false,0);
            await CDSContract.connect(user1).deposit(1001000000,0,false,0);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("5")});

            await CDSContract.connect(user1).withdraw(1);
            await expect(CDSContract.connect(user1).withdraw(2)).to.be.revertedWith("Not enough fund in CDS");
        })

        it("Should revert Already withdrawn",async () => {
            const {CDSContract} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.address,30000000000);
            await usdt.connect(user1).approve(CDSContract.address,30000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            await CDSContract.connect(user1).withdraw(1);
            const tx =  CDSContract.connect(user1).withdraw(1);
            await expect(tx).to.be.revertedWith("Already withdrawn");
        })
        // it("Should calculate cumulative rate correctly",async () =>{
        //     const {CDSContract,BorrowingContract,Token} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await usdt.mint(owner.address,30000000000);
        //     await usdt.connect(owner).approve(CDSContract.address,30000000000);

        //     await Token.mint(user1.address,4000000000);
        //     await Token.connect(user1).approve(CDSContract.address,4000000000);

        //     await CDSContract.deposit(20000000000,0,true,10000000000);
        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.utils.parseEther("2")});

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));
        // })

        // it("Should withdraw with fees",async () =>{
        //     const {CDSContract,BorrowingContract,Token,treasury} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await usdt.mint(owner.address,30000000000);
        //     await usdt.connect(owner).approve(CDSContract.address,30000000000);

        //     await Token.mint(user1.address,ethers.utils.parseEther("4000"));
        //     await Token.connect(user1).approve(CDSContract.address,ethers.utils.parseEther("4000"));

        //     await CDSContract.deposit(20000000000,0,true,10000000000);

        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,0,105000,ethVolatility,{value: ethers.utils.parseEther("1")});
            
        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await CDSContract.connect(user1).deposit(0,1000000000,true,500000000);
        //     await CDSContract.calculateCumulativeRate(ethers.utils.parseEther("60"));

        //     await BorrowingContract.liquidate(user1.address,2,80000);

        //     await CDSContract.connect(user1).withdraw(1);
        // })

        it("Should revert cannot withdraw before the withdraw time limit",async () => {
            const {CDSContract} = await loadFixture(deployer);

            await CDSContract.connect(owner).setWithdrawTimeLimit(1000);
            await usdt.connect(user1).mint(user1.address,30000000000);
            await usdt.connect(user1).approve(CDSContract.address,30000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            const tx = CDSContract.connect(user1).withdraw(1);
            await expect(tx).to.be.revertedWith("cannot withdraw before the withdraw time limit");
        })
    })

    describe("To check cdsAmountToReturn function",function(){
        // it("Should calculate cdsAmountToReturn ",async function(){
        //     const {CDSContract,Token} = await loadFixture(deployer);

        //     await usdt.mint(user1.address,20000000000);
        //     await usdt.connect(user1).approve(CDSContract.address,20000000000);

        //     await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);
        //     const ethPrice = await CDSContract.lastEthPrice();
        //     await CDSContract.connect(user1).cdsAmountToReturn(user1.address,1,ethPrice);
        // })
    })

    describe("Should redeem USDT correctly",function(){
        it("Should redeem USDT correctly",async function(){
            const {CDSContract,BorrowingContract,Token,treasury,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.address,20000000000);
            await usdt.connect(user1).approve(CDSContract.address,20000000000);

            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            await Token.mint(owner.address,800000000);
            await Token.connect(owner).approve(CDSContract.address,800000000);

            await CDSContract.connect(owner).redeemUSDT(800000000,1500,1000);

            expect(await Token.totalSupply()).to.be.equal(20000000000);
            expect(await usdt.balanceOf(owner.address)).to.be.equal(1200000000);
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContract} = await loadFixture(deployer);

            const tx = CDSContract.connect(owner).redeemUSDT(0,1500,1000);
            await expect(tx).to.be.revertedWith("Amount should not be zero");
        })

        it("Should revert Amount should not be zero",async function(){
            const {CDSContract} = await loadFixture(deployer);
            await Token.mint(owner.address,80000000);

            const tx = CDSContract.connect(owner).redeemUSDT(800000000,1500,1000);
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

        // it("Should revert Fees should not be zero",async function(){
        //     const {CDSContract} = await loadFixture(deployer);
        //     await expect(CDSContract.connect(user1).calculateCumulativeRate(0)).to.be.revertedWith("Fees should not be zero");
        // })
    })

    describe("Should calculate value correctly",function(){
        it("Should calculate value for no deposit in borrowing",async function(){
            const {CDSContract,BorrowingContract,Token,treasury,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.address,20000000000);
            await usdt.connect(user1).approve(CDSContract.address,20000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);
        })

        it("Should calculate value for no deposit in borrowing and 2 deposit in cds",async function(){
            const {CDSContract,usdt} = await loadFixture(deployer);
            await usdt.mint(user1.address,20000000000);
            await usdt.connect(user1).approve(CDSContract.address,20000000000);
            await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

            await Token.mint(user2.address,4000000000);
            await Token.connect(user2).approve(CDSContract.address,4000000000);
            await CDSContract.connect(user2).deposit(0,4000000000,true,4000000000);

            await CDSContract.connect(user1).withdraw(1);
        })

        // it("Should calculate value for 1 deposit in borrowing",async function(){
        //     const {CDSContract,usdt} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await usdt.mint(user1.address,20000000000);
        //     await usdt.connect(user1).approve(CDSContract.address,20000000000);
        //     await CDSContract.connect(user1).deposit(20000000000,0,true,10000000000);

        //     const ethPrice = await BorrowingContract.getUSDValue();
        //     await BorrowingContract.connect(user2).depositTokens(ethPrice,timeStamp,1,256785,ethVolatility,{value: ethers.utils.parseEther("2")});

        //     await Token.mint(user3.address,4000000000);
        //     await Token.connect(user3).approve(CDSContract.address,4000000000);
        //     await CDSContract.connect(user3).deposit(0,4000000000,true,4000000000);

        //     await BorrowingContract.connect(user2).depositTokens(ethPrice,timeStamp,1,256785,ethVolatility,{value: ethers.utils.parseEther("2")});

        //     await CDSContract.connect(user1).withdraw(1);
        //     await CDSContract.connect(user3).withdraw(1);

        //     await Token.connect(user1).transfer(user2.address,21);
        //     await Token.connect(user2).approve(BorrowingContract.address,await Token.balanceOf(user2.address));
        //     await BorrowingContract.connect(user2).withDraw(user2.address,1,256885,timeStamp,4);


        //     await abondToken.connect(user2).approve(BorrowingContract.address,await abondToken.balanceOf(user2.address));
        //     await BorrowingContract.connect(user2).withDraw(user2.address,1,ethPrice,timeStamp,4);
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

        // it("Should calculate value correctly during deposit and withdraw",async function(){
        //     const {CDSContract,BorrowingContract,usdt} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();
        //     await usdt.mint(user1.address,20000000000);
        //     await usdt.connect(user1).approve(CDSContract.address,20000000000);

        //     // await CDSContract.connect(user1).deposit(270425,20000000000,0,true,10000000000);
        //     // await BorrowingContract.connect(user2).depositTokens(270425,timeStamp,1,250000,ethVolatility,{value: ethers.utils.parseEther("2")});
        //     await CDSContract.connect(user1).deposit(100000,10000000000,0,true,10000000000);
        //     await CDSContract.connect(user1).deposit(100000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("51")});
        //     await CDSContract.connect(user1).deposit(101000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(101000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).deposit(102000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(102000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).deposit(103000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(103000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     // await CDSContract.connect(user1).withdraw(103000,2);
        //     await CDSContract.connect(user1).deposit(104000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(104000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).withdraw(104000,3);
        //     await CDSContract.connect(user1).deposit(103000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(103000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).deposit(102000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(102000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).deposit(101000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(101000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).deposit(100000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
        //     await CDSContract.connect(user1).deposit(95000,1000000000,0,true,1000000000);
        //     await BorrowingContract.connect(user2).depositTokens(95000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

        //     // await CDSContract.withdraw();


        //     console.log(await CDSContract.cumulativeValue());
        //     console.log(await CDSContract.cumulativeValueSign());

        //     // await Token.mint(user2.address,4000000000);
        //     // await Token.connect(user2).approve(CDSContract.address,4000000000);
        //     // await CDSContract.connect(user2).deposit(290425,0,4000000000,true,4000000000);
        //     // // console.log(await CDSContract.cumulativeValue());

        //     // await CDSContract.connect(user1).withdraw(230425,1);
        //     // console.log(await CDSContract.cumulativeValue());

        // })
    })
})