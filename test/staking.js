const assert = require("assert");
const Web3ProviderEngine = require("web3-provider-engine");

const DefiMinerNFT = artifacts.require("DefiMinerNFT");
const NFTShop = artifacts.require("NFTShop");
const TestCoin = artifacts.require("TestCoin");
const NFTStaking = artifacts.require("NFTStaking");
const BN = require('bn.js')
const Whitelist = artifacts.require("Whitelist");
const YieldStorage = artifacts.require("YieldStorage");

const { checkGetFail, checkTransactionFailed, checkTransactionPassed, advanceTime, advanceBlock, takeSnapshot, revertToSnapShot, advanceTimeAndBlock } = require("./lib/utils.js");
const { strictEqual } = require("assert");

const {nftConstants} = require("../scripts/Parameters.js");

let timestampValues = {
    oneDaySeconds: new BN("86400"),
    oneWeekSeconds: new BN("604800"),
    TwoWeeksSeconds: new BN("1209600"),
    ThreeWeeksSeconds: new BN("1814400"),
    FourWeeksSeconds: new BN("2419200"),
}

let errorMessages = {
    notOwner: "ProjectOwnership: Caller is not the project owner.",
    nftNotWhitelisted: "Staking: This NFT is not an original MinerBox NFT.",
    nftStillLocked: "Staking: This NFT is still locked.",
    nftBlocked: "NFT: This NFT is currently blocked.",
}

contract("Testing NFT Staking", accounts => {
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

    contract("Testing basic staking functions", accounts => {
        before(async () => {
            await shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("5"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });
            await priceToken.mint(new BN("5000000000000000000"), { from: nonOwner });
            await priceToken.approve(shop.address, new BN("5000000000000000001"), { from: nonOwner });
            await shop.mintNFT(nft.address, { from: nonOwner });
        })

        it("should fail staking a fake nft", async () => {
            let nftBalance = await nft.balanceOf(nonOwner);
            let tokenID = await nft.tokenByIndex(nftBalance - 1);
            await checkTransactionFailed(staker.stake(nft.address, tokenID), errorMessages.nftNotWhitelisted);
        })

        it("should pass whitelisting for owner", async () => {

            await checkTransactionPassed(nftWhitelist.setWhitelistStatus(nft.address, true, { from: owner }))
        })

        it("should not allow whitelisting for nonOwner", async () => {
            await checkTransactionFailed(nftWhitelist.setWhitelistStatus(nft.address, true, { from: nonOwner }), errorMessages.notOwner)
        })

        it("should pass staking a whitelisted nft", async () => {
            let nftBalance = await nft.balanceOf(nonOwner);
            let tokenID = await nft.tokenByIndex(nftBalance - 1);
            await checkTransactionPassed(staker.stake(nft.address, tokenID, { from: nonOwner }));
        })

        it("should fail unstaking a whitelisted nft after 1 day", async () => {
            let snapshot = await takeSnapshot();
            await advanceTimeAndBlock(86400);
            let nftBalance = await nft.balanceOf(nonOwner);
            let tokenID = await nft.tokenByIndex(nftBalance - 1);
            await checkTransactionFailed(staker.unStake(nft.address, tokenID, { from: nonOwner }), errorMessages.nftStillLocked);
            await revertToSnapShot(snapshot.id);
        })

        it("should fail sending the nft", async () => {
            let nftBalance = await nft.balanceOf(nonOwner);
            let tokenID = await nft.tokenByIndex(nftBalance - 1);
            await checkTransactionFailed(nft.safeTransferFrom(nonOwner, treasuryAddress, tokenID, { from: nonOwner }), errorMessages.nftBlocked);
        })

        it("should pass unstaking a whitelisted nft after lockingPeriod", async () => {
            let snapshot = await takeSnapshot();
            await advanceTimeAndBlock(86400 * 28);
            let nftBalance = await nft.balanceOf(nonOwner);
            let tokenID = await nft.tokenByIndex(nftBalance - 1);

            await checkTransactionPassed(staker.unStake(nft.address, tokenID, { from: nonOwner }));
            await revertToSnapShot(snapshot.id);
        })
    });

    contract("Simulating a normal request", accounts => {
        before(async () => {
            await shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("5"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });

            await priceToken.mint(new BN("1000000000000000000"), { from: user1 });
            await priceToken.approve(shop.address, new BN("1000000000000000000"), { from: user1 });
            await checkTransactionPassed(shop.mintNFT(nft.address, { from: user1 }));

            await priceToken.mint(new BN("1000000000000000000"), { from: user2 });
            await priceToken.approve(shop.address, new BN("1000000000000000000"), { from: user2 });
            await checkTransactionPassed(shop.mintNFT(nft.address, { from: user2 }));

            await priceToken.mint(new BN("1000000000000000000"), { from: user3 });
            await priceToken.approve(shop.address, new BN("1000000000000000000"), { from: user3 });
            await checkTransactionPassed(shop.mintNFT(nft.address, { from: user3 }));

            await checkTransactionPassed(nftWhitelist.setWhitelistStatus(nft.address, true, { from: owner }))
        })

        it("should not stop due to too high gas fees", async () => {
            let snapshot = await takeSnapshot();

            await checkTransactionPassed(staker.stake(nft.address, 0, { from: user1 }));
            await advanceTimeAndBlock(86400 * nftConstants.lockingPeriodDays / 2);
            await checkTransactionPassed(staker.stake(nft.address, 1, { from: user2 }));
            await checkTransactionFailed(staker.unStake(nft.address, 0, { from: user1 }), errorMessages.nftStillLocked);
            await advanceTimeAndBlock(86400 * nftConstants.lockingPeriodDays);
            await checkTransactionPassed(staker.stake(nft.address, 2, { from: user3 }));
            await advanceTimeAndBlock(86400 * nftConstants.lockingPeriodDays);
            await checkTransactionPassed(staker.unStake(nft.address, 0, { from: user1 }));

            let printStakingInfo = async (user) => {
                let balance = await nft.balanceOf(user);

                for (let i = 0; i < balance.toNumber(); i++) {
                    let tempTokenID = await nft.tokenOfOwnerByIndex(user, i);
                    stakingInfo = await staker.getStakingInfo(nft.address, tempTokenID);
                    if (stakingInfo.exist == true) {
                        let lastPeriod = stakingInfo.stakingPeriods[stakingInfo.stakingPeriods.length - 1];
                        console.log("Latest Staking Info of tokenID: " + tempTokenID);
                        console.log(lastPeriod.unStake == 0 ? "\tIs staked" : "\tIs not staked");

                        console.log("\tLatest Staking started: " + new Date(lastPeriod.startStake * 1000));
                        console.log("\tLatest Staking Blocked until: " + new Date(lastPeriod.blockedUntil * 1000));
                        if (lastPeriod.unStake != 0) {
                            console.log("\tLatest Staking unStaked: " + new Date(lastPeriod.unStake * 1000));
                        }
                    }
                    console.log("");
                }
            }

            //await printStakingInfo(user1);
            //await printStakingInfo(user2);
            //await printStakingInfo(user3);

            await revertToSnapShot(snapshot.id);
        })
    })
});