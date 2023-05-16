//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import "./IPriceOracle.sol";

interface IMixinRegistrarController {
    function rentPrice(string memory, uint256)
        external
        view
        returns (IPriceOracle.Price memory);

    function available(string memory) external returns (bool);

    function register(
        string calldata,
        uint256,
        address,
        bytes[] calldata,
        bool
    ) external;

    function renew(string calldata, uint256) external;
}
