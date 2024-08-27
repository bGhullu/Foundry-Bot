// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Importing interfaces and contracts from OpenZeppelin and Uniswap libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

/**
 * @title SwapOnUniswap
 * @author B. GHULLU
 * @dev A contract to perform token swaps on Uniswap V2 and V3.
 * This contract allows the owner to swap tokens using Uniswap V2 and V3 routers.
 */
contract SwapOnUniswap is Ownable {
    // Uniswap V2 Router contract interface
    IUniswapV2Router02 public uniswapV2Router;

    // Uniswap V3 Router contract interface
    ISwapRouter public uniswapV3Router;

    /**
     * @dev Initializes the contract by setting Uniswap V2 and V3 router addresses.
     * @param _uniswapV2Router Address of the Uniswap V2 router contract
     * @param _uniswapV3Router Address of the Uniswap V3 router contract
     */
    constructor(
        IUniswapV2Router02 _uniswapV2Router,
        ISwapRouter _uniswapV3Router
    ) Ownable(msg.sender) {
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
    }

    /**
     * @dev Swaps a specific amount of tokens on Uniswap V2.
     * The function allows the contract owner to swap tokens using the Uniswap V2 router.
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of the input token to be swapped
     * @param amountOutMin Minimum amount of output tokens expected
     * @param path Array of token addresses representing the swap path
     * @return amounts The amounts of tokens swapped
     */
    function swapOnUniswapV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external onlyOwner returns (uint256[] memory amounts) {
        // Transfer the specified amount of input tokens from the owner to the contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // Approve the Uniswap V2 router to spend the input tokens
        IERC20(tokenIn).approve(address(uniswapV2Router), amountIn);

        // Execute the swap on Uniswap V2 and return the amounts of tokens received
        amounts = uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );
        return amounts;
    }

    /**
     * @dev Swaps a specific amount of tokens on Uniswap V3.
     * The function allows the contract owner to swap tokens using the Uniswap V3 router.
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of the input token to be swapped
     * @param amountOutMin Minimum amount of output tokens expected
     * @param fee The fee tier to use for the pool (e.g., 3000 for 0.3%)
     * @return amountOut The amount of output tokens received
     */
    function swapOnUniswapV3(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint24 fee
    ) external onlyOwner returns (uint256 amountOut) {
        // Transfer the specified amount of input tokens from the owner to the contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // Approve the Uniswap V3 router to spend the input tokens
        IERC20(tokenIn).approve(address(uniswapV3Router), amountIn);

        // Define the swap parameters for Uniswap V3
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

        // Execute the swap on Uniswap V3 and return the amount of tokens received
        amountOut = uniswapV3Router.exactInputSingle(params);
    }

    /**
     * @dev Swaps a specific amount of tokens on Uniswap V3 using a multi-hop path.
     * This function allows the caller to swap tokens through multiple pairs in a single transaction on Uniswap V3.
     * @param path The encoded path for the swap, including token addresses and pool fees.
     * @param amountIn The amount of the input token to be swapped.
     * @return amountOut The amount of the output token received from the swap.
     */
    function multiSwapOnUniswapV3(
        bytes calldata path,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // Decode the first token and intermediate data from the path
        (
            address token1,
            uint24 fee1,
            address token2,
            uint24 fee2,
            address token3
        ) = abi.decode(path, (address, uint24, address, uint24, address));

        // Log the first token address
        console.log("Token1:");
        console.logAddress(token1);

        // Transfer the input token from the sender to this contract
        IERC20(token1).transferFrom(msg.sender, address(this), amountIn);

        // Log the contract's balance of the input token
        console.log("WETH balance of");
        console.logAddress(address(this));
        console.log(IERC20(token1).balanceOf(address(this)));

        // Approve the Uniswap V3 router to spend the input token
        IERC20(token1).approve(address(uniswapV3Router), amountIn);

        // Define the full path for the multi-hop swap, including token addresses and pool fees
        bytes memory _path = abi.encodePacked(
            token1,
            fee1,
            token2,
            fee2,
            token3
        );

        // Set the parameters for the multi-hop swap on Uniswap V3
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: _path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            });

        // Execute the multi-hop swap and store the output amount
        amountOut = uniswapV3Router.exactInput(params);

        // Return the amount of output tokens received
        return amountOut;
    }
}
