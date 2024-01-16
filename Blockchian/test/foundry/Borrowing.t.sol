// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TrinityStablecoin} from "../../contracts/Token/Trinity_ERC20.sol";
import {ProtocolToken} from "../../contracts/Token/Protocol_Token.sol";
import {USDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "../../scripts/script/HelperConfig.s.sol";
import {DeployBorrowing} from "../../scripts/script/DeployBorrowing.s.sol";

import {IWrappedTokenGatewayV3} from "../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
import {IPoolAddressesProvider} from "../../contracts/interface/AaveInterfaces/IPoolAddressesProvider.sol";
import {IPool} from "../../contracts/interface/AaveInterfaces/IPool.sol";

import {ICEther} from "../../contracts/interface/ICEther.sol";
import {IOptions} from "../../contracts/interface/IOptions.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract BorrowTest is Test {
    DeployBorrowing deployer;
    TrinityStablecoin tsc;
    ProtocolToken pToken;
    USDT usdt;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    Options option;
    HelperConfig config;

    address ethUsdPriceFeed;
    address wethAddress = 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
    address cEthAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    IWrappedTokenGatewayV3 wethGateway;
    ICEther cEther;
    // IPoolAddressesProvider public aaveProvider;
    // IPool public aave;
    address public USER = makeAddr("user");
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    uint256 public ETH_AMOUNT = 1 ether;
    uint256 public STARTING_ETH_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployBorrowing();
        (tsc,pToken,usdt,borrow,treasury,cds,config) = deployer.run();
        (ethUsdPriceFeed,) = config.activeNetworkConfig();

        wethGateway = IWrappedTokenGatewayV3(wethAddress);
        cEther = ICEther(cEthAddress);
        vm.startPrank(owner);
        borrow.initializeTreasury(address(treasury));
        borrow.setLTV(80);
        vm.stopPrank();

        vm.deal(USER,STARTING_ETH_BALANCE);
        vm.deal(owner,STARTING_ETH_BALANCE);
    }

    modifier depositInCds {
        vm.startPrank(USER);
        usdt.mint(address(USER),30000000000);
        uint256 usdtBalance = usdt.balanceOf(address(USER));
        usdt.approve(address(cds),usdtBalance);
        cds.deposit(uint128(usdtBalance),0,true,uint128(usdtBalance/2));
        vm.stopPrank();
        _;
    }

    modifier depositETH {
        vm.startPrank(USER);
        usdt.mint(address(USER),20000000000);
        uint256 usdtBalance = usdt.balanceOf(address(USER));
        usdt.approve(address(cds),usdtBalance);
        cds.deposit(uint128(usdtBalance),0,true,uint128(usdtBalance/2));
        borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        vm.stopPrank();
        _;
    }

    function testGetUsdValue() public {
        uint256 expectedUsd = 1000e2;
        uint256 actualUsd = borrow.getUSDValue();
        assertEq(expectedUsd, actualUsd);
    }

    function testCanDepositEth() public depositInCds{
        vm.startPrank(USER);
        borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        uint256 expectedAmount = 800 ether;
        uint256 actualAmount = tsc.balanceOf(USER); 
        assertEq(expectedAmount,actualAmount);
        vm.stopPrank();
    }

    function testCanDepositEthToAave() public depositETH{
        vm.startPrank(owner);
        borrow.depositToAaveProtocol();
        console.log("ATOKEN BALANCE",IERC20(aTokenAddress).balanceOf(address(treasury)));
        vm.warp(block.timestamp + 360000000);
        console.log("ATOKEN BALANCE",IERC20(aTokenAddress).balanceOf(address(treasury)));
        vm.stopPrank();
    }

    function testCanWithdrawEthFromAave() public depositETH{
        vm.startPrank(owner);
        borrow.depositToAaveProtocol();
        uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(address(treasury));
        console.log("ATOKEN BALANCE AFTER DEPSOIT",aTokenBalance);
        console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
        vm.warp(block.timestamp + 360000000);

        borrow.withdrawFromAaveProtocol(1);
        console.log("ATOKEN BALANCE AFTER WITHDRAW",IERC20(aTokenAddress).balanceOf(address(treasury)));
        console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
        vm.stopPrank();
    }

    function testCanDepositEthToCompound() public depositETH{
        vm.startPrank(owner);
        borrow.depositToCompoundProtocol();
        console.log("ETH SUPPLIED TO COMPOUND",cEther.balanceOfUnderlying(address(treasury)));
        console.log("CTOKEN BALANCE",cEther.balanceOf(address(treasury)));
        vm.stopPrank();
    }

    function testCanWithdrawEthFromCompound() public depositETH{
        vm.startPrank(owner);
        borrow.depositToCompoundProtocol();
        console.log("ETH SUPPLIED TO COMPOUND",cEther.balanceOfUnderlying(address(treasury)));
        console.log("CTOKEN BALANCE AFTER DEPOSIT",cEther.balanceOf(address(treasury)));
        console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
        vm.roll(block.number + 100);
        console.log("ETH SUPPLIED TO COMPOUND SKIP",cEther.balanceOfUnderlying(address(treasury)));

        borrow.withdrawFromCompoundProtocol(1);
        console.log("ETH SUPPLIED TO COMPOUND AFTER WITHDRAW",cEther.balanceOfUnderlying(address(treasury)));
        console.log("CTOKEN BALANCE AFTER WITHDRAW",cEther.balanceOf(address(treasury)));
        console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
        vm.stopPrank();
    }

    function testCanCalculateInterestInCompoundCorrectly() public depositETH{
        vm.startPrank(owner);
        uint256 treasuryBalance = treasury.getBalanceInTreasury();
        borrow.depositToCompoundProtocol();
        vm.roll(block.number + 100);

        uint256 interestFromCompound = treasury.getInterestForCompoundDeposit(1);
        borrow.withdrawFromCompoundProtocol(1);
        uint256 expectedInterestFromCompound = treasury.getBalanceInTreasury() - treasuryBalance;
        assertEq(expectedInterestFromCompound,interestFromCompound);
        vm.stopPrank();
    }

    function testCanCalculateInterestInAaveCorrectly() public depositETH{
        vm.startPrank(owner);
        uint256 interest;
        uint256 treasuryBalance = 7 ether;
        borrow.depositTokens{value: 2 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();

        vm.warp(block.timestamp + 2592000);
        borrow.depositTokens{value: 4 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();

        vm.warp(block.timestamp + 2592000);
        interest += treasury.calculateInterestForDepositAave(2);
        borrow.withdrawFromAaveProtocol(2);

        vm.warp(block.timestamp + 2591999);
        interest += treasury.calculateInterestForDepositAave(1);
        borrow.withdrawFromAaveProtocol(1);

        uint256 expectedInterest = treasury.getBalanceInTreasury() - treasuryBalance;
        console.log(expectedInterest);
        console.log(interest);
        assertEq(expectedInterest,interest);
        vm.stopPrank();    
    }

    function testTotalInterestFromExternalProtocol() public depositETH{
        vm.startPrank(owner);
        uint256 interest;
        uint256 treasuryBalance = 52 ether;
        borrow.depositTokens{value: 2 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        borrow.depositTokens{value: 4 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();


        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);


        borrow.depositTokens{value: 6 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        interest += treasury.calculateInterestForDepositAave(1);
        interest += treasury.getInterestForCompoundDeposit(1);

        borrow.withdrawFromAaveProtocol(1);
        borrow.withdrawFromCompoundProtocol(1);


        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);
        borrow.depositTokens{value: 6 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();


        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);
        borrow.depositTokens{value: 8 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        interest += treasury.calculateInterestForDepositAave(3);
        interest += treasury.getInterestForCompoundDeposit(3);

        borrow.withdrawFromAaveProtocol(3);
        borrow.withdrawFromCompoundProtocol(3);

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        interest += treasury.calculateInterestForDepositAave(2);
        interest += treasury.getInterestForCompoundDeposit(2);

        borrow.withdrawFromAaveProtocol(2);
        borrow.withdrawFromCompoundProtocol(2);

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);
        borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);
        borrow.depositTokens{value: 7 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

        interest += treasury.calculateInterestForDepositAave(4);
        interest += treasury.getInterestForCompoundDeposit(4);

        borrow.withdrawFromAaveProtocol(4);
        borrow.withdrawFromCompoundProtocol(4);

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        interest += treasury.calculateInterestForDepositAave(5);
        interest += treasury.getInterestForCompoundDeposit(5);

        borrow.withdrawFromAaveProtocol(5);
        borrow.withdrawFromCompoundProtocol(5);

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);
        borrow.depositTokens{value: 15 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,11000,506226650);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        interest += treasury.calculateInterestForDepositAave(8);
        interest += treasury.getInterestForCompoundDeposit(8);

        borrow.withdrawFromAaveProtocol(8);
        borrow.withdrawFromCompoundProtocol(8);


        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        interest += treasury.calculateInterestForDepositAave(7);
        interest += treasury.getInterestForCompoundDeposit(7);

        borrow.withdrawFromAaveProtocol(7);
        borrow.withdrawFromCompoundProtocol(7);

        vm.warp(block.timestamp + 2);
        vm.roll(block.number + 1);

        interest += treasury.calculateInterestForDepositAave(6);
        interest += treasury.getInterestForCompoundDeposit(6);

        borrow.withdrawFromAaveProtocol(6);
        borrow.withdrawFromCompoundProtocol(6);

        // uint256 interestOwner;
        // for(uint64 i=1; i<=8; i++){
        //     interestOwner += treasury.totalInterestFromExternalProtocol(owner,i);
        // }

        // uint256 interestUser = treasury.totalInterestFromExternalProtocol(address(USER),1);


        uint256 expectedInterest = treasury.getBalanceInTreasury() - treasuryBalance;
        //uint256 interestByUser = interestOwner + interestUser;

        assertEq(expectedInterest,interest);
        //assertEq(expectedInterest,interestByUser);
        vm.stopPrank();
    }

    function testTotalInterestFromExternalProtocolSimple() public depositETH{
        vm.startPrank(owner);
        uint256 interest;
        uint256 treasuryBalance = 6 ether;
        borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        interest += treasury.calculateInterestForDepositAave(1);
        interest += treasury.getInterestForCompoundDeposit(1);

        borrow.withdrawFromAaveProtocol(1);
        borrow.withdrawFromCompoundProtocol(1);

        borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        borrow.depositToAaveProtocol();
        borrow.depositToCompoundProtocol();

        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 100);

        interest += treasury.calculateInterestForDepositAave(2);
        interest += treasury.getInterestForCompoundDeposit(2);

        borrow.withdrawFromAaveProtocol(2);
        borrow.withdrawFromCompoundProtocol(2);
        uint256 interestUser = treasury.totalInterestFromExternalProtocol(address(USER),1);
        uint256 interestOwner;
        for(uint64 i=1; i < 3; i++){
            interestOwner += treasury.totalInterestFromExternalProtocol(owner,i);
        }




        uint256 expectedInterest = treasury.getBalanceInTreasury() - treasuryBalance;
        uint256 interestByUser = interestOwner + interestUser;

        //assertEq(expectedInterest,interest);
        assertEq(expectedInterest,interestByUser);
        vm.stopPrank();
    }

    function testUserCantWithdrawDirectlyFromAave() public depositETH{
        vm.startPrank(USER);
        console.log("USER BALANCE AFTER DEPOSIT",USER.balance);
        vm.warp(block.timestamp + 360000000);

        uint256 balance = IERC20(aTokenAddress).balanceOf(address(USER));
        address poolAddress = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e).getPool();

        IERC20(aTokenAddress).approve(address(wethGateway),balance);
        wethGateway.withdrawETH(poolAddress,balance,address(USER));

        console.log("USER BALANCE AFTER AAVE WITHDRAW",USER.balance);
        vm.stopPrank();
    }

    function testUserCantWithdrawDirectlyFromCompound() public depositETH{
        vm.startPrank(USER);
        vm.roll(block.number + 100);
        console.log("USER BALANCE AFTER DEPOSIT",USER.balance);
        console.log("TREASURY BALANCE AFTER DEPOSIT",treasury.getBalanceInTreasury());

        uint256 balance = cEther.balanceOf(address(treasury));
        console.log(balance);
        //treasury.compoundWithdraw(balance);

        cEther.redeem(balance);
        console.log("USER BALANCE AFTER COMPOUND WITHDRAW",USER.balance);
        console.log("TREASURY BALANCE AFTER COMPOUND WITHDRAW",treasury.getBalanceInTreasury());
        console.log(cEther.balanceOfUnderlying(address(USER)));
        vm.stopPrank();
    }
}
