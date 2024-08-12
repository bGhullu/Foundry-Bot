// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";

contract MockUniswapV3Router is ISwapRouter {
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external override returns (uint256 amountOut) {
        // Simulate a swap by transferring the input token to the contract
        IERC20(params.tokenIn).transferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Simulate output by minting the output token to the `recipient`
        amountOut = params.amountIn; // Simulate a 1:1 swap rate for simplicity
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
    }

    // Implement other functions of ISwapRouter interface with mock behavior or empty bodies

    function exactInput(
        ExactInputParams calldata params
    ) external override returns (uint256 amountOut) {
        // Mock implementation
        amountOut = params.amountIn; // Simulate a 1:1 swap rate for simplicity
    }

    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external override returns (uint256 amountIn) {
        // Mock implementation
        amountIn = params.amountOut; // Simulate a 1:1 swap rate for simplicity
    }

    function exactOutput(
        ExactOutputParams calldata params
    ) external override returns (uint256 amountIn) {
        // Mock implementation
        amountIn = params.amountOut; // Simulate a 1:1 swap rate for simplicity
    }
}
