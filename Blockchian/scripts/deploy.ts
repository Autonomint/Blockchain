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
  aavePoolAddressSepolia,
  aavePoolAddressBaseSepolia,
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

  // const ABONDToken = await ethers.getContractFactory("ABONDTokenV2");
  // const deployedABONDToken = await upgrades.deployProxy(ABONDToken,{initializer:'initialize'}, {kind:'uups'});
  // await deployedABONDToken.waitForDeployment();
  // console.log("PROXY ABOND ADDRESS",await deployedABONDToken.getAddress());

  // const TestUSDT = await ethers.getContractFactory("TestUSDTV2");
  // const deployedTestUSDT = await upgrades.deployProxy(TestUSDT,[
  //   endpointBaseSepolia,
  //   owner1
  // ],{initializer:'initialize'}, {kind:'uups'});
  // await deployedTestUSDT.waitForDeployment();
  // console.log("PROXY TEST USDT ADDRESS",await deployedTestUSDT.getAddress());

  // const multiSign = await ethers.getContractFactory("MultiSignV2");
  // const deployedMultisign = await upgrades.deployProxy(multiSign,[[owner1,owner2,owner3],2],{initializer:'initialize'},{kind:'uups'});
  // await deployedMultisign.waitForDeployment();
  // console.log("PROXY MULTISIGN ADDRESS",await deployedMultisign.getAddress());
  
  // const CDSLibFactory = await ethers.getContractFactory("CDSLib");
  // const CDSLib = await CDSLibFactory.deploy();
  // const CDS = await ethers.getContractFactory("CDSV2",{
  //   libraries: {
  //       CDSLib:await CDSLib.getAddress()
  //   }
  // });
  // const deployedCDS = await upgrades.deployProxy(CDS,[
  //   await deployedAMINTStablecoin.getAddress(),
  //   priceFeedAddressBaseSepolia,
  //   await deployedTestUSDT.getAddress(),
  //   await deployedMultisign.getAddress(),
  //   endpointBaseSepolia,
  //   owner1 ],{initializer:'initialize',
  //       unsafeAllowLinkedLibraries:true
  //   },{kind:'uups'})
  // await deployedCDS.waitForDeployment();
  // console.log("PROXY CDS ADDRESS",await deployedCDS.getAddress());

  
  // const borrowLibFactory = await ethers.getContractFactory("BorrowLib");
  // const borrowLib = await borrowLibFactory.deploy();
  // const Borrowing = await ethers.getContractFactory("BorrowingV2",{
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
  //   endpointBaseSepolia,
  //   owner1],{initializer:'initialize',
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
  // ],{initializer:'initialize',
  //   unsafeAllowLinkedLibraries:true
  // },{kind:'uups'});
  // await deployedLiquidation.waitForDeployment();
  // console.log("PROXY BORROW LIQUIDATION ADDRESS",await deployedLiquidation.getAddress());

  // const Treasury = await ethers.getContractFactory("TreasuryV2");
  // const deployedTreasury = await upgrades.deployProxy(Treasury,[
  //   await deployedBorrowing.getAddress(),
  //   await deployedAMINTStablecoin.getAddress(),
  //   await deployedABONDToken.getAddress(),
  //   await deployedCDS.getAddress(),
  //   await deployedLiquidation.getAddress(),
  //   await deployedTestUSDT.getAddress(),
  //   endpointBaseSepolia,
  //   owner1 ],{initializer:'initialize'},{kind:'uups'});
  // await deployedTreasury.waitForDeployment();
  // console.log("PROXY TREASURY ADDRESS",await deployedTreasury.getAddress());

  // const Option = await ethers.getContractFactory("OptionsV2");
  // const deployedOptions = await upgrades.deployProxy(Option,[await deployedTreasury.getAddress(),await deployedCDS.getAddress(),await deployedBorrowing.getAddress()],{initializer:'initialize'},{kind:'uups'});
  // await deployedOptions.waitForDeployment();
  // console.log("PROXY OPTIONS ADDRESS",await deployedOptions.getAddress());


  // async function sleep(ms:number) {
  //   return new Promise((resolve) => setTimeout(resolve, ms));
  // }

  // await sleep(30 * 1000);

  // await hre.run("verify:verify", {
  //   address: "0x6502432f446402b8f225e639b95d4d03317a26e4",
  //   contract: "contracts/Token/USDa.sol:USDaStablecoin"
  // });

  // await hre.run("verify:verify", {
  //   address: "0x9eb1fc4bdf917e75d455d70f38d6689b10ec6919",
  //   contract: "contracts/Token/Abond_Token.sol:ABONDTokenV2"
  // });

  // await hre.run("verify:verify", {
  //   address: "0x13a7b78e65c7e389cc56fc66a0342f90730120a8",
  //   contract: "contracts/TestContracts/CopyUsdt.sol:TestUSDTV2"
  // });

  // await hre.run("verify:verify", {
  //   address: "0x4440fce307e3cac1734a80e844918e5acf089503",
  //   contract: "contracts/Core_logic/multiSign.sol:MultiSignV2",
  // });

  // await hre.run("verify:verify", {
  //   address: "0x52c8dde1acb2c6530801f7fb35eb83cea5948356",
  //   contract: "contracts/Core_logic/CDS.sol:CDSV2",
  // });

  // await hre.run("verify:verify", {
  //   address: "0x2eac75c1DF39cc7c26E3bF996eE279d34529f7DE",
  //   contract: "contracts/Core_logic/borrowing.sol:BorrowingV2",
  // });

  // await hre.run("verify:verify", {
  //   address: "0xc2c4c0bb1a29c0aa0fd948e807075859603b5a4c",
  //   contract: "contracts/Core_logic/borrowLiquidation.sol:BorrowLiquidation",
  // });

  // await hre.run("verify:verify", {
  //   address: "0x9d88EfAE2D501FcbAf2D7887Cd85130A6A378837",
  //   contract: "contracts/Core_logic/Treasury.sol:TreasuryV2",
  // });

  // await hre.run("verify:verify", {
  //   address: "0xF4e5bD7996aA356651FE2E9233ddf0f04F36D567",
  //   contract: "contracts/Core_logic/Options.sol:OptionsV2",
  // });

  // await deployedTreasury.setExternalProtocolAddresses(
  //   wethGatewayBaseSepolia,
  //   cometBaseSepolia,
  //   aavePoolAddressBaseSepolia,
  //   aTokenAddressBaseSepolia,
  //   wethAddressBaseSepolia
  // )

  // await deployedMultisign.approveSetterFunction([0,1,2,3,4,5,6,7,8,9]);
  // await deployedABONDToken.setBorrowingContract(await deployedBorrowing.getAddress());

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