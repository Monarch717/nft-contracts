// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../staking/NFTStaking.sol";
import "../../util/interfaces/dependant/StakingDependant.sol";
import "../../util/interfaces/subscriber/StakingSubscriber.sol";
import "./../../nft/DefiMinerNFT.sol";
import "./../../util/libraries/DateTime.sol";

/// @title This contract is used to pay out yield.

contract YieldStorage is StakingDependant, StakingSubscriber {
    using SafeMath for uint256;

    struct PeriodStakingData {
        uint256 startValue;
        uint256 add;
        uint256 sub;
        bool startValueExists;
    }

    struct PayoutData {
        uint256 lastPeriodIndex;
        uint256 lastPeriodPaid;
    }

    struct YieldData {
        uint256 amount;
        uint256 amountNFTsStaked;
    }

    struct CalculatedPayoutData {
        //TODO: Reorganize struct -> Storage efficiency
        bool _newLootFound;
        uint256 _lastPeriodPaid;
        uint256 _additionalLoot;
        uint256 _newLastPeriodIndex;
    }

    ERC20 private payoutToken;
    uint256 private startTime;
    uint256 private periodInSeconds = 24 * 3600 * 7;

    // Contains the staking periods
    mapping(DefiMinerNFT => mapping(uint256 => PeriodStakingData)) stakingCache;
    // A mapping to filter duplicate
    mapping(DefiMinerNFT => mapping(uint256 => mapping(uint256 => bool))) alreadySubtracted;
    // A mapping to store every yield that is added to the pool
    mapping(DefiMinerNFT => mapping(uint256 => YieldData)) yieldCache;
    // Stores eligible payout per user
    mapping(DefiMinerNFT => mapping(uint256 => PayoutData)) nftPayoutData;
    // Stores whether a payout period was cashed out by any user
    mapping(uint256 => bool) alreadyPayoutsHappened;

    /// @param _periodInSeconds How long one payout period will be
    /// @param weekDayStartPeriods The weekDay on which the payout cycle starts. (From 1 to 7)
    constructor(
        ProjectOwnership _ownership,
        NFTStaking _staker,
        ERC20 _payoutToken,
        uint256 _periodInSeconds,
        uint8 weekDayStartPeriods
    ) StakingDependant(_ownership, _staker) {
        startTime = getTimestampSundayLastWeek(
            block.timestamp,
            weekDayStartPeriods
        );

        payoutToken = _payoutToken;
        require(
            _periodInSeconds >= 3600 * 24,
            "YieldStorage: Minimum payout period length is 1 day"
        );
        periodInSeconds = _periodInSeconds;
    }

    event YieldAdded(
        DefiMinerNFT _nft,
        uint256 _amount,
        uint256 _timestamp,
        uint256 _periodOfYield
    );
    event Cashout(
        address miner,
        DefiMinerNFT _nft,
        uint256 _tokenID,
        uint256 _amount
    );
    event NFTStaked(
        address miner,
        DefiMinerNFT _nft,
        uint256 _tokenID,
        uint256 period,
        uint256 _timestamp
    );
    event NFTUnStaked(
        address miner,
        DefiMinerNFT _nft,
        uint256 _tokenID,
        uint256 period,
        uint256 _timestamp
    );

    // ## External Functions ##
    // Adds Yield to the pool.
    function addYield(
        DefiMinerNFT _nft,
        uint256 _amount,
        uint256 _timestamp
    ) external onlyProject {
        uint256 currentPeriodID = calculatePeriodIdentifier(block.timestamp);
        uint256 periodOfYield = calculatePeriodIdentifier(_timestamp);
        require(
            staker.getWhitelist().getWhitelistStatus(address(_nft)),
            "YieldStorage: This NFT is not an original MinerBox NFT."
        );
        require(_amount > 0, "Amount has to be > 0");
        require(
            payoutToken.allowance(msg.sender, address(this)) >= _amount,
            "YieldStorage: Yield token not approved"
        );
        require(
            payoutToken.balanceOf(msg.sender) >= _amount,
            "YieldStorage: Not enough funds"
        );
        require(
            currentPeriodID >= periodOfYield,
            "YieldStorage: can't add Yield to an period that has not passed completely."
        );
        require(
            !alreadyPayoutsHappened[periodOfYield],
            "YieldStorage: can't add yield to this period anymore."
        );

        YieldData storage yieldData = yieldCache[_nft][periodOfYield];
        yieldData.amountNFTsStaked = getStakedNFTs(_nft, _timestamp);
        yieldData.amount += _amount;

        emit YieldAdded(_nft, _amount, _timestamp, periodOfYield);

        bool worked = payoutToken.transferFrom(msg.sender, address(this), _amount);
        assert(worked);
    }

    // Triggers a cashout for the msg.sender
    // Also calculates new eligible cashout
    function cashout(DefiMinerNFT _nft, uint256 _tokenID)
        external
        returns (uint256 cashoutAmount)
    {
        require(
            staker.getWhitelist().getWhitelistStatus(address(_nft)),
            "YieldStorage: This NFT is not an original MinerBox NFT."
        );
        require(
            _nft.balanceOf(msg.sender) > 0,
            "YieldStorage: You don't own any NFTs of this kind."
        );
        require(
            _nft.ownerOf(_tokenID) == msg.sender,
            "YieldStorage: You are not the owner of this particular NFT."
        );
        CalculatedPayoutData memory calculatedPayoutData = calculatePayoutData(
            _nft,
            _tokenID
        );
        PayoutData storage payoutData = nftPayoutData[_nft][_tokenID];

        if (calculatedPayoutData._newLootFound) {
            payoutData.lastPeriodPaid = calculatedPayoutData._lastPeriodPaid;
            payoutData.lastPeriodIndex = calculatedPayoutData
                ._newLastPeriodIndex;
            alreadyPayoutsHappened[payoutData.lastPeriodPaid] = true;
        }

        uint256 tokenAmountToSend = calculatedPayoutData._additionalLoot;
        require(
            tokenAmountToSend > 0,
            "YieldStorage: You can only cashout yield if there is yield left for you."
        );
        require(
            payoutToken.balanceOf(address(this)) >= tokenAmountToSend,
            "YieldStorage: YieldPayoutPool is somehow empty."
        );

        emit Cashout(msg.sender, _nft, _tokenID, tokenAmountToSend);

        bool worked = payoutToken.transfer(msg.sender, tokenAmountToSend);
        assert(worked);
        return tokenAmountToSend;
    }

    // Subscription method
    function onStake(DefiMinerNFT _nft, uint256 _tokenID)
        external
        override
        onlyStaker
    {
        uint256 periodID = calculatePeriodIdentifier(block.timestamp);
        PeriodStakingData storage stakingData = stakingCache[_nft][periodID];

        if (!stakingData.startValueExists) {
            stakingData.startValue = staker.getStakedAmount(_nft);
            stakingData.startValueExists = true;
        }
        stakingData.add += 1;

        emit NFTStaked(msg.sender, _nft, _tokenID, periodID, block.timestamp);
    }

    // Subscription method
    function onUnStake(DefiMinerNFT _nft, uint256 _tokenID)
        external
        override
        onlyStaker
    {
        uint256 periodID = calculatePeriodIdentifier(block.timestamp);
        PeriodStakingData storage stakingData = stakingCache[_nft][periodID];

        if (!stakingData.startValueExists) {
            stakingData.startValue = staker.getStakedAmount(_nft);
            stakingData.startValueExists = true;
        }

        // If an NFT would unstake twice in 1 period it wouldn't count twice.
        if (!alreadySubtracted[_nft][periodID][_tokenID]) {
            stakingData.sub += 1;
            alreadySubtracted[_nft][periodID][_tokenID] = true;
        }

        emit NFTUnStaked(msg.sender, _nft, _tokenID, periodID, block.timestamp);
    }

    // ### External View Functions ###

    // Calculates eligible payout + the already stored loot
    function getClaimableLoot(DefiMinerNFT _nft, uint256 _tokenID)
    external
    view
    returns (uint256 claimableLoot)
    {
        CalculatedPayoutData memory calculatedPayoutData = calculatePayoutData(
            _nft,
            _tokenID
        );
        return (calculatedPayoutData._additionalLoot);
    }

    function getStartTime() external view returns (uint256) {
        return startTime;
    }

    function getPeriodTime() external view returns (uint256) {
        return periodInSeconds;
    }

    // Getter function // Used for testing purposes only
    function getBlockTime() external view returns (uint256) {
        return block.timestamp;
    }

    function getPayoutToken() external view returns (ERC20) {
        return payoutToken;
    }

    // ## Public Functions ##

    // Calculates the nfts that where fully staked in a certain time period
    function getStakedNFTs(DefiMinerNFT _nft, uint256 _timestamp)
        public
        view
        returns (uint256)
    {
        uint256 periodID = calculatePeriodIdentifier(_timestamp);
        PeriodStakingData memory stakingData = stakingCache[_nft][periodID];

        uint256 stakedNFTs = !stakingData.startValueExists
            ? staker.getStakedAmount(_nft)
            : stakingData.startValue;
        stakedNFTs -= stakingData.sub;

        return stakedNFTs;
    }

    // Calculates to which period the _timestamp belongs.
    function calculatePeriodIdentifier(uint256 _timestamp)
    public
    view
    returns (uint256 payoutID)
    {
        require(_timestamp >= startTime, "YieldStorage: _timestamp must be >= startTime");
        return (_timestamp.sub(startTime)).div(periodInSeconds);
    }

    // ## Internal Functions ##

    // Calculates the new yield since last calculation
    function calculatePayoutData(DefiMinerNFT _nft, uint256 _tokenID)
    internal
    view
    returns (CalculatedPayoutData memory)
    {
        PayoutData memory payoutData = nftPayoutData[_nft][_tokenID];
        StakingLibrary.StakingPeriod[] memory periods = staker
        .getStakingInfo(_nft, _tokenID)
        .stakingPeriods;

        uint256 newLoot = 0;
        uint256 counter = 0;
        bool newLootFound = false;
        for (uint256 i = payoutData.lastPeriodIndex; i < periods.length; i++) {
            StakingLibrary.StakingPeriod memory period = periods[i];
            // excludes the period in which you unstaked or the current period if you are still staked (Since it is not over yet)
            uint256 endOfPayout = period.unstake == 0
            ? calculatePeriodIdentifier(block.timestamp)
            : calculatePeriodIdentifier(period.unstake);

            uint256 startingPeriod = payoutData.lastPeriodPaid >
            calculatePeriodIdentifier(period.startStake)
            ? payoutData.lastPeriodPaid
            : calculatePeriodIdentifier(period.startStake);
            for (uint256 p = startingPeriod + 1; p < endOfPayout; p++) {
                YieldData memory yieldData = yieldCache[_nft][p];
                if (yieldData.amountNFTsStaked > 0)
                    newLoot += yieldData.amount.div(yieldData.amountNFTsStaked);
                payoutData.lastPeriodPaid = p;
            }
            counter = i;
            newLootFound = true;
        }
        return
        CalculatedPayoutData(
            newLootFound,
            payoutData.lastPeriodPaid,
            newLoot,
            counter
        );
    }

    // Calculation for start period
    //TODO: Remove this function
    function getTimestampSundayLastWeek(
        uint256 _timestamp,
        uint256 weekDayStartPeriods
    ) internal pure returns (uint256) {
        require(
            weekDayStartPeriods >= 1 && weekDayStartPeriods <= 7,
            "YieldStorage: weekDayStartPeriods has to be withing 1-7"
        );
        uint256 offsetTime = 3600 * 24 * 7;
        uint256 timeStampAfterOffset = _timestamp - offsetTime;

        uint256 weekDay = DateTime.getWeekday(timeStampAfterOffset);
        uint256 secondsToAdd = (weekDayStartPeriods - weekDay) * 86400;
        DateTime._DateTime memory dateLastDayOfWeek = DateTime.parseTimestamp(
            timeStampAfterOffset + secondsToAdd
        );
        return
        DateTime.toTimestamp(
            dateLastDayOfWeek.year,
            dateLastDayOfWeek.month,
            dateLastDayOfWeek.day
        );
    }
}
