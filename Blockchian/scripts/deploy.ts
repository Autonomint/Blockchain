import { ethers } from "hardhat";
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

  await deployedBorrowing.initializeTreasury(deployedTreasury.address);
  await deployedBorrowing.setLTV(80);
  await deployedCDS.setTreasury(deployedTreasury.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });



// TRINITY   0x6F0a603bB5059DE0A1B7e5DA607C4dEe1C5EF73a
// DIRAC     0x3161fa24895Da793f797c0B405B7D258DA0F4f88
// CDS       0x96F44146714D6539FF64A31550d8f36aa94DA72b
// BORROWING 0x79448092a379c1187945c8836Cb3EA2E2F6EEd08
// TREASURY  0x101A6D6A73Bf1BE65371E90e8ce0bF467Dfff40A
