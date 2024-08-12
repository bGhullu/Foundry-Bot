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
        mockPancakeRouter = new MockPancakeRouter();
        mockBridge = new MockBridge();

        // Log statements to trace execution
        console.log("Mocks deployed.");

        tokenA.mint(address(this), 1e18);
        tokenB.mint(address(this), 1e18);

        // Initialize the arrays
        address[] memory dexAddresses = new address[](2);
        dexAddresses[0] = address(mockUniswapV2);
        dexAddresses[1] = address(mockPancakeRouter);
        console.log("DEX addresses initialized.");

        bytes4[] memory dexFunctionSelectors = new bytes4[](2);
        dexFunctionSelectors[0] = bytes4(
            keccak256("swapOnUniswapV2(address,address,uint256,address)")
        );
        dexFunctionSelectors[1] = bytes4(
            keccak256("swapOnPancakeSwap(address,address,uint256,address)")
        );
        console.log("DEX function selectors initialized.");

        address[] memory bridgeAddresses = new address[](1);
        bridgeAddresses[0] = address(mockBridge);
        console.log("Bridge addresses initialized.");

        bytes4[] memory bridgeFunctionSelectors = new bytes4[](1);
        bridgeFunctionSelectors[0] = bytes4(
            keccak256("transferToChain(address,uint256,uint16,address)")
        );
        console.log("Bridge function selectors initialized.");

        // Check lengths before proceeding
        require(dexAddresses.length == 2, "dexAddresses array length mismatch");
        require(
            dexFunctionSelectors.length == 2,
            "dexFunctionSelectors array length mismatch"
        );
        require(
            bridgeAddresses.length == 1,
            "bridgeAddresses array length mismatch"
        );
        require(
            bridgeFunctionSelectors.length == 1,
            "bridgeFunctionSelectors array length mismatch"
        );

        // Deploy the TargetArbitrageContract with initialized arrays
        targetContract = new TargetArbitrageContract(
            address(mockEndpoint),
            address(mockPool),
            dexAddresses,
            dexFunctionSelectors,
            bridgeAddresses,
            bridgeFunctionSelectors
        );
        console.log("TargetArbitrageContract deployed.");

        // Set main contract
        targetContract.setMainContract(mainContract);
        console.log("Main contract set.");
    }

    // Other test functions remain the same...
    function testInitialization() public {
        owner = address(this);
        vm.prank(owner);
        assertEq(targetContract.mainContract(), mainContract);
        assertEq(address(targetContract.lendingPool()), address(mockPool));

        bytes4 uniswapV2Selector = targetContract.dexFunctionMapping(
            address(mockUniswapV2)
        );
        assertEq(uniswapV2Selector, targetContract.swapOnUniswapV2.selector);

        bytes4 pancakeswapSelector = targetContract.dexFunctionMapping(
            address(mockPancakeRouter)
        );
        assertEq(
            pancakeswapSelector,
            targetContract.swapOnPancakeSwap.selector
        );
    }

    function testSetDexFunction() public {
        owner = address(this);
        address newDex = address(0x789);
        bytes4 newSelector = bytes4(keccak256("newDexFunction(address)"));
        vm.prank(owner);
        targetContract.setDexFunction(newDex, newSelector);
        assertEq(targetContract.dexFunctionMapping(newDex), newSelector);
    }

    function testAuthorizeDex() public {
        owner = address(this);
        address newDex = address(0x789);
        vm.prank(owner);
        targetContract.authorizedDex(newDex, true);
        assertTrue(targetContract.authorizedDexes(newDex));

        vm.prank(owner);
        targetContract.authorizedDex(newDex, false);
        assertFalse(targetContract.authorizedDexes(newDex));
    }

    function testUnauthorizedCaller() public {
        vm.prank(address(0x999));
        vm.expectRevert("Ownable:caller is not the owner");
        targetContract.setMainContract(address(0x888));
    }

    function testFlashLoan() public {
        owner = address(this);
        // Set up a basic flash loan scenario
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        address[] memory dexes = new address[](1);
        dexes[0] = address(mockUniswapV2);

        vm.prank(owner);
        targetContract.authorizedDex(address(mockUniswapV2), true);
        tokenA.mint(address(targetContract), 1e18);
        tokenA.transfer(address(targetContract), 1e18);
        vm.startPrank(address(mockPool));
        targetContract.executeOperation(
            tokens,
            amounts,
            amounts,
            owner,
            abi.encode(tokens, amounts, dexes, owner)
        );

        //  targetContract._initiateFlashLoan(tokens, amounts, dexes, owner);
        vm.stopPrank();
    }

    function testExecuteSwapOnUniswapV2() public {
        owner = address(this);
        vm.startPrank(owner);
        targetContract.authorizedDex(address(mockUniswapV2), true);
        tokenA.transfer(address(targetContract), 1e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;

        address[] memory dexes = new address[](1);
        dexes[0] = address(mockUniswapV2);

        bytes memory params = abi.encode(tokens, amounts, dexes, owner);
        vm.startPrank(address(mockPool));
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

    function testExecuteSwapOnPancakeSwap() public {
        owner = address(this);
        vm.startPrank(owner);
        targetContract.authorizedDex(address(mockPancakeRouter), true);
        tokenA.transfer(address(targetContract), 1e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;

        address[] memory dexes = new address[](1);
        dexes[0] = address(mockPancakeRouter);

        bytes memory params = abi.encode(tokens, amounts, dexes, owner);
        vm.startPrank(address(mockPool));
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
