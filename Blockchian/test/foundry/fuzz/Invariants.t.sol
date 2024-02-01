// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.19;

// import {Test} from "../../../lib/forge-std/src/Test.sol";
// import {StdInvariant} from "../../../lib/forge-std/src/StdInvariant.sol";
// import {console} from "../../../lib/forge-std/src/console.sol";
// import {BorrowingTest} from "../../../contracts/TestContracts/CopyBorrowing.sol";
// import {Treasury} from "../../../contracts/Core_logic/Treasury.sol";
// import {CDSTest} from "../../../contracts/TestContracts/CopyCDS.sol";
// import {TrinityStablecoin} from "../../../contracts/Token/Trinity_ERC20.sol";
// import {ProtocolToken} from "../../../contracts/Token/Protocol_Token.sol";
// import {USDT} from "../../../contracts/TestContracts/CopyUsdt.sol";
// import {HelperConfig} from "../../../scripts/script/HelperConfig.s.sol";
// import {DeployBorrowing} from "../../../scripts/script/DeployBorrowing.s.sol";
// import {Handler} from "./Handler.t.sol";

// import {IWrappedTokenGatewayV3} from "../../../contracts/interface/AaveInterfaces/IWETHGateway.sol";
// import {ICEther} from "../../../contracts/interface/ICEther.sol";
// import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// contract InvariantTest is StdInvariant,Test {
//     DeployBorrowing deployer;
//     TrinityStablecoin tsc;
//     ProtocolToken pToken;
//     USDT usdt;
//     CDSTest cds;
//     BorrowingTest borrow;
//     Treasury treasury;
//     HelperConfig config;
//     Handler handler;

//     address ethUsdPriceFeed;
//     uint256 deployerKey;
//     address wethAddress = 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;
//     address cEthAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

//     IWrappedTokenGatewayV3 wethGateway;
//     ICEther cEther;
//     // IPoolAddressesProvider public aaveProvider;
//     // IPool public aave;
//     address public USER = makeAddr("user");
//     address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

//     uint256 public ETH_AMOUNT = 1 ether;
//     uint256 public STARTING_ETH_BALANCE = 100 ether;

//     function setUp() public {
//         deployer = new DeployBorrowing();
//         (tsc,pToken,usdt,borrow,treasury,cds,config) = deployer.run();
//         (ethUsdPriceFeed,deployerKey) = config.activeNetworkConfig();
//         handler = new Handler(borrow,cds,treasury,tsc,pToken,usdt);

//         wethGateway = IWrappedTokenGatewayV3(wethAddress);
//         cEther = ICEther(cEthAddress);
//         vm.startPrank(owner);
//         borrow.initializeTreasury(address(treasury));
//         borrow.setLTV(80);
//         vm.stopPrank();

//         vm.deal(USER,STARTING_ETH_BALANCE);
//         targetContract(address(handler));
//     }

//     function invariant_ProtocolMustHaveMoreValueThanSupply() public view{
//         uint256 totalSupply = tsc.totalSupply();
//         uint256 totalDepositedEth = (address(treasury)).balance;
//         uint256 totalEthValue = totalDepositedEth * borrow.getUSDValue();
//         console.log("ETH VALUE",totalEthValue);
//         console.log("TOTAL SUPPLY",totalSupply);
//         assert(totalEthValue >= totalSupply);
//     }
// }