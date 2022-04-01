const {currentUsedContracts, currentUsedNFTs, shopAddresses, MFUELAddresses, yieldTokenAddress} = require("../scripts/Parameters.js");
const {de} = require("truffle/build/647.bundled");

// Dependencies

const ProjectOwnership = artifacts.require("ProjectOwnership");

const DateTime = artifacts.require("DateTime");
const StakingLibrary = artifacts.require("StakingLibrary");

const TestCoin = artifacts.require("TestCoin");

const Whitelist = artifacts.require("Whitelist");

const NFTShop = artifacts.require("NFTShop");
const NFTStaking = artifacts.require("NFTStaking");
const DefiMinerNFT = artifacts.require("DefiMinerNFT");

const YieldStorage = artifacts.require("YieldStorage");

const MinerBoxCoin = artifacts.require("MinerBoxCoin");
const CoinGenerator = artifacts.require("CoinGenerator");

let isTestRun = process.argv[2] === 'test'

module.exports = function (deployer) {

  deployer.then(async () => {
    // Libraries
    await deployer.deploy(StakingLibrary);

    let yieldPayoutTokenAddress;

    if(isTestRun){
      await deployer.deploy(TestCoin);
      let tc = await TestCoin.deployed();
      yieldPayoutTokenAddress = tc.address
      console.log("TestCoin: " + tc.address);
    }
    else {
      yieldPayoutTokenAddress = yieldTokenAddress;
    }

    console.log("Deployed Company Ownership");
    let projectOwnership = await deployer.deploy(ProjectOwnership);

    //Contracts
    console.log("Deployed NFT Shop");
    await deployer.deploy(NFTShop, projectOwnership.address);

    await deployer.link(StakingLibrary, NFTStaking);
    console.log("Deployed NFT Staking");
    await deployer.deploy(NFTStaking, projectOwnership.address, 28);

    await deployYieldStorage(deployer, projectOwnership, yieldPayoutTokenAddress);

    if(isTestRun){
      await deployer.deploy(DefiMinerNFT, projectOwnership.address, "TestNFT", "TNFT", 4750, 250, (await NFTShop.deployed()).address, (await NFTStaking.deployed()).address);
      console.log("Deployed Test NFT");
    }

    //await deployMFUEL(deployer);

    console.log("NFT Shop: " + (await NFTShop.deployed()).address);
    console.log("NFT Staking: " + (await NFTStaking.deployed()).address);
    console.log("YieldStorage: " + (await YieldStorage.deployed()).address);
  })
};

let deployYieldStorage = async (deployer, ownership, yieldCoin) => {
  let staker = await NFTStaking.deployed();

  await deployer.deploy(DateTime);
  console.log("Deployed Date Time");

  await deployer.link(DateTime, YieldStorage);
  await deployer.deploy(YieldStorage, ownership.address, staker.address, yieldCoin, 28 * 3600 * 24, 7);
  console.log("Deployed Yield Storage");

  yieldStorage = await YieldStorage.deployed();
  await staker.addSubscriber(yieldStorage.address);
}

let deployMFUEL = async (deployer, refuelingToken, ) => {
  staker = await NFTStaking.deployed();

  let addresses = [
    strategicPartnershipWalletAddress,
    foundersAndTeamWallet,
    polygonTreasuryWallet,
    reserveWallet,
    liquidityWallet
  ];
  let balances = [
    new BN("10000000000000000000000000"),
    new BN("16000000000000000000000000"),
    new BN("20000000000000000000000000"),
    new BN("10000000000000000000000000"),
    new BN("4000000000000000000000000")
  ]

  let mfuelMintable = new BN("140000000000000000000000000");
  let generationRatePerDay = new BN("10000000000000000");
  
  await deployer.deploy(MinerBoxCoin, "MFUEL", "MFUEL", addresses, balances, mfuelMintable, staker.address, generationRatePerDay, refuelingToken, mfuelFeeTreasury);
}