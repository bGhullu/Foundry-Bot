// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {OApp, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@aave/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "@aave/contracts/interfaces/IPool.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";

interface IPankcakeRouter is IUniswapV2Router02 {}

interface ISushiSwapRouter is IUniswapV2Router02 {}

contract TargetArbitrageContract is Ownable, OApp, IFlashLoanReceiver {
    error TargeContract__NotMainContractOrOwner();
    error TargeContract__InvalidAddress();

    using ECDSA for bytes32;
    IPool public lendingPool;
    address public mainContract;

    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract || msg.sender != owner()) {
            revert TargeContract__NotMainContractOrOwner();
        }
        _;
    }

    constructor(
        address _endpoint,
        address _lendingPool
    ) OApp(_lendingPool, msg.sender) Ownable(msg.sender) {
        if (_endpoint == address(0) || _lendingPool == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        lendingPool = IPool(_lendingPool);
    }

    function setMainContract(address _mainContractAddrs) external onlyOwner {
        if (_mainContractAddrs == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        mainContract = _mainContractAddrs;
    }

    function _lzReceive(
        uint16 _srcChaindId,
        bytes32 _guild,
        bytes memory _payload,
        address _executor,
        bytes memory _extraData
    ) internal override {
        // Decode the payload
        (
            address[] memory tokens,
            uint256[] memory amounts,
            address[] memory dexes,
            address[] memory bridges,
            uint16[] memory chainIds,
            address recipient,
            uint256 nonce,
            bytes memory signature
        ) = abi.decode(
                _payload,
                (
                    address[],
                    uint256[],
                    address[],
                    address[],
                    uint16[],
                    address,
                    uint256,
                    bytes
                )
            );
        executeArbitrage(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce,
            signature
        );
    }

    function executeArbitrage(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address[] memory _dexes,
        address[] memory _bridges,
        uint16[] memory _chainIds,
        address _recipient,
        uint256 _nonce,
        bytes memory _signature
    ) internal onlyMainOrOwner {}
}
