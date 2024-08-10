// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";

// contract MockUniswapV3Router is ISwapRouter {
//     function exactInputSingle(
//         ExactInputSingleParams calldata params
//     ) external override returns (uint256 amountOut) {
//         // For simplicity, assume a 1:1 swap ratio in the mock
//         amountOut = params.amountIn;

//         // Transfer the input tokens to the contract
//         IERC20(params.tokenIn).transferFrom(
//             msg.sender,
//             address(this),
//             params.amountIn
//         );

//         // Transfer the output tokens to the recipient
//         IERC20(params.tokenOut).transfer(params.recipient, amountOut);
//     }
// }
