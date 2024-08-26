// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/cross_chain/_TargetChainArbitrage.sol";
import "../src/mock/MockERC20.sol";
import "../src/mock/MockLending.sol";
import "../src/mock/MockEndpoint.sol";
import "../src/mock/MockUniswapV2Router.sol";
import "../src/mock/MockPancakeRouter.sol";
import "../src/mock/MockBridge.sol";

contract TargetArbitrageContractTest is Test {
    TargetArbitrageContract public targetContract1;
    TargetArbitrageContract public targetContract2;
    MockLZEndpoint public mockEndpoint1;
    MockLZEndpoint public mockEndpoint2;
    MockLendingPool public mockPool;
    Token public tokenA;
    Token public tokenB;
    Token public tokenC;
    MockUniswapV2Router public mockUniswapV2;
    MockPancakeRouter public mockPancakeRouter;
    MockBridge public mockBridge;

    address public owner = address(this);
    address public mainContract = address(0x456);

    function setUp() public {
        // Deploy mocks
        mockEndpoint1 = new MockLZEndpoint();
        mockEndpoint2 = new MockLZEndpoint();
        mockPool = new MockLendingPool();
        tokenA = new Token("Token A", "TKA");
        tokenB = new Token("Token B", "TKB");
        tokenC = new Token("Token C", "TKC");
        mockUniswapV2 = new MockUniswapV2Router();
        mockPancakeRouter = new MockPancakeRouter();
        mockBridge = new MockBridge();

        // Mint tokens for testing
        tokenA.mint(address(this), 1e18);
        tokenB.mint(address(this), 1e18);
        tokenC.mint(address(this), 1e18);

        tokenB.mint(address(mockUniswapV2), 1e18);
        tokenB.mint(address(mockPancakeRouter), 1e18);

        tokenC.mint(address(mockUniswapV2), 1e18);
        tokenC.mint(address(mockPancakeRouter), 1e18);

        // Initialize the arrays
        address[] memory dexAddresses = new address[](2);
        dexAddresses[0] = address(mockUniswapV2);
        dexAddresses[1] = address(mockPancakeRouter);

        bytes4[] memory dexFunctionSelectors = new bytes4[](2);
        dexFunctionSelectors[0] = bytes4(
            keccak256("swapOnUniswapV2(address,address,uint256,address)")
        );
        dexFunctionSelectors[1] = bytes4(
            keccak256("swapOnPancakeSwap(address,address,uint256,address)")
        );

        address[] memory bridgeAddresses = new address[](1);
        bridgeAddresses[0] = address(mockBridge);

        bytes4[] memory bridgeFunctionSelectors = new bytes4[](1);
        bridgeFunctionSelectors[0] = bytes4(
            keccak256("transferToChain(address,uint256,uint16,address)")
        );

        // Deploy two instances of the TargetArbitrageContract to simulate two chains
        targetContract1 = new TargetArbitrageContract(
            address(mockEndpoint1),
            address(mockPool),
            dexAddresses,
            dexFunctionSelectors,
            bridgeAddresses,
            bridgeFunctionSelectors
        );

        targetContract2 = new TargetArbitrageContract(
            address(mockEndpoint2),
            address(mockPool),
            dexAddresses,
            dexFunctionSelectors,
            bridgeAddresses,
            bridgeFunctionSelectors
        );

        // Set peers
        mockEndpoint1.setPeer(
            uint16(block.chainid + 1),
            address(mockEndpoint2)
        );
        mockEndpoint2.setPeer(uint16(block.chainid), address(mockEndpoint1));

        // Set main contracts
        targetContract1.setMainContract(mainContract);
        targetContract2.setMainContract(mainContract);

        // Authorize DEXes and Bridges
        targetContract1.authorizedDex(address(mockUniswapV2), true);
        targetContract1.authorizedBridge(address(mockBridge), true);
        targetContract2.authorizedDex(address(mockPancakeRouter), true);

        // Approve tokens
        tokenB.approve(address(targetContract1), 1e18);
        tokenB.approve(address(targetContract2), 1e18);
        tokenB.approve(address(mockBridge), 1e18);
    }

    function testCrossChainSwapBridgeSwap() public {
        // Transfer tokens to targetContract1
        tokenA.transfer(address(targetContract1), 1e18);
        tokenB.transfer(address(targetContract1), 1e18);
        tokenC.transfer(address(targetContract1), 1e18);

        // Set up initial parameters for swap, bridge, and swap
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA); // First swap on UniswapV2
        tokens[1] = address(tokenB); // TokenB to be bridged
        tokens[2] = address(tokenC); // TokenC to be swapped on the next chain

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e5; // Amount for first swap
        amounts[1] = 1e5; // Amount to bridge
        amounts[2] = 1e5; // Amount for second swap on the next chain

        address[] memory dexes = new address[](2);
        dexes[0] = address(mockUniswapV2); // First swap on UniswapV2
        dexes[1] = address(mockPancakeRouter); // Second swap on PancakeSwap (next chain)

        address[] memory bridges = new address[](1);
        bridges[0] = address(mockBridge); // Bridge operation

        uint16[] memory chainIds = new uint16[](3);
        chainIds[0] = uint16(block.chainid); // Current chain
        chainIds[1] = uint16(block.chainid + 1); // Next chain (for bridging)
        chainIds[2] = uint16(block.chainid + 1); // Continue on the next chain

        // Encode parameters for the first part of the operation
        bytes memory params = abi.encode(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            owner
        );

        // Simulate the first operation (swap and prepare for bridge)
        vm.startPrank(address(mockPool));
        targetContract1.executeOperation(
            tokens,
            amounts,
            amounts,
            owner,
            params
        );
        vm.stopPrank();

        // Create new arrays starting from the second element of the original arrays
        address[] memory remainingTokens = new address[](tokens.length - 1);
        uint256[] memory remainingAmounts = new uint256[](amounts.length - 1);
        address[] memory remainingDexes = new address[](dexes.length - 1);
        uint16[] memory remainingChainIds = new uint16[](chainIds.length - 1);

        for (uint i = 1; i < tokens.length; i++) {
            remainingTokens[i - 1] = tokens[i];
            remainingAmounts[i - 1] = amounts[i];
        }

        for (uint i = 1; i < dexes.length; i++) {
            remainingDexes[i - 1] = dexes[i];
        }

        for (uint i = 1; i < chainIds.length; i++) {
            remainingChainIds[i - 1] = chainIds[i];
        }

        // Prepare payload for the next chain
        bytes memory nextPayload = abi.encode(
            remainingTokens,
            remainingAmounts,
            remainingDexes,
            bridges,
            remainingChainIds,
            owner
        );

        // Simulate sending the payload to the next chain using lzSend
        vm.startPrank(address(mockEndpoint1));
        // targetContract1.lzSend(chainIds[1], nextPayload);
        vm.stopPrank();

        // Simulate receiving the payload on the second chain
        // vm.startPrank(address(mockEndpoint2));
        // targetContract2.lzReceive(
        //     uint16(block.chainid),
        //     address(targetContract1),
        //     nextPayload
        // );
        // vm.stopPrank();

        // Assertions to verify the operations
        assertEq(tokenB.balanceOf(address(mockBridge)), amounts[1]); // After bridge
        assertEq(tokenC.balanceOf(address(targetContract2)), amounts[2]); // After second swap
    }
}
