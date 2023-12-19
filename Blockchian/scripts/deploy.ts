import { ethers } from "hardhat";
import hre = require("hardhat");

import {
  wethGatewayMumbai,
  wethGatewaySepolia,
  cEtherMumbai,
  cEtherSepolia,
  aTokenAddressMumbai,
  aTokenAddressSepolia,
  priceFeedAddressMumbai,
  priceFeedAddressSepolia,
  aavePoolAddressMumbai,
  aavePoolAddressSepolia,
  usdtTokenAddress
  // deployedTrinityStablecoin.address,
  // deployedProtocolToken.address
} from"./index"

async function main() {
  const TrinityStablecoin = await ethers.getContractFactory("TrinityStablecoin");
  const deployedTrinityStablecoin = await TrinityStablecoin.deploy();
  await deployedTrinityStablecoin.deployed();
  console.log("TRINITY ADDRESS",deployedTrinityStablecoin.address);

  const ProtocolToken = await ethers.getContractFactory("ProtocolToken");
  const deployedProtocolToken = await ProtocolToken.deploy();
  await deployedProtocolToken.deployed();
  console.log("DIRAC ADDRESS",deployedProtocolToken.address);

  // const USDT = await ethers.getContractFactory("USDT");
  // const deployedUSDT = await USDT.deploy();
  // await deployedUSDT.deployed();
  // console.log("USDT ADDRESS",deployedUSDT.address);

  const CDS = await ethers.getContractFactory("CDSTest");
  const deployedCDS = await CDS.deploy(deployedTrinityStablecoin.address,priceFeedAddressSepolia,usdtTokenAddress);
  await deployedCDS.deployed();
  console.log("CDS ADDRESS",deployedCDS.address);

  const Borrowing = await ethers.getContractFactory("BorrowingTest");
  const deployedBorrowing = await Borrowing.deploy(deployedTrinityStablecoin.address,deployedCDS.address,deployedProtocolToken.address,priceFeedAddressSepolia);
  await deployedBorrowing.deployed();
  console.log("BORROWING ADDRESS",deployedBorrowing.address);

  const Treasury = await ethers.getContractFactory("Treasury");
  const deployedTreasury = await Treasury.deploy(deployedBorrowing.address,deployedTrinityStablecoin.address,deployedCDS.address,wethGatewaySepolia,cEtherSepolia,aavePoolAddressSepolia,aTokenAddressSepolia,usdtTokenAddress);
  await deployedTreasury.deployed();
  console.log("TREASURY ADDRESS",deployedTreasury.address);

  const options = await ethers.getContractFactory("Options");
  const deployedOptions = await options.deploy();
  await deployedOptions.deployed();
  console.log("OPTIONS ADDRESS",deployedOptions.address);



  async function sleep(ms:number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  await sleep(30 * 1000);

  await hre.run("verify:verify", {
    address: deployedTrinityStablecoin.address,
    contract: "contracts/Token/Trinity_ERC20.sol:TrinityStablecoin"
  });

  await hre.run("verify:verify", {
    address: deployedProtocolToken.address,
    contract: "contracts/Token/Protocol_Token.sol:ProtocolToken"
  });

  await hre.run("verify:verify", {
    address: deployedCDS.address,
    contract: "contracts/TestContracts/CopyCDS.sol:CDSTest",
    constructorArguments: [deployedTrinityStablecoin.address,priceFeedAddressSepolia,usdtTokenAddress],
  });

  await hre.run("verify:verify", {
    address: deployedBorrowing.address,
    contract: "contracts/TestContracts/CopyBorrowing.sol:BorrowingTest",
    constructorArguments: [deployedTrinityStablecoin.address,deployedCDS.address,deployedProtocolToken.address,priceFeedAddressSepolia],
  });

  await hre.run("verify:verify", {
    address: deployedTreasury.address,
    constructorArguments: [deployedBorrowing.address,deployedTrinityStablecoin.address,deployedCDS.address,wethGatewaySepolia,cEtherSepolia,aavePoolAddressSepolia,aTokenAddressSepolia,usdtTokenAddress],
  });

  await hre.run("verify:verify", {
    address: deployedOptions.address,
    constructorArguments: [],
  });

  //await deployedTreasury.setBorrowingContract(deployedBorrowing.address);
  await deployedCDS.setBorrowingContract(deployedBorrowing.address);
  await deployedCDS.setTreasury(deployedTreasury.address);
  await deployedCDS.setAmintLimit(80);
  await deployedCDS.setUsdtLimit(20000);
  await deployedBorrowing.initializeTreasury(deployedTreasury.address);
  await deployedBorrowing.setOptions(deployedOptions.address);

  await deployedBorrowing.setAPY(5);
  await deployedBorrowing.setLTV(80);
  await deployedBorrowing.calculateCumulativeRate();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });