// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

import {StakingLibrary} from "../../util/libraries/StakingLibrary.sol";

import "../DefiMinerNFT.sol";
import "../../util/interfaces/subscriber/Subscribable.sol";
import "../../util/interfaces/subscriber/StakingSubscriber.sol";
import "../../util/Whitelist.sol";

/// @title The codebase for staking NFTs.
/// @author Lukas Jonsson
/// @notice This is a basic NFT Staking Contract that is used for every nft of MinerBox.
/// @dev Only whitelisted nfts can be minted.

contract NFTStaking is Subscribable {
    // ## Variables ##

    uint256 private lockingPeriod;
    Whitelist private whitelist;

    mapping(DefiMinerNFT => uint256) staked;
    mapping(DefiMinerNFT => mapping(uint256 => StakingLibrary.NFTStakingInfo)) stakingVault;

    // ## Event ##

    event Staked(address staker, DefiMinerNFT _nft, uint256 _tokenID);
    event UnStaked(address staker, DefiMinerNFT _nft, uint256 _tokenID);

    // ## Constructor ##

    /// @param _lockingPeriodInDays the number of days the nft is blocked until it can be unstaked
    constructor(ProjectOwnership _ownership, uint256 _lockingPeriodInDays)
        Subscribable(_ownership)
    {
        require(
            _lockingPeriodInDays >= 1,
            "Staking: Minimum locking period for nfts is 1 day"
        );
        lockingPeriod = _lockingPeriodInDays;
        whitelist = new Whitelist(_ownership);
    }

    // ## External functions ##

    /// @notice Allows to stake a certain nft token
    /// @param _nft the address of the nft you want to stake
    /// @param _tokenID the id of the token you want to stake
    function stake(DefiMinerNFT _nft, uint256 _tokenID) external {
        requireNFTOwnership(_nft, _tokenID);

        StakingLibrary.NFTStakingInfo storage stakingInfo = stakingVault[_nft][
            _tokenID
        ];

        stakingInfo.exist = true;
        stakingInfo.tokenID = _tokenID;

        if (stakingInfo.stakingPeriods.length > 0) {
            StakingLibrary.StakingPeriod storage stakingPeriod = stakingInfo
                .stakingPeriods[stakingInfo.stakingPeriods.length - 1];
            /// @dev staking is only possible if the nft is currently unstaked
            require(
                stakingPeriod.unstake > 0,
                "NFTS: Your NFT is already staked."
            );
        }

        uint256 startStake = block.timestamp;
        uint256 blockedUntil = startStake + (lockingPeriod * 3600 * 24);


        /// @dev triggers the onStake functions of the subscribers.
        for (uint256 i = 0; i < subscribers.length; i++) {
            StakingSubscriber sub = StakingSubscriber(address(subscribers[i]));
            sub.onStake(_nft, _tokenID);
        }

        /// @dev this function starts a new stakingPeriod
        stakingInfo.stakingPeriods.push(
            StakingLibrary.StakingPeriod(startStake, blockedUntil, 0)
        );
        staked[_nft] += 1;

        emit Staked(msg.sender, _nft, _tokenID);

        /// @dev blocks the nft
        _nft.blockNFT(_tokenID);
    }

    /// @notice Allows to unstake a certain nft token
    /// @param _nft the address of the nft you want to unstake
    /// @param _tokenID the id of the token you want to unstake
    function unStake(DefiMinerNFT _nft, uint256 _tokenID) external {
        requireNFTOwnership(_nft, _tokenID);

        StakingLibrary.NFTStakingInfo storage stakingInfo = stakingVault[_nft][
            _tokenID
        ];

        require(stakingInfo.exist, "Staking: NFT is not staked.");
        StakingLibrary.StakingPeriod[] storage periods = stakingInfo
            .stakingPeriods;

        require(periods.length > 0, "Staking: This NFT was never staked.");
        StakingLibrary.StakingPeriod storage latestStakingPeriod = periods[
            periods.length - 1
        ];

        require(
            latestStakingPeriod.unstake == 0,
            "Staking: The NFT is not staked right now."
        );
        require(
            block.timestamp >= latestStakingPeriod.blockedUntil,
            "Staking: This NFT is still locked."
        );

        /// @dev trigger the subscriber functions
        for (uint256 i = 0; i < subscribers.length; i++) {
            StakingSubscriber sub = StakingSubscriber(address(subscribers[i]));
            sub.onUnStake(_nft, _tokenID);
        }

        latestStakingPeriod.unstake = block.timestamp;
        staked[_nft] -= 1;

        emit UnStaked(msg.sender, _nft, _tokenID);

        _nft.unblockNFT(_tokenID);
    }

    // ### External view functions ###

    /// @return stakingInfo all staking information that exists for this token
    function getStakingInfo(DefiMinerNFT _nft, uint256 _tokenID)
        external
        view
        returns (StakingLibrary.NFTStakingInfo memory stakingInfo)
    {
        require(
            whitelist.getWhitelistStatus(address(_nft)),
            "Staking: This NFT is not an original MinerBox NFT."
        );
        StakingLibrary.NFTStakingInfo memory info = stakingVault[_nft][
            _tokenID
        ];
        /// @dev If there is no staking Information also set the tokenID value of the empty struct that is returned
        if (!info.exist) info.tokenID = _tokenID;
        return info;
    }

    function getLockingPeriod() external view returns (uint256 _lockingPeriod) {
        return lockingPeriod;
    }

    /// @return amountStaked the amount of staked nfts of a certain nft type
    function getStakedAmount(DefiMinerNFT _nft)
        external
        view
        returns (uint256 amountStaked)
    {
        return staked[_nft];
    }

    function getWhitelist() external view returns (Whitelist) {
        return whitelist;
    }

    // ## Internal Functions ##

    function requireNFTOwnership(DefiMinerNFT _nft, uint256 _tokenID) internal view {
        require(
            whitelist.getWhitelistStatus(address(_nft)),
            "Staking: This NFT is not an original MinerBox NFT."
        );
        require(
            _nft.balanceOf(msg.sender) > 0,
            "Staking: You don't own any NFTs of this kind."
        );
        require(
            _nft.ownerOf(_tokenID) == msg.sender,
            "Staking: You are not the owner of this particular NFT."
        );
    }
}
