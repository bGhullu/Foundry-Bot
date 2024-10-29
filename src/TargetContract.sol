//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/contracts/interfaces/IPool.sol";

contract TargetContract is OApp, Ownable {
    constructor(address mainContract) OApp(mainContract) Ownable(msg.sender) {}

    function initiateArbitrage() internal {}

    function executeOpeation() internal {}

    function swapDex() internal {}
}
