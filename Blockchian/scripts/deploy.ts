import { ethers,upgrades } from "hardhat";
import hre = require("hardhat");

import {
  wethGatewayMumbai,
  wethGatewaySepolia,
  cEtherMumbai,
  cometSepolia,
  aTokenAddressMumbai,
  aTokenAddressSepolia,
  priceFeedAddressMumbai,
  priceFeedAddressSepolia,
  aavePoolAddressMumbai,
  aavePoolAddressSepolia,
  owner1,owner2,owner3,
  PROXY_AMINT_ADDRESS,PROXY_ABOND_ADDRESS,PROXY_BORROWING_ADDRESS,
  PROXY_CDS_ADDRESS,PROXY_OPTIONS_ADDRESS,PROXY_MULTISIGN_ADDRESS,PROXY_TESTUSDT_ADDRESS,PROXY_TREASURY_ADDRESS, wethAddressSepolia
} from"./index"

async function main() {

  const AMINTStablecoin = await ethers.getContractFactory("AMINTStablecoin");
  const deployedAMINTStablecoin = await upgrades.deployProxy(AMINTStablecoin, {kind:'uups'});
  await deployedAMINTStablecoin.waitForDeployment();
  console.log("PROXY AMINT ADDRESS",await deployedAMINTStablecoin.getAddress());

  const ABONDToken = await ethers.getContractFactory("ABONDToken");
  const deployedABONDToken = await upgrades.deployProxy(ABONDToken, {kind:'uups'});
  await deployedABONDToken.waitForDeployment();
  console.log("PROXY ABOND ADDRESS",await deployedABONDToken.getAddress());

  const TestUSDT = await ethers.getContractFactory("TestUSDT");
  const deployedTestUSDT = await upgrades.deployProxy(TestUSDT, {kind:'uups'});
  await deployedTestUSDT.waitForDeployment();
  console.log("PROXY TEST USDT ADDRESS",await deployedTestUSDT.getAddress());

  const multiSign = await ethers.getContractFactory("MultiSign");
  const deployedMultisign = await upgrades.deployProxy(multiSign,[[owner1,owner2,owner3],2],{initializer:'initialize'},{kind:'uups'});
  await deployedMultisign.waitForDeployment();
  console.log("PROXY MULTISIGN ADDRESS",await deployedMultisign.getAddress());

  const CDS = await ethers.getContractFactory("CDS");
  const deployedCDS = await upgrades.deployProxy(CDS,[await deployedAMINTStablecoin.getAddress(),priceFeedAddressSepolia,await deployedTestUSDT.getAddress(),await deployedMultisign.getAddress()],{initializer:'initialize'},{kind:'uups'})
  await deployedCDS.waitForDeployment();
  console.log("PROXY CDS ADDRESS",await deployedCDS.getAddress());

  const Borrowing = await ethers.getContractFactory("Borrowing");
  const deployedBorrowing = await upgrades.deployProxy(Borrowing,[await deployedAMINTStablecoin.getAddress(),await deployedCDS.getAddress(),await deployedABONDToken.getAddress(),await deployedMultisign.getAddress(),priceFeedAddressSepolia,11155111],{initializer:'initialize'},{kind:'uups'});
  await deployedBorrowing.waitForDeployment();
  console.log("PROXY BORROWING ADDRESS",await deployedBorrowing.getAddress());

  const Treasury = await ethers.getContractFactory("Treasury");
  const deployedTreasury = await upgrades.deployProxy(Treasury,[await deployedBorrowing.getAddress(),await deployedAMINTStablecoin.getAddress(),await deployedABONDToken.getAddress(),await deployedCDS.getAddress(),wethGatewaySepolia,cometSepolia,aavePoolAddressSepolia,aTokenAddressSepolia,await deployedTestUSDT.getAddress(),wethAddressSepolia],{initializer:'initialize'},{kind:'uups'});
  await deployedTreasury.waitForDeployment();
  console.log("PROXY TREASURY ADDRESS",await deployedTreasury.getAddress());

  const Option = await ethers.getContractFactory("Options");
  const deployedOptions = await upgrades.deployProxy(Option,[await deployedTreasury.getAddress(),await deployedCDS.getAddress(),await deployedBorrowing.getAddress()],{initializer:'initialize'},{kind:'uups'});
  await deployedOptions.waitForDeployment();
  console.log("PROXY OPTIONS ADDRESS",await deployedOptions.getAddress());


  async function sleep(ms:number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  await sleep(30 * 1000);

  // await hre.run("verify:verify", {
  //   address: "0x4897424de78994b0d449c3253befee9206c6f082",
  //   contract: "contracts/Token/Amint.sol:AMINTStablecoin"
  // });

  // await hre.run("verify:verify", {
  //   address: "0x9f08efc729afd95df9b8e4c7afda29e4d22c6435",
  //   contract: "contracts/Token/Abond_Token.sol:ABONDToken"
  // });

  // await hre.run("verify:verify", {
  //   address: "0xfae4eabe26d6d2b8685404813afd939de3fc49da",
  //   contract: "contracts/TestContracts/CopyUsdt.sol:TestUSDT"
  // });

  // await hre.run("verify:verify", {
  //   address: "0x5e4b8421e25fb7430a0c3896e2a02ccb6e977ab2",
  //   contract: "contracts/Core_logic/multiSign.sol:MultiSign",
  //   //constructorArguments: [[owner1,owner2,owner3],2],
  // });

  // await hre.run("verify:verify", {
  //   address: "0x4f730f6f2e56274d707308e2609c1473b4b518c5",
  //   contract: "contracts/Core_logic/CDS.sol:CDS",
  //   //constructorArguments: [deployedAMINTStablecoin.address,priceFeedAddressGoerli,deployedTestUSDT.address,deployedMultisign.address],
  // });

  // await hre.run("verify:verify", {
  //   address: "0xc128502ef270b2ad214bf5e31095a01049561018",
  //   contract: "contracts/Core_logic/borrowing.sol:Borrowing",
  //   //constructorArguments: [deployedAMINTStablecoin.address,deployedCDS.address,deployedABONDToken.address,deployedMultisign.address,priceFeedAddressGoerli,5],
  // });

  // await hre.run("verify:verify", {
  //   address: "0xae5740aad7bfafca94caff2deb6916cd39afcd98",
  //   contract: "contracts/Core_logic/Treasury.sol:Treasury",
  //   //constructorArguments: [deployedBorrowing.address,deployedAMINTStablecoin.address,deployedCDS.address,wethGatewayGoerli,cEtherGoerli,aavePoolAddressGoerli,aTokenAddressGoerli,deployedTestUSDT.address],
  // });

  // await hre.run("verify:verify", {
  //   address: "0x6E79F4A84a14BC84b5D88E4ce15B0D47B03D55f9",
  //   contract: "contracts/Core_logic/Options.sol:Options",
  //   //constructorArguments: [priceFeedAddressGoerli,deployedTreasury.address,deployedCDS.address,deployedBorrowing.address],
  // });

  await deployedMultisign.approveSetterFunction([0,1,2,3,4,5,6,7,8,9,10]);

  await deployedAMINTStablecoin.setBorrowingContract(await deployedBorrowing.getAddress());
  await deployedAMINTStablecoin.setCdsContract(await deployedCDS.getAddress());

  await deployedABONDToken.setBorrowingContract(await deployedBorrowing.getAddress());


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