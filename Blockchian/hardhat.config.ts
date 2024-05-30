import { HardhatUserConfig } from "hardhat/config";
require("@nomicfoundation/hardhat-chai-matchers");
import "solidity-coverage";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy";
import "hardhat-tracer";
import "hardhat-contract-sizer";
import { EndpointId } from '@layerzerolabs/lz-definitions'
import dotenv from 'dotenv';
dotenv.config({path:".env"});

const INFURA_ID_SEPOLIA = process.env.INFURA_ID_SEPOLIA;
const INFURA_ID_BASE_SEPOLIA = process.env.INFURA_ID_BASE_SEPOLIA;
const INFURA_ID_MODE_SEPOLIA = process.env.INFURA_ID_MODE_SEPOLIA;
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
        viaIR:true
      },
    },
  mocha:{
    timeout:70000
  },
  networks:{
    hardhat: {
      forking: {
        url: "https://mainnet.infura.io/v3/e9cf275f1ddc4b81aa62c5aa0b11ac0f",
        blockNumber: 19381269
      },
    },
    mumbai:{
      url: QUICKNODE_MUMBAI,
      accounts: ["PRIVATE_KEY"]
    },
    sepolia:{
      // eid: EndpointId.SEPOLIA_V2_TESTNET,
      url: INFURA_ID_SEPOLIA,
      accounts: ["PRIVATE_KEY"]
    },
    baseSepolia:{
      // eid: EndpointId.BASESEP_V2_TESTNET,
      url: INFURA_ID_BASE_SEPOLIA,
      accounts: ["PRIVATE_KEY"]
    },
    modeSepolia:{
      // eid: EndpointId.MODE_V2_TESTNET,
      url: INFURA_ID_MODE_SEPOLIA,
      accounts: ["PRIVATE_KEY"]
    },
    goerli:{
      url: INFURA_ID_GOERLI,
      accounts: ["PRIVATE_KEY"]
    },
  },
  etherscan: {
    apiKey: {
      goerli:"MKKA2HY473CWA3HSCJUUD1IX7KKYH45X8U",
      sepolia: "SV9TZ7QYCC79VK2BQD4PIV9MH5RE1AWHIE",
      baseSepolia: "6UNNPWEB76Z1GWR1G5R3C51WDSBD6Z5Y8U",
      modeSepolia: "2077d2155978cb7b4f70585c21a20e32",
      polygonMumbai: "FQCH1175W8JYIKR5ZTD4FK2EJVEBFGQHMF"
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
         apiURL: "https://api-sepolia.basescan.org/api",
         browserURL: "https://sepolia.basescan.org"
        }
      },
      {
        network: "modeSepolia",
        chainId: 919,
        urls: {
         apiURL: "https://sepolia.explorer.mode.network/api",
         browserURL: "https://sepolia.explorer.mode.network/"
        }
      }
    ]
  },
};

export default config;
