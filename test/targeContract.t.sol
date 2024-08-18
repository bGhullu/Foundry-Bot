// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/_TargetContract.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MainnetForkTest is Test {
    TargetArbitrageContract public targetContract;
    IERC20 public dai;
    IERC20 public usdc;
    IERC20 public weth;

    address owner = address(1);
    address user = address(2);
    address dex1 = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap V2 Router
    address dex2 = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 Router
    address bridge1 = address(3); // Mock bridge address for demonstration
    address bridge2 = address(4); // Mock bridge address for demonstration
    address mainContract = address(5);
    uint16 originalChainId = 1;

    function setUp() public {
        // Fork the mainnet at the latest block
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Initialize real tokens from the mainnet
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
        usdc = IERC20(0xA0b86991C6218b36c1d19D4a2e9Eb0cE3606EB48); // USDC
        weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH

        // Deploy the target contract
        targetContract = new TargetArbitrageContract(
            address(this), // LayerZero endpoint
            address(this), // LendingPool address
            [dex1, dex2], // DEX addresses
            [
                bytes4(
                    keccak256(
                        "swapOnUniswapV2(address,address,uint256,address)"
                    )
                ),
                bytes4(
                    keccak256(
                        "swapOnUniswapV3(address,address,uint24,uint256,address)"
                    )
                )
            ], // DEX function selectors
            [bridge1, bridge2], // Bridge addresses
            [
                bytes4(
                    keccak256("bridgeFunction(address,uint256,uint16,address)")
                ),
                bytes4(
                    keccak256("bridgeFunction(address,uint256,uint16,address)")
                )
            ] // Bridge function selectors
        );

        targetContract.setMainContract(mainContract);

        // Authorize the DEXes and bridges
        targetContract.authorizedDex(dex1, true);
        targetContract.authorizedDex(dex2, true);
        targetContract.authorizedBridge(bridge1, true);
        targetContract.authorizedBridge(bridge2, true);
    }

    function testMainnetForkSingleSwap() public {
        uint256 daiAmount = 1000 * 10 ** 18;

        // Transfer DAI to the contract
        deal(address(dai), address(targetContract), daiAmount);

        address;
        tokens[0] = address(dai);
        tokens[1] = address(usdc);

        uint256;
        amounts[0] = daiAmount;

        address;
        dexes[0] = dex1;

        address;

        uint16;
        chainIds[0] = originalChainId;

        targetContract.executeArbitrage(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            user,
            1,
            "", // Placeholder signature
            originalChainId
        );

        uint256 usdcBalance = usdc.balanceOf(address(targetContract));
        assertTrue(
            usdcBalance > 0,
            "USDC balance should be greater than 0 after swap"
        );
    }
}
