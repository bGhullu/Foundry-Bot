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

interface IPankcakeRouter is IUniswapV2Router02 {}

interface ISushiSwapRouter is IUniswapV2Router02 {}

contract TargetArbitrageContract is Ownable, OApp, IFlashLoanReceiver {
    using ECDSA for bytes32;

    error TargetContract__NotMainContractOrOwner();
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

    IPool public lendingPool;
    address public mainContract;
    mapping(address => bytes4) public dexFunctionMapping;
    mapping(address => bytes4) public bridgeFunctionMapping;
    mapping(address => bool) public authorizedDexes;
    mapping(address => bool) public authorizedBridges;

    modifier onlyMainOrOwner() {
        require(
            msg.sender == mainContract || msg.sender == owner(),
            "Not authorized"
        );
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
        require(
            _mainContractAddr != address(0),
            "Invalid main contract address"
        );
        mainContract = _mainContractAddr;
    }

    function setDexFunction(
        address _dexAddress,
        bytes4 _functionSelector
    ) external onlyOwner {
        require(_dexAddress != address(0), "Invalid DEX address");
        dexFunctionMapping[_dexAddress] = _functionSelector;
        emit DexFunctionSet(_dexAddress, _functionSelector);
    }

    function setBridgeFunction(
        address _bridgeAddress,
        bytes4 _functionSelector
    ) external onlyOwner {
        require(_bridgeAddress != address(0), "Invalid bridge address");
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
        (
            address[] memory currentDexes,
            address[] memory currentTokens,
            uint256[] memory currentAmounts
        ) = filterDexesByChainId(
                uint16(block.chainid),
                _dexes,
                _tokens,
                _amounts,
                _chainIds
            );

        _initiateFlashLoan(
            currentTokens,
            currentAmounts,
            currentDexes,
            _recipient
        );
    }

    function filterDexesByChainId(
        uint16 currentChainId,
        address[] memory dexes,
        address[] memory tokens,
        uint256[] memory amounts,
        uint16[] memory chainIds
    )
        internal
        pure
        returns (
            address[] memory filteredDexes,
            address[] memory filteredTokens,
            uint256[] memory filteredAmounts
        )
    {
        uint count = 0;

        // Count how many dexes are for the current chainId
        for (uint i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == currentChainId) {
                count++;
            }
        }

        // Initialize the filtered arrays
        filteredDexes = new address[](count);
        filteredTokens = new address[](count + 1); // +1 to include the final output token
        filteredAmounts = new uint256[](count);

        // Populate the filtered arrays
        uint index = 0;
        for (uint i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == currentChainId) {
                filteredDexes[index] = dexes[i];
                filteredTokens[index] = tokens[i];
                filteredAmounts[index] = amounts[i];
                index++;
            }
        }
        filteredTokens[count] = tokens[count]; // Set the final output token
    }

    function _initiateFlashLoan(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address[] memory _dexes,
        address _recipient
    ) public {
        uint256[] memory modes = new uint256[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            modes[i] = 0; // 0 means no debt
        }

        bytes memory params = abi.encode(_tokens, _amounts, _dexes, _recipient);

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

        // Filter dexes, tokens, and amounts for the current chain
        (
            address[] memory filteredDexes,
            address[] memory filteredTokens,
            uint256[] memory filteredAmounts
        ) = filterDexesByChainId(
                uint16(block.chainid),
                _dexes,
                _tokens,
                _amounts,
                _chainIds
            );

        // Execute swaps on designated DEXes for the current chain
        for (uint256 i = 0; i < filteredDexes.length; i++) {
            address dexAddress = filteredDexes[i];
            require(dexAddress != address(0), "Invalid DEX address");
            require(authorizedDexes[dexAddress], "DEX not authorized");

            _swapOnDex(
                dexAddress,
                filteredTokens[i],
                filteredTokens[i + 1],
                filteredAmounts[i]
            );
        }

        // Handle the bridge operation after swaps are complete
        if (_bridges.length > 0 && filteredDexes.length > 0) {
            uint bridgeIndex = filteredDexes.length - 1;

            _executeBridge(
                _bridges[bridgeIndex], // The bridge to use for the current operation
                filteredTokens[filteredTokens.length - 1], // Last token after swaps
                filteredAmounts[filteredAmounts.length - 1], // Last amount after swaps
                _chainIds[bridgeIndex + 1], // The next chain ID
                _recipient // The recipient address (contract on the next chain)
            );
        }

        // Repay the flash loan
        _repayFlashLoan(assets, amounts, premiums);

        return true;
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
    ) internal {
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

    function _repayFlashLoan(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums
    ) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amountOwing = amounts[i] + premiums[i];
            IERC20(assets[i]).approve(address(lendingPool), amountOwing);
        }

        emit FlashLoanRepaid(assets, amounts, premiums);
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
        IERC20(tokenIn).approve(dexRouterAddress, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2Router02(dexRouterAddress).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp + 200
        );
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
}
