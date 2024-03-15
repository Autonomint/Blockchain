//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "../../test/foundry/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../../test/foundry/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig{
        address ethUsdPriceFeed;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;
    
    constructor(){
        if(block.chainid == 11155111){
            activeNetworkConfig = getSepoliaEthConfig();
        }else if(block.chainid == 1){
            activeNetworkConfig = getMainnetEthConfig();
        }else{
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory){
        return NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory){
        return NetworkConfig({
            ethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory){
        if(activeNetworkConfig.ethUsdPriceFeed != address(0)){
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS,ETH_USD_PRICE);
        vm.stopBroadcast();
        return NetworkConfig({
            ethUsdPriceFeed: address(ethUsdPriceFeed),
            deployerKey: DEFAULT_ANVIL_KEY            
        });
    }
}