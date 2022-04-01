// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "./Subscribable.sol";
import "../../../nft/DefiMinerNFT.sol";

abstract contract GeneratorSubscriber is Subscriber {
    function onCalculateLoot(
        DefiMinerNFT _nft,
        uint256 _tokenID,
        uint256 alreadyCalculated
    ) external view virtual returns (uint256 additionalLoot) {return 0;}

    function onRefuel() external virtual {}
}
