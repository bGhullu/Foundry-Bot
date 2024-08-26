// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {TargetArbitrageContract} from "../src/cross_chain/_TargetChainArbitrage.sol";

contract DeployTargetArbitrageContract is Script {
    function run() external {
        // Set your deployment parameters here
        address endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // Replace with LayerZero endpoint
        address lendingPool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD; // Aave lending pool address

        address[] memory dexAddresses = new address[](2);
        bytes4[] memory dexFunctionSelectors = new bytes4[](2);
        address[] memory bridgeAddresses = new address[](1);
        bytes4[] memory bridgeFunctionSelectors = new bytes4[](1);

        dexAddresses[0] = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Uniswap V2
        dexAddresses[1] = 0x5E325eDA8064b456f4781070C0738d849c824258; // Uniswap V3
        dexFunctionSelectors[0] = TargetArbitrageContract
            .swapOnUniswapV2
            .selector;
        dexFunctionSelectors[1] = TargetArbitrageContract
            .swapOnUniswapV3
            .selector;

        bridgeAddresses[0] = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5; // Bridge
        bridgeFunctionSelectors[0] = TargetArbitrageContract
            ._executeBridge
            .selector;

        vm.startBroadcast();

        TargetArbitrageContract targetContract = new TargetArbitrageContract(
            endpoint,
            lendingPool,
            dexAddresses,
            dexFunctionSelectors,
            bridgeAddresses,
            bridgeFunctionSelectors
        );

        console.log(
            "Deployed TargetArbitrageContract at:",
            address(targetContract)
        );

        vm.stopBroadcast();
    }
}
