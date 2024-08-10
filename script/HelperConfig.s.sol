// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Script, console2} from "forge-std/Script.sol";
// import "forge-std/console.sol";

// contract HelperConfig is Script {
//     error HelperConfig_InvalidChainId();

//     struct NetworkConfig {
//         address endPoint;
//         address account;
//     }

//     uint256 constant ARBITRUM_MAINNET_CHAIN_ID = 42161;
//     uint256 constant LOCAL_CHAIN_ID = 31337;
//     address constant BURNER_WALLET = 0x643315C9Be056cDEA171F4e7b2222a4ddaB9F88D;
//     address constant ANVIL_DEFAULT_ACCOUNT =
//         0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
//     NetworkConfig public localNetworkConfig;
//     mapping(uint256 => NetworkConfig) public networkConfigs;

//     constructor() {
//         networkConfigs[ARBITRUM_MAINNET_CHAIN_ID] = getArbitrumConfig();
//     }

//     function getConfig() public returns (NetworkConfig memory) {
//         return getConfigByChainId(block.chainid);
//     }

//     function getConfigByChainId(
//         uint256 chainId
//     ) public returns (NetworkConfig memory) {
//         if (chainId == 42161) {
//             return getArbitrumConfig();
//         } else if (chainId == LOCAL_CHAIN_ID) {
//             return getOrCreateAnvilEthConfig();
//         } else if (networkConfigs[chainId].account != address(0)) {
//             return networkConfigs[chainId];
//         } else {
//             revert HelperConfig_InvalidChainId();
//         }
//     }

//     function getArbitrumConfig() public pure returns (NetworkConfig memory) {
//         return
//             NetworkConfig({
//                 endPoint: 0x1a44076050125825900e736c501f859c50fE728c, //0x6EDCE65403992e310A62460808c4b910D972f10f,// exampleendPoint address on Arbitrum
//                 account: 0x3e8734Ec146C981E3eD1f6b582D447DDE701d90c
//             });
//     }

//     function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
//         if (localNetworkConfig.account != address(0)) {
//             return localNetworkConfig;
//         }

//         console2.log("Deploying MockendPoint...");
//         vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT);
//         console.log(ANVIL_DEFAULT_ACCOUNT);
//         address mockEntryPoint = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // Using Anvil default account as mock entry point for simplicity
//         vm.stopBroadcast();
//         localNetworkConfig = NetworkConfig({
//             endPoint: mockEntryPoint,
//             account: ANVIL_DEFAULT_ACCOUNT
//         });
//         return localNetworkConfig;
//     }
// }
