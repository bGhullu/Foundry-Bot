// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";

// contract MockUniswapV2Router is IUniswapV2Router02 {
//     function swapExactTokensForTokens(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address to,
//         uint256 deadline
//     ) external override returns (uint256[] memory amounts) {
//         // Simulate a 1:1 swap ratio
//         amounts = new uint256[](path.length);
//         amounts[0] = amountIn;
//         amounts[1] = amountIn; // 1:1 swap ratio

//         // Transfer the input tokens to the contract
//         IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

//         // Transfer the output tokens to the recipient
//         IERC20(path[1]).transfer(to, amounts[1]);
//     }

//     function swapExactETHForTokens(
//         uint256 amountOutMin,
//         address[] calldata path,
//         address to,
//         uint256 deadline
//     ) external payable override returns (uint256[] memory amounts) {
//         // Simulate a 1:1 swap ratio for ETH to Tokens
//         amounts = new uint256[](path.length);
//         amounts[0] = msg.value;
//         amounts[1] = msg.value; // 1:1 swap ratio

//         // Transfer the output tokens to the recipient
//         IERC20(path[1]).transfer(to, amounts[1]);
//     }

//     function swapExactTokensForETH(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address to,
//         uint256 deadline
//     ) external override returns (uint256[] memory amounts) {
//         // Simulate a 1:1 swap ratio for ETH
//         amounts = new uint256[](path.length);
//         amounts[0] = amountIn;
//         amounts[1] = amountIn; // 1:1 swap ratio

//         // Transfer the input tokens to the contract
//         IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

//         // Simulate sending ETH to the recipient
//         payable(to).transfer(amounts[1]);
//     }

//     function addLiquidity(
//         address tokenA,
//         address tokenB,
//         uint256 amountADesired,
//         uint256 amountBDesired,
//         uint256 amountAMin,
//         uint256 amountBMin,
//         address to,
//         uint256 deadline
//     )
//         external
//         override
//         returns (uint256 amountA, uint256 amountB, uint256 liquidity)
//     {
//         // In a real implementation, this function would calculate liquidity.
//         // Here, we simply return the desired amounts and mock liquidity.
//         amountA = amountADesired;
//         amountB = amountBDesired;
//         liquidity = amountADesired + amountBDesired; // Simple mock logic
//     }

//     function removeLiquidity(
//         address tokenA,
//         address tokenB,
//         uint256 liquidity,
//         uint256 amountAMin,
//         uint256 amountBMin,
//         address to,
//         uint256 deadline
//     ) external override returns (uint256 amountA, uint256 amountB) {
//         // In a real implementation, this function would return the amount of tokens.
//         // Here, we simply mock returning liquidity as the amount.
//         amountA = liquidity / 2;
//         amountB = liquidity / 2;

//         // Transfer tokens back to the recipient
//         IERC20(tokenA).transfer(to, amountA);
//         IERC20(tokenB).transfer(to, amountB);
//     }

//     function removeLiquidityETH(
//         address token,
//         uint256 liquidity,
//         uint256 amountTokenMin,
//         uint256 amountETHMin,
//         address to,
//         uint256 deadline
//     ) external override returns (uint256 amountToken, uint256 amountETH) {
//         // In a real implementation, this function would return the amount of tokens and ETH.
//         // Here, we simply mock returning liquidity as the amount.
//         amountToken = liquidity / 2;
//         amountETH = liquidity / 2;

//         // Transfer tokens back to the recipient
//         IERC20(token).transfer(to, amountToken);

//         // Simulate sending ETH to the recipient
//         payable(to).transfer(amountETH);
//     }

//     function removeLiquidityETHSupportingFeeOnTransferTokens(
//         address token,
//         uint256 liquidity,
//         uint256 amountTokenMin,
//         uint256 amountETHMin,
//         address to,
//         uint256 deadline
//     ) external override returns (uint256 amountETH) {
//         // In a real implementation, this function would return the amount of ETH.
//         // Here, we simply mock returning liquidity as the amount.
//         amountETH = liquidity / 2;

//         // Simulate sending ETH to the recipient
//         payable(to).transfer(amountETH);
//     }

//     function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
//         address token,
//         uint256 liquidity,
//         uint256 amountTokenMin,
//         uint256 amountETHMin,
//         address to,
//         uint256 deadline,
//         bool approveMax,
//         uint8 v,
//         bytes32 r,
//         bytes32 s
//     ) external override returns (uint256 amountETH) {
//         // Permit-related parameters are ignored in this mock implementation
//         amountETH = liquidity / 2;

//         // Simulate sending ETH to the recipient
//         payable(to).transfer(amountETH);
//     }

//     function swapExactTokensForTokensSupportingFeeOnTransferTokens(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address to,
//         uint256 deadline
//     ) external override {
//         // Simulate a 1:1 swap ratio
//         uint256 amountOut = amountIn; // 1:1 swap ratio

//         // Transfer the input tokens to the contract
//         IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

//         // Transfer the output tokens to the recipient
//         IERC20(path[1]).transfer(to, amountOut);
//     }

//     function swapExactETHForTokensSupportingFeeOnTransferTokens(
//         uint256 amountOutMin,
//         address[] calldata path,
//         address to,
//         uint256 deadline
//     ) external payable override {
//         // Simulate a 1:1 swap ratio for ETH to Tokens
//         uint256 amountOut = msg.value; // 1:1 swap ratio

//         // Transfer the output tokens to the recipient
//         IERC20(path[1]).transfer(to, amountOut);
//     }

//     function swapExactTokensForETHSupportingFeeOnTransferTokens(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address to,
//         uint256 deadline
//     ) external override {
//         // Simulate a 1:1 swap ratio for ETH
//         uint256 amountOut = amountIn; // 1:1 swap ratio

//         // Transfer the input tokens to the contract
//         IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

//         // Simulate sending ETH to the recipient
//         payable(to).transfer(amountOut);
//     }

//     function getAmountsOut(
//         uint256 amountIn,
//         address[] calldata path
//     ) external view override returns (uint256[] memory amounts) {
//         // Simulate a 1:1 output amount for the input
//         amounts = new uint256[](path.length);
//         amounts[0] = amountIn;
//         amounts[1] = amountIn;
//     }

//     function getAmountsIn(
//         uint256 amountOut,
//         address[] calldata path
//     ) external view override returns (uint256[] memory amounts) {
//         // Simulate a 1:1 input amount for the output
//         amounts = new uint256[](path.length);
//         amounts[0] = amountOut;
//         amounts[1] = amountOut;
//     }

//     // Other required functions can be implemented similarly

//     function addLiquidityETH(
//         address token,
//         uint256 amountTokenDesired,
//         uint256 amountTokenMin,
//         uint256 amountETHMin,
//         address to,
//         uint256 deadline
//     )
//         external
//         payable
//         override
//         returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
//     {
//         amountToken = amountTokenDesired;
//         amountETH = msg.value;
//         liquidity = amountTokenDesired + msg.value; // Simple mock logic

//         // Transfer the tokens to the contract
//         IERC20(token).transferFrom(msg.sender, address(this), amountToken);

//         // Simulate sending ETH to the contract
//     }

//     function removeLiquidityETHWithPermit(
//         address token,
//         uint256 liquidity,
//         uint256 amountTokenMin,
//         uint256 amountETHMin,
//         address to,
//         uint256 deadline,
//         bool approveMax,
//         uint8 v,
//         bytes32 r,
//         bytes32 s
//     ) external override returns (uint256 amountToken, uint256 amountETH) {
//         amountToken = liquidity / 2;
//         amountETH = liquidity / 2;

//         // Transfer tokens back to the recipient
//         IERC20(token).transfer(to, amountToken);

//         // Simulate sending ETH to the recipient
//         payable(to).transfer(amountETH);
//     }

//     function removeLiquidityWithPermit(
//         address tokenA,
//         address tokenB,
//         uint256 liquidity,
//         uint256 amountAMin,
//         uint256 amountBMin,
//         address to,
//         uint256 deadline,
//         bool approveMax,
//         uint8 v,
//         bytes32 r,
//         bytes32 s
//     ) external override returns (uint256 amountA, uint256 amountB) {
//         amountA = liquidity / 2;
//         amountB = liquidity / 2;

//         // Transfer tokens back to the recipient
//         IERC20(tokenA).transfer(to, amountA);
//         IERC20(tokenB).transfer(to, amountB);
//     }

//     function quote(
//         uint256 amountA,
//         uint256 reserveA,
//         uint256 reserveB
//     ) external pure override returns (uint256 amountB) {
//         // In a real implementation, this function would calculate amountB
//         // based on reserves. Here we mock it.
//         amountB = (amountA * reserveB) / reserveA;
//     }

//     function factory() external pure override returns (address) {
//         return address(0); // Mock value
//     }

//     function WETH() external pure override returns (address) {
//         return address(0); // Mock value
//     }
// }
