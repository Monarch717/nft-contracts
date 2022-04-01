const assert = require("assert");
const Web3ProviderEngine = require("web3-provider-engine");

const DefiMinerNFT = artifacts.require("DefiMinerNFT");
const NFTShop = artifacts.require("NFTShop");
const TestCoin = artifacts.require("TestCoin");
const NFTStaking = artifacts.require("NFTStaking");
const BN = require('bn.js')
const Whitelist = artifacts.require("Whitelist");
const YieldStorage = artifacts.require("YieldStorage");
const ProjectOwnership = artifacts.require("ProjectOwnership");

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
    noBatchFound : "Shop: No Batch found for this NFT.",
    batchAlreadyExists: "Shop: NFT Batch already exists.",
    notOwner: "ProjectOwnership: Caller is not the project owner.",
    priceNotApproved: "Shop: Price token not approved.",
    notEnoughFunds: "Shop: Not enough funds to buy NFT.",
    batchSoldOut: "Shop: This Batch is sold out.",
    notOnWhitelist: "Shop: You are not on the whitelist for this NFT Batch.",
    limitReached: "Shop: You have already bought the maximum allowed amount of NFTs in this batch.",
}

contract("Testing NFT Shop", accounts => {
    let priceToken;
    let shop;
    let nft;
    let staker;
    let yieldStorage;

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
    })

    contract("Testing basic shop functions", accounts => {
        it("should fail getBatch nonExistent", async () => {
            await checkGetFail(shop.getBatch(nft.address), errorMessages.noBatchFound);
        })

        it("should fail createNFTBatch as nonOwner", async () => {

            let promise = shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("200"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: nonOwner });
            await checkTransactionFailed(promise, errorMessages.notOwner);
        })

        it("should pass createNFTBatch as owner", async () => {
            let promise = shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("200"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });
            await checkTransactionPassed(promise);
        })

        it("should fail createNFTBatch second time as owner", async () => {
            let promise = shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("200"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });
            await checkTransactionFailed(promise, errorMessages.batchAlreadyExists);
        })

        it("should fail deleteBatch as nonOwner", async () => {
            let promise = shop.deleteBatch(nft.address, { from: nonOwner });
            await checkTransactionFailed(promise, errorMessages.notOwner);
        })

        it("should pass deleteBatch as owner", async () => {
            let promise = shop.deleteBatch(nft.address, { from: owner });
            await checkTransactionPassed(promise);
        })

        it("should fail getBatch after Deletion", async () => {
            await checkGetFail(shop.getBatch(nft.address), errorMessages.noBatchFound);
        })

        it("should pass buying NFT", async () => {
            await shop.createNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("1"), new BN("0"), treasuryAddress, "TestDescription", 0, { from: owner });
            await priceToken.mint(new BN("1000000000000000000"), { from: nonOwner });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: nonOwner });
            let promise = shop.mintNFT(nft.address, { from: nonOwner });
            await checkTransactionPassed(promise);
        })

        it("should fail buying NFT because price not approved", async () => {
            let promise = shop.mintNFT(nft.address, { from: nonOwner });
            await checkTransactionFailed(promise, errorMessages.priceNotApproved);
        })

        it("should fail buying NFT because can't afford", async () => {
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: nonOwner });
            let promise = shop.mintNFT(nft.address, { from: nonOwner });
            await checkTransactionFailed(promise, errorMessages.notEnoughFunds);
        })

        it("should fail buying nFT because sold out", async () => {
            await priceToken.mint(new BN("1000000000000000000"), { from: nonOwner });
            await priceToken.approve(shop.address, new BN("1000000000000000001"), { from: nonOwner });
            let promise = shop.mintNFT(nft.address, { from: nonOwner });
            await checkTransactionFailed(promise, errorMessages.batchSoldOut);
        })
    });

    contract("Testing shop whitelisting functions", accounts => {
        before(async () => {
            let ownership = await ProjectOwnership.deployed();
            let whitelist = await Whitelist.new(ownership.address);
            let promise = shop.createWhitelistedNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("200"), new BN("0"), treasuryAddress, "TestDescription", 0, whitelist.address, { from: owner });
            await checkTransactionPassed(promise);

            await checkTransactionPassed(priceToken.mint(new BN("1000000000000000000"), { from: user1 }));
            await checkTransactionPassed(priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user1 }));

            await checkTransactionPassed(priceToken.mint(new BN("1000000000000000000"), { from: user2 }));
            await checkTransactionPassed(priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user2 }));
        })

        it("should allow whitelisting a user", async () => {
            let batch = await shop.getBatch(nft.address);
            let batchWhitelist = await Whitelist.at(await batch.nftBatch.whitelist);
            await checkTransactionPassed(batchWhitelist.setWhitelistStatus(user1, true));
        })

        it("shouldn't allow whitelisting a user as nonOwner", async () => {
            let batch = await shop.getBatch(nft.address);
            let batchWhitelist = await Whitelist.at(await batch.nftBatch.whitelist);
            await checkTransactionFailed(batchWhitelist.setWhitelistStatus(user1, true, { from: user1 }), errorMessages.notOwner);
        })

        it("shouldn't allow a non whitelisted user to buy an NFT", async () => {
            await checkTransactionFailed(shop.mintNFT(nft.address, { from: user2 }), errorMessages.notOnWhitelist);
        })

        it("should allow a whitelisted user to buy an NFT", async () => {
            await checkTransactionPassed(shop.mintNFT(nft.address, { from: user1 }));
        })
    });

    contract("Testing limited sales", accounts => {
        before(async () => {
            let ownership = await ProjectOwnership.deployed();
            let whitelist = await Whitelist.new(ownership.address);
            let promise = shop.createWhitelistedNFTBatch(nft.address, priceToken.address, new BN("1000000000000000000"), new BN("200"), new BN("0"), treasuryAddress, "TestDescription", 1, whitelist.address, { from: owner });
            await checkTransactionPassed(promise);

            await checkTransactionPassed(priceToken.mint(new BN("1000000000000000000"), { from: user1 }));
            await checkTransactionPassed(priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user1 }));

            await checkTransactionPassed(priceToken.mint(new BN("1000000000000000000"), { from: user2 }));
            await checkTransactionPassed(priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user2 }));
        })

        it("should allow whitelisting a user", async () => {
            let batch = await shop.getBatch(nft.address);
            let batchWhitelist = await Whitelist.at(await batch.nftBatch.whitelist);
            await checkTransactionPassed(batchWhitelist.setWhitelistStatus(user1, true));
        })

        it("should allow a whitelisted user to buy an NFT", async () => {
            await checkTransactionPassed(shop.mintNFT(nft.address, { from: user1 }));
        })

        it("shouldn't allow to buy over limit", async () => {
            await checkTransactionPassed(priceToken.mint(new BN("1000000000000000000"), { from: user1 }));
            await checkTransactionPassed(priceToken.approve(shop.address, new BN("1000000000000000001"), { from: user1 }));
            await checkTransactionFailed(shop.mintNFT(nft.address, { from: user1 }), errorMessages.limitReached);
        })
    });


});

