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
    ) OApp(_endpoint, msg.sender) Ownable(msg.sender) {
        emit Debug("Constructor started");
        require(_endpoint != address(0), "Invalid endpoint address");
        emit DebugAddress("Endpoint Address", _endpoint);
        emit DebugAddress("Owner Address", msg.sender);
        emit Debug("Constructor finished");
        _owner = msg.sender;
        endpointAddr = _endpoint;
    }

    function setChainToArbitrageContract(
        uint16 chainId,
        address arbitrageContract
    ) external onlyOwner {
        peers[chainId] = addressToBytes32(arbitrageContract);
        emit PeersSet(chainId, addressToBytes32(arbitrageContract));
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

        bytes32 messageHash = getMessageHash(
            tokens,
            amounts,
            dexes,
            bridges,
            chainIds,
            recipient,
            nonce
        );
        console.log("Message Hash");
        console.logBytes32(messageHash);

        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        console.log("Ethereum Signed Message Hash");
        console.logBytes32(ethSignedMessageHash);
        console.log("Signature");
        console.logBytes(signature);

        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );
        console.log("Contract Recovered Signer", recoveredSigner);
        console.log("Contract Expected Signer", owner());

        require(recoveredSigner == owner(), "Invalid Signature");

        bytes memory payload = abi.encode(
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
        emit DebugUint("Native Fee", nativeFee);
        emit DebugUint("LZ Token Fee", lzTokenFee);

        _lzSend(chainIds[0], payload, options, fee, payable(msg.sender));
    }

    function addressToBytes32(address addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
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

            bytes memory newPayload = abi.encode(
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
        } else if (keccak256(bytes(messageType)) == keccak256("SYNC")) {
            (uint16 originalChainId, bytes32 syncId, string memory status) = abi
                .decode(messageData, (uint16, bytes32, string));
            emit CrossChainSync(originalChainId, syncId, status);
        }
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
        bytes32 ethSingedHash,
        bytes memory signature
    ) external pure returns (address) {
        return ECDSA.recover(ethSingedHash, signature);
    }
}
