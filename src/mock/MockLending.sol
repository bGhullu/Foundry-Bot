// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@aave/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLendingPool {
    event FlashLoanExecuted(
        address receiver,
        address[] assets,
        uint256[] amounts
    );

    function flashloan(
        address receiver,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory modes,
        address onBehalfOf,
        bytes memory params,
        uint16 referralCode
    ) external {
        // Simulate transfer of flash loaned assets to the receiver contract
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).transfer(receiver, amounts[i]);
        }

        // Call the executeOperation function on the receiver contract
        IFlashLoanReceiver(receiver).executeOperation(
            assets,
            amounts,
            new uint256[](assets.length),
            msg.sender,
            params
        );

        // Emit an event to simulate flash loan execution
        emit FlashLoanExecuted(receiver, assets, amounts);
    }
}
