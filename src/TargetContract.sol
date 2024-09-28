//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@aave/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "@aave/contracts/interfaces/IPool.sol";
import "forge-std/console.sol";

contract TargetContract is Ownable, IFlashLoanReceiver {
    error TargetContract__UnauthorizedCaller();
    IPool public lendingPool;
    address private immutable mainContract;

    constructor(
        address _lendingPool,
        address _mainContract
    ) Ownable(msg.sender) {
        lendingPool = IPool(_lendingPool);
        mainContract = _mainContract;
    }

    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract || msg.sender != owner()) {
            revert TargetContract__UnauthorizedCaller();
        }
        _;
    }

    function _intialFlashLoan(
        address memory _token,
        uint256 memory _amounts
    ) internal {}
}
