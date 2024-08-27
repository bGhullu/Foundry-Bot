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

    /**
     * @notice mainnet address
     */
    IERC20 public constant DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /**
     * @notice arbitrum address
     */
    address public constant UNISWAP_V2_ROUTER =
        0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address public constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // 0x5E325eDA8064b456f4781070C0738d849c824258;
    // IERC20 public constant WETH =
    //     IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    // IERC20 public constant USDC =
    //     IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // Arb USDC
    // IERC20 public constant DAI =
    //     IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

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
        uint256 amountOutMin = 2000e6; //

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
        uint256 amountIn = 1e18;
        uint256 amountOutMin = 2000e6;
        uint24 fee = 3000;

        arbitrageContract.swapOnUniswapV3(
            address(WETH),
            address(USDC),
            amountIn,
            amountOutMin,
            fee
        );

        uint256 UsdcBalance = USDC.balanceOf(address(this));
        console.log("USDC balance:", UsdcBalance);
        assertGt(
            UsdcBalance,
            amountOutMin,
            "USDC balance should be greater than amountOutMin"
        );
    }

    function testMultihopSwapOnUniswapV3() public {
        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0;
        uint24 fee = 3000;
        bytes memory path = abi.encode(
            address(WETH),
            fee,
            address(USDC),
            fee,
            address(DAI)
        );
        arbitrageContract.multiSwapOnUniswapV3(path, amountIn);

        uint256 UsdcBalance = USDC.balanceOf(address(this));
        uint256 daiBalance = DAI.balanceOf(address(this));
        console.log("DAI balance:", daiBalance);
    }
}
