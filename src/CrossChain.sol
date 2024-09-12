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
    event CrossChainSync(uint16 chainId, bytes32 syncId, string status);
    event SwapExecuted(
        address indexed dex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    );
    event BridgeExecuted(
        address indexed bridge,
        address token,
        uint256 amount,
        uint16 chainId
    );

    event BridgeInitiated(
        address indexed token,
        address recipient,
        uint16 destinationChainId
    );

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

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address _executor,
        bytes calldata _extraData
    ) internal override {
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

        _executeArbitrage(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce,
            signature
        );

        if (chainIds.length > 1) {
            bytes memory nextPayload = _createNextPayload(
                tokens,
                amounts,
                dexes,
                bridges,
                chainIds,
                recipient,
                nonce,
                signature
            );

            (, , , , uint16[] memory nextChainIds, , , ) = abi.decode(
                nextPayload,
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

            bytes memory options = abi.encode(uint16(1), uint256(200000));
            MessagingFee memory fee = MessagingFee({
                nativeFee: 0,
                lzTokenFee: 0
            });

            _lzSend(
                nextChainIds[0],
                nextPayload,
                options,
                fee,
                payable(msg.sender)
            );
        } else {
            emit CrossChainSync(
                uint16(_origin.srcEid),
                _guid,
                "Arbitrage completed"
            );
        }
    }

    function _createNextPayload(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce,
        bytes memory signature
    ) internal pure returns (bytes memory) {
        if (chainIds.length > 1) {
            uint operationsPerformed = 0;

            // Count how many operations are performed on the current chain
            for (uint i = 0; i < chainIds.length; i++) {
                if (chainIds[i] == chainIds[0]) {
                    operationsPerformed++;
                } else {
                    break;
                }
            }

            uint16[] memory nextChainIds = new uint16[](
                chainIds.length - operationsPerformed
            );
            address[] memory nextDexes = new address[](
                dexes.length - operationsPerformed
            );
            address[] memory nextBridges = new address[](
                bridges.length -
                    (
                        operationsPerformed > 1
                            ? operationsPerformed - 1
                            : operationsPerformed
                    )
            );
            address[] memory nextTokens = new address[](
                tokens.length - operationsPerformed
            );
            uint256[] memory nextAmounts = new uint256[](
                amounts.length - operationsPerformed
            );

            for (uint i = 0; i < nextChainIds.length; i++) {
                nextChainIds[i] = chainIds[i + operationsPerformed];
                nextDexes[i] = dexes[i + operationsPerformed];
                nextTokens[i] = tokens[i + operationsPerformed];
                nextAmounts[i] = amounts[i + operationsPerformed];
            }

            for (uint i = 0; i < nextBridges.length; i++) {
                nextBridges[i] = bridges[
                    i +
                        (
                            operationsPerformed > 1
                                ? operationsPerformed - 1
                                : operationsPerformed
                        )
                ];
            }

            return
                abi.encode(
                    nextTokens,
                    nextAmounts,
                    nextDexes,
                    nextBridges,
                    nextChainIds,
                    recipient,
                    nonce,
                    signature
                );
        } else {
            return ""; // Return an empty payload if there are no further operations
        }
    }

    function _executeArbitrage(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address[] memory _dexes,
        address[] memory _bridges,
        uint16[] memory _chainIds,
        address _recipient,
        uint256 _nonce,
        bytes memory _signature
    ) internal onlyMainOrOwner {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                _tokens,
                _amounts,
                _dexes,
                _chainIds,
                _recipient,
                _nonce
            )
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = ECDSA.recover(ethSignedMessageHash, _signature);
        require(signer == owner(), "Invalid Signature");
        _initiateFlashLoan(_tokens, _amounts, _dexes, _bridges, _recipient);
    }

    function _initiateFlashLoan(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address[] memory _dexes,
        address[] memory _bridges,
        address _recipient
    ) public {
        uint256[] memory modes = new uint256[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            modes[i] = 0; // 0 means no debt
        }

        bytes memory params = abi.encode(
            _tokens,
            _amounts,
            _dexes,
            _bridges,
            _recipient
        );

        lendingPool.flashLoan(
            address(this),
            _tokens,
            _amounts,
            modes,
            address(this),
            params,
            0
        );
    }

    function _swapOnDex(
        address dexAddress,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        bytes4 swapFunctionSelector = dexFunctionMapping[dexAddress];
        require(swapFunctionSelector != bytes4(0), "DEX function not set");

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSelector(
                swapFunctionSelector,
                tokenIn,
                tokenOut,
                amountIn,
                dexAddress
            )
        );

        require(success, "Swap on DEX failed");
        emit SwapExecuted(dexAddress, tokenIn, tokenOut, amountIn);
    }

    function _executeBridge(
        address bridgeAddress,
        address token,
        uint256 amount,
        uint16 chainId,
        address recipient
    ) public {
        require(authorizedBridges[bridgeAddress], "Bridge not authorized");

        bytes4 bridgeFunctionSelector = bridgeFunctionMapping[bridgeAddress];
        (bool success, ) = bridgeAddress.call(
            abi.encodeWithSelector(
                bridgeFunctionSelector,
                token,
                amount,
                chainId,
                recipient
            )
        );

        require(success, "Bridge failed");
        emit BridgeExecuted(bridgeAddress, token, amount, chainId);
    }

    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address initiator,
        bytes memory params
    ) external override returns (bool) {
        require(
            msg.sender == address(lendingPool),
            "Caller is not the lending pool"
        );

        (
            address[] memory _tokens,
            uint256[] memory _amounts,
            address[] memory _dexes,
            address[] memory _bridges,
            uint16[] memory _chainIds,
            address _recipient
        ) = abi.decode(
                params,
                (address[], uint256[], address[], address[], uint16[], address)
            );

        // Ensure that assets, amounts, and premiums lengths match
        require(
            assets.length == amounts.length,
            "Mismatched assets and amounts"
        );
        require(
            assets.length == premiums.length,
            "Mismatched assets and premiums"
        );

        uint lastSwapIndex = 0;
        uint bridgeIndex = 0;

        if (_chainIds.length == 1 && _dexes.length == 1) {
            _swapOnDex(_dexes[0], _tokens[0], _tokens[1], _amounts[0]);
            _repayFlashLoan(assets, amounts, premiums);
            return true;
        } else {
            for (uint i = 0; i < _chainIds.length - 1; i++) {
                require(
                    lastSwapIndex < _dexes.length,
                    "DEX index out of bounds"
                );
                require(
                    lastSwapIndex < _tokens.length - 1,
                    "Token index out of bounds"
                );

                _swapOnDex(
                    _dexes[lastSwapIndex],
                    _tokens[lastSwapIndex],
                    _tokens[lastSwapIndex + 1],
                    _amounts[lastSwapIndex]
                );

                if (_chainIds[i] != _chainIds[i + 1]) {
                    _executeBridge(
                        _bridges[bridgeIndex],
                        _tokens[lastSwapIndex + 1],
                        _amounts[lastSwapIndex],
                        _chainIds[i + 1],
                        _recipient
                    );
                    bridgeIndex++;
                    _waitForBridgeCompletion(
                        _tokens[lastSwapIndex + 1],
                        _recipient,
                        _chainIds[i + 1]
                    );
                }

                lastSwapIndex++;
            }

            if (
                lastSwapIndex < _dexes.length &&
                lastSwapIndex < _tokens.length - 1
            ) {
                _swapOnDex(
                    _dexes[lastSwapIndex],
                    _tokens[lastSwapIndex],
                    _tokens[lastSwapIndex + 1],
                    _amounts[lastSwapIndex]
                );
            }
        }
        _repayFlashLoan(assets, amounts, premiums);

        return true;
    }

    function _repayFlashLoan(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums
    ) internal {
        require(
            assets.length == amounts.length,
            "Mismatched assets and amounts"
        );
        require(
            assets.length == premiums.length,
            "Mismatched assets and premiums"
        );

        for (uint i = 0; i < assets.length; i++) {
            // Repay each flash loan
            uint amountOwed = amounts[i] + premiums[i];

            IERC20(assets[i]).approve(address(lendingPool), amountOwed);
            // Assuming the function to repay looks something like this:
            // IERC20(assets[i]).transfer(address(lendingPool), amountOwed);
        }
    }

    function _waitForBridgeCompletion(
        address token,
        address recipient,
        uint16 destinationChainId
    ) internal {
        emit BridgeInitiated(token, recipient, destinationChainId);

        _notifyMainContractBridgeInitiated(
            token,
            recipient,
            destinationChainId
        );
    }

    function _notifyMainContractBridgeInitiated(
        address token,
        address recipient,
        uint16 destinationChainId
    ) internal {
        bytes memory payload = abi.encode(token, recipient, destinationChainId);

        bytes memory options = abi.encode(uint16(1), uint256(200000));
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        _lzSend(destinationChainId, payload, options, fee, payable(msg.sender));
    }
}
