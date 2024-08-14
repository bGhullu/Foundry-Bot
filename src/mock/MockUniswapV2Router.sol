// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";

contract MockUniswapV2Router is IUniswapV2Router02 {
    mapping(address => mapping(address => uint256)) public balances;

    function WETH() external pure override returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // You can replace this with any mock address
    }

    constructor() {}

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {
        require(amountIn > 0, "Amount in must be greater than 0");
        require(path.length >= 2, "Path length must be at least 2");

        // Initialize the amounts array to track the amounts of each token in the path
        amounts = new uint[](path.length);

        // Set the input amount as the first element in the amounts array
        amounts[0] = amountIn;

        // Simulate token transfer to the router
        IERC20 inputToken = IERC20(path[0]);
        inputToken.transferFrom(msg.sender, address(this), amountIn);

        // Perform the swaps along the path
        for (uint i = 1; i < path.length; i++) {
            IERC20 fromToken = IERC20(path[i - 1]);
            IERC20 toToken = IERC20(path[i]);

            // Simulate the output amount for this hop (e.g., 1:1 ratio for simplicity)
            // In a real scenario, this would involve calculating the output based on the exchange rate
            uint amountOut = amounts[i - 1]; // This can be more complex depending on your needs
            require(amountOut > 0, "Insufficient amount out");

            // Store the amount out in the amounts array for the next hop
            amounts[i] = amountOut;

            // Simulate the transfer to the next token in the path
            fromToken.transfer(address(this), amounts[i - 1]);
            require(
                toToken.balanceOf(address(this)) >= amounts[i],
                "Insufficient output token balance"
            );

            // Transfer the output tokens to the recipient if it's the last token in the path
            if (i == path.length - 1) {
                require(
                    amounts[i] >= amountOutMin,
                    "Insufficient final output amount"
                );
                toToken.transfer(to, amounts[i]);
            }
        }

        // Ensure the last output amount meets the minimum output requirement
        require(
            amounts[path.length - 1] >= amountOutMin,
            "Insufficient final output amount"
        );
    }

    // function swapExactTokensForTokens(
    //     uint amountIn,
    //     uint amountOutMin,
    //     address[] calldata path,
    //     address to,
    //     uint deadline
    // ) external override returns (uint[] memory amounts) {
    //     require(amountIn > 0, "Amount in must be greater than 0");
    //     require(path.length >= 2, "Path length must be at least 2");

    //     IERC20 inputToken = IERC20(path[0]);
    //     IERC20 outputToken = IERC20(path[path.length - 1]);

    //     // Simulate token transfer to the router
    //     inputToken.transferFrom(msg.sender, address(this), amountIn);

    //     // Ensure the router has a sufficient balance of the output token
    //     require(
    //         outputToken.balanceOf(address(this)) >= amountOutMin,
    //         "Insufficient output token balance"
    //     );

    //     // Simulate the output amount (e.g., 1:1 ratio for simplicity)
    //     uint amountOut = amountIn; // This can be more complex depending on your needs
    //     require(amountOut >= amountOutMin, "Insufficient output amount");

    //     // Transfer the output tokens to the recipient
    //     outputToken.transfer(to, amountOut);

    //     // Return the amounts array
    //     amounts = new uint[](path.length);
    //     amounts[0] = amountIn;
    //     amounts[path.length - 1] = amountOut;
    // }

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external pure override returns (uint[] memory amounts) {
        require(path.length >= 2, "Path length must be at least 2");

        // For simplicity, let's assume a 1:1 swap rate in this mock
        amounts = new uint[](path.length);
        amounts[0] = amountIn;

        // All amounts out are equal to amountIn for simplicity
        for (uint i = 1; i < path.length; i++) {
            amounts[i] = amountIn;
        }
    }

    // Implement required but unused functions as empty
    function factory() external pure override returns (address) {}

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override returns (uint amountA, uint amountB, uint liquidity) {}

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        override
        returns (uint amountToken, uint amountETH, uint liquidity)
    {}

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override returns (uint amountA, uint amountB) {}

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external override returns (uint amountToken, uint amountETH) {}

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {}

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable override returns (uint[] memory amounts) {}

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {}

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {}

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable override returns (uint[] memory amounts) {}

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) external pure override returns (uint amountB) {}

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure override returns (uint amountOut) {}

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) external pure override returns (uint amountIn) {}

    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view override returns (uint[] memory amounts) {}

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external override returns (uint amountETH) {}

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint amountETH) {}

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override {}

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable override {}

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override {}

    // function WETH() external pure override returns (address) {}

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint amountA, uint amountB) {}

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint amountToken, uint amountETH) {}
}
