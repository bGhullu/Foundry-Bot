// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TargetArbitrageContract} from "../src/_TargetChainArbitrage.sol"; // Adjust the path as needed
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IUniswapV2Router02} from "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "@uniswapV3/contracts/interfaces/ISwapRouter.sol";

contract TargetArbitrageTest is Test {
    TargetArbitrageContract public targetContract =
        TargetArbitrageContract(0x290d5b2F55866d2357cbf0a31724850091dF5dd5);
    IPool public lendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Mainnet Aave lending pool address
    IUniswapV2Router02 public uniswapV2Router =
        IUniswapV2Router02(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24); // Uniswap V2 router address
    ISwapRouter public uniswapV3Router =
        ISwapRouter(0x5E325eDA8064b456f4781070C0738d849c824258); // Uniswap V3 router address

    IERC20 public tokenA = IERC20(0x6985884C4392D348587B19cb9eAAf157F13271cd); // Arb ZRO
    IERC20 public tokenB = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // Arb USDC
    IERC20 public tokenC = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1); // Arb DAI

    address public endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    address public owner;
    uint256 private ownerPrivateKey;

    function setUp() public {
        console.log("Setting up the test environment...");
        ownerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        owner = vm.addr(ownerPrivateKey);
        // Deploy the TargetArbitrageContract with mock endpoints and pool
        address[] memory dexAddresses = new address[](2);
        bytes4[] memory dexFunctionSelectors = new bytes4[](2);
        address[] memory bridgeAddresses = new address[](1);
        bytes4[] memory bridgeFunctionSelectors = new bytes4[](1);

        console.log("Assigning the Addresses...");

        dexAddresses[0] = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; //arb uniswapV2
        dexAddresses[1] = 0x5E325eDA8064b456f4781070C0738d849c824258; //arb uniswapV3
        dexFunctionSelectors[0] = targetContract.swapOnUniswapV2.selector;
        dexFunctionSelectors[1] = targetContract.swapOnUniswapV2.selector;

        bridgeAddresses[0] = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5; // BungeeAddress
        bridgeFunctionSelectors[0] = targetContract._executeBridge.selector;

        // Impersonate an address with a large balance of tokenA
        address tokenHolder = 0xbDfA4f4492dD7b7Cf211209C4791AF8d52BF5c50; // Replace with a real address holding tokens
        vm.startPrank(tokenHolder);

        // uint256 holderBalanceA = tokenA.balanceOf(tokenHolder);
        // console.log("Token Holder A balance:", holderBalanceA);
        console.log("Transfering the token....");
        // Transfer some tokens to the owner for testing
        tokenA.transfer(owner, 1 * 1e18);
        tokenB.transfer(owner, 1 * 1e18);
        tokenC.transfer(owner, 1 * 1e18);

        vm.stopPrank();

        // console.log("Assigning Tokens...");
        // deal(address(tokenA), owner, 1000 * 1e18);
        // deal(address(tokenB), owner, 1000 * 1e18);
        // deal(address(tokenC), owner, 1000 * 1e18);

        console.log("Checking token balances...");
        uint256 balanceA = tokenA.balanceOf(owner);
        uint256 balanceB = tokenB.balanceOf(owner);
        uint256 balanceC = tokenC.balanceOf(owner);

        console.log("Token A balance:", balanceA);
        console.log("Token B balance:", balanceB);
        console.log("Token C balance:", balanceC);

        require(balanceA > 0, "Token A balance is insufficient");
        require(balanceB > 0, "Token B balance is insufficient");
        require(balanceC > 0, "Token C balance is insufficient");

        console.log("Approving the tokens....");

        tokenA.approve(address(targetContract), 1000 * 1e18);
        tokenB.approve(address(targetContract), 1000 * 1e18);
        tokenC.approve(address(targetContract), 1000 * 1e18);

        console.log("Authorization initiating for Dexes and Bridges....");

        // Set authorized DEXs and bridges
        targetContract.authorizedDex(address(uniswapV2Router), true);
        targetContract.authorizedDex(address(uniswapV3Router), true);
        targetContract.authorizedBridge(bridgeAddresses[0], true);
    }

    function testArbitrageOperation() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA); // Token to be swapped on UniswapV2
        tokens[1] = address(tokenB); // Token to be bridged or swapped on UniswapV3
        tokens[2] = address(tokenC); // Final token after cross-chain operation

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 * 1e18; // Amount for first swap
        amounts[1] = 100 * 1e18; // Amount to be bridged or swapped
        amounts[2] = 100 * 1e18; // Final amount

        address[] memory dexes = new address[](2);
        dexes[0] = address(uniswapV2Router); // First swap on UniswapV2
        dexes[1] = address(uniswapV3Router); // Second swap on UniswapV3

        address[] memory bridges = new address[](1);
        bridges[0] = address(0); // Replace with a real or mock bridge address

        uint16[] memory chainIds = new uint16[](3);
        chainIds[0] = uint16(1); // Mainnet
        chainIds[1] = uint16(1); // For testing, same chain (no actual bridge)
        chainIds[2] = uint16(1); // Continue on Mainnet

        uint256[] memory premiums = new uint256[](3);
        for (uint i = 0; i < amounts.length; i++) {
            premiums[i] = (amounts[i] * 9) / 10000; // Assuming 0.09% fee for Aave V2
        }

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                tokens,
                amounts,
                dexes,
                bridges,
                chainIds,
                owner,
                uint256(1) // Example nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory params = abi.encode(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            owner,
            uint256(1), // Example nonce
            bytes("") // Example signature (not used in this mock setup)
        );

        vm.startPrank(address(lendingPool)); // Simulate Aave calling the contract
        targetContract.executeOperation(
            tokens,
            amounts,
            premiums, // Premiums (mocked)
            owner,
            params
        );
        vm.stopPrank();

        // Assertions to validate the operation
        assertEq(tokenC.balanceOf(address(targetContract)), amounts[2]);
        console.log(
            "Final tokenC balance:",
            tokenC.balanceOf(address(targetContract))
        );
    }
}
