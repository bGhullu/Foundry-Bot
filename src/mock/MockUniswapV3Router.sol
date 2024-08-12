// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";

abstract contract MockUniswapV3Router is ISwapRouter {
    // Event to log swaps for testing purposes
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // Simulate a swap by transferring the input token to the contract
        IERC20(params.tokenIn).transferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Simulate output by transferring the output token to the `recipient`
        amountOut = params.amountIn; // Simulate a 1:1 swap rate for simplicity
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);

        emit SwapExecuted(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut
        );
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // Decode the path into addresses
        address tokenIn;
        address tokenOut;

        bytes memory path = params.path;
        assembly {
            tokenIn := mload(add(path, 20))
            tokenOut := mload(add(add(path, 20), 20))
        }

        // Simulate exact input for a swap
        IERC20(tokenIn).transferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Simulate output by transferring the output token to the `recipient`
        amountOut = params.amountIn; // Simulate a 1:1 swap rate for simplicity
        IERC20(tokenOut).transfer(params.recipient, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, params.amountIn, amountOut);
    }

    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable override returns (uint256 amountIn) {
        // Simulate exact output single swap
        amountIn = params.amountOut; // Simulate a reverse swap rate for simplicity
        IERC20(params.tokenIn).transferFrom(
            msg.sender,
            address(this),
            amountIn
        );

        // Simulate output by transferring the output token to the `recipient`
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);

        emit SwapExecuted(
            params.tokenIn,
            params.tokenOut,
            amountIn,
            params.amountOut
        );
    }

    function exactOutput(
        ExactOutputParams calldata params
    ) external payable override returns (uint256 amountIn) {
        // Decode the path into addresses
        address tokenIn;
        address tokenOut;

        bytes memory path = params.path;
        assembly {
            tokenIn := mload(add(path, 20))
            tokenOut := mload(add(add(path, 20), 20))
        }

        // Simulate exact output swap
        amountIn = params.amountOut; // Simulate a reverse swap rate for simplicity
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Simulate output by transferring the output token to the `recipient`
        IERC20(tokenOut).transfer(params.recipient, params.amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, params.amountOut);
    }
}
