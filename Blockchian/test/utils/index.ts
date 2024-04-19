export const wethGatewaySepolia = "0x387d311e47e80b498169e6fb51d3193167d89F7D";
export const cometSepolia = "0x2943ac1216979aD8dB76D9147F64E61adc126e96";
export const wethAddressSepolia = "0x2D5ee574e710219a521449679A4A7f2B43f046ad";
export const priceFeedAddressSepolia = "0x694AA1769357215DE4FAC081bf1f309aDC325306";
export const aavePoolAddressSepolia = "0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A";
export const aTokenAddressSepolia = "0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830";

export const wethGatewayMainnet = "0x893411580e590D62dDBca8a703d61Cc4A8c7b2b9";
export const cometMainnet = "0xA17581A9E3356d9A858b789D68B4d866e593aE94";
export const wethAddressMainnet = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
export const priceFeedAddressMainnet = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
export const aavePoolAddressMainnet = "0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e";
export const aTokenAddressMainnet = "0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8";
export const endPointAddressMainnet = "0x1a44076050125825900e736c501f859c50fe728c";
export const eidMainnet = 30101;

export const INFURA_URL_SEPOLIA = "https://sepolia.infura.io/v3/e9cf275f1ddc4b81aa62c5aa0b11ac0f";
export const INFURA_URL_MAINNET = "https://mainnet.infura.io/v3/e9cf275f1ddc4b81aa62c5aa0b11ac0f";


export const aTokenABI =[{"inputs":[{"internalType":"address","name":"admin","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"implementation","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"name":"initialize","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address","name":"newImplementation","type":"address"}],"name":"upgradeTo","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newImplementation","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"upgradeToAndCall","outputs":[],"stateMutability":"payable","type":"function"}]

export const cETH_ABI =[{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"address","name":"admin_","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"admin_","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newAdmin","type":"address"}],"name":"changeAdmin","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"implementation","outputs":[{"internalType":"address","name":"implementation_","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newImplementation","type":"address"}],"name":"upgradeTo","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newImplementation","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"upgradeToAndCall","outputs":[],"stateMutability":"payable","type":"function"},{"stateMutability":"payable","type":"receive"}]