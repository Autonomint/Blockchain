import { ethers,upgrades } from "hardhat";
import hre = require("hardhat");

import {
  wethGatewayMumbai,
  wethGatewayGoerli,
  wethGatewaySepolia,
  cEtherMumbai,
  cEtherGoerli,
  cEtherSepolia,
  aTokenAddressMumbai,
  aTokenAddressGoerli,
  aTokenAddressSepolia,
  priceFeedAddressMumbai,
  priceFeedAddressGoerli,
  priceFeedAddressSepolia,
  aavePoolAddressMumbai,
  aavePoolAddressGoerli,
  aavePoolAddressSepolia,
  owner1,owner2,owner3
  // deployedAMINTStablecoin.address,
  // deployedABONDToken.address
} from"./index"

async function main() {

  const AMINTStablecoin = await ethers.getContractFactory("TestAMINTStablecoin");
  const deployedAMINTStablecoin = await upgrades.deployProxy(AMINTStablecoin, {kind:'uups'});
  await deployedAMINTStablecoin.waitForDeployment();
  console.log("PROXY ABOND ADDRESS",deployedAMINTStablecoin.address);

  const ABONDToken = await ethers.getContractFactory("TestABONDToken");
  const deployedABONDToken = await upgrades.deployProxy(ABONDToken, {kind:'uups'});
  await deployedABONDToken.waitForDeployment();
  console.log("PROXY ABOND ADDRESS",deployedABONDToken.address);

  const TestUSDT = await ethers.getContractFactory("TestUSDT");
  const deployedTestUSDT = await upgrades.deployProxy(TestUSDT, {kind:'uups'});
  await deployedTestUSDT.waitForDeployment();
  console.log("PROXY TEST USDT ADDRESS",deployedTestUSDT.address);

  const multiSign = await ethers.getContractFactory("MultiSign");
  const deployedMultisign = await upgrades.deployProxy(multiSign,[[owner1,owner2,owner3],2],{initializer:'initialize'},{kind:'uups'});
  await deployedMultisign.waitForDeployment();
  console.log("PROXY MULTISIGN ADDRESS",deployedMultisign.address);

  const CDS = await ethers.getContractFactory("CDSTest");
  const deployedCDS = await upgrades.deployProxy(CDS,[await deployedAMINTStablecoin.getAddress(),priceFeedAddressGoerli,await deployedTestUSDT.getAddress(),await deployedMultisign.getAddress()],{initializer:'initialize'},{kind:'uups'})
  await deployedCDS.waitForDeployment();
  console.log("PROXY CDS ADDRESS",deployedCDS.address);

  const Borrowing = await ethers.getContractFactory("BorrowingTest");
  const deployedBorrowing = await upgrades.deployProxy(Borrowing,[await deployedAMINTStablecoin.getAddress(),await deployedCDS.getAddress(),await deployedABONDToken.getAddress(),await deployedMultisign.getAddress(),priceFeedAddressGoerli,1],{initializer:'initialize'},{kind:'uups'});
  await deployedBorrowing.waitForDeployment();
  console.log("PROXY BORROWING ADDRESS",deployedBorrowing.address);

  const Treasury = await ethers.getContractFactory("Treasury");
  const deployedTreasury = await upgrades.deployProxy(Treasury,[await deployedBorrowing.getAddress(),await deployedAMINTStablecoin.getAddress(),await deployedCDS.getAddress(),wethGatewayGoerli,cEtherGoerli,aavePoolAddressGoerli,aTokenAddressGoerli,await deployedTestUSDT.getAddress()],{initializer:'initialize'},{kind:'uups'});
  await deployedTreasury.waitForDeployment();
  console.log("PROXY TREASURY ADDRESS",deployedTreasury.address);

  const Option = await ethers.getContractFactory("Options");
  const deployedOptions = await upgrades.deployProxy(Option,[priceFeedAddressGoerli,await deployedTreasury.getAddress(),await deployedCDS.getAddress(),await deployedBorrowing.getAddress()],{initializer:'initialize'},{kind:'uups'});
  await deployedOptions.deployed();
  console.log("PROXY OPTIONS ADDRESS",deployedOptions.address);


  async function sleep(ms:number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  await sleep(30 * 1000);

  await hre.run("verify:verify", {
    address: deployedAMINTStablecoin.address,
    contract: "contracts/Token/Amint.sol:AMINTStablecoin"
  });

  await hre.run("verify:verify", {
    address: deployedABONDToken.address,
    contract: "contracts/Token/Abond_Token.sol:ABONDToken"
  });

  await hre.run("verify:verify", {
    address: deployedTestUSDT.address,
    contract: "contracts/TestContracts/CopyUsdt.sol:TestUSDT"
  });

  await hre.run("verify:verify", {
    address: deployedMultisign.address,
    contract: "contracts/Core_logic/multiSign.sol:MultiSign",
    constructorArguments: [[owner1,owner2,owner3],2],
  });

  await hre.run("verify:verify", {
    address: deployedCDS.address,
    contract: "contracts/Core_logic/CDS.sol:CDS",
    constructorArguments: [deployedAMINTStablecoin.address,priceFeedAddressGoerli,deployedTestUSDT.address,deployedMultisign.address],
  });

  await hre.run("verify:verify", {
    address: deployedBorrowing.address,
    contract: "contracts/Core_logic/borrowing.sol:Borrowing",
    constructorArguments: [deployedAMINTStablecoin.address,deployedCDS.address,deployedABONDToken.address,deployedMultisign.address,priceFeedAddressGoerli,5],
  });

  await hre.run("verify:verify", {
    address: deployedTreasury.address,
    contract: "contracts/Core_logic/Treasury.sol:Treasury",
    constructorArguments: [deployedBorrowing.address,deployedAMINTStablecoin.address,deployedCDS.address,wethGatewayGoerli,cEtherGoerli,aavePoolAddressGoerli,aTokenAddressGoerli,deployedTestUSDT.address],
  });

  await hre.run("verify:verify", {
    address: deployedOptions.address,
    contract: "contracts/Core_logic/Options.sol:Options",
    constructorArguments: [priceFeedAddressGoerli,deployedTreasury.address,deployedCDS.address,deployedBorrowing.address],
  });

  await deployedMultisign.approveSetterFunction(4);
  await deployedMultisign.approveSetterFunction(5);
  await deployedMultisign.approveSetterFunction(6);
  await deployedMultisign.approveSetterFunction(0);
  await deployedMultisign.approveSetterFunction(8);
  await deployedMultisign.approveSetterFunction(7);
  await deployedMultisign.approveSetterFunction(9);
  await deployedMultisign.approveSetterFunction(10);
  await deployedMultisign.approveSetterFunction(1);


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

  await deployedTestUSDT.mint(owner1,10000000000);
  await deployedTestUSDT.approve(deployedCDS.address,10000000000);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });