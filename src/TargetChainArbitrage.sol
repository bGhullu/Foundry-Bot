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
    error TargeContract__NotOwner();
    error TargeContract__CallerMustBeLendingPool();

    using ECDSA for bytes32;
    IPool public lendingPool;
    address public mainContract;
    mapping(uint8 => address) public dexMapping;
    modifier onlyMainOrOwner() {
        if (msg.sender != mainContract || msg.sender != owner()) {
            revert TargeContract__NotMainContractOrOwner();
        }
        _;
    }

    constructor(
        address _endpoint,
        address _lendingPool,
        address[] memory _dexAddresses;
    ) OApp(_lendingPool, msg.sender) Ownable(msg.sender) {
        if (_endpoint == address(0) || _lendingPool == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        lendingPool = IPool(_lendingPool);
        for (int256 i=0;i<_dexAddresses.length;i++) {
            dexMapping[i] = _dexAddresses[i];
        }
    }

    function setMainContract(address _mainContractAddrs) external onlyOwner {
        if (_mainContractAddrs == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        mainContract = _mainContractAddrs;
    }

    function setDexAddress(
        uint8 dexId,
        address _dexAddrress
    ) external onlyOwner {
        if (_dex == address(0)) {
            revert TargeContract__InvalidAddress();
        }
        dexMapping[dexId] = _dexAddrress;
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
       
    
    }
}
