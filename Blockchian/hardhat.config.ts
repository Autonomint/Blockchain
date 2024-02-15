import { HardhatUserConfig } from "hardhat/config";
require("@nomicfoundation/hardhat-chai-matchers");
import "solidity-coverage";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-tracer";
import dotenv from 'dotenv';
dotenv.config({path:".env"});

const INFURA_ID_SEPOLIA = process.env.INFURA_ID_SEPOLIA;
const INFURA_ID_GOERLI = process.env.INFURA_ID_GOERLI;
const QUICKNODE_MUMBAI = process.env.QUICKNODE_MUMBAI;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const MUMBAI_API_KEY = process.env.MUMBAI_API_KEY;

const config: HardhatUserConfig = {
  solidity: {
    version :"0.8.20",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
        // viaIR:true
      },

    },
  networks:{
    mumbai:{
      url: QUICKNODE_MUMBAI,
      accounts: [PRIVATE_KEY]
    },
    hardhat: {
      forking: {
        url: "https://goerli.infura.io/v3/e9cf275f1ddc4b81aa62c5aa0b11ac0f",
        blockNumber: 10360783
      },
    },
    sepolia:{
      url: INFURA_ID_SEPOLIA,
      accounts: [PRIVATE_KEY]
    },
    goerli:{
      url: INFURA_ID_GOERLI,
      accounts: [PRIVATE_KEY]
    },
  },
  etherscan: {
    apiKey: {
      goerli:"",
      sepolia: "",
      polygonMumbai: ""
    },
  },
};

export default config;
