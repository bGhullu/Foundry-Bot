//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@aave/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/contracts/interfaces/IPool.sol";
import "forge-std/console.sol";

contract TargetContract is Ownable, IFlashLoanSimpleReceiver {
    error TargetContract__UnauthorizedCaller();
    error TargetContract__CallerMustBeLendingPool();

    IPoolAddressesProvider public immutable provider;
    IPool public immutable pool;
    address private immutable mainContract;

    constructor(address _provider, address _mainContract) Ownable(msg.sender) {
        provider = IPoolAddressesProvider(_provider);
        pool = IPool(provider.getPool());
        mainContract = _mainContract;
    }

    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract || msg.sender != owner()) {
            revert TargetContract__UnauthorizedCaller();
        }
        _;
    }

    function _intialFlashLoan(
        address _token,
        uint256 _amount
    ) internal onlyMainOrOwner {
        address receiverAddress = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;
        pool.flashLoanSimple(
            receiverAddress,
            _token,
            _amount,
            params,
            referralCode
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(pool)) {
            revert TargetContract__CallerMustBeLendingPool();
        }
    }
}
