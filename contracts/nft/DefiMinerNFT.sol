// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./NFTShop.sol";
import "./staking/NFTStaking.sol";

import "../util/ownership/ProjectOwnable.sol";

/// @title The codebase for any stackable NFT MinerBox is about to sell.
/// @author Lukas Jonsson
/// @notice This is a basic NFT Contract that is used for every nft of MinerBox.
/// @dev The NFTs are only mintable through official Shop Contracts. They can only be blocked by official Staking Contracts.

contract DefiMinerNFT is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    ProjectOwnable
{
    // ## Variables ##
    using Counters for Counters.Counter;

    // Token Counter
    Counters.Counter private _tokenIdCounter;
    // base uri of the nft
    string private baseURI;
    // shop that mints this nft
    NFTShop private shop;
    // staker that blocks this nft
    NFTStaking private staker;
    // unchangeable maxAmount of sellable NFTs
    uint256 private saleLimit;
    // unchangeable maxAmount of giftable NFTs
    uint256 private giftLimit;
    // Mapping that saves whether an NFT is blocked through staking or not.
    mapping(uint256 => bool) blocked;

    // ## Modifiers ##

    /// @notice A modifier that only allows the shop to trigger a function.
    /// @dev The Shop Variable is set in constructor and can be changed afterwards.
    modifier onlyShop() {
        require(address(shop) == _msgSender(), "NFT: Caller ist not the Shop");
        _;
    }

    /// @notice A modifier that only allows the staker to trigger a function.
    /// @dev The Shop Variable is set in constructor and can be changed afterwards.
    modifier onlyStaker() {
        require(
            address(staker) == _msgSender(),
            "NFT: Caller ist not the Staker"
        );
        _;
    }

    // ## Constructors ##

    constructor(
        ProjectOwnership _ownership,
        string memory _nftName,
        string memory _nftSymbol,
        uint256 _saleLimit,
        uint256 _giftLimit,
        NFTShop _shop,
        NFTStaking _staker
    ) ERC721(_nftName, _nftSymbol) ProjectOwnable(_ownership) {
        shop = _shop;
        staker = _staker;
        saleLimit = _saleLimit;
        giftLimit = _giftLimit;
    }

    // ## External functions ##

    /// @notice Used to set baseURI
    function setBaseURI(string memory _newBaseURI) external onlyProject {
        baseURI = _newBaseURI;
    }

    /// @notice Function to mint an NFT.
    /// @dev This can only be called by the shop address.
    function safeMint(address to) external onlyShop {
        require(
            totalSupply() + 1 <= saleLimit + giftLimit,
            "The max amount of nfts was minted."
        );
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    /// @notice Completely blocks the nft.
    function blockNFT(uint256 _tokenID) external onlyStaker {
        blocked[_tokenID] = true;
    }

    /// @notice Unblocks the nft.
    function unblockNFT(uint256 _tokenID) external onlyStaker {
        blocked[_tokenID] = false;
    }

    /// @dev Setter Functions

    function setShop(NFTShop _shop) external onlyProject {
        shop = _shop;
    }

    function setStaker(NFTStaking _staker) external onlyProject {
        staker = _staker;
    }

    // ### External View Functions ###

    /// @dev Getter Functions

    /// @notice Returns the tokenID of the next minted NFT.
    function getNextTokenID() external view returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        return ++tokenId;
    }

    function getShop() external view returns (NFTShop) {
        return shop;
    }

    function getStaker() external view returns (NFTStaking) {
        return staker;
    }

    function getSaleLimit() external view returns (uint256 nftSaleLimit) {
        return saleLimit;
    }

    function getGiftLimit() external view returns (uint256 nftGiftLimit) {
        return giftLimit;
    }

    // ## Public View Functions ##

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ## Internal Functions ##

    // This function override is required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        if (blocked[tokenId])
            revert("NFT: This NFT is currently blocked.");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
