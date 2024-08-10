// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBridge {
    event TokenBridged(
        address token,
        uint256 amount,
        uint16 chainId,
        address recipient
    );

    function bridge(
        address token,
        uint256 amount,
        uint16 chainId,
        address recipient
    ) external {
        // Simulate transferring tokens to the bridge (in reality, this would involve a cross-chain operation)
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Emit an event to indicate the token was bridged
        emit TokenBridged(token, amount, chainId, recipient);
    }
}
