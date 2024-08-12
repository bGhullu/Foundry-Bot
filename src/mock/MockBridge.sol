// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBridge {
    event BridgeTransfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint16 destinationChainId
    );

    function transferToChain(
        address token,
        uint256 amount,
        uint16 destinationChainId,
        address recipient
    ) external {
        require(
            IERC20(token).balanceOf(msg.sender) >= amount,
            "Insufficient balance"
        );

        // Simulate the token transfer to the bridge contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Emit an event to simulate the bridging process
        emit BridgeTransfer(
            token,
            msg.sender,
            recipient,
            amount,
            destinationChainId
        );
    }

    function receiveFromChain(
        address token,
        uint256 amount,
        address recipient
    ) external {
        // Simulate the reception of tokens on the destination chain
        IERC20(token).transfer(recipient, amount);
    }
}
