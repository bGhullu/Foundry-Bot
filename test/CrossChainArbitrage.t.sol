//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";

import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";
import "../src/CrossChainArbitrage.sol";
import "forge-std/console.sol";

contract TesCrossChainArbitrage is Test {
    CrossChainArbitrage public arbitrageContract;

    address public owner;

    address public constant UNISWAP_V2_ROUTER =
        0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address public constant UNISWAP_V3_ROUTER =
        0x5E325eDA8064b456f4781070C0738d849c824258;
    IERC20 public constant WETH =
        IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant USDC =
        IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // Arb USDC
    IERC20 public constant DAI =
        IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

    function setUp() public {
        owner = msg.sender;
        arbitrageContract = new CrossChainArbitrage(
            IUniswapV2Router02(UNISWAP_V2_ROUTER),
            ISwapRouter(UNISWAP_V3_ROUTER)
        );

        // Transfer some tokens to the test contract for swapping
        deal(address(WETH), address(this), 20000 ether); // Set an appropriate amount

        // Approve the CrossChainArbitrage contract to spend tokens
        WETH.approve(address(arbitrageContract), type(uint256).max);
    }

    function testSwapOnUniswapV2() public {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOutMin = 200e6; // Minimum of 1000 USDC

        // Add an appropriate path for the Uniswap V2 swap
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);

        arbitrageContract.swapOnUniswapV2(
            address(WETH),
            address(USDC),
            amountIn,
            amountOutMin,
            path
        );

        uint256 UsdcBalance = IERC20(USDC).balanceOf(address(this));
        assertGt(
            UsdcBalance,
            amountOutMin,
            "USDC balance should be greater than amountOutMin"
        );
    }

    function testSwapOnUniswapV3() public {
        uint256 amountIn = 1 ether;
        uint256 amountOutMin = 0;
        uint24 fee = 500;

        arbitrageContract.swapOnUniswapV3(
            address(WETH),
            address(USDC),
            amountIn,
            amountOutMin,
            fee
        );

        uint256 UsdcBalance = IERC20(USDC).balanceOf(address(this));
        assertGt(
            UsdcBalance,
            amountOutMin,
            "USDC balance should be greater than amountOutMin"
        );
    }
}
