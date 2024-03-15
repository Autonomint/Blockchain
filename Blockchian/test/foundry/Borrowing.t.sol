// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {BorrowingTest} from "../../contracts/TestContracts/CopyBorrowing.sol";
import {Treasury} from "../../contracts/Core_logic/Treasury.sol";
import {Options} from "../../contracts/Core_logic/Options.sol";
import {MultiSign} from "../../contracts/Core_logic/multiSign.sol";
import {CDSTest} from "../../contracts/TestContracts/CopyCDS.sol";
import {TestAMINTStablecoin} from "../../contracts/TestContracts/CopyAmint.sol";
import {TestABONDToken} from "../../contracts/TestContracts/Copy_Abond_Token.sol";
import {TestUSDT} from "../../contracts/TestContracts/CopyUsdt.sol";
import {HelperConfig} from "../../scripts/script/HelperConfig.s.sol";
import {DeployBorrowing} from "../../scripts/script/DeployBorrowing.s.sol";

import {IWrappedTokenGatewayV3} from "../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
import {IPoolAddressesProvider} from "../../contracts/interface/AaveInterfaces/IPoolAddressesProvider.sol";
import {ILendingPoolAddressesProvider} from "../../contracts/interface/AaveInterfaces/ILendingPoolAddressesProvider.sol";
import {IPool} from "../../contracts/interface/AaveInterfaces/IPool.sol";
import {State} from "../../contracts/interface/IAbond.sol";

import {CometMainInterface} from "../../contracts/interface/CometMainInterface.sol";
import {IOptions} from "../../contracts/interface/IOptions.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract BorrowTest is Test {
    DeployBorrowing deployer;
    TestAMINTStablecoin amint;
    TestABONDToken abond;
    TestUSDT usdt;
    CDSTest cds;
    BorrowingTest borrow;
    Treasury treasury;
    Options option;
    MultiSign multiSign;
    HelperConfig config;

    address ethUsdPriceFeed;

    // IPoolAddressesProvider public aaveProvider;
    // IPool public aave;
    address public USER = makeAddr("user");
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public owner1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address public cometAddress = 0xA17581A9E3356d9A858b789D68B4d866e593aE94; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    uint8[] functions = [0,1,2,3,4,5,6,7,8,9,10];

    uint256 public ETH_AMOUNT = 1 ether;
    uint256 public STARTING_ETH_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployBorrowing();
        (DeployBorrowing.Contracts memory contracts) = deployer.run();
        amint = contracts.amint;
        abond = contracts.abond;
        usdt = contracts.usdt;
        borrow = contracts.borrow;
        treasury = contracts.treasury;
        cds = contracts.cds;
        multiSign = contracts.multiSign;
        option = contracts.option;
        config = contracts.config;
        (ethUsdPriceFeed,) = config.activeNetworkConfig();

        vm.startPrank(owner1);
        multiSign.approveSetterFunction(functions);
        vm.stopPrank();

        vm.startPrank(owner);
        abond.setBorrowingContract(address(borrow));
        borrow.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        borrow.setTreasury(address(treasury));
        borrow.setOptions(address(option));
        borrow.setLTV(80);
        borrow.setBondRatio(4);
        borrow.setAPR(1000000001547125957863212449);

        cds.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        cds.setTreasury(address(treasury));
        cds.setBorrowingContract(address(borrow));
        cds.setAmintLimit(80);
        cds.setUsdtLimit(20000000000);
        borrow.calculateCumulativeRate();
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

    // function testCanDepositEth() public depositInCds{
    //     vm.startPrank(USER);
    //     borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     uint256 expectedAmount = ((800*1e6) - option.calculateOptionPrice(100000,50622665,ETH_AMOUNT,Options.StrikePrice.TEN));
    //     uint256 actualAmount = amint.balanceOf(USER); 
    //     assertEq(expectedAmount,actualAmount);
    //     vm.stopPrank();
    // }

    // function testCanDepositEthToAave() public depositETH{
    //     vm.startPrank(owner);
    //     borrow.depositToAaveProtocol();
    //     console.log("ATOKEN BALANCE",IERC20(aTokenAddress).balanceOf(address(treasury)));
    //     vm.warp(block.timestamp + 360000000);
    //     console.log("ATOKEN BALANCE",IERC20(aTokenAddress).balanceOf(address(treasury)));
    //     vm.stopPrank();
    // }

    // function testCanWithdrawEthFromAave() public depositETH{
    //     vm.startPrank(owner);
    //     borrow.depositToAaveProtocol();
    //     uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(address(treasury));
    //     console.log("ATOKEN BALANCE AFTER DEPSOIT",aTokenBalance);
    //     console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
    //     vm.warp(block.timestamp + 360000000);

    //     borrow.withdrawFromAaveProtocol(1);
    //     console.log("ATOKEN BALANCE AFTER WITHDRAW",IERC20(aTokenAddress).balanceOf(address(treasury)));
    //     console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
    //     vm.stopPrank();
    // }

    // function testCanDepositEthToCompound() public depositETH{
    //     vm.startPrank(owner);
    //     borrow.depositToCompoundProtocol();
    //     console.log("ETH SUPPLIED TO COMPOUND",cEther.balanceOfUnderlying(address(treasury)));
    //     console.log("CTOKEN BALANCE",cEther.balanceOf(address(treasury)));
    //     vm.stopPrank();
    // }

    // function testCanWithdrawEthFromCompound() public depositETH{
    //     vm.startPrank(owner);
    //     borrow.depositToCompoundProtocol();
    //     console.log("ETH SUPPLIED TO COMPOUND",cEther.balanceOfUnderlying(address(treasury)));
    //     console.log("CTOKEN BALANCE AFTER DEPOSIT",cEther.balanceOf(address(treasury)));
    //     console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
    //     vm.roll(block.number + 100);
    //     console.log("ETH SUPPLIED TO COMPOUND SKIP",cEther.balanceOfUnderlying(address(treasury)));

    //     borrow.withdrawFromCompoundProtocol(1);
    //     console.log("ETH SUPPLIED TO COMPOUND AFTER WITHDRAW",cEther.balanceOfUnderlying(address(treasury)));
    //     console.log("CTOKEN BALANCE AFTER WITHDRAW",cEther.balanceOf(address(treasury)));
    //     console.log("TREASURY BALANCE",treasury.getBalanceInTreasury());
    //     vm.stopPrank();
    // }

    // function testCanCalculateInterestInCompoundCorrectly() public depositETH{
    //     vm.startPrank(owner);
    //     uint256 treasuryBalance = treasury.getBalanceInTreasury();
    //     borrow.depositToCompoundProtocol();
    //     vm.roll(block.number + 100);

    //     uint256 interestFromCompound = treasury.getInterestForCompoundDeposit(address(owner),1);
    //     borrow.withdrawFromCompoundProtocol(1);
    //     uint256 expectedInterestFromCompound = treasury.getBalanceInTreasury() - treasuryBalance;
    //     assertEq(expectedInterestFromCompound,interestFromCompound);
    //     vm.stopPrank();
    // }

    // function testCanCalculateInterestInAaveCorrectly() public depositETH{
    //     vm.startPrank(owner);
    //     uint256 interest;
    //     uint256 treasuryBalance = 7 ether;
    //     borrow.depositTokens{value: 2 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     borrow.depositTokens{value: 4 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     interest += treasury.calculateInterestForDepositAave(2);
    //     borrow.withdrawFromAaveProtocol(2);

    //     vm.warp(block.timestamp + 2591999);
    //     interest += treasury.calculateInterestForDepositAave(1);
    //     borrow.withdrawFromAaveProtocol(1);

    //     uint256 expectedInterest = treasury.getBalanceInTreasury() - treasuryBalance;
    //     console.log(expectedInterest);
    //     console.log(interest);
    //     assertEq(expectedInterest,interest);
    //     vm.stopPrank();    
    // }

    // function testTotalInterestFromExternalProtocol() public depositETH{
    //     vm.startPrank(owner);
    //     uint256 interest;
    //     uint256 treasuryBalance = 52 ether;
    //     borrow.depositTokens{value: 2 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     borrow.depositTokens{value: 4 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();


    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);


    //     borrow.depositTokens{value: 6 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     interest += treasury.calculateInterestForDepositAave(1);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),1);

    //     borrow.withdrawFromAaveProtocol(1);
    //     borrow.withdrawFromCompoundProtocol(1);


    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);
    //     borrow.depositTokens{value: 6 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();


    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);
    //     borrow.depositTokens{value: 8 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     interest += treasury.calculateInterestForDepositAave(3);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),3);

    //     borrow.withdrawFromAaveProtocol(3);
    //     borrow.withdrawFromCompoundProtocol(3);

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     interest += treasury.calculateInterestForDepositAave(2);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),2);

    //     borrow.withdrawFromAaveProtocol(2);
    //     borrow.withdrawFromCompoundProtocol(2);

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);
    //     borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);
    //     borrow.depositTokens{value: 7 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

    //     interest += treasury.calculateInterestForDepositAave(4);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),4);

    //     borrow.withdrawFromAaveProtocol(4);
    //     borrow.withdrawFromCompoundProtocol(4);

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     interest += treasury.calculateInterestForDepositAave(5);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),5);

    //     borrow.withdrawFromAaveProtocol(5);
    //     borrow.withdrawFromCompoundProtocol(5);

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);
    //     borrow.depositTokens{value: 15 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,11000,506226650);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 1);
    //     vm.roll(block.number + 1);

    //     interest += treasury.calculateInterestForDepositAave(8);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),8);

    //     borrow.withdrawFromAaveProtocol(8);
    //     borrow.withdrawFromCompoundProtocol(8);


    //     vm.warp(block.timestamp + 1);
    //     vm.roll(block.number + 1);

    //     interest += treasury.calculateInterestForDepositAave(7);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),7);

    //     borrow.withdrawFromAaveProtocol(7);
    //     borrow.withdrawFromCompoundProtocol(7);

    //     vm.warp(block.timestamp + 2);
    //     vm.roll(block.number + 1);

    //     interest += treasury.calculateInterestForDepositAave(6);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),6);

    //     borrow.withdrawFromAaveProtocol(6);
    //     borrow.withdrawFromCompoundProtocol(6);

    //     // uint256 interestOwner;
    //     // for(uint64 i=1; i<=8; i++){
    //     //     interestOwner += treasury.totalInterestFromExternalProtocol(owner,i);
    //     // }

    //     // uint256 interestUser = treasury.totalInterestFromExternalProtocol(address(USER),1);


    //     uint256 expectedInterest = treasury.getBalanceInTreasury() - treasuryBalance;
    //     //uint256 interestByUser = interestOwner + interestUser;

    //     assertEq(expectedInterest,interest);
    //     //assertEq(expectedInterest,interestByUser);
    //     vm.stopPrank();
    // }

    // function testTotalInterestFromExternalProtocolSimple() public depositETH{
    //     vm.startPrank(owner);
    //     uint256 interest;
    //     uint256 treasuryBalance = 6 ether;
    //     borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     interest += treasury.calculateInterestForDepositAave(1);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),1);

    //     borrow.withdrawFromAaveProtocol(1);
    //     borrow.withdrawFromCompoundProtocol(1);

    //     borrow.depositTokens{value: 3 ether}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
    //     borrow.depositToAaveProtocol();
    //     borrow.depositToCompoundProtocol();

    //     vm.warp(block.timestamp + 2592000);
    //     vm.roll(block.number + 100);

    //     interest += treasury.calculateInterestForDepositAave(2);
    //     interest += treasury.getInterestForCompoundDeposit(address(owner),2);

    //     borrow.withdrawFromAaveProtocol(2);
    //     borrow.withdrawFromCompoundProtocol(2);
    //     uint256 interestUser = treasury.totalInterestFromExternalProtocol(address(USER),1);
    //     uint256 interestOwner;
    //     for(uint64 i=1; i < 3; i++){
    //         interestOwner += treasury.totalInterestFromExternalProtocol(owner,i);
    //     }




    //     uint256 expectedInterest = treasury.getBalanceInTreasury() - treasuryBalance;
    //     uint256 interestByUser = interestOwner + interestUser;

    //     //assertEq(expectedInterest,interest);
    //     assertEq(expectedInterest,interestByUser);
    //     vm.stopPrank();
    // }

    // function testUserCantWithdrawDirectlyFromAave() public depositETH{
    //     vm.startPrank(USER);
    //     console.log("USER BALANCE AFTER DEPOSIT",USER.balance);
    //     vm.warp(block.timestamp + 360000000);

    //     uint256 balance = IERC20(aTokenAddress).balanceOf(address(USER));
    //     address poolAddress = ILendingPoolAddressesProvider(0x5E52dEc931FFb32f609681B8438A51c675cc232d/*0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e*/).getLendingPool();

    //     IERC20(aTokenAddress).approve(address(wethGateway),balance);
    //     wethGateway.withdrawETH(poolAddress,balance,address(USER));

    //     console.log("USER BALANCE AFTER AAVE WITHDRAW",USER.balance);
    //     vm.stopPrank();
    // }

    // function testUserCantWithdrawDirectlyFromCompound() public depositETH{
    //     vm.startPrank(USER);
    //     vm.roll(block.number + 100);
    //     console.log("USER BALANCE AFTER DEPOSIT",USER.balance);
    //     console.log("TREASURY BALANCE AFTER DEPOSIT",treasury.getBalanceInTreasury());

    //     uint256 balance = cEther.balanceOf(address(treasury));
    //     console.log(balance);
    //     //treasury.compoundWithdraw(balance);

    //     cEther.redeem(balance);
    //     console.log("USER BALANCE AFTER COMPOUND WITHDRAW",USER.balance);
    //     console.log("TREASURY BALANCE AFTER COMPOUND WITHDRAW",treasury.getBalanceInTreasury());
    //     console.log(cEther.balanceOfUnderlying(address(USER)));
    //     vm.stopPrank();
    // }

    function testUserCanDepositAndWithdraw() public depositETH{
        vm.startPrank(USER);
        vm.warp(block.timestamp + 2592000);
        vm.roll(block.number + 216000);

        borrow.calculateCumulativeRate();

        amint.mint(address(USER),10000000);
        uint256 amintBalance = amint.balanceOf(address(USER));

        amint.approve(address(borrow),amintBalance);
        borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));

        assertEq(address(USER).balance, STARTING_ETH_BALANCE - 5e17);

        vm.stopPrank();
    }

    function testUserCanRedeemAbond() public depositETH{
        vm.startPrank(USER);

        vm.warp(block.timestamp + 2592000);

        borrow.calculateCumulativeRate();

        amint.mint(address(USER),10000000);
        uint256 amintBalance = amint.balanceOf(address(USER));

        amint.approve(address(borrow),amintBalance);
        borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));

        borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

        vm.warp(block.timestamp + 2592000);

        borrow.calculateCumulativeRate();

        amint.mint(address(USER),10000000);

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),2,99900,uint64(block.timestamp));

        uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(address(treasury));
        uint256 cETHbalance = CometMainInterface(cometAddress).balanceOf(address(treasury));

        uint256 abondBalance = abond.balanceOf(address(USER));
        abond.approve(address(borrow), abondBalance);
        uint256 withdrawAmount = borrow.redeemYields(address(USER),uint128(abondBalance));

        assert((aTokenBalance + cETHbalance - withdrawAmount) <= 1e14);

        vm.stopPrank();
    }

    function testAbondDataAreStoringCorrectlyForMultipleIndex() public depositETH{
        vm.startPrank(USER);

        vm.warp(block.timestamp + 2592000);
        borrow.calculateCumulativeRate();

        amint.mint(address(USER),10000000000);

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));

        (uint256 cR1,uint128 ethBacked1,uint128 aBondAmount1) = abond.userStates(address(USER));

        borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);

        (uint256 cR2,uint128 ethBacked2,) = abond.userStatesAtDeposits(address(USER),2);

        vm.warp(block.timestamp + 2592000);
        borrow.calculateCumulativeRate();

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),2,99000,uint64(block.timestamp));

        (uint256 cR3,uint128 ethBacked3,uint128 aBondAmount3) = abond.userStates(address(USER));

        assertEq(((aBondAmount1 * cR1) + ((aBondAmount3 - aBondAmount1) * cR2))/aBondAmount3,cR3);
        assertEq(((aBondAmount1 * ethBacked1) + ((aBondAmount3 - aBondAmount1) * ((ethBacked2 * 1e18)/(aBondAmount3 - aBondAmount1))))/aBondAmount3,ethBacked3);

        vm.stopPrank();
    }

    function testAbondDataAreStoringCorrectlyForOneTransfer() public depositETH{
        vm.startPrank(USER);
        (uint256 cR1d,uint128 ethBacked1d,uint128 abondBalance1d) = abond.userStatesAtDeposits(address(USER),1);

        vm.warp(block.timestamp + 2592000);
        borrow.calculateCumulativeRate();

        amint.mint(address(USER),10000000);

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));
        (uint256 cR1w,uint128 ethBacked1w,uint128 abondBalance1w) = abond.userStates(address(USER));

        borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        (uint256 cR2d,uint128 ethBacked2d,uint128 abondBalance2d) = abond.userStatesAtDeposits(address(USER),2);

        vm.warp(block.timestamp + 2592000);
        borrow.calculateCumulativeRate();

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),2,99000,uint64(block.timestamp));
        (uint256 cR2w,uint128 ethBacked2w,uint128 abondBalance2w) = abond.userStates(address(USER));

        abond.transfer(owner,(abond.balanceOf(address(USER)) * 50)/100);

        (uint256 cR1,uint128 ethBacked1,uint128 aBondAmount1) = abond.userStates(address(USER));
        (uint256 cR2,uint128 ethBacked2,uint128 aBondAmount2) = abond.userStates(owner);

        assertEq(cR2,cR1);
        assertEq(aBondAmount1,aBondAmount2);
        assertEq(ethBacked1,ethBacked2);

        vm.stopPrank();
    }

    function testAbondDataAreStoringCorrectlyForMultipleTransfers() public depositETH{
        vm.startPrank(USER);
        (uint256 cR1d,uint128 ethBacked1d,uint128 abondBalance1d) = abond.userStatesAtDeposits(address(USER),1);

        vm.warp(block.timestamp + 2592000);
        borrow.calculateCumulativeRate();

        amint.mint(address(USER),10000000);

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),1,99900,uint64(block.timestamp));
        (uint256 cR1w,uint128 ethBacked1w,uint128 abondBalance1w) = abond.userStates(address(USER));

        borrow.depositTokens{value: ETH_AMOUNT}(100000,uint64(block.timestamp),IOptions.StrikePrice.TEN,110000,50622665);
        (uint256 cR2d,uint128 ethBacked2d,uint128 abondBalance2d) = abond.userStatesAtDeposits(address(USER),2);

        vm.warp(block.timestamp + 2592000);
        borrow.calculateCumulativeRate();

        amint.approve(address(borrow),amint.balanceOf(address(USER)));
        borrow.withDraw(address(USER),2,100000,uint64(block.timestamp));
        (uint256 cR2w,uint128 ethBacked2w,uint128 abondBalance2w) = abond.userStates(address(USER));

        // console.log("CR 1D",cR1d);
        // console.log("EB 1D",ethBacked1d);
        // console.log("AB 1D",abondBalance1d);

        // console.log("CR 1W",cR1w);
        // console.log("EB 1W",ethBacked1w);
        // console.log("AB 1W",abondBalance1w);

        // console.log("CR 2D",cR2d);
        // console.log("EB 2D",ethBacked2d);
        // console.log("AB 2D",abondBalance2d);

        // console.log("CR 2W",cR2w);
        // console.log("EB 2W",ethBacked2w);
        // console.log("AB 2W",abondBalance2w);

        abond.transfer(owner,(abond.balanceOf(address(USER)) * 50)/100);
        vm.warp(block.timestamp + 2592000);

        (uint256 cR1,uint128 ethBacked1,uint128 aBondAmount1) = abond.userStates(address(USER));
        (uint256 cR2,uint128 ethBacked2,uint128 aBondAmount2) = abond.userStates(owner);

        // console.log("CR o",cR2);
        // console.log("EB o",ethBacked2);
        // console.log("AB o",aBondAmount2);

        uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(address(treasury));
        uint256 cETHbalance = CometMainInterface(cometAddress).balanceOf(address(treasury));

        abond.approve(address(borrow), aBondAmount1);
        uint256 withdrawAmount1 = borrow.redeemYields(address(USER),uint128(aBondAmount1));
        vm.stopPrank();

        vm.startPrank(owner);
        abond.approve(address(borrow), aBondAmount2);
        uint256 withdrawAmount2 = borrow.redeemYields(owner,uint128(aBondAmount2));

        assertEq(cR1,cR2);
        assertEq(aBondAmount1,aBondAmount2);
        assertEq(ethBacked1,ethBacked2);

        vm.stopPrank();
    }
}
