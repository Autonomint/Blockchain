// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.20;

// import {Test} from "../../../lib/forge-std/src/Test.sol";
// import {StdInvariant} from "../../../lib/forge-std/src/StdInvariant.sol";
// import {console} from "../../../lib/forge-std/src/console.sol";
// import {BorrowingTest} from "../../../contracts/TestContracts/CopyBorrowing.sol";
// import {Treasury} from "../../../contracts/Core_logic/Treasury.sol";
// import {CDSTest} from "../../../contracts/TestContracts/CopyCDS.sol";
// import {Options} from "../../../contracts/Core_logic/Options.sol";
// import {MultiSign} from "../../../contracts/Core_logic/multiSign.sol";
// import {TestUSDaStablecoin} from "../../../contracts/TestContracts/CopyUSDa.sol";
// import {TestABONDToken} from "../../../contracts/TestContracts/Copy_Abond_Token.sol";
// import {TestUSDT} from "../../../contracts/TestContracts/CopyUsdt.sol";
// import {HelperConfig} from "../../../scripts/script/HelperConfig.s.sol";
// import {DeployBorrowing} from "../../../scripts/script/DeployBorrowing.s.sol";

// import {IWrappedTokenGatewayV3} from "../../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
// import {CometMainInterface} from "../../../contracts/interface/CometMainInterface.sol";


// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// interface IAToken is IERC20 {}

// contract OpenInvariantTest is StdInvariant,Test {
//     DeployBorrowing deployer;
//     TestUSDaStablecoin usda;
//     TestABONDToken abond;
//     TestUSDT usdt;
//     CDSTest cds;
//     BorrowingTest borrow;
//     Treasury treasury;
//     Options option;
//     MultiSign multiSign;
//     HelperConfig config;

//     address ethUsdPriceFeed;

//     // IPoolAddressesProvider public aaveProvider;
//     // IPool public aave;
//     address public USER = makeAddr("user");
//     address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
//     address public owner1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
//     address public aTokenAddress = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
//     address public cometAddress = 0xA17581A9E3356d9A858b789D68B4d866e593aE94; // 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

//     uint8[] functions = [0,1,2,3,4,5,6,7,8,9,10];

//     uint256 public ETH_AMOUNT = 1 ether;
//     uint256 public STARTING_ETH_BALANCE = 100 ether;

//     function setUp() public {
//         deployer = new DeployBorrowing();
//         (DeployBorrowing.Contracts memory contracts) = deployer.run();
//         usda = contracts.usda;
//         abond = contracts.abond;
//         usdt = contracts.usdt;
//         borrow = contracts.borrow;
//         treasury = contracts.treasury;
//         cds = contracts.cds;
//         multiSign = contracts.multiSign;
//         option = contracts.option;
//         config = contracts.config;
//         (ethUsdPriceFeed,) = config.activeNetworkConfig();

//         vm.startPrank(owner1);
//         multiSign.approveSetterFunction(functions);
//         vm.stopPrank();

//         vm.startPrank(owner);
//         abond.setBorrowingContract(address(borrow));
//         borrow.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
//         borrow.setTreasury(address(treasury));
//         borrow.setOptions(address(option));
//         borrow.setLTV(80);
//         borrow.setBondRatio(4);
//         borrow.setAPR(1000000001547125957863212449);

//         cds.setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
//         cds.setTreasury(address(treasury));
//         cds.setBorrowingContract(address(borrow));
//         cds.setUSDaLimit(80);
//         cds.setUsdtLimit(20000000000);
//         borrow.calculateCumulativeRate();
//         vm.stopPrank();

//         vm.deal(USER,STARTING_ETH_BALANCE);
//         vm.deal(owner,STARTING_ETH_BALANCE);
//         targetContract(address(borrow));
//     }

//     function invariant_ProtocolMustHaveMoreValueThanSupply() public view{
//         uint256 totalSupply = usda.totalSupply();
//         uint256 totalDepositedEth = (address(treasury)).balance;
//         uint256 totalEthValue = totalDepositedEth * borrow.getUSDValue();
//         assert(totalEthValue >= totalSupply);
//     }
// }