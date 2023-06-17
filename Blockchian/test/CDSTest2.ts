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

    describe("To check CDS withdrawl function",function(){
        it("Should withdraw from cds",async () => {
            await BorrowingContract.setLTV(100);
            //console.log(await Token.balanceOf(user1.address))
            await Token.mint(owner.address,1000000000000000);
            await Token.mint(user1.address,1000000000000000);
            await Token.connect(user1).approve(CDSContract.address,1000000000000000);
            await Token.approve(CDSContract.address,1000000000000000);
            
            const timestamp = await time.latest();
            
            await  CDSContract.deposit(400,timestamp);
            await  CDSContract.connect(user1).deposit(600,timestamp);
            await BorrowingContract.connect(user2).depositTokens(100,timestamp,20,0,{value: ethers.utils.parseEther("0.000000000000002000")});
            
            var CDStotalBal:any = await CDSContract.totalCdsDepositedAmount();

            await CDSContract.setWithdrawTimeLimit(1);
           
            await CDSContract.connect(user1).withdraw(user1.address,1,timestamp);

            expect(await CDSContract.totalCdsDepositedAmount()).to.be.equal( (CDStotalBal - 360));

            

        })
    })

})