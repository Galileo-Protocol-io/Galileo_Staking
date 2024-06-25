const { expect } = require("chai");
const hardhat = require("hardhat");
const { ethers } = hardhat;
const util = require("util");
const {
  parseEther,
  formatEther,
  parseUnits,
  formatUnits,
} = require("ethers/utils");

describe("Galileo Staking", function () {
  const ADMIN_ROLE = ethers.id("ADMIN_ROLE");

  let mockERC20,
    mockERC20Address,
    mockERC721,
    mockERC721Address,
    galileoStaking,
    galileoStakingAddress,
    galileoSoulBoundToken,
    galileoSoulBoundTokenAddress;
  let owner, deployer, user;

  before(async function () {
    const signers = await ethers.getSigners();
    [owner, deployer, user] = signers;

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.connect(owner).deploy();
    mockERC20Address = await mockERC20.getAddress();

    const MockERC721 = await ethers.getContractFactory("MockERC721");
    mockERC721 = await MockERC721.connect(owner).deploy();
    mockERC721Address = await mockERC721.getAddress();

    const GalileoSoulBoundToken = await ethers.getContractFactory(
      "GalileoSoulBoundToken"
    );
    galileoSoulBoundToken = await GalileoSoulBoundToken.connect(owner).deploy(
      "Galileo Soul Bound Token",
      "GSBT",
      "htts://tokenuri/"
    );
    galileoSoulBoundTokenAddress = await galileoSoulBoundToken.getAddress();

    const GalileoStaking = await ethers.getContractFactory("GalileoStaking");
    galileoStaking = await GalileoStaking.connect(owner).deploy(
      mockERC20Address,
      galileoSoulBoundTokenAddress
    );
    galileoStakingAddress = await galileoStaking.getAddress();

    // ═══════════════════════ MINT NFTS ════════════════════════
    const tokenId = 25;
    await (await mockERC721.mint(user.address, tokenId)).wait();
    await (await mockERC721.mint(user.address, 140)).wait();

    // ═══════════════════════ TRANSFER ERC20 TOKENS ════════════════════════
    await (await mockERC20.transfer(user.address, parseEther("100000"))).wait();

    // ═══════════════════════ GRANT ROLE SBT ═══════════════════════════════
    await (
      await galileoSoulBoundToken
        .connect(owner)
        .grantRole(ADMIN_ROLE, galileoStakingAddress)
    ).wait();

    // ═══════════════════════ CONFIGURE CONFIGURATION ════════════════════════
    let _stakeInfo = [];

    // Define the number of elements per sub-array
    const batchSize = 100;
    const totalTokens = 300;
    let leoxAmount = [
      parseEther("1000"),
      parseEther("2000"),
      parseEther("3000"),
    ];
    // Loop to generate sub-arrays
    let _index = 0;
    for (let i = 0; i < totalTokens; i += batchSize) {
      let start = i + 1;
      let end = Math.min(i + batchSize, totalTokens);
      let tokenIds = Array.from(
        { length: end - start + 1 },
        (_, index) => start + index
      );
      let category = Math.ceil(end / batchSize);
      _stakeInfo.push([tokenIds, leoxAmount[_index], category]);
      _index = ++_index;
    }

    const tx = await (
      await galileoStaking
        .connect(owner)
        .configureCollection(
          mockERC721Address,
          galileoSoulBoundTokenAddress,
          _stakeInfo
        )
    ).wait();

    const events = getEvents(tx);

    // ═══════════════════════ CONFIGURE MULTIPLIER ════════════════════════
    const stakingTime = [60, 120, 180, 240, 300];
    const stakingBoost = [0, 1.25, 1.5, 2, 3];

    const multipliers = generateMultipliers(stakingTime, stakingBoost);

    await (
      await galileoStaking
        .connect(owner)
        .setMultipliers(mockERC721Address, multipliers)
    ).wait();

    // ═══════════════════════ CONFIGURE POOL ═══════════════════════════════
    const etherValue = 3; // Ether value
    const startTimes = [12, 24, 36]; // Start times of the pool
    const rewardWindows = [2500, 3000, 3500];

    const pool = generatePool(
      mockERC721Address,
      etherValue,
      startTimes,
      rewardWindows
    );
    await (await galileoStaking.connect(owner).configurePool(pool)).wait();

    // console.log(util.inspect(_stakeInfo, { depth: null }));
  });

  describe("Configure Collection", function () {
    it("Should configurations of the staking contract by ADMIN_ROLE", async function () {
      let _stakeInfo = [];

      // Define the number of elements per sub-array
      const batchSize = 100;
      const totalTokens = 300;
      let leoxAmount = [
        parseEther("5000"),
        parseEther("4000"),
        parseEther("3000"),
      ];

      // Loop to generate sub-arrays
      let _index = 0;
      for (let i = 0; i < totalTokens; i += batchSize) {
        let start = i + 1;
        let end = Math.min(i + batchSize, totalTokens);
        let tokenIds = Array.from(
          { length: end - start + 1 },
          (_, index) => start + index
        );
        let category = Math.ceil(end / batchSize);
        _stakeInfo.push([tokenIds, leoxAmount[_index], category]);
        _index = ++_index;
      }

      await (
        await galileoStaking
          .connect(owner)
          .configureCollection(
            mockERC721Address,
            galileoSoulBoundTokenAddress,
            _stakeInfo
          )
      ).wait();

      // const currentUnixTimestamp = Math.floor(Date.now() / 1000);

      const stakingTime = [60, 120, 180, 240, 300];
      const stakingBoost = [0, 1.25, 1.5, 2, 3];

      const multipliers = generateMultipliers(stakingTime, stakingBoost);
      await (
        await galileoStaking
          .connect(owner)
          .setMultipliers(mockERC721Address, multipliers)
      ).wait();

      const etherValue = 3; // Ether value
      const startTimes = [60, 120, 180]; // Start times of the pool
      const rewardWindows = [2500, 3000, 3500];

      const pool = generatePool(
        mockERC721Address,
        etherValue,
        startTimes,
        rewardWindows
      );

      // console.log(util.inspect(pool, { depth: null }));

      await (await galileoStaking.connect(owner).configurePool(pool)).wait();
    });

    it("Should Stake the NFT", async function () {
      // await (
      //   await mockERC721.connect(user).setApprovalForAll(galileoStakingAddress, true)
      // ).wait();
      // await (
      //   await mockERC20
      //     .connect(user)
      //     .approve(galileoStakingAddress, parseEther("5000"))
      // ).wait();
      const currentUnixTimestamp = Math.floor(Date.now() / 1000);
      const tx = await (
        await galileoStaking
          .connect(user)
          .stake(mockERC721Address, 1, 1, parseEther("1000"), 120)
      ).wait();
      // const events = getEvents(tx)
    });

    it("Should get staking points", async function () {

      await (
        await mockERC721.connect(user).setApprovalForAll(galileoStakingAddress, true)
      ).wait();
      // await (
      //   await mockERC20
      //     .connect(user)
      //     .approve(galileoStakingAddress, parseEther("4000"))
      // ).wait();
      const currentUnixTimestamp = Math.floor(Date.now() / 1000);
      const tx = await (
        await galileoStaking
          .connect(user)
          .stake(mockERC721Address, 140, 2, parseEther("2000"), 120)
      ).wait();

      await galileoStaking.calculateSharePoints(user.address, mockERC721Address, 1)

    });
  });

  function getEvents(transactionHash) {
    const event = transactionHash.logs.find((log) => {
      try {
        return (
          galileoStaking.interface.parseLog(log).name === "ConfigureCollection"
        );
      } catch (e) {
        return false;
      }
    });

    if (event) {
      const parsedEvent = galileoStaking.interface.parseLog(event);
      return parsedEvent.args;
    } else {
      console.log("ConfigureCollection event not found in logs");
      return 0;
    }
  }
});

const generateMultipliers = (intervals, values) => {
  if (intervals.length !== values.length) {
    throw new Error("Intervals and values arrays must have the same length");
  }

  return intervals.map((interval, index) => [
    interval,
    parseEther(values[index].toString()),
  ]);
};

const generatePool = (
  mockERC721Address,
  etherValue,
  startTimes,
  rewardWindows
) => {
  if (startTimes.length !== rewardWindows.length) {
    throw new Error(
      "Start times and reward windows arrays must have the same length"
    );
  }

  const rewards = startTimes.map((startTime, index) => [
    startTime,
    rewardWindows[index],
  ]);

  return [[mockERC721Address, parseEther(etherValue.toString()), rewards]];
};
