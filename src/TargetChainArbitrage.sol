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
    using ECDSA for bytes32;

    error TargeContract__NotMainContractOrOwner();
    error TargeContract__InvalidAddress();
    error TargeContract__NotOwner();
    error TargeContract__CallerMustBeLendingPool();

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

    IPool public lendingPool;
    address public mainContract;
    mapping(address => bytes4) public dexFunctionMapping;
    mapping(address => bytes4) public bridgeFunctionMapping;
    mapping(address => bool) public authorizedDex;
    mapping(address => bool) public authorizedBridge;

    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract || msg.sender != owner()) {
            revert TargeContract__NotMainContractOrOwner();
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

    function setDexFunction(
        address _dexAddress,
        bytes4 _functionSelector
    ) external onlyOwner {
        if (_dexAddress == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        dexFunctions[_dexAddress] = _functionSelector;
        emit DexFunctionSet(_dexAddress, _functionSelector);
    }

    function setBridgeFunction(
        address _bridgeAddress,
        bytes4 _functionSelector
    ) external onlyOwner {
        if (_bridgeAddress == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        bridgeFunctionMapping[_bridgeAddress] = _functionSelector;
        emit BridgeFunctionSet(_bridgeAddress, _functionSelector);
    }

    function authorizedDex(
        address _dexAddress,
        bool _status
    ) external onlyOwner {
        authorizedDex[_dexAddress] = _status;
        emit DexAuthorized(_dexAddress, _status);
    }

    function authorizedBridge(
        address _bridgeAddress,
        bool _status
    ) external onlyOwner {
        authorizedBridge[_bridgeAddress] = _status;
        emit BridgeAuthorized(_bridgeAddress, _status);
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
            revert TargeContract__NotOwner();
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
        lendingPool.flashloan(
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
            revert TargeContract__CallerMustBeLendingPool();
        }
        //Decode the params
        (
            address[] memory tokens,
            uint256[] memory amounts,
            address[] memory dexes,
            address[] memory bridges,
            uint16[] memory chainIds,
            address recipient
        ) = abi.decode(
                params,
                (address[], uint256[], address[], address[], uint16[], address)
            );

        //Execute swap on designated DEXes and handle Bridging
        for (uint256 i = 0; i < dexes.length; i++) {
            address dexAddress = dexes[i];
            if (dexAddress == address(0)) {
                revert TargeContract__InvalidAddress();
            }
            bytes4 swapFunctionSelector = dexFunctionMapping[dexAddress];
            (bool success, bytes memory result) = address(this).delegatecall(
                abi.encodeWithSelector(
                    swapFunctionSelector,
                    tokens[i],
                    tokens[i + 1],
                    amounts[i],
                    dexAddress
                )
            );
            require(success, "Swap failed");
            emit SwapExecuted(dexAddress, tokens[i], tokens[i + 1], amounts[i]);
            unchecked {
                i++;
            }

            _handleBridge(bridges, tokens, amounts, chainIds, recipient);

            for (uint256 i = 0; i < assets.length; i++) {
                uint256 amountOwing = amounts[i] + premiums[i];
                IERC20(assets[i]).approve(address(lendingPool), amountOwing);
                IERC20(assets[i]).transfer(lendingPool, amountOwing);
            }
        }
        emit FlashLoanRepaid(assets, amounts, premiums);
        return true;
    }

    function _handleBridging(
        address[] memory _bridges,
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint16[] memory _chainIds,
        address _recipient
    ) internal {
        for (uint256 i = 0; i < _bridges.length; ) {
            address bridgeAddress = _bridges[i];
            if (bridgeAddress == address(0)) {
                revert TargeContract__InvalidAddress();
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

        IUniswapV2Router02(dexRouterAddrss).swapExactTokenFortTokens(
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
}
