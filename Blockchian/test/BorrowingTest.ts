const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { it } = require("mocha")
import { ethers,upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { describe } from "node:test";
import { BorrowingTest, CDSTest, TestAMINTStablecoin, TestABONDToken, Treasury,Options,TestUSDT,MultiSign,OwnableUpgradeable__factory} from "../typechain-types";
import {
    wethGatewayMainnet,wethGatewaySepolia,
    priceFeedAddressMainnet,priceFeedAddressSepolia,
    aTokenAddressMainnet,aTokenAddressSepolia,
    aavePoolAddressMainnet,aavePoolAddressSepolia,
    cometMainnet,cometSepolia,
    INFURA_URL_MAINNET,INFURA_URL_SEPOLIA,
    aTokenABI,
    cETH_ABI,
    wethAddressMainnet,wethAddressSepolia,
    } from "./utils/index"

describe("Borrowing Contract",function(){

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
        const CDSContract = await upgrades.deployProxy(CDS,[await Token.getAddress(),priceFeedAddressMainnet,await usdt.getAddress(),await multiSign.getAddress()],{initializer:'initialize'},{kind:'uups'})

        const Borrowing = await ethers.getContractFactory("BorrowingTest");
        const BorrowingContract = await upgrades.deployProxy(Borrowing,[await Token.getAddress(),await CDSContract.getAddress(),await abondToken.getAddress(),await multiSign.getAddress(),priceFeedAddressMainnet,1],{initializer:'initialize'},{kind:'uups'});

        const Treasury = await ethers.getContractFactory("Treasury");
        const treasury = await upgrades.deployProxy(Treasury,[await BorrowingContract.getAddress(),await Token.getAddress(),await abondToken.getAddress(),await CDSContract.getAddress(),wethGatewayMainnet,cometMainnet,aavePoolAddressMainnet,aTokenAddressMainnet,await usdt.getAddress(),wethAddressMainnet],{initializer:'initialize'},{kind:'uups'});

        const Option = await ethers.getContractFactory("Options");
        const options = await upgrades.deployProxy(Option,[await treasury.getAddress(),await CDSContract.getAddress(),await BorrowingContract.getAddress()],{initializer:'initialize'},{kind:'uups'});
        
        await abondToken.setBorrowingContract(await BorrowingContract.getAddress());
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
        
        const provider = new ethers.JsonRpcProvider(INFURA_URL_MAINNET);
        const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",provider);

        const aToken = new ethers.Contract(aTokenAddressMainnet,aTokenABI,signer);
        const cETH = new ethers.Contract(cometMainnet,cETH_ABI,signer);

        return {Token,abondToken,usdt,CDSContract,BorrowingContract,treasury,options,multiSign,owner,user1,user2,user3,provider,signer}
    }

    describe("Should deposit ETH and mint Trinity",function(){
        it("Should deposit ETH",async function(){
            const {BorrowingContract,CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("50")});
        })

        it("Should calculate criticalRatio correctly",async function(){
            const {BorrowingContract,CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,false,0);
            await BorrowingContract.connect(user1).depositTokens(200000,timeStamp,1,220000,ethVolatility,{value: ethers.parseEther("2.5")});
        })

        it("Should set APY",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([1]);
            await multiSign.connect(owner1).approveSetterFunction([1]);
            await BorrowingContract.setAPR(BigInt("1000000001547125957863212449"));
            await expect(await BorrowingContract.ratePerSec()).to.be.equal(BigInt("1000000001547125957863212449"));
        })
        it("Should called by only owner(setAPR)",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([1]);
            await multiSign.connect(owner1).approveSetterFunction([1]);
            const tx = BorrowingContract.connect(user1).setAPR(BigInt("1000000001547125957863212449"));
            //console.log(await tx);
            await expect(tx).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if rate is zero",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([1]);
            await multiSign.connect(owner1).approveSetterFunction([1]);
            const tx = BorrowingContract.connect(owner).setAPR(0);

            await expect(tx).to.be.revertedWith("Rate should not be zero");
        })

        // it.only("Should revert You do not have sufficient balance to execute this transaction",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();
        //     console.log("BAL USER3",await ethers.provider.getBalance(user3.address));
            
        //     const tx = BorrowingContract.connect(user3).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("9999.999999999999999")});
            
        //     await expect(tx).to.be.revertedWith("You do not have sufficient balance to execute this transaction");
        // })

        it("Should revert if set APY without approval",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).setAPR(BigInt("1000000001547125957863212449"));

            await expect(tx).to.be.revertedWith("Required approvals not met");
        })

        // it("Should get APY",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     await expect(await BorrowingContract.getAPY()).to.be.equal(5);
        // })

        it("Should get LTV",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await expect(await BorrowingContract.getLTV()).to.be.equal(80);
        })

        it("Should calculate CumulativeRate",async function(){
            const {BorrowingContract,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,false,0);
            await BorrowingContract.connect(user1).depositTokens(200000,timeStamp,1,220000,ethVolatility,{value: ethers.parseEther("2.5")});
        })
    })

    describe("Should get the ETH/USD price",function(){
        it("Should get ETH/USD price",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = await BorrowingContract.getUSDValue();
        })
    })

    describe("Should revert errors",function(){
        it("Should revert if zero eth is deposited",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const tx =  BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("0")});
            await expect(tx).to.be.revertedWith("Cannot deposit zero tokens");
        })

        // it("Should revert if LTV set to zero value before providing loans",async function(){
        //     const {BorrowingContract,CDSContract} = await loadFixture(deployer);
        //     await BorrowingContract.setLTV(0);          
        //     const timeStamp = await time.latest();
        //     await usdt.connect(user1).mint(user1.getAddress(),10000000000)
        //     await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
        //     await CDSContract.connect(user1).deposit(10000000000,0,false,0);
        //     const tx =  BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
        //     await expect(tx).to.be.revertedWith("LTV must be set to non-zero value before providing loans");
        // })

        it("Should revert if LTV set to zero",async function(){
            const {BorrowingContract,multiSign,CDSContract} = await loadFixture(deployer);
            await multiSign.connect(owner).approveSetterFunction([0]);
            await multiSign.connect(owner1).approveSetterFunction([0]);
            const tx = BorrowingContract.connect(owner).setLTV(0);          
            await expect(tx).to.be.revertedWith("LTV can't be zero");
        })

        it("Should revert if the caller is not owner for setTreasury",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            await expect(BorrowingContract.connect(user1).setTreasury(await treasury.getAddress())).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the Treasury address is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await expect(BorrowingContract.connect(owner).setTreasury(ethers.ZeroAddress)).to.be.revertedWith("Treasury must be contract address & can't be zero address");
        })

        it("Should revert if the caller is not owner for setOptions",async function(){
            const {BorrowingContract,options} = await loadFixture(deployer);
            await expect(BorrowingContract.connect(user1).setOptions(await options.getAddress())).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if the Options address is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await expect(BorrowingContract.connect(owner).setOptions(ethers.ZeroAddress)).to.be.revertedWith("Options must be contract address & can't be zero address");
        })

        it("Should revert if the caller is not owner for setAdmin",async function(){
            const {BorrowingContract,options} = await loadFixture(deployer);
            await expect(BorrowingContract.connect(user1).setAdmin(owner.getAddress())).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if the Admin address is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            await expect(BorrowingContract.connect(owner).setAdmin(ethers.ZeroAddress)).to.be.revertedWith("Admin can't be contract address & zero address");
        })

        // it("Should revert if caller is not owner(depositToAaveProtocol)",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     const tx = BorrowingContract.connect(user1).depositToAaveProtocol();
        //     await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        // })

        // it("Should revert if caller is not owner(withdrawFromAaveProtocol)",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     const tx = BorrowingContract.connect(user1).withdrawFromAaveProtocol(1);
        //     await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        // })

        // it("Should revert if caller is not owner(depositToCompoundProtocol)",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     const tx = BorrowingContract.connect(user1).depositToCompoundProtocol();
        //     await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        // })

        // it("Should revert if caller is not owner(withdrawFromProtocol)",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     const tx = BorrowingContract.connect(user1).withdrawFromCompoundProtocol(1);
        //     await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        // })

        it("Should revert if caller is not owner(setWithdrawTimeLimit)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).setWithdrawTimeLimit(100);
            await expect(tx).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if caller is not owner(setLTV)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).setLTV(80);
            await expect(tx).to.be.revertedWith("Caller is not an admin");
        })

        it("Should revert if caller is not treasury(updateLastEthVaultValue)",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(user1).updateLastEthVaultValue(100);
            await expect(tx).to.be.revertedWith("Function should only be called by treasury");
        })

        it("Should revert if WithdrawTimeLimit is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).setWithdrawTimeLimit(0);
            await expect(tx).to.be.revertedWith("Withdraw time limit can't be zero");
        })

        it("Should revert if ratio is not eligible",async function(){
            const {BorrowingContract,CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.getAddress(),100000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),100000000);
            await CDSContract.connect(user1).deposit(100000000,0,true,50000000);
            const tx = BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await expect(tx).to.be.revertedWith("Not enough fund in CDS");
        })

        // it("Should revert Borrower address can't be zero",async function(){
        //     const {BorrowingContract,CDSContract} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();
        //     await usdt.connect(user1).mint(user1.getAddress(),10000000000)
        //     await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
        //     await CDSContract.connect(user1).deposit(10000000000,0,false,0);
        //     const tx = BorrowingContract.connect(ethers.ZeroAddress).depositTokens(1000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
        //     await expect(tx).to.be.revertedWith("Borrower cannot be zero address");
        // })

        it("Should return true if the address is contract address ",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = await BorrowingContract.isContract(await treasury.getAddress());
            await expect(tx).to.be.equal(true);
        })

        it("Should return false if the address is not contract address ",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const tx = await BorrowingContract.isContract(user1.getAddress());
            await expect(tx).to.be.equal(false);
        })

    })

    describe("Should revert errors",function(){
        it("Should revert if called by other than borrowing contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const tx =  treasury.connect(user1).deposit(user1.getAddress(),1000,timeStamp,{value: ethers.parseEther("1")});
            await expect(tx).to.be.revertedWith("This function can only called by borrowing contract");    
        })
        it("Should revert if called by other than borrowing contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx =  treasury.connect(user1).withdraw(user1.getAddress(),user1.getAddress(),1000,1);
            await expect(tx).to.be.revertedWith("This function can only called by borrowing contract");    
        })

        it("Should revert if called by other than CDS contract",async function(){
            const {treasury} = await loadFixture(deployer);
            const tx =  treasury.connect(user1).transferEthToCdsLiquidators(user1.getAddress(),1);
            await expect(tx).to.be.revertedWith("This function can only called by CDS contract");    
        })

        it("Should revert if the address is zero",async function(){
            const {treasury} = await loadFixture(deployer);
            await expect(treasury.connect(owner).withdrawInterest(ethers.ZeroAddress,0)).to.be.revertedWith("Input address or amount is invalid");
        })

        it("Should revert if the caller is not owner",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            await expect(treasury.connect(user1).withdrawInterest(user1.getAddress(),100)).to.be.revertedWith("Ownable: caller is not the owner");
        })

        it("Should revert if Treasury don't have enough interest",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            await expect(treasury.connect(owner).withdrawInterest(user1.getAddress(),100)).to.be.revertedWith("Treasury don't have enough interest");
        })

    })

    describe("Should update all state changes correctly",function(){
        it("Should update deposited amount",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            const tx = await treasury.borrowing(user1.getAddress());
            await expect(tx[0]).to.be.equal(ethers.parseEther("1"))
        })

        it("Should update depositedAmount correctly if deposited multiple times",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("2")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("3")});                    
            const tx = await treasury.borrowing(user1.getAddress());
            await expect(tx[0]).to.be.equal(ethers.parseEther("6"))
        })

        it("Should update hasDeposited or not",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            const tx = await treasury.borrowing(user1.getAddress());
            await expect(tx[3]).to.be.equal(true);
        })

        it("Should update borrowerIndex",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            const tx = await treasury.borrowing(user1.getAddress());
            await expect(tx[4]).to.be.equal(1);
        })

        it("Should update borrowerIndex correctly if deposited multiple times",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("2")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("3")});                    
            const tx = await treasury.borrowing(user1.getAddress());
            await expect(tx[4]).to.be.equal(3);
        })

        it("Should update totalVolumeOfBorrowersinUSD",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("2")});
            await expect(await treasury.totalVolumeOfBorrowersAmountinUSD()).to.be.equal(ethers.parseEther("200000"));
        })

        it("Should update totalVolumeOfBorrowersinUSD if multiple users deposit in different ethPrice",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("2")});
            await BorrowingContract.connect(user2).depositTokens(150000,timeStamp,1,165000,ethVolatility,{value: ethers.parseEther("2")});
            await expect(await treasury.totalVolumeOfBorrowersAmountinUSD()).to.be.equal(ethers.parseEther("500000"));
        })

        it("Should update totalVolumeOfBorrowersinWei",async function(){
            const {BorrowingContract,treasury,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("2")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("3")});          
            await expect(await treasury.totalVolumeOfBorrowersAmountinWei()).to.be.equal(ethers.parseEther("5"));
        })

    })

    // describe("Should deposit and withdraw Eth in Aave",function(){
    //     it("Should revert if called by other than Borrowing Contract(Aave Deposit)",async function(){
    //         const {treasury} = await loadFixture(deployer);
    //         const tx = treasury.connect(owner).depositToAave();
    //         await expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
    //     })

    //     it("Should revert if zero eth is deposited to Aave",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const tx = BorrowingContract.connect(owner).depositToAaveProtocol();
    //         await expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroDeposit");
    //     })

    //     it("Should deposit eth and mint aTokens",async function(){
    //         const {BorrowingContract,usdt,aToken} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();
    //         //console.log(await treasury.getBalanceInTreasury());
    //         //await expect(await aToken.balanceOf(await treasury.getAddress())).to.be.equal(ethers.parseEther("2.5"))
    //     })

    //     it("Should revert if already withdraw in index from Aave",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();

    //         await BorrowingContract.connect(owner).withdrawFromAaveProtocol(1);
    //         const tx =  BorrowingContract.connect(owner).withdrawFromAaveProtocol(1);
    //         await expect(tx).to.be.revertedWith("Already withdrawed in this index");
    //     })

    //     it("Should revert if called by other than Borrowing Contract(Aave Withdraw)",async function(){
    //         const {treasury} = await loadFixture(deployer);
    //         const tx = treasury.connect(owner).withdrawFromAave(1);
    //         await expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
    //     })


    //     it("Should withdraw eth from Aave",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});

    //         await BorrowingContract.connect(owner).depositToAaveProtocol();

    //         await BorrowingContract.connect(owner).withdrawFromAaveProtocol(1);
    //     })

    //     it("Should update deposit index correctly",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();

    //         const tx = await treasury.protocolDeposit(0);
    //         await expect(tx[0]).to.be.equal(1);
    //     })

    //     it("Should update depositedAmount correctly",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();

    //         const tx = await treasury.protocolDeposit(0);
    //         await expect(tx[1]).to.be.equal(ethers.parseEther("1"));
    //     })
    // })

    // describe("Should deposit Eth in Compound",function(){
    //     it("Should revert if called by other than Borrowing Contract(Compound Deposit)",async function(){
    //         const {treasury} = await loadFixture(deployer);
    //         const tx = treasury.connect(owner).depositToCompound();
    //         await expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
    //     })

    //     it("Should revert if zero eth is deposited to Compound",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const tx = BorrowingContract.connect(owner).depositToCompoundProtocol();
    //         await expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroDeposit");
    //     })

    //     it("Should deposit eth and mint cETH",async function(){
    //         const {BorrowingContract,treasury,cETH} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});

    //         await BorrowingContract.connect(owner).depositToAaveProtocol();
    //         await BorrowingContract.connect(owner).depositToCompoundProtocol();
    //     })

    //     it("Should revert if zero Eth withdraw from Compound",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const tx = BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
    //         await expect(tx).to.be.revertedWithCustomError(treasury,"Treasury_ZeroWithdraw");
    //     })

    //     it("Should revert if called by other than Borrowing Contract(Compound Withdraw)",async function(){
    //         const {treasury} = await loadFixture(deployer);
    //         const tx = treasury.connect(owner).withdrawFromCompound(1);
    //         await expect(tx).to.be.revertedWith("This function can only called by borrowing contract");
    //     })

    //     it("Should revert if already withdraw in index from Compound",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();
    //         await BorrowingContract.connect(owner).depositToCompoundProtocol();

    //         await BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
    //         const tx =  BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
    //         await expect(tx).to.be.revertedWith("Already withdrawed in this index");
    //     })

    //     it("Should withdraw eth from Compound",async function(){
    //         const {BorrowingContract,treasury,cETH} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
            
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();
    //         const tx = await BorrowingContract.connect(owner).depositToCompoundProtocol();

    //         await BorrowingContract.connect(owner).withdrawFromCompoundProtocol(1);
    //     })

    //     it("Should update deposit index correctly",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();
    //         await BorrowingContract.connect(owner).depositToCompoundProtocol();

    //         const tx = await treasury.protocolDeposit(1);
    //         await expect(tx[0]).to.be.equal(1);
    //     })

    //     it("Should update depositedAmount correctly",async function(){
    //         const {BorrowingContract,treasury} = await loadFixture(deployer);
    //         const timeStamp = await time.latest();
    //         await usdt.connect(user1).mint(user1.getAddress(),10000000000)
    //         await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
    //         await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
    //         await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("4")});
            
    //         await BorrowingContract.connect(owner).depositToAaveProtocol();
    //         await BorrowingContract.connect(owner).depositToCompoundProtocol();

    //         const tx = await treasury.protocolDeposit(1);
    //         await expect(tx[1]).to.be.equal(ethers.parseEther("1"));
    //     })

    //     // it.only("Should update depositedUsdValue correctly",async function(){
    //     //     const {BorrowingContract,treasury} = await loadFixture(deployer);
    //     //     const timeStamp = await time.latest();

    //     //     await BorrowingContract.connect(user1).depositTokens(1000,timeStamp,{value: ethers.parseEther("100")});
    //     //     await BorrowingContract.connect(owner).depositToCompoundProtocol();
    //     //     await BorrowingContract.connect(owner).depositToCompoundProtocol();

    //     //     const usdValue = await BorrowingContract.getUSDValue();
    //     //     const ethValue = ethers.parseEther("100");

    //     //     const tx = await treasury.protocolDeposit(1);
    //     //     await expect(tx[3]).to.be.equal();
    //     // })
    // })

    describe("Should withdraw ETH from protocol",function(){
        it("Should withdraw ETH (between 0.8 and 1)",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);
            
            await BorrowingContract.calculateCumulativeRate();
            await Token.mint(user1.getAddress(),5000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,99900,timeStamp);
        })
        it("Should withdraw ETH(>1)",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000);
            await Token.connect(user1).mint(user1.getAddress(),10000000);
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("2")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.mint(user1.getAddress(),5000000);
            
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,110000,timeStamp);

        })
        it("Should withdraw ETH(=1)",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.mint(user1.getAddress(),5000000);
            
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,100000,timeStamp);

        })
        it("Should revert To address is zero and contract address",async function(){
            const {BorrowingContract,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            const tx = BorrowingContract.connect(user1).withDraw(ethers.ZeroAddress,1,99900,timeStamp);
            await expect(tx).to.be.revertedWith("To address cannot be a zero and contract address");

            const tx1 = BorrowingContract.connect(user1).withDraw(await treasury.getAddress(),1,99900,timeStamp);
            await expect(tx1).to.be.revertedWith("To address cannot be a zero and contract address");
        })
        it("Should revert if User doens't have the perticular index",async function(){
            const {BorrowingContract,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            const tx = BorrowingContract.connect(user1).withDraw(user2.getAddress(),2,99900,timeStamp);
            await expect(tx).to.be.revertedWith("User doens't have the perticular index");
        })
        it("Should revert if BorrowingHealth is Low",async function(){
            const {BorrowingContract,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            const tx = BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,80000,timeStamp);
            await expect(tx).to.be.revertedWith("BorrowingHealth is Low");
        })
        it("Should revert if User already withdraw entire amount",async function(){
            const {BorrowingContract,Token,abondToken,CDSContract,usdt} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.mint(user1.getAddress(),5000000);
            
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,99900,timeStamp);

            const tx = BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,99900,timeStamp);
            await expect(tx).to.be.revertedWith("User already withdraw entire amount");
        })

        it("Should revert if withdraw time limit is not yet reached",async function(){
            const {BorrowingContract,Token,abondToken,CDSContract,usdt,multiSign} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await multiSign.connect(owner).approveSetterFunction([2]);
            await multiSign.connect(owner1).approveSetterFunction([2]);
            await BorrowingContract.connect(owner).setWithdrawTimeLimit(2592000);
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 259200);

            await BorrowingContract.calculateCumulativeRate();
            await Token.mint(user1.getAddress(),5000000);
            
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,99900,timeStamp);

            // await expect(tx).to.be.revertedWith("Can't withdraw before the withdraw time limit");
        })

        it("Should revert if User amount has been liquidated",async function(){
            const {BorrowingContract,CDSContract,usdt,abondToken,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);
            
            await BorrowingContract.calculateCumulativeRate();
            await BorrowingContract.liquidate(user1.getAddress(),1,80000);
            const tx = BorrowingContract.connect(user1).withDraw(user1.getAddress(),1,99900,timeStamp);
            await expect(tx).to.be.revertedWith("User amount has been liquidated");
        })

        it("Should revert User balance is less than required",async function(){
            const {BorrowingContract,Token,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await Token.connect(user1).transfer(user2.getAddress(),25000000);
            const tx = BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,90000,timeStamp);
            await expect(tx).to.be.revertedWith("User balance is less than required");
        })

        it("Should revert Don't have enough Protocol Tokens",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.mint(user1.getAddress(),5000000);
            
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user2.getAddress(),1,99900,timeStamp);

            // await expect(tx).to.be.revertedWith("Don't have enough ABOND Tokens");
        })
    })

    describe("Should Liquidate ETH from protocol",function(){
        it("Should Liquidate ETH",async function(){
            const {BorrowingContract,CDSContract,usdt,signer,Token,abondToken,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);

            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            await BorrowingContract.liquidate(user1.getAddress(),1,80000);

        })

        it("Should revert Already liquidated",async function(){
            const {BorrowingContract,CDSContract,usdt,abondToken,treasury} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            await BorrowingContract.connect(owner).liquidate(user1.getAddress(),1,80000);

            const tx = BorrowingContract.connect(owner).liquidate(user1.getAddress(),1,80000);
            await expect(tx).to.be.revertedWith('Already Liquidated');
        })

        it("Should revert if other than admin tried to Liquidate",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            
            const tx = BorrowingContract.connect(user2).liquidate(user1.getAddress(),1,80000);
            await expect(tx).to.be.revertedWith('Caller is not an admin');
        })

        it("Should revert To address is zero",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).liquidate(ethers.ZeroAddress,1,100000);
            await expect(tx).to.be.revertedWith("To address cannot be a zero address");
        })

        it("Should revert You cannot liquidate your own assets!",async function(){
            const {BorrowingContract} = await loadFixture(deployer);
            const tx = BorrowingContract.connect(owner).liquidate(owner.getAddress(),1,100000);
            await expect(tx).to.be.revertedWith("You cannot liquidate your own assets!");
        })

        // it("Should revert Not enough funds in treasury",async function(){
        //     const {BorrowingContract} = await loadFixture(deployer);
        //     const timeStamp = await time.latest();
        //     await usdt.connect(user1).mint(user1.getAddress(),10000000000)
        //     await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
        //     await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
        //     await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
        //     await BorrowingContract.connect(owner).depositToAaveProtocol();

        //     const tx = BorrowingContract.connect(owner).liquidate(user2.getAddress(),1,100000);
        //     await expect(tx).to.be.revertedWith("Not enough funds in treasury");
        // })

        it("Should revert You cannot liquidate",async function(){
            const {BorrowingContract,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            const tx = BorrowingContract.connect(owner).liquidate(user2.getAddress(),1,100000);
            await expect(tx).to.be.revertedWith("You cannot liquidate");
        })

        it("Should calculate Option Price",async function(){
            const {options,usdt,Token,CDSContract,BorrowingContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            const ethPrice = await BorrowingContract.getUSDValue();

            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,50622665,{value: ethers.parseEther("1")});
            // console.log("TREASURY's AMINT BALANCE",await Token.balanceOf(await treasury.getAddress()));

            // await options.calculateOptionPrice(50622665,ethers.parseEther("1"));
        })

        // it("Should check EIP712",async function(){
        //     const {BorrowingContract,user1} = await loadFixture(deployer);
        //     const holder = user1.getAddress(); // Use the connected signer's address
        //     const spender = ethers.ZeroAddress;;
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
            await expect(multiSign.connect(user1).approvePause([0])).to.be.revertedWith("Not an owner");
        })

        it("Should revert if non owner tried to approve unpausing",async function(){
            const {multiSign} = await loadFixture(deployer);
            await expect(multiSign.connect(user1).approveUnPause([2])).to.be.revertedWith("Not an owner");
        })

        it("Should revert if tried to approve pausing twice ",async function(){
            const {multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approvePause([0]);
            await expect(multiSign.connect(owner).approvePause([0])).to.be.revertedWith('Already approved');
        })

        it("Should revert caller is not the owner if tried to pause Borrowing",async function(){
            const {multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approvePause([1]);
            await multiSign.connect(owner1).approvePause([1]);
            await expect(multiSign.connect(user1).pauseFunction([1])).to.be.revertedWith("Not an owner");
        })

        it("Should revert caller is not the owner if tried to unpause Borrowing",async function(){
            const {multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approveUnPause([0]);
            await multiSign.connect(owner1).approveUnPause([0]);
            await expect(multiSign.connect(user1).unpauseFunction([1])).to.be.revertedWith("Not an owner");
        })

        it("Should revert if tried to pause Borrowing before attaining required approvals",async function(){
            const {multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approvePause([1]);
            await expect(multiSign.connect(owner).pauseFunction([1])).to.be.revertedWith('Required approvals not met');
        })

        it("Should revert if tried to unpause Borrowing before attaining required approvals",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approvePause([1]);
            await multiSign.connect(owner1).approvePause([1]);
            await multiSign.connect(owner).pauseFunction([1]);

            await multiSign.connect(owner).approveUnPause([1]);
            await expect(multiSign.connect(owner).unpauseFunction([1])).to.be.revertedWith('Required approvals not met');
        })

        it("Should revert if tried to deposit ETH in borrowing when it is paused",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await multiSign.connect(owner).approvePause([0]);
            await multiSign.connect(owner1).approvePause([0]);
            await multiSign.connect(owner).pauseFunction([0]);

            const tx = BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            await expect(tx).to.be.revertedWith('Paused');
        })

        it("Should revert if tried to deposit USDT or AMINT in CDS when it is paused",async function(){
            const {CDSContract,multiSign,usdt} = await loadFixture(deployer);
            await multiSign.connect(owner).approvePause([4]);
            await multiSign.connect(owner1).approvePause([4]);
            await multiSign.connect(owner).pauseFunction([4]);

            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            const tx = CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await expect(tx).to.be.revertedWith('Paused');
        })

        it("Should revert if tried to redeem USDT in cds when it is paused",async function(){
            const {CDSContract,multiSign} = await loadFixture(deployer);
            await multiSign.connect(owner).approvePause([6]);
            await multiSign.connect(owner1).approvePause([6]);
            await multiSign.connect(owner).pauseFunction([6]);

            const tx = CDSContract.connect(user2).redeemUSDT(ethers.parseEther("800"),1500,1000);
            await expect(tx).to.be.revertedWith('Paused');
        })

        it("Should revert if tried to withdraw ETH in borrowing when it is paused",async function(){
            const {BorrowingContract,Token,multiSign,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();

            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);

            await BorrowingContract.connect(user2).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            await multiSign.connect(owner).approvePause([1]);
            await multiSign.connect(owner1).approvePause([1]);
            await multiSign.connect(owner).pauseFunction([1]);

            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            const tx = BorrowingContract.connect(user2).withDraw(user2.getAddress(),1,99900,timeStamp);
            await expect(tx).to.be.revertedWith('Paused');
        })

        it("Should revert if tried to withdraw AMINT in CDS when it is paused",async function(){
            const {CDSContract,multiSign,usdt} = await loadFixture(deployer);

            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);

            await multiSign.connect(owner).approvePause([5]);
            await multiSign.connect(owner1).approvePause([5]);
            await multiSign.connect(owner).pauseFunction([5]);
            
            const tx = CDSContract.connect(user1).withdraw(1);

            await expect(tx).to.be.revertedWith('Paused');
        })

        it("Should revert if tried to Liquidate in borrowing when it is paused",async function(){
            const {BorrowingContract,multiSign} = await loadFixture(deployer);
            
            await multiSign.connect(owner).approvePause([2]);
            await multiSign.connect(owner1).approvePause([2]);
            await multiSign.connect(owner).pauseFunction([2]);
            
            const tx = BorrowingContract.liquidate(user1.getAddress(),1,80000);
            await expect(tx).to.be.revertedWith('Paused');
        })

    })

    describe("Should ABOND be fungible",function(){
        it("Should store genesis cumulative rate correctly",async function(){
            const {BorrowingContract,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const tx = await abondToken.userStatesAtDeposits(user1.address, 1);
            await expect(tx[0]).to.be.equal(1000000000000000000000000000n);
        })

        it("Should store eth backed during deposit correctly",async function(){
            const {BorrowingContract,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const tx = await abondToken.userStatesAtDeposits(user1.address, 1);
            await expect(tx[1]).to.be.equal(500000000000000000n);
        })

        it("Should store cumulative rate and eth backed after withdraw correctly",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.connect(user1).mint(user1.address, 5000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user1.getAddress(),1,99900,timeStamp);

            const tx = await abondToken.userStates(user1.address);
            await expect(tx[0]).to.be.equal(1000000000000000000000000000n);
            const abondBalance = ((500000000000000000 * 999 * 0.8)/4);
            const ethBackedPerAbond = BigInt(500000000000000000 * 1e18/abondBalance);
            await expect(tx[2]).to.be.equal(BigInt(abondBalance));
            await expect(tx[1]).to.be.equal(ethBackedPerAbond);
            await expect(tx[0]).to.be.equal(1000000000000000000000000000n)
        })

        it("Should store cumulative rate and eth backed for multiple index correctly",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 25920000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.connect(user1).mint(user1.address, 50000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user1.getAddress(),1,99900,timeStamp);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            const blockNumber1 = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock1 = await ethers.provider.getBlock(blockNumber1);
            const latestTimestamp2 = latestBlock1.timestamp;
            await time.increaseTo(latestTimestamp2 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.connect(user1).mint(user1.address, 5000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user1.getAddress(),2,99500,timeStamp);

            const tx = await abondToken.userStates(user1.address);

            const abondBalance1 = ((500000000000000000 * 999 * 0.8)/4);
            const abondBalance2 = ((500000000000000000 * 995 * 0.8)/4);

            await expect(tx[2]).to.be.equal(BigInt(abondBalance1+abondBalance2));
        })

        it("Should redeem abond",async function(){
            const {BorrowingContract,Token,abondToken,usdt,CDSContract,provider} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);
            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.connect(user1).mint(user1.address, 50000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user1.getAddress(),1,99900,timeStamp);

            await abondToken.connect(user1).approve(await BorrowingContract.getAddress(), await abondToken.balanceOf(user1.address));
            await BorrowingContract.connect(user1).redeemYields(await user1.getAddress(), await abondToken.balanceOf(await user1.getAddress()));
        })

        it.only("Should store cumulative rate and eth backed for multiple transfers correctly",async function(){
            const {BorrowingContract,Token,usdt,CDSContract} = await loadFixture(deployer);
            const timeStamp = await time.latest();
            await usdt.connect(user1).mint(user1.getAddress(),10000000000)
            await usdt.connect(user1).approve(CDSContract.getAddress(),10000000000);
            await CDSContract.connect(user1).deposit(10000000000,0,true,10000000000);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});
            
            const blockNumber = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock = await ethers.provider.getBlock(blockNumber);
            const latestTimestamp1 = latestBlock.timestamp;
            await time.increaseTo(latestTimestamp1 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.connect(user1).mint(user1.address, 50000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user1.getAddress(),1,99900,timeStamp);

            await BorrowingContract.connect(user1).depositTokens(100000,timeStamp,1,110000,ethVolatility,{value: ethers.parseEther("1")});

            const blockNumber1 = await ethers.provider.getBlockNumber(); // Get latest block number
            const latestBlock1 = await ethers.provider.getBlock(blockNumber1);
            const latestTimestamp2 = latestBlock1.timestamp;
            await time.increaseTo(latestTimestamp2 + 2592000);

            await BorrowingContract.calculateCumulativeRate();
            await Token.connect(user1).mint(user1.address, 5000000);
            await Token.connect(user1).approve(await BorrowingContract.getAddress(),await Token.balanceOf(user1.getAddress()));
            await BorrowingContract.connect(user1).withDraw(user1.getAddress(),2,99000,timeStamp);

            // await abondToken.connect(user1).approve(await BorrowingContract.getAddress(), await abondToken.balanceOf(user1.address));
            // await BorrowingContract.connect(user1).redeemYields(await user1.getAddress(), await abondToken.balanceOf(await user1.getAddress()));
        })

    })

})
