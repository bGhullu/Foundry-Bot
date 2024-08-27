//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

contract CrossChainArbitrage is Ownable {
    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;

    constructor(
        IUniswapV2Router02 _uniswapV2Router,
        ISwapRouter _uniswapV3Router
    ) Ownable(msg.sender) {
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
    }

    function swapOnUniswapV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external onlyOwner returns (uint256[] memory amounts) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(uniswapV2Router), amountIn);

        amounts = uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );
        return amounts;
    }

    function swapOnUniswapV3(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint24 fee
    ) external onlyOwner returns (uint256 amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(uniswapV3Router), amountIn);

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

        amountOut = uniswapV3Router.exactInputSingle(params);
        return amountOut;
    }

    function multiSwapOnUniswapV3(
        bytes calldata path,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        (
            address token1,
            uint24 fee1,
            address token2,
            uint24 fee2,
            address token3
        ) = abi.decode(path, (address, uint24, address, uint24, address));
        console.log("Token1:");
        console.logAddress(token1);
        IERC20(token1).transferFrom(msg.sender, address(this), amountIn);
        console.log("WETH balance of");
        console.logAddress(address(this));
        console.log(IERC20(token1).balanceOf(address(this)));
        IERC20(token1).approve(address(uniswapV3Router), amountIn);

        bytes memory _path = abi.encodePacked(
            token1,
            fee1,
            token2,
            fee2,
            token3
        );

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: _path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOut
            });

        amountOut = uniswapV3Router.exactInput(params);
        return amountOut;
    }
}
