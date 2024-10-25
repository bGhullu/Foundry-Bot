//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;


import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@aave/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/contracts/interfaces/IPool.sol";

contract TargetContract is OApp, Ownable {
    constructor(address mainContract) OApp(mainContract) Ownable(msg.sender) {}

    function initiateArbitrage() internal {}

    function executeOpeation() internal {}

    function swapDex() internal {}
}
