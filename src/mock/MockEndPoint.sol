// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

contract MockLZEndpoint {
    address public delegate;

    event MessageSent(
        uint16 indexed chainId,
        bytes payload,
        bytes options,
        uint256 nativeFee,
        address sender
    );

    mapping(uint32 eid => bytes32 peer) public peers;

    function send(
        uint16 _chainId,
        bytes calldata _payload,
        bytes calldata _options,
        uint256 _nativeFee
    ) external payable {
        emit MessageSent(_chainId, _payload, _options, _nativeFee, msg.sender);
    }

    function setPeer(uint16 chainId, address arbitrageContract) external {
        peers[chainId] = bytes32(uint256(uint160(arbitrageContract)));
        console.log(
            "Peer set for chainId:",
            chainId,
            " with address:",
            arbitrageContract
        );
    }

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }
}
