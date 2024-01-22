const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers } from "hardhat";
import { Contract,utils,providers,Wallet, Signer } from "ethers";
import { hexValue } from "@ethersproject/bytes";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { BorrowingTest, CDSTest, TrinityStablecoin, ProtocolToken, Treasury,Options,USDT,MultiSign} from "../typechain-types";
import {
    wethGateway,
    priceFeedAddress,
    aTokenAddress,
    aavePoolAddress,
    cEther,
    INFURA_URL,
    aTokenABI,
    cETH_ABI,
    } from "./utils/index"

describe("Borrowing Contract",function(){

    let CDSContract : CDSTest;
    let BorrowingContract : BorrowingTest;
    let Token : TrinityStablecoin;
    let pToken : ProtocolToken;
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

        const TrinityStablecoin = await ethers.getContractFactory("TrinityStablecoin");
        Token = await TrinityStablecoin.deploy();

        const ProtocolToken = await ethers.getContractFactory("ProtocolToken");
        pToken = await ProtocolToken.deploy();

        const MultiSign = await ethers.getContractFactory("MultiSign");
        multiSign = await MultiSign.deploy([owner.address,owner1.address,owner2.address],2);

        const USDTToken = await ethers.getContractFactory("USDT");
        usdt = await USDTToken.deploy();

        const CDS = await ethers.getContractFactory("CDSTest");
        CDSContract = await CDS.deploy(Token.address,priceFeedAddress,usdt.address,multiSign.address);

        const Borrowing = await ethers.getContractFactory("BorrowingTest");
        BorrowingContract = await Borrowing.deploy(Token.address,CDSContract.address,pToken.address,multiSign.address,priceFeedAddress,1);

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
        await BorrowingContract.calculateCumulativeRate();
        await CDSContract.setUsdtLimit(20000000000);
        

        const provider = new ethers.providers.JsonRpcProvider(INFURA_URL);
        const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",provider);

        const aToken = new ethers.Contract(aTokenAddress,aTokenABI,signer);
        const cETH = new ethers.Contract(cEther,cETH_ABI,signer);

        await BorrowingContract.setAdmin(owner.address);
        return {Token,pToken,usdt,CDSContract,BorrowingContract,treasury,options,multiSign,aToken,cETH,owner,user1,user2,user3,provider}
    }

    describe("Should deposit ETH and mint Trinity",function(){
        it("Should deposit ETH",async function(){
            const {BorrowingContract,usdt,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(200000,timeStamp,1,220000,ethVolatility,{value: ethers.utils.parseEther("2.5")});
            // expect(await Token.totalSupply()).to.be.equal(ethers.utils.parseEther("800"));
        })

        it("Should calculate criticalRatio correctly",async function(){
            const {BorrowingContract,CDSContract,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,false,0);
            await BorrowingContract.connect(user1).depositTokens(200000,timeStamp,1,220000,ethVolatility,{value: ethers.utils.parseEther("2.5")});
            // await BorrowingContract.connect(user2).depositTokens(ethers.utils.parseEther("1216.12094444444"),timeStamp,{value: ethers.utils.parseEther("1")});
            // await BorrowingContract.connect(user3).depositTokens(ethers.utils.parseEther("1190.84086805555"),timeStamp,{value: ethers.utils.parseEther("1")});
            // await BorrowingContract.connect(owner).depositTokens(ethers.utils.parseEther("1163.07447222222"),timeStamp,{value: ethers.utils.parseEther("1")});
        })

        it("Should set APY",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await BorrowingContract.connect(owner).setAPY(5);
            expect(await BorrowingContract.APY()).to.be.equal(5);
        })
        it("Should called by only owner(setAPY)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).setAPY(5);
            expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        })
        it("Should get APY",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await BorrowingContract.setAPY(5);
            expect(await BorrowingContract.getAPY()).to.be.equal(5);
        })

        it("Should get LTV",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            expect(await BorrowingContract.getLTV()).to.be.equal(80);
        })

        it("Should calculate CumulativeRate",async function(){
            const {BorrowingContract,Token,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,false,0);
            await BorrowingContract.connect(user1).depositTokens(200000,timeStamp,1,220000,ethVolatility,{value: ethers.utils.parseEther("2.5")});
        })
    })

    describe("Should get the ETH/USD price",function(){
        it("Should get ETH/USD price",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = await BorrowingContract.getUSDValue();
            console.log("ETH/USD : ",tx.toString());
        })
    })

    describe("Should revert errors",function(){
        it("Should revert if zero eth is deposited",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const tx =  BorrowingContract.connect(user1).depositTokens(100000,timeStamp,110000,{value: ethers.utils.parseEther("0")});
            expect(tx).to.be.revertedWith("Cannot deposit zero tokens");
        })

        it("Should revert if LTV set to zero value before providing loans",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await BorrowingContract.setLTV(0);          
            const timeStamp = await time.latest();
            const tx =  BorrowingContract.connect(user1).depositTokens(100000,timeStamp,110000,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith("LTV must be set to non-zero value before providing loans");
        })


        it("Should revert if the caller is not owner for initializeTreasury",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            expect(BorrowingContract.connect(user1).initializeTreasury(treasury.address)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the Treasury address is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            expect(BorrowingContract.connect(owner).initializeTreasury(ethers.constants.AddressZero)).to.be.revertedWith("Treasury must be contract address & can't be zero address");
        })

        it("Should revert if caller is not owner(depositToAaveProtocol)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).depositToAaveProtocol();
            expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if caller is not owner(withdrawFromAaveProtocol)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).withdrawFromAaveProtocol(1,ethers.utils.parseEther("10"));
            expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if caller is not owner(depositToCompoundProtocol)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).depositToCompoundProtocol();
            expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if caller is not owner(withdrawFromProtocol)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).withdrawFromCompoundProtocol(1);
            expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if caller is not owner(setLTV)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).setLTV(80);
            expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if ratio is not eligible",async function(){
            const {BorrowingContract,CDSContract,Token} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            console.log(await CDSContract.totalCdsDepositedAmount());
            const tx = BorrowingContract.connect(user1).depositTokens(100000,timeStamp,110000,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith("Not enough fund in CDS");
        })

        // it("Should revert Borrower address can't be zero",async function(){
        //     const {BorrowingContract,Token} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();
        //     const tx = BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("1")});
        //     expect(tx).to.be.revertedWith("Borrower cannot be zero address");
        // })

        // it("Should return true if the address is contract address ",async function(){
        //     const {BorrowingContract,treasury} = await loadFixture(deployer);
        //     const tx = await BorrowingContract.isContract(treasury.address);
        //     expect(tx).to.be.equal(true);
        // })

        // it("Should return false if the address is not contract address ",async function(){
        //     const {BorrowingContract,treasury} = await loadFixture(deployer);
        //     const tx = await BorrowingContract.isContract(user1.address);
        //     expect(tx).to.be.equal(false);
        // })

    })

    describe("Should revert errors",function(){
        it("Should revert if called by other than borrowing contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const tx =  treasury.connect(user1).deposit(user1.address,1000,timeStamp,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");    
        })
        it("Should revert if called by other than borrowing contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx =  treasury.connect(user1).withdraw(user1.address,user1.address,1000,1,1000);
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");    
        })

        it("Should revert if called by other than CDS contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx =  treasury.connect(user1).transferEthToCdsLiquidators(user1.address,1);
            expect(tx).to.be.revertedWith("This function can only called by CDS contract");    
        })

        it("Should revert if the address is zero",async function(){
            const {treasury} = await loadFixture(deployer);
            expect(treasury.connect(owner).setBorrowingContract(ethers.constants.AddressZero)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the address is invalid",async function(){
            const {treasury} = await loadFixture(deployer);
            expect(treasury.connect(owner).setBorrowingContract(user1.address)).to.be.revertedWith("Input address is invalid");
        })

        it("Should revert if the caller is not owner",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            expect(treasury.connect(user1).setBorrowingContract(BorrowingContract.address)).to.be.revertedWith("Ownable: caller is not the owner");
        })





        it("Should revert if the address is zero",async function(){
            const {treasury} = await loadFixture(deployer);
            expect(treasury.connect(owner).withdrawInterest(ethers.constants.AddressZero,0)).to.be.revertedWith("Input address or amount is invalid");
        })

        it("Should revert if the caller is not owner",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            expect(treasury.connect(user1).withdrawInterest(user1.address,100)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if Treasury don't have enough interest",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            expect(treasury.connect(owner).withdrawInterest(user1.address,100)).to.be.revertedWith("Treasury don't have enough interest");
        })

    })

    describe("Should update all state changes correctly",function(){
        it("Should update deposited amount",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            const tx = await treasury.borrowing(user1.address);
            expect(tx[0]).to.be.equal(ethers.utils.parseEther("1"))
        })

        it("Should update depositedAmount correctly if deposited multiple times",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("3")});                    
            const tx = await treasury.borrowing(user1.address);
            expect(tx[0]).to.be.equal(ethers.utils.parseEther("6"))
        })

        it("Should update hasDeposited or not",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            const tx = await treasury.borrowing(user1.address);
            expect(tx[3]).to.be.equal(true);
        })

        it("Should update borrowerIndex",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            const tx = await treasury.borrowing(user1.address);
            expect(tx[4]).to.be.equal(1);
        })

        it("Should update borrowerIndex correctly if deposited multiple times",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("3")});                    
            const tx = await treasury.borrowing(user1.address);
            expect(tx[4]).to.be.equal(3);
        })

        it("Should update totalVolumeOfBorrowersinUSD",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("2")});
            expect(await treasury.totalVolumeOfBorrowersAmountinUSD()).to.be.equal(ethers.utils.parseEther("200000"));
        })

        it("Should update totalVolumeOfBorrowersinUSD if multiple users deposit in different ethPrice",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user2).depositTokens(150000,timeStamp,1,165000,ethVolatility,{value: ethers.utils.parseEther("2")});
            expect(await treasury.totalVolumeOfBorrowersAmountinUSD()).to.be.equal(ethers.utils.parseEther("500000"));
        })

        it("Should update totalVolumeOfBorrowersinWei",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("2")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("3")});          
            expect(await treasury.totalVolumeOfBorrowersAmountinWei()).to.be.equal(ethers.utils.parseEther("5"));
        })

        it("Should update borrowingContract",async () => {
            const {BorrowingContract,treasury} = await loadFixture(deployer);  
            await treasury.connect(owner).setBorrowingContract(BorrowingContract.address);
            expect(await treasury.borrowingContract()).to.be.equal(BorrowingContract.address);
        })
    })

    describe("Should deposit and withdraw Eth in Aave",function(){
        it("Should revert if called by other than Borrowing Contract(Aave Deposit)",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx = treasury.connect(owner).depositToAave();
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
        })

        it("Should revert if zero eth is deposited to Aave",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).depositToAaveProtocol();
            expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroDeposit");
        })

        it("Should deposit eth and mint aTokens",async function(){
            const {BorrowingContract,usdt,aToken} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            //console.log(await treasury.getBalanceInTreasury());
            //expect(await aToken.balanceOf(treasury.address)).to.be.equal(ethers.utils.parseEther("2.5"))
        })

        it("Should revert if zero Eth withdraw from Compound",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).withdrawFromAaveProtocol(1,ethers.utils.parseEther("0"));
            expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroWithdraw");
        })

        it("Should revert if already withdraw in index from Aave",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();

            await BorrowingContract.connect(owner).withdrawFromAaveProtocol(1);
            const tx =  BorrowingContract.connect(owner).withdrawFromAaveProtocol(1);
            expect(tx).to.be.revertedWith("Already withdrawed in this index");
        })

        it("Should revert if called by other than Borrowing Contract(Aave Withdraw)",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx = treasury.connect(owner).withdrawFromAave(1,ethers.utils.parseEther("25"));
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
        })


        it("Should withdraw eth from Aave",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            console.log("TREASURY BALANCE AFTER DEPOSIT : ",(await treasury.getBalanceInTreasury()).toString());

            await BorrowingContract.connect(owner).depositToAaveProtocol();
            console.log("TREASURY BALANCE AFTER DEPOSIT TO AAVE : ",(await treasury.getBalanceInTreasury()).toString());

            await BorrowingContract.connect(owner).withdrawFromAaveProtocol(1);
            console.log("TREASURY BALANCE AFTER WITHDRAW FROM AAVE : ",(await treasury.getBalanceInTreasury()).toString());
        })

        it("Should update deposit index correctly",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();

            const tx = await treasury.protocolDeposit(0);
            expect(tx[0]).to.be.equal(1);
        })

        it("Should update depositedAmount correctly",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();

            const tx = await treasury.protocolDeposit(0);
            expect(tx[1]).to.be.equal(ethers.utils.parseEther("1"));
        })
    })

    describe("Should deposit Eth in Compound",function(){
        it("Should revert if called by other than Borrowing Contract(Compound Deposit)",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx = treasury.connect(owner).depositToCompound();
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
        })

        it("Should revert if zero eth is deposited to Compound",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).depositToCompoundProtocol();
            expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroDeposit");
        })

        it("Should deposit eth and mint cETH",async function(){
            const {BorrowingContract,treasury,cETH} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});

            await BorrowingContract.connect(owner).depositToAaveProtocol();
            await BorrowingContract.connect(owner).depositToCompoundProtocol();
            //console.log(await cETH.balanceOf(treasury.address));         
        })

        it("Should revert if zero Eth withdraw from Compound",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
            expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroWithdraw");
        })

        it("Should revert if called by other than Borrowing Contract(Compound Withdraw)",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx = treasury.connect(owner).withdrawFromCompound(1);
            expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
        })

        it("Should revert if already withdraw in index from Compound",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            await BorrowingContract.connect(owner).depositToCompoundProtocol();

            await BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
            const tx =  BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
            expect(tx).to.be.revertedWith("Already withdrawed in this index");
        })

        it("Should withdraw eth from Compound",async function(){
            const {BorrowingContract,treasury,cETH} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            console.log("TREASURY BALANCE AFTER DEPOSIT : ",(await treasury.getBalanceInTreasury()).toString());
            
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            const tx = await BorrowingContract.connect(owner).depositToCompoundProtocol();
            console.log("TREASURY BALANCE AFTER DEPOSIT TO COMPOUND : ",(await treasury.getBalanceInTreasury()).toString());

            await BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
            console.log("TREASURY BALANCE AFTER WITHDRAW FROM COMPOUND : ",(await treasury.getBalanceInTreasury()).toString());
        })

        it("Should update deposit index correctly",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            await BorrowingContract.connect(owner).depositToCompoundProtocol();

            const tx = await treasury.protocolDeposit(1);
            expect(tx[0]).to.be.equal(1);
        })

        it("Should update depositedAmount correctly",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("4")});
            
            await BorrowingContract.connect(owner).depositToAaveProtocol();
            await BorrowingContract.connect(owner).depositToCompoundProtocol();

            const tx = await treasury.protocolDeposit(1);
            expect(tx[1]).to.be.equal(ethers.utils.parseEther("1"));
        })

        it("Should update totalCreditedTokens correctly",async function(){
             const {BorrowingContract,treasury,cETH} = await loadFixture(deployer);
            // const timeStamp = await time.latest();

            // await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("100")});
            // await BorrowingContract.connect(owner).depositToCompoundProtocol();
            // await BorrowingContract.connect(owner).depositToCompoundProtocol();

            // const tx = await treasury.protocolDeposit(1);
            // expect(tx[2]).to.be.equal();
            //console.log(await cETH.connect(user1).balanceOf(treasury.address));
        })

        // it.only("Should update depositedUsdValue correctly",async function(){
        //     const {BorrowingContract,treasury} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.utils.parseEther("100")});
        //     await BorrowingContract.connect(owner).depositToCompoundProtocol();
        //     await BorrowingContract.connect(owner).depositToCompoundProtocol();

        //     const usdValue = await BorrowingContract.getUSDValue();
        //     const ethValue = ethers.utils.parseEther("100");

        //     const tx = await treasury.protocolDeposit(1);
        //     expect(tx[3]).to.be.equal();
        // })
    })

    describe("Should withdraw ETH from protocol",function(){
        it("Should withdraw ETH (between 0.8 and 1)",async function(){
            const {BorrowingContract,Token,pToken,treasury,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await Token.connect(user1).approve(BorrowingContract.address,await Token.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);

            await pToken.connect(user1).approve(BorrowingContract.address,await pToken.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);
            console.log(await treasury.getBalanceInTreasury());
        })
        it("Should withdraw ETH(>1)",async function(){
            const {BorrowingContract,Token,pToken,treasury,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000);
            await Token.connect(user1).mint(user1.address,ethers.utils.parseEther("10"));
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("2")});

            await Token.connect(user1).approve(BorrowingContract.address,await Token.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,110000,timeStamp,4);

            await pToken.connect(user1).approve(BorrowingContract.address,await pToken.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);
            console.log(await treasury.getBalanceInTreasury());

        })
        it("Should withdraw ETH(=1)",async function(){
            const {BorrowingContract,Token,pToken,treasury,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await Token.connect(user1).approve(BorrowingContract.address,await Token.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,100000,timeStamp,4);

            await pToken.connect(user1).approve(BorrowingContract.address,await pToken.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);
            console.log(await treasury.getBalanceInTreasury());

        })
        it("Should revert To address is zero and contract address",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            const tx = BorrowingContract.connect(user1).withDraw(ethers.constants.AddressZero,1,99900,timeStamp);
            expect(tx).to.be.revertedWith("To address cannot be a zero and contract address");

            const tx1 = BorrowingContract.connect(user1).withDraw(treasury.address,1,99900,timeStamp);
            expect(tx1).to.be.revertedWith("To address cannot be a zero and contract address");
        })
        it("Should revert if User doens't have the perticular index",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            const tx = BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp);
            expect(tx).to.be.revertedWith("User doens't have the perticular index");
        })
        it("Should revert if BorrowingHealth is Low",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            const tx = BorrowingContract.connect(user1).withDraw(user2.address,1,80000,timeStamp,4);
            expect(tx).to.be.revertedWith("BorrowingHealth is Low");
        })
        it("Should revert if User already withdraw entire amount",async function(){
            const {BorrowingContract,Token,pToken,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await Token.connect(user1).approve(BorrowingContract.address,await Token.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);

            await pToken.connect(user1).approve(BorrowingContract.address,await pToken.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);

            const tx = BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp);
            expect(tx).to.be.revertedWith("User already withdraw entire amount");
        })

        it("Should revert if User amount has been liquidated",async function(){
            const {BorrowingContract,CDSContract,Token,pToken,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("10000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await BorrowingContract.liquidate(user1.address,1,80000);
            const tx = BorrowingContract.connect(user1).withDraw(user1.address,1,99900,timeStamp,4);
            expect(tx).to.be.revertedWith("User amount has been liquidated");
        })

        // it("Should revert User balance is less than required",async function(){
        //     const {BorrowingContract,treasury} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();

        //     await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,{value: ethers.utils.parseEther("1")});
        //     await Token.connect(user1).transfer(user2.address,ethers.utils.parseEther("0.25"));
        //     const tx = BorrowingContract.connect(user1).withDraw(user2.address,1,90000,timeStamp);
        //     expect(tx).to.be.revertedWith("User balance is less than required");
        // })

        it("Should revert Don't have enough Protocol Tokens",async function(){
            const {BorrowingContract,Token,pToken} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await Token.connect(user1).approve(BorrowingContract.address,await Token.balanceOf(user1.address));
            await BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);
            await pToken.connect(user1).transfer(user2.address,ethers.utils.parseEther("0.1"));

            const tx = BorrowingContract.connect(user1).withDraw(user2.address,1,99900,timeStamp,4);
            expect(tx).to.be.revertedWith("Don't have enough Protocol Tokens");
        })
    })

    describe("Should Liquidate ETH from protocol",function(){
        it("Should Liquidate ETH",async function(){
            const {BorrowingContract,CDSContract,Token,pToken,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await Token.mint(user2.address,ethers.utils.parseEther("2000"))
            //await BorrowingContract.calculateCumulativeRate();
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await BorrowingContract.liquidate(user1.address,1,80000);
        })

        it("Should revert To address is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).liquidate(ethers.constants.AddressZero,1,100000);
            expect(tx).to.be.revertedWith("To address cannot be a zero address");
        })

        it("Should revert You cannot liquidate your own assets!",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).liquidate(user1.address,1,100000);
            expect(tx).to.be.revertedWith("You cannot liquidate your own assets!");
        })

        it("Should revert Not enough funds in treasury",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            await BorrowingContract.connect(owner).depositToAaveProtocol();

            const tx = BorrowingContract.connect(user1).liquidate(user2.address,1,100000);
            expect(tx).to.be.revertedWith("Not enough funds in treasury");
        })

        it("Should revert You cannot liquidate",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            const tx = BorrowingContract.connect(user1).liquidate(user2.address,1,100000);
            expect(tx).to.be.revertedWith("You cannot liquidate");
        })

        it("Should calculate Option Price",async function(){
            const {options,usdt,Token,CDSContract,BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const ethPrice = await BorrowingContract.getUSDValue();
            console.log(ethPrice);

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            await BorrowingContract.connect(user1).depositTokens(ethPrice,timeStamp,1,(ethPrice * 1.1),50622665,{value: ethers.utils.parseEther("1")});
            console.log("USER's AMINT BALANCE",(await Token.balanceOf(user1.address)).toString());
            // console.log("TREASURY's AMINT BALANCE",await Token.balanceOf(treasury.address));

            // await options.calculateOptionPrice(50622665,ethers.utils.parseEther("1"));
        })

        // it("Should check EIP712",async function(){
        //     const {BorrowingContract,user1} = await loadFixture(deployer);
        //     const holder = user1.address; // Use the connected signer's address
        //     const spender = ethers.constants.AddressZero;;
        //     const allowedAmount = 100;
        //     const allowed = true;
        //     const expiry = Math.floor(Date.now() / 1000) + 3600;
        //     const DOMAIN_SEPARATOR = await BorrowingContract.DOMAIN_SEPARATOR();
   
        //     const messageHash = ethers.utils.solidityPack(
        //                     ["address", "address", "uint256", "bool", "uint256"],
        //                     [holder, spender, allowedAmount, allowed, expiry]
        //             )

        //     const permitHash = await BorrowingContract.connect(user1).getMessageHash(messageHash);
        //     // const permitHash = ethers.utils.keccak256(
        //     //     ethers.utils.solidityPack(
        //     //       ["bytes1", "bytes32", "bytes32"],
        //     //       [number, DOMAIN_SEPARATOR, (ethers.utils.keccak256(
        //     //         ethers.utils.solidityPack(
        //     //           ["address", "address", "uint256", "bool", "uint256"],
        //     //           [holder, spender, allowedAmount, allowed, expiry]
        //     //         )
        //     //       ))]
        //     //     )
        //     // );

        //     console.log(1);
        //     const rawSignature = await user1.signMessage(permitHash);
        //     console.log(2);
        //     const { v, r, s } = ethers.utils.splitSignature(rawSignature);
        //     console.log(3);

        //     const bool = await BorrowingContract.connect(user1).permit(holder,spender,allowedAmount,allowed,expiry,v,r,s);
            
        //     console.log(bool);
        // })

        it("Should revert if non owner tried to approve pausing",async function(){
            const {multiSign} = await loadFixture(deployer);
            expect(multiSign.connect(user1).approve()).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if non owner tried to approve unpausing",async function(){
            const {multiSign} = await loadFixture(deployer);
            expect(multiSign.connect(user1).approve()).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if tried to approve pausing twice ",async function(){
            const {multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            expect(multiSign.connect(owner).approve()).to.be.revertedWith('Already approved');
        })

        it("Should revert caller is not the owner if tried to pause Borrowing",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            expect(BorrowingContract.connect(user1).pause()).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert caller is not the owner if tried to pause CDS",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);

            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            expect(CDSContract.connect(user2).pause()).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert caller is not the owner if tried to unpause Borrowing",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            expect(BorrowingContract.connect(user1).unpause()).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert caller is not the owner if tried to unpause CDS",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);

            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            expect(CDSContract.connect(user2).unpause()).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if tried to pause Borrowing before attaining required approvals",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            expect(BorrowingContract.connect(owner).pause()).to.be.revertedWith('Required approvals not met');
        })

        it("Should revert if tried to pause CDS before attaining required approvals",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            expect(CDSContract.connect(owner).pause()).to.be.revertedWith('Required approvals not met');
        })

        it("Should revert if tried to unpause Borrowing before attaining required approvals",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            expect(BorrowingContract.connect(owner).unpause()).to.be.revertedWith('Required approvals not met');
        })

        it("Should revert if tried to unpause CDS before attaining required approvals",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            expect(CDSContract.connect(owner).unpause()).to.be.revertedWith('Required approvals not met');
        })

        it("Should revert if tried to deposit ETH in borrowing when it is paused",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            await BorrowingContract.connect(owner).pause();

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            const tx = BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});
            expect(tx).to.be.revertedWith('Pausable: paused');
        })

        it("Should revert if tried to deposit USDT or AMINT in CDS when it is paused",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            await CDSContract.connect(owner).pause();

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            const tx = CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));
            expect(tx).to.be.revertedWith('Pausable: paused');
        })

        it("Should revert if tried to withdraw ETH in borrowing when it is paused",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));

            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.utils.parseEther("1")});

            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            await BorrowingContract.connect(owner).pause();

            await Token.connect(user1).approve(BorrowingContract.address,await Token.balanceOf(user1.address));
            const tx = BorrowingContract.connect(user2).withDraw(user2.address,1,99900,timeStamp,4);
            expect(tx).to.be.revertedWith('Pausable: paused');
        })

        it("Should revert if tried to withdraw AMINT in CDS when it is paused",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.address,10000000000)
            await usdt.connect(user1).approve(CDSContract.address,10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,ethers.utils.parseEther("5000"));

            await multiSign.connect(owner).approve();
            await multiSign.connect(owner1).approve();
            await CDSContract.connect(owner).pause();
            
            const tx = CDSContract.connect(user1).withdraw(1);

            expect(tx).to.be.revertedWith('Pausable: paused');
        })

    })
})
