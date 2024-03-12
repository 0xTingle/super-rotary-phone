// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {DN404} from "../DN404.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title SimpleDN404
 * @notice Sample DN404 contract that demonstrates the owner selling fungile tokens.
 * When a user has at least one base unit (10^18) amount of tokens, they will automatically receive an NFT.
 * NFTs are minted as an address accumulates each base unit amount of tokens.
 */
contract Underworld is DN404, Ownable, UUPSUpgradeable {
    string private _name;
    string private _symbol;
    string private _baseURI;

    constructor() payable {
        _initializeOwner(address(1));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _guardInitializeOwner() internal pure virtual override(Ownable) returns (bool) {
        return true;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialTokenSupply,
        address initialSupplyOwner,
        address mirror
    ) public payable {
        _initializeOwner(msg.sender);

        _name = name_;
        _symbol = symbol_;

        _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory result) {
        if (bytes(_baseURI).length != 0) {
            result = string(abi.encodePacked(_baseURI, LibString.toString(tokenId)));
        }
    }

    function setNameAndSymbol(string calldata name_, string calldata symbol_) public onlyOwner {
        _name = name_;
        _symbol = symbol_;
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function setSkipNFTFor(address account, bool state) public onlyOwner {
        _setSkipNFT(account, state);
    }

    function setExchangeNFTFeeRate(uint256 feeBips) public onlyOwner {
        _setExchangeNFTFeeRate(feeBips);
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }
}
