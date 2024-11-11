//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TargetContract is Ownable {
    function executeOperation() internal {}

    function initiateArbitrage() internal {}

    function swapDex() internal {}
}
