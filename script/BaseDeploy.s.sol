// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {BaseReceiver} from "../src/Base.sol";
// import {Script} from "forge-std/Script.sol";
// import {console} from "forge-std/console.sol";

// contract DeployArbitrageReceiver is Script {
//     function run() external {
//         address endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
//         address owner = msg.sender;
//         vm.deal(owner, 1000 ether);
//         vm.startBroadcast();
//         BaseReceiver receiver = new BaseReceiver(endpoint, owner);
//         vm.stopBroadcast();

//         console.log("ArbitrageBot deployed at:", address(receiver));
//     }
// }

// //https://base-mainnet.g.alchemy.com/v2/PznJR9OOxrm9KOKEBBaiI3alUN4MhTlk
