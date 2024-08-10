// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Script} from "forge-std/Script.sol";
// import {ArbitrageBot} from "../src/ArbitrageBot.sol";
// import {HelperConfig} from "./HelperConfig.s.sol";

// contract DeployArbitrageBot is Script {
//     function run() public {}

//     function deployArbitrageBot() public returns (HelperConfig, ArbitrageBot) {
//         HelperConfig helperConfig = new HelperConfig();
//         HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
//         vm.startBroadcast(config.account);
//         ArbitrageBot arbitrageBot = new ArbitrageBot(
//             config.endPoint,
//             config.account
//         );
//         arbitrageBot.transferOwnership(config.account);
//         vm.stopBroadcast();
//         return (helperConfig, arbitrageBot);
//     }
// }
