import { ethers } from "hardhat";
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
  const AMINTStablecoin = await ethers.getContractFactory("AMINTStablecoin");
  const deployedAMINTStablecoin = await AMINTStablecoin.deploy();
  await deployedAMINTStablecoin.deployed();
  console.log("AMINT ADDRESS",deployedAMINTStablecoin.address);

  const ABONDToken = await ethers.getContractFactory("ABONDToken");
  const deployedABONDToken = await ABONDToken.deploy();
  await deployedABONDToken.deployed();
  console.log("ABOND ADDRESS",deployedABONDToken.address);

  const TestUSDT = await ethers.getContractFactory("TestUSDT");
  const deployedTestUSDT = await TestUSDT.deploy();
  await deployedTestUSDT.deployed();
  console.log("TEST USDT ADDRESS",deployedTestUSDT.address);

  const multiSign = await ethers.getContractFactory("MultiSign");
  const deployedMultisign = await multiSign.deploy([owner1,owner2,owner3],2);
  await deployedMultisign.deployed();
  console.log("MULTISIGN ADDRESS",deployedMultisign.address);

  const CDS = await ethers.getContractFactory("CDS");
  const deployedCDS = await CDS.deploy(deployedAMINTStablecoin.address,priceFeedAddressGoerli,deployedTestUSDT.address,deployedMultisign.address);
  await deployedCDS.deployed();
  console.log("CDS ADDRESS",deployedCDS.address);

  const Borrowing = await ethers.getContractFactory("Borrowing");
  const deployedBorrowing = await Borrowing.deploy(deployedAMINTStablecoin.address,deployedCDS.address,deployedABONDToken.address,deployedMultisign.address,priceFeedAddressGoerli,5);
  await deployedBorrowing.deployed();
  console.log("BORROWING ADDRESS",deployedBorrowing.address);

  const Treasury = await ethers.getContractFactory("Treasury");
  const deployedTreasury = await Treasury.deploy(deployedBorrowing.address,deployedAMINTStablecoin.address,deployedCDS.address,wethGatewayGoerli,cEtherGoerli,aavePoolAddressGoerli,aTokenAddressGoerli,deployedTestUSDT.address);
  await deployedTreasury.deployed();
  console.log("TREASURY ADDRESS",deployedTreasury.address);

  const options = await ethers.getContractFactory("Options");
  const deployedOptions = await options.deploy(priceFeedAddressGoerli,deployedTreasury.address,deployedCDS.address);
  await deployedOptions.deployed();
  console.log("OPTIONS ADDRESS",deployedOptions.address);



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
    constructorArguments: [priceFeedAddressGoerli,deployedTreasury.address,deployedCDS.address],
  });


  await deployedBorrowing.initializeTreasury(deployedTreasury.address);
  await deployedBorrowing.setOptions(deployedOptions.address);
  await deployedBorrowing.setLTV(80);
  await deployedBorrowing.setAdmin(owner1);

  await deployedCDS.setBorrowingContract(deployedBorrowing.address);
  await deployedCDS.setTreasury(deployedTreasury.address);
  await deployedCDS.setAmintLimit(80);
  await deployedCDS.setUsdtLimit(20000000000);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });