// Dependencies
const BN = require('bn.js')
const DateTime = artifacts.require("DateTime");
const StakingLibrary = artifacts.require("StakingLibrary");

const TestCoin = artifacts.require("TestCoin");

const Whitelist = artifacts.require("Whitelist");

const NFTShop = artifacts.require("NFTShop");
const NFTStaking = artifacts.require("NFTStaking");
const DefiMinerNFT = artifacts.require("DefiMinerNFT");

const YieldStorage = artifacts.require("YieldStorage");

const {currentUsedContracts, currentUsedNFTs, shopAddresses, MFUELAddresses, yieldTokenAddress} = require("../scripts/Parameters.js");

let deployNewNFT = async (name, symbol, maxAmount) => {
    let newNFT = await DefiMinerNFT.new(name, symbol, maxAmount, currentUsedContracts.shopContract, currentUsedContracts.stakingContract);
    console.log("Deployed NFT: " + newNFT.address);
    return newNFT;
}

let createBatchForNFT = async (nftAddress, priceTokenAddress, price, maxSell, treasuryAddress, description, limitPerCustomer, whitelisted) => {
    let shop = await NFTShop.at(currentUsedContracts.shopContract);
    console.log("Attempting to create new NFT Batch for: " + nftAddress + " (Whitelist: " + whitelisted + ")")

    if (whitelisted === true) {
        let newWhitelist = await Whitelist.new();
        console.log("Deployed new whitelist for Batch: " + newWhitelist.address);
        await shop.createWhitelistedNFTBatch(nftAddress, priceTokenAddress, price, maxSell, new BN("0"), treasuryAddress, description, limitPerCustomer, newWhitelist.address);
    } else {
        console.log("Creating batch...");
        await shop.createNFTBatch(nftAddress, priceTokenAddress, price, maxSell, new BN("0"), treasuryAddress, description, limitPerCustomer);
    }
}

let whitelistNFTForStaking = async (nftAddress, stakerAddress) => {
    let staker = await NFTStaking.at(stakerAddress);
    console.log("Found Staking Contract at: "+stakerAddress)
    await staker.setStatus(nftAddress, true);
}

let createBatchAndStakeWhitelist = async (nftAddress, price, maxSell, description, limitPerCustomer, whitelisted) => {
    await createBatchForNFT(nftAddress , shopAddresses.priceTokenAddress, price, maxSell, shopAddresses.maticTreasury, description, limitPerCustomer, whitelisted);
    console.log("Batch created");
    await whitelistNFTForStaking(nftAddress, currentUsedContracts.stakingContract);
    console.log("NFT whitelisted for staking");
}

let addYield = async(nftAddress, timestampInSeconds, yieldTokenAddress) => {
    let ys = await YieldStorage.at(currentUsedContracts.yieldStorageContract);
    let yieldToken = await TestCoin.at(yieldTokenAddress);
    await ys.setPayoutToken(yieldTokenAddress);
    await yieldToken.approve(ys.address, yieldTokenAddress);

    await ys.addYield(nftAddress, yieldTokenAddress, timestampInSeconds);
}

let changeURI = async(nftAddress, uriLink) => {
    let nft = await DefiMinerNFT.at(nftAddress);
    await nft.setURILink(uriLink);
}

module.exports = async function (callback) {
    let nft = await deployNewNFT("Second URI Edition", "SUE", 7000);
    await createBatchAndStakeWhitelist(
        nft.address,
        new BN("600000000000000000000"),
        7000,
        "This is our first Mining Machine. Only 7000 in existence! <br/>There is no whitelist for this sale.",
        5,
        false)
    await changeURI(nft.address, "https://ipfs.io/ipfs/QmYnifaNeSavusKkxqsU3Y7Sge17Tm8jKgMhkKRgJ6KyQS?filename=tokenURI_template.json");
    callback();
}
