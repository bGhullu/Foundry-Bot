// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "forge-std/console.sol";

contract ArbitrageBot is Ownable, OApp {
    using ECDSA for bytes32;

    event PeersSet(uint16 chainId, bytes32 arbitrageContract);
    event CrossChainSync(uint16 originalChainId, bytes32 syncId, string status);
    event Debug(string message);
    event DebugAddress(string message, address addr);
    event DebugBytes(string message, bytes data);
    event DebugUint(string message, uint value);
    event DebugBytes32(string message, bytes32 data);

    struct ArbParams {
        address[] tokens;
        uint256[] amounts;
        address[] dexes;
        address[] bridges;
        uint16[] chainIds;
        address recipient;
        uint256 nonce;
        bytes signature;
    }

    ArbParams public arbParams;
    address public endpointAddr;

    constructor(
        address _endpoint,
        address _owner
    ) OApp(_endpoint, msg.sender) Ownable(_owner) {
        require(_endpoint != address(0), "Invalid endpoint address");
        endpointAddr = _endpoint;
        emit Debug("Constructor finished");
    }

    function setChainToArbitrageContract(
        uint16 chainId,
        address arbitrageContract
    ) external onlyOwner {
        peers[chainId] = bytes32(uint256(uint160((arbitrageContract))));
        emit PeersSet(chainId, bytes32(uint256(uint160((arbitrageContract)))));
    }

    function executeCrossChainArbitrage(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce,
        bytes memory signature
    ) external payable onlyOwner {
        _storeArbParams(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce,
            signature
        );
        _verifySignature(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce,
            signature
        );

        bytes memory payload = _createPayload(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce,
            signature
        );
        bytes memory options = abi.encode(uint16(1), uint256(200000));

        uint nativeFee = msg.value;
        uint lzTokenFee = 0; // Adjust this if necessary

        MessagingFee memory fee = MessagingFee({
            nativeFee: nativeFee,
            lzTokenFee: lzTokenFee
        });

        emit Debug("Executing _lzSend with payload");
        _lzSend(chainIds[0], payload, options, fee, payable(msg.sender));
    }

    function _storeArbParams(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce,
        bytes memory signature
    ) internal {
        arbParams = ArbParams(
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

    function _verifySignature(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce,
        bytes memory signature
    ) internal view {
        bytes32 messageHash = getMessageHash(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );
        require(recoveredSigner == owner(), "Invalid Signature");
    }

    function _createPayload(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce,
        bytes memory signature
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
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

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        (string memory messageType, bytes memory messageData) = abi.decode(
            payload,
            (string, bytes)
        );

        if (keccak256(bytes(messageType)) == keccak256("ARBITRAGE")) {
            _processArbitrageMessage(messageData);
        } else if (keccak256(bytes(messageType)) == keccak256("SYNC")) {
            _processSyncMessage(messageData, uint16(_origin.srcEid), _guid);
        }
    }

    function _processArbitrageMessage(bytes memory messageData) internal {
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
                messageData,
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

        _storeArbParams(
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
            bytes memory newPayload = _createNextPayload(
                tokens,
                amounts,
                dexes,
                bridges,
                chainIds,
                recipient,
                nonce,
                signature
            );

            bytes memory options = abi.encode(uint16(1), uint256(200000));
            MessagingFee memory fee = MessagingFee({
                nativeFee: 0,
                lzTokenFee: 0
            });

            emit Debug("Executing _lzSend with newPayload");
            _lzSend(chainIds[1], newPayload, options, fee, payable(msg.sender));
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
        // Dynamically calculate operations performed on the current chain
        uint operationsPerformed = 0;
        for (uint i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == chainIds[0]) {
                operationsPerformed++;
            } else {
                break;
            }
        }

        // Resize the arrays based on operationsPerformed
        uint16[] memory nextChainIds = new uint16[](
            chainIds.length - operationsPerformed
        );
        address[] memory nextDexes = new address[](
            dexes.length - operationsPerformed
        );
        address[] memory nextBridges = new address[](
            bridges.length > 0 ? bridges.length - (operationsPerformed - 1) : 0
        );
        address[] memory nextTokens = new address[](
            tokens.length - operationsPerformed
        );
        uint256[] memory nextAmounts = new uint256[](
            amounts.length - operationsPerformed
        );

        // Populate the next arrays
        for (uint i = 0; i < nextChainIds.length; i++) {
            nextChainIds[i] = chainIds[i + operationsPerformed];
            nextDexes[i] = dexes[i + operationsPerformed];
            nextTokens[i] = tokens[i + operationsPerformed];
            nextAmounts[i] = amounts[i + operationsPerformed];
        }

        if (bridges.length > 0) {
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
        }

        // Return the encoded payload
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
    }

    function _processSyncMessage(
        bytes memory messageData,
        uint16 originChainId,
        bytes32 _syncId
    ) internal {
        (uint16 originalChainId, bytes32 syncId, string memory status) = abi
            .decode(messageData, (uint16, bytes32, string));
        emit CrossChainSync(originalChainId, syncId, status);
    }

    function getMessageHash(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    tokens,
                    amounts,
                    dexes,
                    bridges,
                    chainIds,
                    recipient,
                    nonce
                )
            );
    }

    function getEthSignedMessageHash(
        bytes32 messageHash
    ) public pure returns (bytes32) {
        return MessageHashUtils.toEthSignedMessageHash(messageHash);
    }

    function verifySignature(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory dexes,
        address[] memory bridges,
        uint16[] memory chainIds,
        address recipient,
        uint256 nonce,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 messageHash = getMessageHash(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );
        return recoveredSigner == owner();
    }

    function getArbParams() external view returns (ArbParams memory) {
        return arbParams;
    }

    function getEndPoint() external view returns (address) {
        return endpointAddr;
    }

    function getRecoverSigner(
        bytes32 ethSignedHash,
        bytes memory signature
    ) external pure returns (address) {
        return ECDSA.recover(ethSignedHash, signature);
    }
}
