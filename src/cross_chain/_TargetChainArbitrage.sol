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
import {TransferHelper} from "@uniswapV3/contracts/libraries/TransferHelper.sol";
import "forge-std/console.sol";

interface IPankcakeRouter is IUniswapV2Router02 {}

interface ISushiSwapRouter is IUniswapV2Router02 {}

contract TargetArbitrageContract is Ownable, OApp, IFlashLoanReceiver {
    using ECDSA for bytes32;

    error TargetContract__UnauthorizedCaller();
    error TargetContract__InvalidAddress();
    error TargetContract__NotOwner();
    error TargetContract__CallerMustBeLendingPool();
    error TargetContract__UnauthorizedDex();
    error TargetContract__UnauthorizedBridge();

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
    event FlashLoanRepaid(
        address[] assets,
        uint256[] amounts,
        uint256[] premiums
    );
    event DexFunctionSet(address indexed dex, bytes4 functionSelector);
    event BridgeFunctionSet(address indexed bridge, bytes4 functionSelector);
    event DexAuthorized(address indexed dex, bool status);
    event BridgeAuthorized(address indexed bridge, bool status);
    event BridgeInitiated(
        address indexed token,
        address recipient,
        uint16 destinationChainId
    );
    event TokensBridgedBack(
        address indexed token,
        uint256 amount,
        uint16 originalChainId
    );

    IPool public lendingPool;
    address public mainContract;
    mapping(address => bytes4) public dexFunctionMapping;
    mapping(address => bytes4) public bridgeFunctionMapping;
    mapping(address => bool) public authorizedDexes;
    mapping(address => bool) public authorizedBridges;

    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract || msg.sender != owner()) {
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

    function setMainContract(address _mainContractAddr) external onlyOwner {
        if (_mainContractAddr == address(0)) {
            revert TargetContract__InvalidAddress();
        }
        mainContract = _mainContractAddr;
    }

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

    function executeArbitrage(
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

        // Filter dexes, tokens, and amounts for the current chain
        // (
        //     address[] memory currentDexes,
        //     address[] memory currentTokens,
        //     uint256[] memory currentAmounts
        // ) = filterDexesByChainId(
        //         uint16(block.chainid),
        //         _dexes,
        //         _tokens,
        //         _amounts,
        //         _chainIds
        //     );

        // _initiateFlashLoan(
        //     currentTokens,
        //     currentAmounts,
        //     currentDexes,
        //     _recipient
        // );
        _initiateFlashLoan(_tokens, _amounts, _dexes, _bridges, _recipient);
    }

    // function filterDexesByChainId(
    //     uint16 currentChainId,
    //     address[] memory dexes,
    //     address[] memory tokens,
    //     uint256[] memory amounts,
    //     uint16[] memory chainIds
    // )
    //     internal
    //     pure
    //     returns (
    //         address[] memory filteredDexes,
    //         address[] memory filteredTokens,
    //         uint256[] memory filteredAmounts
    //     )
    // {
    //     uint count = 0;

    //     // Count how many dexes are for the current chainId
    //     for (uint i = 0; i < chainIds.length; i++) {
    //         if (chainIds[i] == currentChainId) {
    //             count++;
    //         } else {
    //             break;
    //         }
    //     }
    //     console.log("Count:", count);

    //     // Initialize the filtered arrays
    //     filteredDexes = new address[](count);
    //     filteredTokens = new address[](count + 1); // +1 to include the final output token
    //     filteredAmounts = new uint256[](count);

    //     // Populate the filtered arrays

    //     for (uint i = 0; i < count; i++) {
    //         if (chainIds[i] == currentChainId) {
    //             console.log("Index:", i);

    //             filteredDexes[i] = dexes[i];
    //             filteredTokens[i] = tokens[i];
    //             filteredAmounts[i] = amounts[i];
    //             // Ensure we don't access out-of-bounds
    //             console.log("Filtered DEX", i, "is", filteredDexes[i]);
    //             console.log("Filtered Token In", i, "is", filteredTokens[i]);
    //             if (i < count - 1) {
    //                 filteredTokens[i + 1] = tokens[i + 1];
    //             }
    //         }
    //     }
    //     console.log("Final Filtered Tokens Length:", filteredTokens.length);

    //     // Ensure the last token is correctly assigned if it's a multi-chain operation
    //     if (count < tokens.length) {
    //         filteredTokens[count] = tokens[count];
    //     } else {
    //         filteredTokens[count] = tokens[tokens.length - 1];
    //     }

    //     require(
    //         filteredDexes.length == filteredTokens.length - 1,
    //         "Mismatch between dexes and tokens"
    //     );

    //     console.log("Final Filtered Dexes Length:", filteredDexes.length);
    //     console.log("Final Filtered Tokens Length:", filteredTokens.length);
    //     console.log("Final Filtered Amounts Length:", filteredAmounts.length);
    //     // Set the final output token
    //     // filteredTokens[count] = tokens[tokens.length - 1];
    // }

    //     // Count how many dexes are for the current chainId
    //     for (uint i = 0; i < chainIds.length; i++) {
    //         if (chainIds[i] == currentChainId) {
    //             count++;
    //         }
    //     }

    //     // Initialize the filtered arrays
    //     filteredDexes = new address[](count);
    //     filteredTokens = new address[](count + 1); // +1 to include the final output token
    //     filteredAmounts = new uint256[](count);

    //     // Populate the filtered arrays
    //     uint index = 0;
    //     for (uint i = 0; i < chainIds.length; i++) {
    //         if (chainIds[i] == currentChainId) {
    //             filteredDexes[index] = dexes[i];
    //             filteredTokens[index] = tokens[i];
    //             // Handle tokens assignment:
    //             if (index == 0) {
    //                 // For the first dex, assign the start token and the first output token

    //                 if (i + 1 < tokens.length) {
    //                     filteredTokens[index + 1] = tokens[i + 1];
    //                 }
    //             } else {
    //                 // For subsequent dexes, assign the corresponding tokens
    //                 if (i + 1 < tokens.length) {
    //                     filteredTokens[index + 1] = tokens[i + 1];
    //                 }
    //             }

    //             filteredAmounts[index] = amounts[i];
    //             index++;
    //         }
    //     }

    //     // Ensure the last token is correctly assigned if it's a multi-chain operation
    //     filteredTokens[count] = tokens[tokens.length - 1];
    // }

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

        // Debugging statements to identify issues
        console.log("Assets array:");
        for (uint i = 0; i < assets.length; i++) {
            console.log(assets[i]);
        }
        console.log("Amounts array:");
        for (uint i = 0; i < amounts.length; i++) {
            console.log(amounts[i]);
        }
        console.log("Premiums array:");
        for (uint i = 0; i < premiums.length; i++) {
            console.log(premiums[i]);
        }

        // Ensure that assets, amounts, and premiums lengths match
        require(
            assets.length == amounts.length,
            "Mismatched assets and amounts"
        );
        require(
            assets.length == premiums.length,
            "Mismatched assets and premiums"
        );

        // Debugging statements for decoded params
        console.log("_tokens length:", _tokens.length);
        console.log("_amounts length:", _amounts.length);
        console.log("_dexes length:", _dexes.length);
        console.log("_bridges length:", _bridges.length);

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

        // if (_chainIds[_chainIds.length - 1] != _originalChainId) {
        //     _bridgeTokensBackToOriginalChain(
        //         assets,
        //         amounts,
        //         premiums,
        //         _recipient
        //         // _originalChainId
        //     );
        //     _waitForBridgeCompletion(assets[0], _recipient, _originalChainId);
        // } else {
        //     _repayFlashLoan(assets, amounts);
        // }

        _repayFlashLoan(assets, amounts, premiums);

        return true;

        // // Filter dexes, tokens, and amounts for the current chain
        // (
        //     address[] memory filteredDexes,
        //     address[] memory filteredTokens,
        //     uint256[] memory filteredAmounts
        // ) = filterDexesByChainId(
        //         uint16(block.chainid),
        //         _dexes,
        //         _tokens,
        //         _amounts,
        //         _chainIds
        //     );
        // console.log("Filtered Dexes Length:", filteredDexes.length);
        // console.log("Filtered Tokens Length:", filteredTokens.length);
        // console.log("Filtered Amounts Length:", filteredAmounts.length);

        // require(
        //     filteredDexes.length == filteredTokens.length - 1,
        //     "Mismatch between dexes and tokens"
        // );
        // require(
        //     filteredDexes.length > 0,
        //     "No dexes found for the current chain"
        // );
        // require(filteredTokens.length > 1, "Not enough tokens for swapping");
        // require(filteredAmounts.length > 0, "Not enough amounts for swapping");

        // // Execute swaps on designated DEXes for the current chain
        // for (uint256 i = 0; i < filteredDexes.length; i++) {
        //     require(
        //         i + 1 < filteredTokens.length,
        //         "Token array length mismatch"
        //     );
        //     address dexAddress = filteredDexes[i];
        //     require(dexAddress != address(0), "Invalid DEX address");
        //     require(authorizedDexes[dexAddress], "DEX not authorized");

        //     _swapOnDex(
        //         dexAddress,
        //         filteredTokens[i],
        //         filteredTokens[i + 1],
        //         filteredAmounts[i]
        //     );
        // }

        // // Handle the bridge operation after swaps are complete
        // if (
        //     _bridges.length > 0 &&
        //     filteredDexes.length > 0 &&
        //     _chainIds.length > 1
        // ) {
        //     uint bridgeIndex = filteredDexes.length - 1;
        //     require(
        //         bridgeIndex + 1 < _chainIds.length,
        //         "Chain ID array out of bounds"
        //     );

        //     _executeBridge(
        //         _bridges[bridgeIndex], // The bridge to use for the current operation
        //         filteredTokens[filteredTokens.length - 1], // Last token after swaps
        //         filteredAmounts[filteredAmounts.length - 1], // Last amount after swaps
        //         _chainIds[bridgeIndex + 1], // The next chain ID
        //         _recipient // The recipient address (contract on the next chain)
        //     );
        // }

        // Repay the flash loan
        // _repayFlashLoan(assets, amounts, premiums);

        // return true;
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

    // function _bridgeTokensBackToOriginalChain(
    //     address[] memory assets,
    //     uint256[] memory amounts,
    //     uint256[] memory premiums,
    //     address recipient,
    //     uint16 originalChainId
    // ) internal {
    //     for (uint i = 0; i < assets.length; i++) {
    //         _executeBridge(
    //             // authorizedBridges[assets[i]],
    //             assets[i],
    //             amounts[i] + premiums[i],
    //             originalChainId,
    //             recipient
    //         );

    // emit TokensBridgedBack(
    //     assets[i],
    //     amounts[i] + premiums[i],
    //     originalChainId
    //         // );
    //     }

    //     _notifyMainContractTokensBridgedBack(
    //         assets,
    //         amounts,
    //         recipient,
    //         originalChainId
    //     );
    // }

    function _notifyMainContractTokensBridgedBack(
        address[] memory assets,
        uint256[] memory amounts,
        address recipient,
        uint16 originalChainId
    ) internal {
        bytes memory payload = abi.encode(
            true,
            abi.encode(assets, amounts, recipient, originalChainId)
        );

        bytes memory options = abi.encode(uint16(1), uint256(200000));
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        _lzSend(originalChainId, payload, options, fee, payable(msg.sender));
    }

    function _repayFlashLoan(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums
    ) internal {
        console.log("Assets length:", assets.length);
        console.log("Amounts length:", amounts.length);
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
            console.log("Repaying asset:", assets[i]);
            console.log("Total amount to repay:", amountOwed);
            IERC20(assets[i]).approve(address(lendingPool), amountOwed);
            // Assuming the function to repay looks something like this:
            // IERC20(assets[i]).transfer(address(lendingPool), amountOwed);
        }
    }

    function _initializeDexAndBridgeMappings(
        address[] memory dexAddresses,
        bytes4[] memory dexFunctionSelectors,
        address[] memory bridgeAddresses,
        bytes4[] memory bridgeFunctionSelectors
    ) public {
        require(
            dexAddresses.length == dexFunctionSelectors.length,
            "DEX addresses and function selectors length mismatch"
        );
        require(
            bridgeAddresses.length == bridgeFunctionSelectors.length,
            "Bridge addresses and function selectors length mismatch"
        );

        // Initialize DEX mappings
        for (uint i = 0; i < dexAddresses.length; i++) {
            dexFunctionMapping[dexAddresses[i]] = dexFunctionSelectors[i];
            authorizedDexes[dexAddresses[i]] = true;
        }

        // Initialize Bridge mappings
        for (uint i = 0; i < bridgeAddresses.length; i++) {
            bridgeFunctionMapping[bridgeAddresses[i]] = bridgeFunctionSelectors[
                i
            ];
            authorizedBridges[bridgeAddresses[i]] = true;
        }
    }

    function swapOnUniswapV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address dexRouterAddress
    ) public {
        uint256 deadline = block.timestamp + 30;
        uint256 swap_amount_out = 0;
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        TransferHelper.safeApprove(
            tokenIn,
            address(dexRouterAddress),
            amountIn
        );
        swap_amount_out = IUniswapV2Router02(dexRouterAddress)
            .swapExactTokensForTokens({
                amountIn: amountIn,
                amountOutMin: 0,
                path: path,
                to: address(this),
                deadline: deadline
            })[1];
    }

    function swapOnUniswapV3(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        address dexRouterAddress
    ) public {
        IERC20(tokenIn).approve(dexRouterAddress, amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 200,
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });
        ISwapRouter(dexRouterAddress).exactInputSingle(params);
    }

    function swapOnSushiSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address dexRouterAddress
    ) internal {
        IERC20(tokenIn).approve(dexRouterAddress, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        ISushiSwapRouter(dexRouterAddress).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp + 200
        );
    }

    function swapOnPancakeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address dexRouterAddress
    ) public {
        IERC20(tokenIn).approve(dexRouterAddress, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IPankcakeRouter(dexRouterAddress).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp + 200
        );
    }

    function ADDRESSES_PROVIDER()
        external
        pure
        returns (IPoolAddressesProvider)
    {
        return IPoolAddressesProvider(address(0));
    }

    function POOL() external view override returns (IPool) {
        return lendingPool;
    }

    function testLzSend(uint16 _dstChainId, bytes calldata _payload) external {
        bytes32 peer = peers[_dstChainId];
        console.log("Attempting to send to chainId:", _dstChainId);
        console.log(" with peer address:");
        console.logBytes32(peer);
        require(peer != bytes32(0), "NoPeer");
        // Simulate the logic that would be inside lzSend
        _lzSend(
            _dstChainId,
            _payload,
            abi.encode(uint16(1), uint256(200000)), // Simulating adapterParams
            MessagingFee({nativeFee: 0, lzTokenFee: 0}), // Simulating MessagingFee
            payable(msg.sender)
        );
    }

    function testLzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address _executor,
        bytes calldata _extraData
    ) external {
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

        // Example: Log or assert the decoded values (for testing purposes)
        console.log("Received payload for cross-chain operation");

        // Process the first swap on the current chain
        if (dexes.length > 0 && chainIds[0] == uint16(block.chainid)) {
            _swapOnDex(dexes[0], tokens[0], tokens[1], amounts[0]);
        }

        // If there's a bridge operation to perform, handle it
        if (bridges.length > 0 && chainIds.length > 1) {
            _executeBridge(
                bridges[0],
                tokens[1],
                amounts[1],
                chainIds[1],
                recipient
            );

            // Prepare the next payload for the subsequent chain
            uint16[] memory nextChainIds = new uint16[](chainIds.length - 1);
            address[] memory nextTokens = new address[](tokens.length - 1);
            uint256[] memory nextAmounts = new uint256[](amounts.length - 1);
            address[] memory nextDexes = new address[](dexes.length - 1);
            address[] memory nextBridges = new address[](bridges.length - 1);

            // Populate the next operation's details
            for (uint i = 1; i < chainIds.length; i++) {
                nextChainIds[i - 1] = chainIds[i];
                nextTokens[i - 1] = tokens[i];
                nextAmounts[i - 1] = amounts[i];
                if (i < dexes.length) {
                    nextDexes[i - 1] = dexes[i];
                }
                if (i < bridges.length) {
                    nextBridges[i - 1] = bridges[i];
                }
            }

            // Encode the next payload
            bytes memory nextPayload = abi.encode(
                nextTokens,
                nextAmounts,
                nextDexes,
                nextBridges,
                nextChainIds,
                recipient,
                nonce,
                signature
            );

            // Send the payload to the next chain (using a mocked LayerZero function)
            _lzSend(
                chainIds[1],
                nextPayload,
                abi.encode(uint16(1), uint256(200000)), // Simulating adapterParams
                MessagingFee({nativeFee: 0, lzTokenFee: 0}),
                payable(msg.sender)
            );
        } else if (dexes.length > 1) {
            // If no bridging is required and there are more swaps to perform on the same chain
            _swapOnDex(dexes[1], tokens[1], tokens[2], amounts[1]);
        }

        // Log the completion of the operation
        console.log("Completed cross-chain operation");
    }
}
