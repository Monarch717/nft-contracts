// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../MinerBoxCoin.sol";
import "../../nft/staking/NFTStaking.sol";
import "../../util/interfaces/dependant/StakingDependant.sol";

contract CoinGenerator is StakingDependant {
    MinerBoxCoin private coinToGenerate;
    uint256 private generationRatePerDay;
    GenerationData[] private generationDataArray;

    //TODO: Constructor argument / getter / setter
    uint256 timeAddedRefueling = 28 * 3600 * 24;
    uint256 maxRefuelPeriods = 6;
    uint256 fuelPercentageLeftToAllowRefuel = 30;
    uint256 publicDiscountPercentage = 0;

    ERC20 refuelingToken;
    address refuelingTreasury;

    mapping(uint256 => RefuelingMultiplier) refuelingFees;

    mapping(DefiMinerNFT => mapping(uint256 => PayoutData)) payoutDataPerNFT;
    mapping(DefiMinerNFT => mapping(uint256 => FuelData[])) fuelDataPerNFT;

    constructor(
        ProjectOwnership _ownership,
        MinerBoxCoin _coinToGenerate,
        NFTStaking _staker,
        uint256 _generationRatePerDay,
        ERC20 _refuelingToken,
        address _refuelingTreasury
    ) StakingDependant(_ownership, _staker) {
        coinToGenerate = _coinToGenerate;
        generationDataArray.push(
            GenerationData(_generationRatePerDay, block.timestamp)
        );

        refuelingToken = _refuelingToken;
        refuelingTreasury = _refuelingTreasury;
    }

    function addRefuelingFee(
        uint256 _feeAmount,
        uint256 _multiplier,
        uint256 _decimalPlaces
    ) external onlyProject {
        refuelingFees[_feeAmount] = RefuelingMultiplier(
            _multiplier,
            _decimalPlaces,
            true
        );
    }

    function removeRefuelingFee(uint256 _feeAmount) external onlyProject {
        delete refuelingFees[_feeAmount];
    }

    function refuelMachine(
        DefiMinerNFT _nft,
        uint256 _tokenID,
        uint256 _feeAmount,
        uint256 periodsToPay
    ) external {
        require(
            staker.getWhitelist().getWhitelistStatus(address(_nft)) == true,
            "YS: This NFT is not an original MinerBox NFT."
        );
        require(
            _nft.balanceOf(msg.sender) > 0,
            "YS: You don't own any NFTs of this kind."
        );
        require(
            _nft.ownerOf(_tokenID) == msg.sender,
            "YS: You are not the owner of this particular NFT."
        );
        uint256 feeAmountAfterDiscount = _feeAmount -
            ((_feeAmount * publicDiscountPercentage) / 100);

        require(
            periodsToPay > 0 && periodsToPay <= maxRefuelPeriods,
            "Illegal RefuelPeriod Argument"
        );
        require(
            refuelingFees[_feeAmount].exist,
            "You can't refuel this amount."
        );
        require(
            refuelingToken.allowance(msg.sender, address(this)) >=
                feeAmountAfterDiscount * periodsToPay,
            "Refuelling Token not approved"
        );
        require(
            refuelingToken.balanceOf(msg.sender) >=
                feeAmountAfterDiscount * periodsToPay,
            "Refuelling Token not approved"
        );

        RefuelingMultiplier memory refuelMultiplier = refuelingFees[_feeAmount];
        FuelData[] storage fuelDataArray = fuelDataPerNFT[_nft][_tokenID];

        uint256 newFuelUntil = block.timestamp +
            (periodsToPay * timeAddedRefueling);

        // There is still some fuel left.
        // Then we need to check if it is allowed yet to refuel.
        if (
            fuelDataArray.length > 0 &&
            block.timestamp < fuelDataArray[fuelDataArray.length - 1].fuelUntil
        ) {
            uint256 fuelTimeLeft = fuelDataArray[fuelDataArray.length - 1]
                .fuelUntil - block.timestamp;
            uint256 percentageLeft = (fuelTimeLeft * 100) / timeAddedRefueling;
            require(
                percentageLeft <= fuelPercentageLeftToAllowRefuel,
                "You can't refuel yet."
            );
            // Refuel is made for when fuel runs out.
            newFuelUntil =
                fuelDataArray[fuelDataArray.length - 1].fuelUntil +
                (periodsToPay * timeAddedRefueling);
        }

        // Pay the refuel
        refuelingToken.transferFrom(
            msg.sender,
            refuelingTreasury,
            feeAmountAfterDiscount * periodsToPay
        );
        // Add the refuleing to the storage
        fuelDataArray.push(
            FuelData(
                block.timestamp,
                newFuelUntil,
                refuelMultiplier.multiplier,
                refuelMultiplier.decimalPlaces
            )
        );
    }

    function claimCoins(DefiMinerNFT _nft, uint256 _tokenID) external {
        require(
            staker.getWhitelist().getWhitelistStatus(address(_nft)) == true,
            "YS: This NFT is not an original MinerBox NFT."
        );
        require(
            _nft.balanceOf(msg.sender) > 0,
            "YS: You don't own any NFTs of this kind."
        );
        require(
            _nft.ownerOf(_tokenID) == msg.sender,
            "YS: You are not the owner of this particular NFT."
        );

        PayoutCalculationData memory payoutCalcData = calculateClaimableCoins(
            _nft,
            _tokenID
        );
        PayoutData storage payoutData = payoutDataPerNFT[_nft][_tokenID];

        payoutData.lastGenDataArrayIndex = payoutCalcData.lastGenDataArrayIndex;
        payoutData.lastClaim = payoutCalcData.lastClaim;

        require(
            coinToGenerate.balanceOf(address(this)) > generationRatePerDay,
            "The reward pool doesn't have enough tokens left to trigger a payout."
        );

        if (
            coinToGenerate.balanceOf(address(this)) <
            payoutCalcData.calculatedCoins
        ) {
            // If only a portion can be claimed. Claim the portion and save the rest for later.
            payoutData.leftToClaim =
                payoutCalcData.calculatedCoins -
                coinToGenerate.balanceOf(address(this));
            coinToGenerate.transfer(
                msg.sender,
                coinToGenerate.balanceOf(address(this))
            );
        } else {
            coinToGenerate.transfer(msg.sender, payoutCalcData.calculatedCoins);
        }
    }

    //TODO: Add Subscriber that can add additionalLoot.
    function calculateClaimableCoins(DefiMinerNFT _nft, uint256 _tokenID)
        public
        view
        returns (PayoutCalculationData memory payoutCalcData)
    {
        PayoutData memory payoutData = payoutDataPerNFT[_nft][_tokenID];
        FuelData[] memory fuelDataArray = fuelDataPerNFT[_nft][_tokenID];
        if (fuelDataArray.length == 0) return PayoutCalculationData(0, 0, 0);

        uint256 calculatedCoins;
        uint256 lastClaim;
        uint256 lastGenDataArrayIndex;

        uint256 genDataArrayIndex = payoutData.lastGenDataArrayIndex;

        for (
            uint256 i = payoutData.lastFuelDataArrayIndex;
            i < fuelDataArray.length;
            i++
        ) {
            FuelData memory fuelData = fuelDataArray[i];

            // We split the fuel phase into subphases from one generationRateChange to the next.
            // If our lastClaim was after the fuelUp -> Start the subPhase at lastClaim
            uint256 subPayoutPhaseStart = payoutData.lastClaim >
                fuelData.fueledUp
                ? payoutData.lastClaim
                : fuelData.fueledUp;
            uint256 subPayoutPhaseEnd;

            for (
                uint256 j = genDataArrayIndex;
                j < generationDataArray.length;
                j++
            ) {
                GenerationData memory currentGenData = generationDataArray[j];

                // This new payoutRate starts after this fuelData.
                if (
                    generationDataArray[j].timeStampStarted > fuelData.fuelUntil
                ) {
                    // Store j?
                    genDataArrayIndex = j;
                    break;
                }
                // Not last Entry in Array
                if (j + 1 < generationDataArray.length) {
                    subPayoutPhaseEnd = generationDataArray[j + 1]
                        .timeStampStarted > fuelData.fuelUntil
                        ? fuelData.fuelUntil
                        : generationDataArray[j + 1].timeStampStarted;
                } else {
                    subPayoutPhaseEnd = block.timestamp > fuelData.fuelUntil
                        ? fuelData.fuelUntil
                        : block.timestamp;
                }

                // Skip this generationRate
                if (subPayoutPhaseEnd > subPayoutPhaseStart) continue;
                calculatedCoins +=
                    ((subPayoutPhaseEnd - subPayoutPhaseStart) *
                        (currentGenData.generationRatePerDay / 86400) *
                        fuelData.multiplier) /
                    10**fuelData.decimalPlaces;
                subPayoutPhaseStart = subPayoutPhaseEnd;
            }
        }

        uint256 timeFrame;
        for (
            uint256 i = payoutData.lastGenDataArrayIndex;
            i < generationDataArray.length;
            i++
        ) {
            GenerationData memory currentGenData = generationDataArray[i];

            uint256 a = payoutData.lastClaim >= currentGenData.timeStampStarted
                ? payoutData.lastClaim
                : currentGenData.timeStampStarted;

            // i is not the last entry in the array
            if (i + 1 < generationDataArray.length) {
                GenerationData memory nextGenData = generationDataArray[i + 1];
                timeFrame = nextGenData.timeStampStarted - a;
            }
            // i is the last entry
            else timeFrame = block.timestamp - a;

            calculatedCoins = (generationRatePerDay / 86400) * timeFrame;
            lastClaim = block.timestamp;
            lastGenDataArrayIndex = i;
        }

        return
            PayoutCalculationData(
                calculatedCoins + payoutData.leftToClaim,
                lastClaim,
                lastGenDataArrayIndex
            );
    }

    // SETTER
    function changeGenerationRatePerDay(uint256 _newRate) external onlyProject {
        require(
            generationDataArray[generationDataArray.length - 1]
                .generationRatePerDay != _newRate,
            "You have to change the current generation rate."
        );
        generationDataArray.push(GenerationData(_newRate, block.timestamp));
    }

    // GETTER
    function getCurrentGenerationRatePerDay() external view returns (uint256) {
        return
            generationDataArray[generationDataArray.length - 1]
                .generationRatePerDay;
    }

    function getCurrentGenerationRatePerSecond()
        external
        view
        returns (uint256)
    {
        return
            generationDataArray[generationDataArray.length - 1]
                .generationRatePerDay / 86400;
    }

    struct GenerationData {
        uint256 generationRatePerDay;
        uint256 timeStampStarted;
    }

    struct PayoutCalculationData {
        uint256 calculatedCoins;
        uint256 lastClaim;
        uint256 lastGenDataArrayIndex;
    }

    struct PayoutData {
        uint256 lastGenDataArrayIndex;
        uint256 lastFuelDataArrayIndex;
        uint256 leftToClaim;
        uint256 lastClaim;
    }

    struct FuelData {
        uint256 fueledUp;
        uint256 fuelUntil;
        uint256 multiplier;
        uint256 decimalPlaces;
    }

    struct RefuelingMultiplier {
        uint256 multiplier;
        uint256 decimalPlaces;
        bool exist;
    }
}
