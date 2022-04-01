// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../util/ownership/ProjectOwnable.sol";
import "../../../nft/staking/NFTStaking.sol";

/// @title StakingDependant requires a staker as constructor argument
/// @author Lukas Jonsson
/// @dev An interface to reduce duplicated code
abstract contract StakingDependant is ProjectOwnable {
    NFTStaking staker;

    // A modifier to prevent any caller except from the shop to call a method
    modifier onlyStaker() {
        require(
            address(staker) == msg.sender,
            "StakingDependant: Caller ist not the Staker"
        );
        _;
    }

    constructor(ProjectOwnership _ownership, NFTStaking _staker)
        ProjectOwnable(_ownership)
    {
        staker = _staker;
    }

    function setStaker(NFTStaking _staker) external onlyProject {
        staker = _staker;
    }

    function getStaker() external view returns (NFTStaking) {
        return staker;
    }
}
