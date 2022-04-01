const assert = require("assert");
const Web3ProviderEngine = require("web3-provider-engine");

const DefiMinerNFT = artifacts.require("DefiMinerNFT");
const NFTShop = artifacts.require("NFTShop");
const TestCoin = artifacts.require("TestCoin");
const NFTStaking = artifacts.require("NFTStaking");
const BN = require('bn.js')
const Whitelist = artifacts.require("Whitelist");
const YieldStorage = artifacts.require("YieldStorage");

const {nftConstants} = require("../scripts/Parameters.js");

const { checkGetFail, checkTransactionFailed, checkTransactionPassed, advanceTime, advanceBlock, takeSnapshot, revertToSnapShot, advanceTimeAndBlock } = require("./lib/utils.js");
const { strictEqual } = require("assert");

let timestampValues = {
    oneDaySeconds: new BN("86400"),
    oneWeekSeconds: new BN("604800"),
    TwoWeeksSeconds: new BN("1209600"),
    ThreeWeeksSeconds: new BN("1814400"),
    FourWeeksSeconds: new BN("2419200"),
}

let errorMessages = {
    noYieldLeft : "YieldStorage: You can only cashout yield if there is yield left for you.",
}

contract("Testing Yield Contract", accounts => {
    let priceToken;
    let shop;
    let nft;
    let staker;
    let yieldStorage;
    let nftWhitelist;

    let owner = accounts[0];
    let nonOwner = accounts[1];
    let treasuryAddress = accounts[2];

    let user1 = accounts[3];
    let user2 = accounts[4];
    let user3 = accounts[5];

    before(async () => {
        priceToken = await TestCoin.deployed();
        shop = await NFTShop.deployed();
        nft = await DefiMinerNFT.deployed();
        staker = await NFTStaking.deployed();
        yieldStorage = await YieldStorage.deployed();
        nftWhitelist = await Whitelist.at(await staker.getWhitelist());
    })

    contract("Testing basic yield functions", accounts => {
        before(async () => {
            await shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("3"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });

            await priceToken.mint(new BN("1000000000000000000"), { from: user1 });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user1 });
            await shop.mintNFT(nft.address, { from: user1 });

            await priceToken.mint(new BN("1000000000000000000"), { from: user2 });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user2 });
            await shop.mintNFT(nft.address, { from: user2 });

            await priceToken.mint(new BN("1000000000000000000"), { from: user3 });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user3 });
            await shop.mintNFT(nft.address, { from: user3 });

            await checkTransactionPassed(nftWhitelist.setWhitelistStatus(nft.address, true, { from: owner }))
        })

        it("should return the right yield period startTime", async () => {
            let startTime = await yieldStorage.getStartTime();
            console.log(new Date(startTime.toNumber() * 1000));
        })

        it("should calculate the right payoutID", async () => {
            let snapshot = await takeSnapshot();
            await advanceTimeAndBlock(3600);
            let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });

            let payoutIDCurrentMonth = await yieldStorage.calculatePeriodIdentifier(currentTime);
            let payoutIDAfter1Months = await yieldStorage.calculatePeriodIdentifier(currentTime.add(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod)));
            let payoutIDAfter2Months = await yieldStorage.calculatePeriodIdentifier(currentTime.add(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod * 2)));
            let payoutIDAfter4Months = await yieldStorage.calculatePeriodIdentifier(currentTime.add(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod * 4)));

            assert(payoutIDCurrentMonth.toNumber() === 0);
            assert(payoutIDAfter1Months.toNumber() === 1);
            assert(payoutIDAfter2Months.toNumber() === 2);
            assert(payoutIDAfter4Months.toNumber() === 4);

            await advanceTimeAndBlock(timestampValues.oneDaySeconds * nftConstants.payoutPeriod);

            let newCurrentTime = await yieldStorage.getBlockTime({ from: nonOwner });
            let payoutIDSub1Month = await yieldStorage.calculatePeriodIdentifier(newCurrentTime.sub(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod)));

            //console.log(payoutID.toNumber());
            //console.log(payoutIDSub2Weeks.toNumber());
            assert(payoutIDSub1Month.toNumber() === 0);

            await revertToSnapShot(snapshot.id);
        })

        it("should return the right amount of NFTs staked #1", async () => {
            let snapshot = await takeSnapshot();
            // Month 1: 2 Staked
            await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.stake(nft.address, 1, { from: user2 }));
            // Month 2: 1 Staked
            await advanceTimeAndBlock(timestampValues.oneDaySeconds * nftConstants.payoutPeriod);
            await checkTransactionPassed(staker.stake(nft.address, 2, { from: user3 }));
            // Month 3: Checking numbers of Week 2
            await advanceTimeAndBlock(timestampValues.oneDaySeconds * nftConstants.payoutPeriod);

            await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.unStake(nft.address, 1, { from: user2 }));
            await checkTransactionPassed(staker.unStake(nft.address, 2, { from: user3 }));

            let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });
            let numberStaked = await yieldStorage.getStakedNFTs(nft.address, await currentTime.sub(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod)), { from: nonOwner });

            assert(numberStaked.eq(new BN("2")), "Printed wrong amount of NFTs");
            await revertToSnapShot(snapshot.id);
        })

        it("should return the right amount of NFTs staked #2", async () => {
            let snapshot = await takeSnapshot();
            // Month 1: 2 Staked
            await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));

            // Month 2: 1 Staked
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
            await checkTransactionPassed(staker.stake(nft.address, 2, { from: user3 }));
            // Month 3: Checking numbers of Week 2
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);

            await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.unStake(nft.address, 2, { from: user3 }));

            let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });
            let numberStaked = await yieldStorage.getStakedNFTs(nft.address, await currentTime.sub(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod)), { from: nonOwner });



            assert(numberStaked.eq(new BN("1")), "Printed wrong amount of NFTs");
            await revertToSnapShot(snapshot.id);
        })

        it("should return the right amount of NFTs staked #3", async () => {
            let snapshot = await takeSnapshot();
            // Month 1: 2 Staked
            await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.stake(nft.address, 1, { from: user2 }));
            // Month 2: 1 Staked
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
            await checkTransactionPassed(staker.stake(nft.address, 2, { from: user3 }));
            // Month 3: 1 unstaked
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
            await checkTransactionPassed(staker.unStake(nft.address, 1, { from: user2 }));
            // Month 4: Checking numbers of Week 2
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);

            await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.unStake(nft.address, 2, { from: user3 }));

            let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });
            let numberStakedWeek2 = await yieldStorage.getStakedNFTs(nft.address, await currentTime.sub(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod * 2)), { from: nonOwner });
            let numberStakedWeek3 = await yieldStorage.getStakedNFTs(nft.address, await currentTime.sub(new BN(timestampValues.oneDaySeconds * nftConstants.payoutPeriod)), { from: nonOwner });

            assert(numberStakedWeek2.eq(new BN("2")));
            assert(numberStakedWeek3.eq(new BN("2")));
            await revertToSnapShot(snapshot.id);
        })

        it("should return the right yield amount #1", async () => {


            let snapshot = await takeSnapshot();
            // Week 1: 2 Staked
            let month1 = await yieldStorage.getBlockTime({ from: nonOwner });
            await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.stake(nft.address, 1, { from: user2 }));


            //console.log("2 Staked in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())));
            // Week 2: 1 Staked
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
            let month2 = await yieldStorage.getBlockTime({ from: nonOwner });
            await checkTransactionPassed(staker.stake(nft.address, 2, { from: user3 }));

            //console.log("1 Staked in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())));
            // Week 3: 1 unstaked
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
            let month3 = await yieldStorage.getBlockTime({ from: nonOwner });
            await checkTransactionPassed(staker.unStake(nft.address, 1, { from: user2 }));

            //console.log("1 UnStaked in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())));
            // Week 5: Checking numbers of Week 2
            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod * 2);
            let month4 = await yieldStorage.getBlockTime({ from: nonOwner });

            let amount = new BN("100000000000000000000");

            // Adding Yield for Week 2

            await priceToken.mint(amount, { from: owner });
            await checkTransactionPassed(priceToken.approve(yieldStorage.address, amount, { from: owner }));
            /*             console.log(
                            "Adding Yield in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())) + 
                            " for period " + (await yieldStorage.calculatePeriodIdentifier(currentTime.sub(timestampValues.ThreeWeeksSeconds))) + 
                            " with "+ (await yieldStorage.getStakedNFTs(nft.address, currentTime.sub(timestampValues.ThreeWeeksSeconds))) +"NFT eligible to get the funds."); */

            await checkTransactionPassed(yieldStorage.addYield(nft.address, amount, month2, { from: owner }))

            await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
            await checkTransactionPassed(staker.unStake(nft.address, 2, { from: user3 }));

            // Adding Yield for Week 2

            let cashoutAmount1 = await (await yieldStorage.cashout(nft.address, 1, { from: user2 })).logs[0].args._amount;
            await checkTransactionFailed(yieldStorage.cashout(nft.address, 1, { from: user2 }), errorMessages.noYieldLeft);
            //console.log("Cashing out " + cashoutAmount1.toString() + " in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())));
            //console.log("Cashing out " + cashoutAmount2.toString() + " in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())));
            assert(cashoutAmount1.eq(new BN("50000000000000000000")));


            // Adding Yield for Week 3
            await priceToken.mint(amount, { from: owner });
            await checkTransactionPassed(priceToken.approve(yieldStorage.address, amount, { from: owner }));
            /*             console.log(
                            "Adding Yield in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())) + 
                            " for period " + (await yieldStorage.calculatePeriodIdentifier(currentTime.sub(timestampValues.TwoWeeksSeconds))) + 
                            " with "+ (await yieldStorage.getStakedNFTs(nft.address, currentTime.sub(timestampValues.TwoWeeksSeconds))) +"NFT eligible to get the funds."); */

            await checkTransactionPassed(yieldStorage.addYield(nft.address, amount, month3, { from: owner }))

            //console.log("Cashing out in Period: " + (await yieldStorage.calculatePeriodIdentifier(await yieldStorage.getBlockTime())));
            await checkTransactionFailed(yieldStorage.cashout(nft.address, 1, { from: user2 }), errorMessages.noYieldLeft);
            let cashoutAmount4 = await (await yieldStorage.cashout(nft.address, 2, { from: user3 })).logs[0].args._amount;
            assert(cashoutAmount4.eq(new BN("50000000000000000000")));

            let cashoutAmount5 = await (await yieldStorage.cashout(nft.address, 0, { from: user1 })).logs[0].args._amount;
            assert(cashoutAmount5.eq(new BN("100000000000000000000")));

            await revertToSnapShot(snapshot.id);
        })
    })

    contract("Simulating some requests", accounts => {
        before(async () => {
            await shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("3"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });

            await priceToken.mint(new BN("1000000000000000000"), { from: user1 });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user1 });
            await shop.mintNFT(nft.address, { from: user1 });

            await priceToken.mint(new BN("1000000000000000000"), { from: user2 });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user2 });
            await shop.mintNFT(nft.address, { from: user2 });

            await priceToken.mint(new BN("1000000000000000000"), { from: user3 });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user3 });
            await shop.mintNFT(nft.address, { from: user3 });

            await checkTransactionPassed(nftWhitelist.setWhitelistStatus(nft.address, true, { from: owner }))
        })

        it("should be able to get the whole payout amount after 1 year with 1 nft random staking", async () => {
            await advanceTimeAndBlock(86400 * 28);

            let amount = new BN("1000000000000000000");

            let staked = false;
            let stakedOn = 0;
            let countedPeriods = 0;

            for (let i = 0; i < 12; i++) {

                let randomPercentage = Math.floor(Math.random() * 101);

                if (randomPercentage <= 40 && !staked) {
                    //console.log("%cStaking [Period " + i + "]", 'color: #68FF33');
                    await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
                    stakedOn = i;
                    staked = true;
                }
                else if (randomPercentage <= 20 && staked && i - stakedOn >= 2) {
                    //console.log("%cUnstaking [Period " + i + "]", 'color: #FF3333');
                    await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
                    staked = false;
                }
                else {
                    if (staked)
                        countedPeriods++;
                }
                let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });
                await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
                await priceToken.mint(amount, { from: owner });
                await checkTransactionPassed(priceToken.approve(yieldStorage.address, amount, { from: owner }));
                await checkTransactionPassed(yieldStorage.addYield(nft.address, amount, currentTime, { from: owner }))
            }
            let claimableLoot = await yieldStorage.getClaimableLoot(nft.address, 0);
            await checkTransactionPassed(yieldStorage.cashout(nft.address, 0, { from: user1 }));

            //console.log("Eligible Periods: " + countedPeriods);
            let assumedLoot = amount.mul(new BN(countedPeriods));
            //console.log("Assumed Loot: " + assumedLoot.toString());
            //console.log("Claimed Loot: " + claimableLoot.toString());

            await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod * 2);
            if (staked)
                await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));

            assert(claimableLoot.eq(assumedLoot));
        })

        it("should be able to get the whole cumulative payout amount after 1 year with 1 nft random staking", async () => {
            await advanceTimeAndBlock(86400 * 28);

            let amount = new BN("1000000000000000000");

            let staked = false;
            let stakedOn = 0;
            let countedPeriods = 0;
            let claimableLoot = 0;

            for (let i = 0; i < 12; i++) {

                let randomPercentage = Math.floor(Math.random() * 101);

                if (randomPercentage <= 40 && !staked) {
                    console.log("%cStaking [Period " + i + "]", 'color: #68FF33');
                    await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
                    stakedOn = i;
                    staked = true;
                }
                else if (randomPercentage <= 30 && staked && i - stakedOn >= 2) {
                    console.log("%cUnstaking [Period " + i + "]", 'color: #FF3333');
                    await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
                    staked = false;
                }
                else {
                    if (staked){
                        countedPeriods++;
                    }
                }
                let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });
                await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);

                await priceToken.mint(amount, { from: owner });
                await checkTransactionPassed(priceToken.approve(yieldStorage.address, amount, { from: owner }));
                //TODO: change to one month
                await checkTransactionPassed(yieldStorage.addYield(nft.address, amount, currentTime, { from: owner }))
                console.log("%cAdding Yield for [Period " + (i-1) + "]", 'color: #FA3333');

                if(staked && i - stakedOn >= 2){
                    randomPercentage = Math.floor(Math.random() * 101);
                    if(randomPercentage <= 50){
                        let hurensohn = await yieldStorage.getClaimableLoot(nft.address, 0, { from: user1 });
                        let tempLootAsNumber = hurensohn.div(new BN("1000000000000000000")).toNumber();
                        claimableLoot += tempLootAsNumber;
                        await checkTransactionPassed(yieldStorage.cashout(nft.address, 0, { from: user1 }));
                        let hurensohn2 = await yieldStorage.getClaimableLoot(nft.address, 0, { from: user1 });
                        let tempLootAsNumber2 = hurensohn2.div(new BN("1000000000000000000")).toNumber();
                        claimableLoot += tempLootAsNumber2;
                        if(randomPercentage <= 30){
                            console.log("%cUnstaking after Cashout [Period " + i + "]", 'color: #FF3333');
                            await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
                            staked = false;
                        }
                    }
                }
            }

            let keinBockMehr = await yieldStorage.getClaimableLoot(nft.address, 0, { from: user1 });
            let tempLootAsNumber = keinBockMehr.div(new BN("1000000000000000000")).toNumber();
            claimableLoot += tempLootAsNumber;

            console.log("Eligible Periods: " + countedPeriods);
            let assumedLoot = amount.mul(new BN(countedPeriods)).div(new BN("1000000000000000000")).toNumber();
            console.log("Assumed Loot: " + assumedLoot.toString());
            console.log("Claimed Loot: " + claimableLoot.toString());

            if(tempLootAsNumber > 0)
                await checkTransactionPassed(yieldStorage.cashout(nft.address, 0, { from: user1 }));

            await advanceTimeAndBlock(86400 * 56);
            if (staked)
                await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));

            assert(claimableLoot === assumedLoot);
        })

        it("should be able to get the whole payout amount after 1 year with 2 random NFTs staking", async () => {
            await advanceTimeAndBlock(86400 * 28);

            let amount = new BN("1000000000000000000");

            let stakedNFT0 = false;
            let stakedOnNFT0 = 0;
            let countedPeriodsNFT0 = 0;

            let stakedNFT1 = false;
            let stakedOnNFT1 = 0;
            let countedPeriodsNFT1 = 0;

            let sharedPeriods = 0;

            for (let i = 0; i < 12; i++) {

                let counted0 = false;
                let counted1 = false;

                let randomPercentage = Math.floor(Math.random() * 101);

                if (randomPercentage <= 40 && !stakedNFT0) {
                    //console.log("%cNFT 0 Staking [Period " + i + "]", 'color: #68FF33');
                    await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
                    stakedOnNFT0 = i;
                    stakedNFT0 = true;
                }
                else if (randomPercentage <= 20 && stakedNFT0 && i - stakedOnNFT0 >= 2) {
                    //console.log("%cNFT 0 Unstaking [Period " + i + "]", 'color: #FF3333');
                    await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));
                    stakedNFT0 = false;
                }
                else {
                    if (stakedNFT0){
                        countedPeriodsNFT0++;
                        counted0 = true;
                    }
                }

                randomPercentage = Math.floor(Math.random() * 101);

                if (randomPercentage <= 40 && !stakedNFT1) {
                    //console.log("%cNFT 1 Staking [Period " + i + "]", 'color: #68FF33');
                    await checkTransactionPassed(staker.stake(nft.address, 1, { from: user2 }));
                    stakedOnNFT1 = i;
                    stakedNFT1 = true;
                }
                else if (randomPercentage <= 20 && stakedNFT1 && i - stakedOnNFT1 >= 2) {
                    //console.log("%cNFT 1 Unstaking [Period " + i + "]", 'color: #FF3333');
                    await checkTransactionPassed(staker.unStake(nft.address, 1, { from: user2 }));
                    stakedNFT1 = false;
                }
                else {
                    if (stakedNFT1){
                        countedPeriodsNFT1++;
                        counted1 = true;
                    }
                }

                if(counted0 && counted1){
                    //console.log("Sharing [Period " + i + "]");
                    sharedPeriods++;
                }

                let currentTime = await yieldStorage.getBlockTime({ from: nonOwner });
                await advanceTimeAndBlock(86400 * nftConstants.payoutPeriod);
                
                await priceToken.mint(amount, { from: owner });
                await checkTransactionPassed(priceToken.approve(yieldStorage.address, amount, { from: owner }));
                await checkTransactionPassed(yieldStorage.addYield(nft.address, amount, currentTime, { from: owner }))
            }
            let claimableLoot = await yieldStorage.getClaimableLoot(nft.address, 1);

            //let factor0 = amount.mul(new BN(countedPeriodsNFT1)).sub(new BN(sharedPeriods).mul(amount.div(new BN(2))));
            let factor0 = countedPeriodsNFT1 - (sharedPeriods / 2);

            //console.log("Eligible Periods NFT0: " + countedPeriodsNFT0);
            //console.log("Eligible Periods NFT1: " + countedPeriodsNFT1);
            //console.log("NFT1 shared periods with NFT0: "+sharedPeriods);
            //console.log("Eligible Period Factor NFT1: "+factor0);
            let assumedLoot = amount.mul(new BN(factor0*10)).div(new BN(10));
            //console.log("Assumed Loot NFT0: " + assumedLoot.toString());
            //console.log("Claimed Loot NFT0: " + claimableLoot.toString());
            assert(claimableLoot.eq(assumedLoot));
        })
    })
});