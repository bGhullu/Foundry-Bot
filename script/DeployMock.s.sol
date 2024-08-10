// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Script} from "forge-std/Script.sol";
// import {MockLZEndpoint} from "../src/mock/Mock.sol";
// import {HelperConfig} from "./HelperConfig.s.sol";
// import "forge-std/console.sol";

// contract MockEndpoint is Script {
//     function run() public {
//         deployMock();
//     }

//     function deployMock() public {
//         HelperConfig helperConfig = new HelperConfig();
//         HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
//         vm.startBroadcast(config.account);
//         MockLZEndpoint arbitrageBot = new MockLZEndpoint();
//         vm.stopBroadcast();
//         console.log("MockLZEndpoint deployed at:", address(arbitrageBot));
//     }
// }
