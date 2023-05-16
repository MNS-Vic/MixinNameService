//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";
import {StringUtils} from "./StringUtils.sol";
import {Resolver} from "../resolvers/Resolver.sol";
import {ReverseRegistrar} from "../registry/ReverseRegistrar.sol";
import {IMixinRegistrarController, IPriceOracle} from "./IMixinRegistrarController.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {INameWrapper} from "../wrapper/INameWrapper.sol";
import {ERC20Recoverable} from "../utils/ERC20Recoverable.sol";

error CommitmentTooNew(bytes32 commitment);
error CommitmentTooOld(bytes32 commitment);
error NameNotAvailable(string name);
error DurationTooShort(uint256 duration);
error ResolverRequiredWhenDataSupplied();
error UnexpiredCommitmentExists(bytes32 commitment);
error InsufficientValue();
error InvalidCaller();
error Unauthorised(bytes32 node);
error MaxCommitmentAgeTooLow();
error MaxCommitmentAgeTooHigh();

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract MixinRegistrarController is
    Ownable,
    IMixinRegistrarController,
    IERC165,
    ERC20Recoverable
{
    using StringUtils for *;
    using Address for address;

    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;
    bytes32 private constant MIXIN_NODE =
        0x8c5d48f8096ceef6fc7b28f3610c980b07a951e66ce2827868b3de5309dc37b8;
    uint64 private constant MAX_EXPIRY = type(uint64).max;
    BaseRegistrarImplementation immutable base;
    IPriceOracle public prices;
    ReverseRegistrar public immutable reverseRegistrar;

    mapping(bytes32 => uint256) public commitments;
    address operatorAddress;
    uint256 minDigit = 3;

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );
    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint256 cost,
        uint256 expires
    );

    constructor(
        BaseRegistrarImplementation _base,
        IPriceOracle _prices,
        ReverseRegistrar _reverseRegistrar
    ) {
        base = _base;
        prices = _prices;
        reverseRegistrar = _reverseRegistrar;
    }

    function rentPrice(
        string memory name,
        uint256 duration
    ) public view override returns (IPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.price(name, base.nameExpires(uint256(label)), duration);
    }

    function valid(string memory name) public view returns (bool) {
        return name.strlen() >= minDigit;
    }

    function available(string memory name) public view override returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function setMinDigit(uint256 digit) public {
        minDigit = digit;
    }

    function getMinDigit() public view returns (uint256) {
        return minDigit;
    }

    function getOperator() public view returns (address) {
        return operatorAddress;
    }

    function setPriceOracle(IPriceOracle addrs) public onlyOwner {
        prices = addrs;
    }

    function setOperatorAddress(address addrs) public onlyOwner {
        operatorAddress = addrs;
    }

    function register(
        string calldata name,
        uint256 duration,
        address resolver,
        bytes[] calldata data,
        bool reverseRecord
    ) public override {
        if (operatorAddress != msg.sender) {
            revert InvalidCaller();
        }

        IPriceOracle.Price memory price = rentPrice(name, duration);

        if (!available(name)) {
            revert NameNotAvailable(name);
        }

        // Set this contract as the (temporary) owner, giving it
        // permission to set up the resolver.
        uint256 expires = base.register(
            uint256(keccak256(bytes(name))),
            address(this),
            duration
        );

        // Set the resolver
        base.mns().setResolver(
            keccak256(
                abi.encodePacked(base.baseNode(), keccak256(bytes(name)))
            ),
            resolver
        );
        address owner = owner();
        // Now transfer full ownership to the expeceted owner
        base.reclaim(uint256(keccak256(bytes(name))), owner);
        base.transferFrom(
            address(this),
            owner,
            uint256(keccak256(bytes(name)))
        );

        if (data.length > 0) {
            _setRecords(resolver, keccak256(bytes(name)), data);
        }

        if (reverseRecord) {
            _setReverseRecord(name, resolver, msg.sender);
        }

        emit NameRegistered(
            name,
            keccak256(bytes(name)),
            owner,
            price.base,
            price.premium,
            expires
        );
    }

    function renew(string calldata name, uint256 duration) external override {
        if (operatorAddress != msg.sender) {
            revert InvalidCaller();
        }
        bytes32 labelhash = keccak256(bytes(name));
        IPriceOracle.Price memory price = rentPrice(name, duration);
        uint256 expires = base.renew(uint256(labelhash), duration);

        emit NameRenewed(name, labelhash, price.base + price.premium, expires);
    }

    function withdraw() public {
        payable(owner()).transfer(address(this).balance);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IMixinRegistrarController).interfaceId;
    }

    function _setRecords(
        address resolverAddress,
        bytes32 label,
        bytes[] calldata data
    ) internal {
        // use hardcoded .mixin namehash
        Resolver resolver = Resolver(resolverAddress);
        resolver.multicallWithNodeCheck(
            keccak256(abi.encodePacked(MIXIN_NODE, label)),
            data
        );
    }

    function _setReverseRecord(
        string memory name,
        address resolver,
        address owner
    ) internal {
        reverseRegistrar.setNameForAddr(
            msg.sender,
            owner,
            resolver,
            string.concat(name, ".mixin")
        );
    }
}
