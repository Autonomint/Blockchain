import { ethers,upgrades } from "hardhat";
import hre = require("hardhat");

import {
  wethGatewaySepolia,
  wethGatewayBaseSepolia,
  cometSepolia,
  cometBaseSepolia,
  aTokenAddressSepolia,
  aTokenAddressBaseSepolia,
  priceFeedAddressSepolia,
  priceFeedAddressBaseSepolia,
  aavePoolAddressBaseSepolia,
  aavePoolAddressSepolia,
  owner1,owner2,owner3,
  eidSepolia,eidBaseSepolia,
  endpointSepolia,endpointBaseSepolia,endpointModeSepolia,
  wethAddressSepolia,wethAddressBaseSepolia
} from"./index"

async function main() {

  // const AMINTStablecoin = await ethers.getContractFactory("USDaStablecoin");
  // const deployedAMINTStablecoin = await upgrades.deployProxy(AMINTStablecoin,[
  //   endpointModeSepolia,
  //   owner1
  // ],{initializer:'initialize'}, {kind:'uups'});
  // await deployedAMINTStablecoin.waitForDeployment();
  // console.log("PROXY AMINT ADDRESS",await deployedAMINTStablecoin.getAddress());

  // const ABONDToken = await ethers.getContractFactory("ABONDToken");
  // const deployedABONDToken = await upgrades.deployProxy(ABONDToken,{initializer:'initialize'}, {kind:'uups'});
  // await deployedABONDToken.waitForDeployment();
  // console.log("PROXY ABOND ADDRESS",await deployedABONDToken.getAddress());

  // const TestUSDT = await ethers.getContractFactory("TestUSDT");
  // const deployedTestUSDT = await upgrades.deployProxy(TestUSDT,[
  //   endpointBaseSepolia,
  //   owner1
  // ],{initializer:'initialize'}, {kind:'uups'});
  // await deployedTestUSDT.waitForDeployment();
  // console.log("PROXY TEST USDT ADDRESS",await deployedTestUSDT.getAddress());

  // const multiSign = await ethers.getContractFactory("MultiSign");
  // const deployedMultisign = await upgrades.deployProxy(multiSign,[[owner1,owner2,owner3],2],{initializer:'initialize'},{kind:'uups'});
  // await deployedMultisign.waitForDeployment();
  // console.log("PROXY MULTISIGN ADDRESS",await deployedMultisign.getAddress());
  
  // const CDSLibFactory = await ethers.getContractFactory("CDSLib");
  // const CDSLib = await CDSLibFactory.deploy();
  // const CDS = await ethers.getContractFactory("CDS",{
  //   libraries: {
  //       CDSLib:await CDSLib.getAddress()
  //   }
  // });
  // const deployedCDS = await upgrades.deployProxy(CDS,[
  //   await deployedAMINTStablecoin.getAddress(),
  //   priceFeedAddressBaseSepolia,
  //   await deployedTestUSDT.getAddress(),
  //   await deployedMultisign.getAddress()
  //   ],{initializer:'initialize',
  //       unsafeAllowLinkedLibraries:true
  //   },{kind:'uups'})
  // await deployedCDS.waitForDeployment();
  // console.log("PROXY CDS ADDRESS",await deployedCDS.getAddress());

  // const GlobalVariables = await ethers.getContractFactory("GlobalVariables");
  // const deployedGlobalVariables = await upgrades.deployProxy(GlobalVariables,[
  //   await deployedAMINTStablecoin.getAddress(),
  //   await deployedCDS.getAddress(),
  //   endpointBaseSepolia,
  //   owner1
  //   ],{initializer:'initialize',
  //       unsafeAllowLinkedLibraries:true
  //   },{kind:'uups'})
  // await deployedGlobalVariables.waitForDeployment();
  // console.log("PROXY GLOBAL ADDRESS",await deployedGlobalVariables.getAddress());

  
  // const borrowLibFactory = await ethers.getContractFactory("BorrowLib");
  // const borrowLib = await borrowLibFactory.deploy();
  // const Borrowing = await ethers.getContractFactory("Borrowing",{
  //   libraries: {
  //       BorrowLib:await borrowLib.getAddress()
  //   }
  // });
  // const deployedBorrowing = await upgrades.deployProxy(Borrowing,[
  //   await deployedAMINTStablecoin.getAddress(),
  //   await deployedCDS.getAddress(),
  //   await deployedABONDToken.getAddress(),
  //   await deployedMultisign.getAddress(),
  //   priceFeedAddressBaseSepolia,
  //   11155111,
  //   await deployedGlobalVariables.getAddress()
  //   ],{initializer:'initialize',
  //       unsafeAllowLinkedLibraries:true
  //   },{kind:'uups'})
  // await deployedBorrowing.waitForDeployment();
  // console.log("PROXY BORROWING ADDRESS",await deployedBorrowing.getAddress());

  // const BorrowLiq = await ethers.getContractFactory("BorrowLiquidation",{
  //   libraries: {
  //       BorrowLib:await borrowLib.getAddress()
  //   }
  // });

  // const deployedLiquidation = await upgrades.deployProxy(BorrowLiq,[
  //   await deployedBorrowing.getAddress(),
  //   await deployedCDS.getAddress(),
  //   await deployedAMINTStablecoin.getAddress(),
  //   await deployedGlobalVariables.getAddress()
  // ],{initializer:'initialize',
  //   unsafeAllowLinkedLibraries:true
  // },{kind:'uups'});
  // await deployedLiquidation.waitForDeployment();
  // console.log("PROXY BORROW LIQUIDATION ADDRESS",await deployedLiquidation.getAddress());

  // const Treasury = await ethers.getContractFactory("Treasury");
  // const deployedTreasury = await upgrades.deployProxy(Treasury,[
  //   await deployedBorrowing.getAddress(),
  //   await deployedAMINTStablecoin.getAddress(),
  //   await deployedABONDToken.getAddress(),
  //   await deployedCDS.getAddress(),
  //   await deployedLiquidation.getAddress(),
  //   await deployedTestUSDT.getAddress(),
  //   await deployedGlobalVariables.getAddress()
  // ],{initializer:'initialize'},{kind:'uups'});
  // await deployedTreasury.waitForDeployment();
  // console.log("PROXY TREASURY ADDRESS",await deployedTreasury.getAddress());

  // const Option = await ethers.getContractFactory("Options");
  // const deployedOptions = await upgrades.deployProxy(Option,[
  //   await deployedTreasury.getAddress(),
  //   await deployedCDS.getAddress(),
  //   await deployedBorrowing.getAddress(),
  //   await deployedGlobalVariables.getAddress()
  // ],{initializer:'initialize'},{kind:'uups'});
  // await deployedOptions.waitForDeployment();
  // console.log("PROXY OPTIONS ADDRESS",await deployedOptions.getAddress());


  // async function sleep(ms:number) {
  //   return new Promise((resolve) => setTimeout(resolve, ms));
  // }

  // await sleep(30 * 1000);

  await hre.run("verify:verify", {
    address: "0xc136a17f3c18698e3adf754dbdf7537a2f3265d4",
    contract: "contracts/Token/USDa.sol:USDaStablecoin"
  });

  await hre.run("verify:verify", {
    address: "0xe5d4b991861e70d563e7d061e017e5566935941f",
    contract: "contracts/Token/Abond_Token.sol:ABONDToken"
  });

  await hre.run("verify:verify", {
    address: "0x74e0f0492e8f180f4fef6d9392e9f0e0fc8824be",
    contract: "contracts/TestContracts/CopyUsdt.sol:TestUSDT"
  });

  await hre.run("verify:verify", {
    address: "0x4440fce307e3cac1734a80e844918e5acf089503",
    contract: "contracts/Core_logic/multiSign.sol:MultiSign",
  });

  await hre.run("verify:verify", {
    address: "0x96d7ab459caeef767afce5c22a2ec31491d8be82",
    contract: "contracts/Core_logic/CDS.sol:CDS",
  });

  await hre.run("verify:verify", {
    address: "0x57ce4a4d5dbaad3e0082f0d5833794fc56f8e9fc",
    contract: "contracts/Core_logic/GlobalVariables.sol:GlobalVariables",
  });

  await hre.run("verify:verify", {
    address: "0x8e5e24b408a08c55ea4dbbc557716a88601758f4",
    contract: "contracts/Core_logic/borrowing.sol:Borrowing",
  });

  await hre.run("verify:verify", {
    address: "0xb84ba6aebb9dc009f8e7551515bf3724e762b7fe",
    contract: "contracts/Core_logic/borrowLiquidation.sol:BorrowLiquidation",
  });

  await hre.run("verify:verify", {
    address: "0x94a0482983626c6fcfd929b6b29eaa1a7f3a50ac",
    contract: "contracts/Core_logic/Treasury.sol:Treasury",
  });

  await hre.run("verify:verify", {
    address: "0xa2e7ac795784c66fe43d63ac7f3d1476070ba2d7",
    contract: "contracts/Core_logic/Options.sol:Options",
  });

  // await deployedTreasury.setExternalProtocolAddresses(
  //   wethGatewayBaseSepolia,
  //   cometBaseSepolia,
  //   aavePoolAddressBaseSepolia,
  //   aTokenAddressBaseSepolia,
  //   wethAddressBaseSepolia
  // )

  // await deployedMultisign.approveSetterFunction([0,1,2,3,4,5,6,7,8,9]);
  // await deployedABONDToken.setBorrowingContract(await deployedBorrowing.getAddress());

  // await deployedGlobalVariables.setTreasury(await deployedTreasury.getAddress());
  // await deployedGlobalVariables.setBorrowLiq(await deployedLiquidation.getAddress());
  // await deployedGlobalVariables.setBorrowing(await deployedBorrowing.getAddress());

  // await deployedLiquidation.setTreasury(await deployedTreasury.getAddress());
  // await deployedLiquidation.setAdmin(owner1);

  // await deployedBorrowing.setDstEid(eidSepolia);
  // await deployedCDS.setDstEid(eidSepolia);
  // await deployedTreasury.setDstEid(eidSepolia);
  // await deployedAMINTStablecoin.setDstEid(eidSepolia);
  // await deployedTestUSDT.setDstEid(eidSepolia);


  // await deployedBorrowing.setAdmin(owner1);
  // await deployedBorrowing.setTreasury(deployedTreasury.address);
  // await deployedBorrowing.setOptions(deployedOptions.address);
  // await deployedBorrowing.setLTV(80);
  // await deployedBorrowing.setBondRatio(4);

  // await deployedCDS.setAdmin(owner1);
  // await deployedCDS.setBorrowingContract(deployedBorrowing.address);
  // await deployedCDS.setTreasury(deployedTreasury.address);
  // await deployedCDS.setAmintLimit(80);
  // await deployedCDS.setUsdtLimit(20000000000);

  // await deployedTestUSDT.mint("0x876b4dE42e35A37E6D0eaf8762836CAD860C0c18",10000000000);
  // await deployedTestUSDT.approve(await deployedCDS.getAddress(),10000000000);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });