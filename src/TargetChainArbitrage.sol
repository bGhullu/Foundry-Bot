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
        if (msg.sender != mainContract || msg.sender != owner()) {
            revert TargetContract__NotMainContractOrOwner();
        }
        _;
    }

    constructor(
        address _endpoint,
        address _lendingPool,
        address[] memory _dexAddresses,
        address[] memory _bridgeAddresses
    ) OApp(_lendingPool, msg.sender) Ownable(msg.sender) {
        if (_endpoint == address(0) || _lendingPool == address(0)) {
            revert TargetContract__InvalidAddress();
        }
        lendingPool = IPool(_lendingPool);
    }

    function setMainContract(address _mainContractAddrs) external onlyOwner {
        if (_mainContractAddrs == address(0)) {
            revert TargetContract__InvalidAddress();
        }
        mainContract = _mainContractAddrs;
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
        uint16 _srcChaindId,
        bytes32 _guild,
        bytes memory _payload,
        address _executor,
        bytes memory _extraData
    ) internal {
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
        if (chainIds.length > 1) {
            uint operationPerformed = 0;
            for (uint i = 0; i < chainIds.length - 1; i++) {
                if (chainIds[i] == chainIds[0]) {
                    operationPerformed++;
                } else {
                    break;
                }
            }
            uint16[] memory nextChainIds = new uint16[](
                chainIds.length - operationPerformed
            );
            address[] memory nextTokens = new address[](
                tokens.length - operationPerformed
            );
            uint256[] memory nextAmounts = new uint256[](
                amounts.length - operationPerformed
            );
            address[] memory nextDexes = new address[](
                dexes.length - operationPerformed
            );
            address[] memory nextBridges = new address[](
                bridges.length - operationPerformed - 1
            );

            for (uint i = 0; i < nextChainIds.length; i++) {
                nextChainIds[i] = chainIds[i + operationPerformed];
                nextDexes[i] = dexes[i + operationPerformed];
                nextTokens[i] = tokens[i + operationPerformed];
                nextAmounts[i] = amounts[i + operationPerformed];
            }
            for (uint i = 0; i < nextBridges.length; i++) {
                nextBridges[i] = bridges[i + (operationPerformed - 1)];
            }

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
            emit CrossChainSync(_srcChaindId, _guild, "Arbitrage completed");
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
                _bridges,
                _chainIds,
                _recipient,
                _nonce
            )
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = ECDSA.recover(ethSignedMessageHash, _signature);
        if (signer != owner()) {
            revert TargetContract__NotOwner();
        }

        //Prepare for the flash loan
        uint256[] memory modes = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            modes[i] = 0; // 0 for no debt
        }

        bytes memory params = abi.encode(
            _tokens,
            _amounts,
            _dexes,
            _bridges,
            _chainIds,
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
        if (msg.sender != address(lendingPool)) {
            revert TargetContract__CallerMustBeLendingPool();
        }
        //Decode the params
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

        //Execute swap on designated DEXes and handle Bridging
        for (uint256 i = 0; i < _dexes.length; i++) {
            address dexAddress = _dexes[i];
            if (dexAddress == address(0)) {
                revert TargetContract__InvalidAddress();
            }
            if (!authorizedDexes[dexAddress]) {
                revert TargetContract__UnauthorizedDex();
            }
            bytes4 swapFunctionSelector = dexFunctionMapping[dexAddress];
            (bool success, bytes memory result) = address(this).delegatecall(
                abi.encodeWithSelector(
                    swapFunctionSelector,
                    _tokens[i],
                    _tokens[i + 1],
                    _amounts[i],
                    dexAddress
                )
            );
            require(success, "Swap failed");
            emit SwapExecuted(
                dexAddress,
                _tokens[i],
                _tokens[i + 1],
                _amounts[i]
            );
            unchecked {
                i++;
            }

            _handleBridge(_bridges, _tokens, _amounts, _chainIds, _recipient);

            for (uint256 j = 0; j < assets.length; j++) {
                uint256 amountOwing = amounts[i] + premiums[i];
                IERC20(assets[i]).approve(address(lendingPool), amountOwing);
                IERC20(assets[i]).transfer(address(lendingPool), amountOwing);
            }
        }
        emit FlashLoanRepaid(assets, amounts, premiums);
        return true;
    }

    function _handleBridge(
        address[] memory _bridges,
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint16[] memory _chainIds,
        address _recipient
    ) internal {
        for (uint256 i = 0; i < _bridges.length; ) {
            address bridgeAddress = _bridges[i];
            if (bridgeAddress == address(0)) {
                revert TargetContract__InvalidAddress();
            }
            if (!authorizedBridges[bridgeAddress]) {
                revert TargetContract__UnauthorizedBridge();
            }
            _executeBridge(
                bridgeAddress,
                _tokens[i],
                _amounts[i],
                _chainIds[i],
                _recipient
            );
            emit BridgeExecuted(
                bridgeAddress,
                _tokens[i],
                _amounts[i],
                _chainIds[i]
            );
            unchecked {
                i++;
            }
        }
    }

    function _executeBridge(
        address _bridgeAddress,
        address _token,
        uint256 _amount,
        uint16 _chainId,
        address _recipient
    ) internal {
        bytes4 bridgeFunctionSelector = bridgeFunctionMapping[_bridgeAddress];
        (bool success, ) = _bridgeAddress.call(
            abi.encodeWithSelector(
                bridgeFunctionSelector,
                _token,
                _amount,
                _chainId,
                _recipient
            )
        );
        require(success, "Bridge failed");
    }

    function swapOnUniswapV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address dexRouterAddress
    ) internal {
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
    ) internal {
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
    ) internal {
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
