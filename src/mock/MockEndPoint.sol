// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockLZEndpoint {
    address public delegate;

    event MessageSent(
        uint16 indexed chainId,
        bytes payload,
        bytes options,
        uint256 nativeFee,
        address sender
    );

    function send(
        uint16 _chainId,
        bytes calldata _payload,
        bytes calldata _options,
        uint256 _nativeFee
    ) external payable {
        emit MessageSent(_chainId, _payload, _options, _nativeFee, msg.sender);
    }

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }
}
