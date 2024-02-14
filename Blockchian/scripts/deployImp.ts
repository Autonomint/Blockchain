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
  owner1,owner2,owner3,
  PROXY_AMINT_ADDRESS,PROXY_ABOND_ADDRESS,PROXY_BORROWING_ADDRESS,
  PROXY_CDS_ADDRESS,PROXY_MULTISIGN_ADDRESS,PROXY_TESTUSDT_ADDRESS,PROXY_TREASURY_ADDRESS
} from"./index"

async function main() {

  // const AMINTStablecoin = await ethers.getContractFactory("TestAMINTStablecoin");
  // const deployedAMINTStablecoin = await upgrades.upgradeProxy(AMINTStablecoin, {kind:'uups'});
  // await deployedAMINTStablecoin.waitForDeployment();
  // console.log("NEW IMP ABOND ADDRESS",deployedAMINTStablecoin.address);

  // const ABONDToken = await ethers.getContractFactory("TestABONDToken");
  // const deployedABONDToken = await upgrades.upgradeProxy(ABONDToken, {kind:'uups'});
  // await deployedABONDToken.waitForDeployment();
  // console.log("NEW IMP ABOND ADDRESS",deployedABONDToken.address);

  // const TestUSDT = await ethers.getContractFactory("TestUSDT");
  // const deployedTestUSDT = await upgrades.upgradeProxy(TestUSDT, {kind:'uups'});
  // await deployedTestUSDT.waitForDeployment();
  // console.log("NEW IMP TEST USDT ADDRESS",deployedTestUSDT.address);

  // const multiSign = await ethers.getContractFactory("MultiSign");
  // const deployedMultisign = await upgrades.upgradeProxy(multiSign,[[owner1,owner2,owner3],2],{initializer:'initialize'},{kind:'uups'});
  // await deployedMultisign.waitForDeployment();
  // console.log("NEW IMP MULTISIGN ADDRESS",deployedMultisign.address);

  // const CDS = await ethers.getContractFactory("CDSTest");
  // const deployedCDS = await upgrades.upgradeProxy(CDS,[await deployedAMINTStablecoin.getAddress(),priceFeedAddressGoerli,await deployedTestUSDT.getAddress(),await deployedMultisign.getAddress()],{initializer:'initialize'},{kind:'uups'})
  // await deployedCDS.waitForDeployment();
  // console.log("NEW IMP CDS ADDRESS",deployedCDS.address);

  const Borrowing = await ethers.getContractFactory("Borrowing");
  const deployedBorrowing = await upgrades.upgradeProxy(PROXY_BORROWING_ADDRESS,Borrowing,{kind:'uups'});
  await deployedBorrowing.waitForDeployment();
  console.log("NEW IMP BORROWING ADDRESS",await deployedBorrowing.getAddress());

  // const Treasury = await ethers.getContractFactory("Treasury");
  // const deployedTreasury = await upgrades.upgradeProxy(Treasury,[await deployedBorrowing.getAddress(),await deployedAMINTStablecoin.getAddress(),await deployedCDS.getAddress(),wethGatewayGoerli,cEtherGoerli,aavePoolAddressGoerli,aTokenAddressGoerli,await deployedTestUSDT.getAddress()],{initializer:'initialize'},{kind:'uups'});
  // await deployedTreasury.waitForDeployment();
  // console.log("NEW IMP TREASURY ADDRESS",deployedTreasury.address);

  // const Option = await ethers.getContractFactory("Options");
  // const deployedOptions = await upgrades.upgradeProxy(Option,[priceFeedAddressGoerli,await deployedTreasury.getAddress(),await deployedCDS.getAddress(),await deployedBorrowing.getAddress()],{initializer:'initialize'},{kind:'uups'});
  // await deployedOptions.deployed();
  // console.log("NEW IMP OPTIONS ADDRESS",deployedOptions.address);
  await hre.run("verify:verify", {
    address: "0xf349148a601d27fe13115025503f34451d4bf2a5",
    contract: "contracts/Core_logic/borrowing.sol:Borrowing",
    //constructorArguments: [deployedAMINTStablecoin.address,deployedCDS.address,deployedABONDToken.address,deployedMultisign.address,priceFeedAddressGoerli,5],
  });

  // async function sleep(ms:number) {
  //   return new Promise((resolve) => setTimeout(resolve, ms));
  // }

  // await sleep(30 * 1000);

  // await hre.run("verify:verify", {
  //   address: deployedAMINTStablecoin.address,
  //   contract: "contracts/Token/Amint.sol:AMINTStablecoin"
  // });

  // await hre.run("verify:verify", {
  //   address: deployedABONDToken.address,
  //   contract: "contracts/Token/Abond_Token.sol:ABONDToken"
  // });

  // await hre.run("verify:verify", {
  //   address: deployedTestUSDT.address,
  //   contract: "contracts/TestContracts/CopyUsdt.sol:TestUSDT"
  // });

  // await hre.run("verify:verify", {
  //   address: deployedMultisign.address,
  //   contract: "contracts/Core_logic/multiSign.sol:MultiSign",
  //   constructorArguments: [[owner1,owner2,owner3],2],
  // });

  // await hre.run("verify:verify", {
  //   address: deployedCDS.address,
  //   contract: "contracts/Core_logic/CDS.sol:CDS",
  //   constructorArguments: [deployedAMINTStablecoin.address,priceFeedAddressGoerli,deployedTestUSDT.address,deployedMultisign.address],
  // });

  // await hre.run("verify:verify", {
  //   address: deployedBorrowing.address,
  //   contract: "contracts/Core_logic/borrowing.sol:Borrowing",
  //   constructorArguments: [deployedAMINTStablecoin.address,deployedCDS.address,deployedABONDToken.address,deployedMultisign.address,priceFeedAddressGoerli,5],
  // });

  // await hre.run("verify:verify", {
  //   address: deployedTreasury.address,
  //   contract: "contracts/Core_logic/Treasury.sol:Treasury",
  //   constructorArguments: [deployedBorrowing.address,deployedAMINTStablecoin.address,deployedCDS.address,wethGatewayGoerli,cEtherGoerli,aavePoolAddressGoerli,aTokenAddressGoerli,deployedTestUSDT.address],
  // });

  // await hre.run("verify:verify", {
  //   address: deployedOptions.address,
  //   contract: "contracts/Core_logic/Options.sol:Options",
  //   constructorArguments: [priceFeedAddressGoerli,deployedTreasury.address,deployedCDS.address,deployedBorrowing.address],
  // });


  // await deployedBorrowing.initializeTreasury(deployedTreasury.address);
  // await deployedBorrowing.setOptions(deployedOptions.address);
  // await deployedBorrowing.setLTV(80);
  // await deployedBorrowing.setAdmin(owner1);
  // await deployedBorrowing.setBondRatio(4);

  // await deployedCDS.setBorrowingContract(deployedBorrowing.address);
  // await deployedCDS.setTreasury(deployedTreasury.address);
  // await deployedCDS.setAmintLimit(80);
  // await deployedCDS.setUsdtLimit(20000000000);

  // await deployedTestUSDT.mint(owner1,10000000000);
  // await deployedTestUSDT.approve(deployedCDS.address,10000000000);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });