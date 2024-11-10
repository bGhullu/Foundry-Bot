//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TargetContract is Ownable {
    function executeOperation() internal {}

    function initiateArbitrage() internal {}

    function swapDex() internal {}
}
