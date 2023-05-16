//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(
        address to,
        uint256 value
    ) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface MixinRegistrarController { 
	function register(
        string calldata name,
        uint256 duration,
        address resolver,
        bytes[] calldata data,
        bool reverseRecord
    )  external; 

    function renew(
        string calldata name,
        uint256 duration
    )  external; 

    function rentPrice(string memory, uint256)
        external
        view
        returns (IPriceOracle.Price memory);
}

interface IPriceOracle {
    struct Price {
        uint256 base;
        uint256 premium;
    }
}

error InsufficientValue();

contract MnsDelegate { 
    address public immutable XIN;//0x034a771797a1c8694bc33e1aa89f51d1f828e5a4
    address public immutable MSNCONTROLLER;
    address public immutable receiver;
    uint256 BASE = 100000000;

    constructor(address xin, address controller, address rcver) {
        XIN = xin;
        MSNCONTROLLER = controller;
        receiver = rcver;
    }

    function register(
        string calldata name,
        uint256 duration,
        address resolver,
        bytes[] calldata data,
        bool reverseRecord,
        uint256 amount
    ) public  {
        MixinRegistrarController mnsController = MixinRegistrarController(MSNCONTROLLER);
        IPriceOracle.Price memory price = mnsController.rentPrice(name, duration);
        if (amount * BASE < price.base + price.premium) {
            revert InsufficientValue();
        }

        mnsController.register(name, duration, resolver, data, reverseRecord);

        IERC20 xin = IERC20(XIN);
        xin.transferFrom(msg.sender, address(this), amount);
        xin.transfer(receiver, amount);
    }

    function renew(
        string calldata name,
        uint256 duration,
        uint256 amount
    ) public  {
        MixinRegistrarController mnsController = MixinRegistrarController(MSNCONTROLLER);
        IPriceOracle.Price memory price = mnsController.rentPrice(name, duration);
        if (amount * BASE < price.base + price.premium) {
            revert InsufficientValue();
        }

        mnsController.renew(name, duration);

        IERC20 xin = IERC20(XIN);
        xin.transferFrom(msg.sender, address(this), amount);
        xin.transfer(receiver, amount);
    }
}