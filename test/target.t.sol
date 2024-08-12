// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/_TargetChainArbitrage.sol";
import "../src/mock/MockERC20.sol";
import "../src/mock/MockEndpoint.sol";
import "../src/mocK/MockLending.sol";
import "../src/mock/MockUniswapV2Router.sol";
import "../src/mock/MockPancakeRouter.sol";
import "../src/mock/MockBridge.sol";

contract TargetArbitrageContractTest is Test {
    TargetArbitrageContract public targetContract;
    MockLZEndpoint public mockEndpoint;
    MockLendingPool public mockPool;
    Token public tokenA;
    Token public tokenB;
    MockUniswapV2Router public mockUniswapV2; // Uniswap V2 mock for Uniswap-like DEXes
    MockPancakeRouter public mockPancakeRouter; // PancakeSwap mock
    MockBridge public mockBridge;

    address owner = address(0x123);
    address mainContract = address(0x456);

    function setUp() public {
        // Deploy mocks
        mockEndpoint = new MockLZEndpoint();
        mockPool = new MockLendingPool();
        tokenA = new Token("Token A", "TKA");
        tokenB = new Token("Token B", "TKB");
        mockUniswapV2 = new MockUniswapV2Router();
        mockPancakeRouter = new MockPancakeRouter(); // Use the PancakeSwap mock
        mockBridge = new MockBridge();

        // Deploy the TargetArbitrageContract
        address[] memory dexAddresses;
        dexAddresses[0] = address(mockUniswapV2);
        dexAddresses[1] = address(mockPancakeRouter); // Use PancakeSwap instead of Uniswap V3

        bytes4[] memory dexFunctionSelectors;
        dexFunctionSelectors[0] = targetContract.swapOnUniswapV2.selector;
        dexFunctionSelectors[1] = targetContract.swapOnPancakeSwap.selector; // Use PancakeSwap function

        address[] memory bridgeAddresses;
        bridgeAddresses[0] = address(mockBridge);

        bytes4[] memory bridgeFunctionSelectors;
        bridgeFunctionSelectors[0] = bytes4(
            keccak256("transferToChain(address,uint256,uint16,address)")
        );

        targetContract = new TargetArbitrageContract(
            address(mockEndpoint),
            address(mockPool),
            dexAddresses,
            dexFunctionSelectors,
            bridgeAddresses,
            bridgeFunctionSelectors
        );

        // Set main contract
        targetContract.setMainContract(mainContract);
    }

    // Other test functions remain the same...

    function testExecuteSwapOnPancakeSwap() public {
        vm.startPrank(owner);
        targetContract.authorizedDex(address(mockPancakeRouter), true);
        tokenA.transfer(address(targetContract), 1e18);

        address[] memory tokens;
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts;
        amounts[0] = 1e18;

        address[] memory dexes;
        dexes[0] = address(mockPancakeRouter);

        bytes memory params = abi.encode(tokens, amounts, dexes, owner);
        targetContract.executeOperation(
            tokens,
            amounts,
            amounts,
            owner,
            params
        );

        assertEq(tokenB.balanceOf(address(targetContract)), 1e18);
        vm.stopPrank();
    }
}
