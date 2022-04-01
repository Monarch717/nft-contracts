// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

library StakingLibrary {
    struct NFTStakingInfo {
        StakingPeriod[] stakingPeriods;
        uint256 tokenID;
        bool exist;
    }

    struct StakingPeriod {
        uint256 startStake;
        uint256 blockedUntil;
        uint256 unstake;
    }
}
