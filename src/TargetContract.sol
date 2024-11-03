//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract TargetContract is OApp, Ownable {
    constructor(address mainContract) OApp(mainContract) Ownable(msg.sender) {}


}
