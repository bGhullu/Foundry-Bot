//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {OApp, MessagingFee, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MainContract is OApp, Ownable {
    address endpoint;

    constructor(
        address _endpoint
    ) OApp(_endpoint, msg.sender) Ownable(msg.sender) {
        endpoint = _endpoint;
    }
}
