// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "../../../nft/DefiMinerNFT.sol";
import "../../Whitelist.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Subscribable.sol";


/// @title A simple subscriber for the shop contract.
/// @author Lukas Jonsson
abstract contract ShopSubscriber is Subscriber {
    function onNFTMint(DefiMinerNFT _nft, uint256 _tokenID) external virtual {}

    function onNFTGift(
        DefiMinerNFT _nft,
        uint256 _firstTokenID,
        uint256 _amount
    ) external virtual {}

    function onBatchCreate(
        DefiMinerNFT _nft,
        ERC20 _priceToken,
        uint256 _pricePerNFT,
        uint256 _maxSellAmount,
        uint256 _alreadySold,
        address _treasuryAddress,
        string memory _description,
        uint256 limitPerCustomer,
        Whitelist _whitelist
    ) external virtual {}
}
