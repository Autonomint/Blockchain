import { ethers } from "hardhat";
import hre = require("hardhat");

import {
  wethGateway,
  cEther,
  aTokenAddress,
  priceFeedAddress,
  aavePoolAddress} from"./index"

async function main() {
  const TrinityStablecoin = await ethers.getContractFactory("TrinityStablecoin");
  const deployedTrinityStablecoin = await TrinityStablecoin.deploy();
  await deployedTrinityStablecoin.deployed();
  console.log("TRINITY ADDRESS",deployedTrinityStablecoin.address);

  const ProtocolToken = await ethers.getContractFactory("ProtocolToken");
  const deployedProtocolToken = await ProtocolToken.deploy();
  await deployedProtocolToken.deployed();
  console.log("DIRAC ADDRESS",deployedProtocolToken.address);

  const CDS = await ethers.getContractFactory("CDSTest");
  const deployedCDS = await CDS.deploy(deployedTrinityStablecoin.address,priceFeedAddress);
  await deployedCDS.deployed();
  console.log("CDS ADDRESS",deployedCDS.address);

  const Borrowing = await ethers.getContractFactory("BorrowingTest");
  const deployedBorrowing = await Borrowing.deploy(deployedTrinityStablecoin.address,deployedCDS.address,deployedProtocolToken.address,priceFeedAddress);
  await deployedBorrowing.deployed();
  console.log("BORROWING ADDRESS",deployedBorrowing.address);

  const Treasury = await ethers.getContractFactory("Treasury");
  const deployedTreasury = await Treasury.deploy(deployedBorrowing.address,deployedTrinityStablecoin.address,deployedCDS.address,wethGateway,cEther,aavePoolAddress,aTokenAddress);
  await deployedTreasury.deployed();
  console.log("TREASURY ADDRESS",deployedTreasury.address);

  async function sleep(ms:number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  await sleep(80 * 1000);

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
    constructorArguments: [deployedTrinityStablecoin.address,priceFeedAddress],
  });

  await hre.run("verify:verify", {
    address: deployedBorrowing.address,
    contract: "contracts/TestContracts/CopyBorrowing.sol:BorrowingTest",
    constructorArguments: [deployedTrinityStablecoin.address,deployedCDS.address,deployedProtocolToken.address,priceFeedAddress],
  });

  await hre.run("verify:verify", {
    address: deployedTreasury.address,
    constructorArguments: [deployedBorrowing.address,deployedTrinityStablecoin.address,deployedCDS.address,wethGateway,cEther,aavePoolAddress,aTokenAddress],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });