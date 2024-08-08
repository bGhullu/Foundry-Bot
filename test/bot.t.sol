// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/ArbitrageBot.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ArbitrageBotTest is Test {
    using ECDSA for bytes32;

    ArbitrageBot public arbitrageBot;
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // Replace with your LayerZero endpoint address
    address public peerAddress = 0x1234567890123456789012345678901234567890; // Replace with a valid peer address
    string rpcUrl = vm.envString("rpc_url");
    bytes32 privateKey = vm.envBytes32("private_key");

    function setUp() public {
        vm.createSelectFork(rpcUrl, 239609138);

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        arbitrageBot = new ArbitrageBot(endpoint, owner);

        // Set the peer for chainId 1
        vm.prank(owner);
        arbitrageBot.setChainToArbitrageContract(1, peerAddress);
    }

    function testDeploy() public view {
        assertEq(arbitrageBot.owner(), owner);
        assertEq(arbitrageBot.getEndPoint(), endpoint);
    }

    function testSetChainToArbitrageContract() public {
        uint16 chainId = 1;
        address contractAddr = address(
            0x1230000000000000000000000000000000000000
        );

        vm.prank(owner);
        arbitrageBot.setChainToArbitrageContract(chainId, contractAddr);

        bytes32 expectedPeer = bytes32(uint256(uint160(contractAddr)));
        assertEq(arbitrageBot.peers(chainId), expectedPeer);
    }

    function testExecuteCrossChainArbitrage() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0x1111111111111111111111111111111111111111);
        tokens[1] = address(0x2222222222222222222222222222222222222222);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000;
        amounts[1] = 2000;
        address[] memory dexes = new address[](2);
        dexes[0] = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        dexes[1] = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
        address[] memory bridges = new address[](2);
        bridges[0] = 0x0b2402144Bb366A632D14B83F244D2e0e21bD39c;
        bridges[1] = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;
        uint16[] memory chainIds = new uint16[](2);
        chainIds[0] = 1;
        chainIds[1] = 2;
        address recipient = address(0x4444444444444444444444444444444444444444);
        uint256 nonce = 1;

        bytes32 messageHash = arbitrageBot.getMessageHash(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(privateKey),
            ethSignedMessageHash
        );

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.deal(owner, 1 ether);

        vm.prank(owner);
        arbitrageBot.executeCrossChainArbitrage{value: 0.1 ether}(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce,
            signature
        );

        // Validate the state changes
        ArbitrageBot.ArbParams memory arbParams = arbitrageBot.getArbParams();
        assertEq(arbParams.tokens[0], tokens[0]);
        assertEq(arbParams.tokens[1], tokens[1]);
        assertEq(arbParams.amounts[0], amounts[0]);
        assertEq(arbParams.amounts[1], amounts[1]);
        assertEq(arbParams.dexes[0], dexes[0]);
        assertEq(arbParams.dexes[1], dexes[1]);
        assertEq(arbParams.chainIds[0], chainIds[0]);
        assertEq(arbParams.recipient, recipient);
        assertEq(arbParams.nonce, nonce);
        assertEq(arbParams.signature, signature);

        // Ensure the owner is correctly validated
        bytes32 computedMessageHash = arbitrageBot.getMessageHash(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce
        );
        bytes32 expectedMessageHash = keccak256(
            abi.encodePacked(
                tokens,
                amounts,
                dexes,
                bridges,
                chainIds,
                recipient,
                nonce
            )
        );
        assertEq(computedMessageHash, expectedMessageHash);

        bytes32 computedEthSignedMessageHash = MessageHashUtils
            .toEthSignedMessageHash(computedMessageHash);
        address computedSigner = ECDSA.recover(
            computedEthSignedMessageHash,
            signature
        );
        assertEq(computedSigner, owner);
    }
}
