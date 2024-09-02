// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@aave/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "@aave/contracts/interfaces/IPool.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswapV3/contracts/interfaces/ISwapRouter.sol";
import "forge-std/console.sol";

interface IPankcakeRouter is IUniswapV2Router02 {}

interface ISushiSwapRouter is IUniswapV2Router02 {}

contract CrossChain is Ownable, OApp, IFlashLoanReceiver {
    using ECDSA for bytes32;

    error TargetContract__UnauthorizedCaller();
    error TargetContract__InvalidAddress();

    event DexFunctionSet(address indexed dex, bytes4 functionSelector);
    event BridgeFunctionSet(address indexed bridge, bytes4 functionSelector);
    event DexAuthorized(address indexed dex, bool status);
    event BridgeAuthorized(address indexed bridge, bool status);

    IPool public lendingPool;
    address public mainContract;
    mapping(address => bytes4) public dexFunctionMapping;
    mapping(address => bytes4) public bridgeFunctionMapping;
    mapping(address => bool) public authorizedDexes;
    mapping(address => bool) public authorizedBridges;

    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract && msg.sender != owner()) {
            revert TargetContract__UnauthorizedCaller();
        }
        _;
    }

    constructor(
        address _endpoint,
        address _lendingPool,
        address[] memory _dexAddresses,
        bytes4[] memory _dexFunctionSelectors,
        address[] memory _bridgeAddresses,
        bytes4[] memory _bridgeFunctionSelectors
    ) OApp(_endpoint, msg.sender) Ownable(msg.sender) {
        require(
            _endpoint != address(0) && _lendingPool != address(0),
            "Invalid address"
        );
        lendingPool = IPool(_lendingPool);
        _initializeDexAndBridgeMappings(
            _dexAddresses,
            _dexFunctionSelectors,
            _bridgeAddresses,
            _bridgeFunctionSelectors
        );
    }

    function setMainContract(address _mainContractAddrs) external onlyOwner {
        if (_mainContractAddrs == address(0)) {
            revert TargetContract__InvalidAddress();
        }
        mainContract = _mainContractAddrs;
    }

    function _initializeDexAndBridgeMappings(
        address[] memory dexAddress,
        bytes4[] memory dexFunctionSelector,
        address[] memory bridgeAddress,
        bytes4[] memory bridgeFuncitonSelector
    ) internal {}

    function setDexFunction(
        address _dexAddress,
        bytes4 _functionSelector
    ) external onlyOwner {
        if (_dexAddress == address(0)) {
            revert TargetContract__InvalidAddress();
        }
        dexFunctionMapping[_dexAddress] = _functionSelector;
        emit DexFunctionSet(_dexAddress, _functionSelector);
    }

    function setBridgeFunction(
        address _bridgeAddress,
        bytes4 _functionSelector
    ) external onlyOwner {
        if (_bridgeAddress == address(0)) {
            revert TargetContract__InvalidAddress();
        }
        bridgeFunctionMapping[_bridgeAddress] = _functionSelector;
        emit BridgeFunctionSet(_bridgeAddress, _functionSelector);
    }

    function authorizedDex(
        address _dexAddress,
        bool _status
    ) external onlyOwner {
        authorizedDexes[_dexAddress] = _status;
        emit DexAuthorized(_dexAddress, _status);
    }

    function authorizedBridge(
        address _bridgeAddress,
        bool _status
    ) external onlyOwner {
        authorizedBridges[_bridgeAddress] = _status;
        emit BridgeAuthorized(_bridgeAddress, _status);
    }
}
