// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "./Subscribable.sol";
import "../../../nft/DefiMinerNFT.sol";

/// @title A simple subscriber for the Staking contract
/// @author Lukas Jonsson
abstract contract StakingSubscriber is Subscriber {
    function onStake(DefiMinerNFT _nft, uint256 _tokenID) external virtual {}
    function onUnStake(DefiMinerNFT _nft, uint256 _tokenID) external virtual {}
}
