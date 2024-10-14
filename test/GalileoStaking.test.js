const { expect } = require('chai');
const { parseEther, formatEther } = require('ethers');
const { ethers } = require('hardhat');
const { sign } = require('../utils/eip712_staking.js');

let stakeTime = 60;

let stakingMultiplier = parseEther('1.5');

let rewardRate = parseEther('1');
let totalNebulaSupply = 3333;
let yieldTraitPointC1 = 5;
let yieldTraitPointC2 = 4;

const ADMIN_ROLE = ethers.id('ADMIN_ROLE');
const VALIDATOR_ROLE = ethers.id('VALIDATOR_ROLE');

describe('GalileoStaking', async function () {
  let GalileoStaking, galileoStaking, admin, staker1, staker2, staker3;
  let ERC20Token, erc20Token;
  let ERC721Token, erc721Token;
  let SoulBounToken, soulBounToken;
  let leoxAddress, nebulaAddress, galileoStakingAddress, sbtAddress;

  let tokenArray1, tokenArray2;

  beforeEach(async function () {
    [admin, staker1, staker2, staker3] = await ethers.getSigners();

    // Deploy mock ERC20 token
    ERC20Token = await ethers.getContractFactory('MockLeox');
    erc20Token = await ERC20Token.deploy();
    leoxAddress = await erc20Token.getAddress();

    // Deploy mock ERC721 token
    ERC721Token = await ethers.getContractFactory('MockNebula');
    erc721Token = await ERC721Token.deploy('https://tokenURIs/');
    nebulaAddress = await erc721Token.getAddress();

    // Deploy GalileoStaking contract
    GalileoStaking = await ethers.getContractFactory('GalileoStaking');
    galileoStaking = await GalileoStaking.deploy(leoxAddress);
    galileoStakingAddress = await galileoStaking.getAddress();

    // Deploy soul bound token contract
    SoulBounToken = await ethers.getContractFactory('GalileoSoulBoundToken');
    soulBounToken = await SoulBounToken.deploy('NEBULA SBT', 'NSBT', 'https://tokenuri/');
    sbtAddress = await soulBounToken.getAddress();

    await erc721Token.mint(staker1.address); // Mint NFT to staker1
    await erc20Token.transfer(staker1.address, parseEther('1000')); // Transfer LEOX to staker1

    await soulBounToken.grantRole(ADMIN_ROLE, galileoStakingAddress);
    await galileoStaking.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);

    const stakeInfo = [
      [parseEther('5000'), yieldTraitPointC1],
      [parseEther('4000'), yieldTraitPointC2],
    ];
    await (await galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)).wait();

    let currentTime = Math.floor(Date.now() / 1000);
    const poolInfo = [[nebulaAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

    await (await galileoStaking.connect(admin).configurePool(poolInfo)).wait();

    const muliplier = [[stakeTime, stakingMultiplier]];

    await (await galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).wait();
  });
  describe('Deployment', function () {
    it('Should set the right LEOX address', async function () {
      expect(await galileoStaking.LEOX()).to.equal(leoxAddress);
    });

    it('Should revert if LEOX address is zero address', async function () {
      let GalileoStakings = await ethers.getContractFactory('GalileoStaking');
      await expect(GalileoStakings.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(GalileoStakings, 'InvalidAddress');
    });

    it('Should assign admin role to deployer', async function () {
      expect(await galileoStaking.hasRole(await galileoStaking.ADMIN_ROLE(), admin.address)).to.equal(true);
    });
  });

  describe('Staking', function () {
    it('Should allow staking of NFT and LEOX', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      const stakeInfo = await galileoStaking.getStakersPosition(staker1.address, nebulaAddress, 1);
      expect(stakeInfo.tokenId).to.equal(1);
    });

    it('Should allow multiple stakers to stake their NFTs and LEOX', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      const citizen = 1;

      await galileoStaking.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);
      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await erc721Token.mint(staker2.address); // Mint NFT to staker1
      await erc20Token.transfer(staker2.address, parseEther('1000')); // Transfer LEOX to staker1

      tokenId = await erc721Token.totalSupply(); // Get the latest tokenId

      await erc721Token.connect(staker2).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker2).approve(galileoStakingAddress, stakeLeoxAmount);
      signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker2).stake(voucher);

      let stakeInfo = await galileoStaking.getStakersPosition(staker1.address, nebulaAddress, 1);
      expect(stakeInfo.tokenId).to.equal(1);

      stakeInfo = await galileoStaking.getStakersPosition(staker2.address, nebulaAddress, tokenId);
      expect(stakeInfo.tokenId).to.equal(tokenId);
    });

    it('Should return the correct staked percentage', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      const citizen = 1;

      await galileoStaking.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);
      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);
      let stakedPercentage = await galileoStaking.getStakedPercentage(nebulaAddress);

      stakedPercentage = Number(formatEther(stakedPercentage));

      const expectedStakedPercent = (100 * 1) / 3333;

      expect(expectedStakedPercent).to.equal(stakedPercentage);
    });

    it('Should return 0 if no token is staked', async function () {
      const GalileoStaking1 = await ethers.getContractFactory('GalileoStaking');
      const galileoStaking1 = await GalileoStaking1.deploy(leoxAddress);
      let stakedPercentage = await galileoStaking1.getStakedPercentage(nebulaAddress);

      expect(stakedPercentage).to.equal(0);
    });

    it('Should not allow staking with unapproved NFT or LEOX', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      const citizen = 1;

      await galileoStaking.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);
      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError;
    });

    it('Should not allow staking with zero NFT address', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      const citizen = 1;

      await galileoStaking.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);
      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, ethers.ZeroAddress, tokenId, citizen, stakeTime, stakeLeoxAmount);

      let voucher = {
        collectionAddress: ethers.ZeroAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking, 'InvalidAddress');
    });

    it('Should not allow staking with invalid time', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      await galileoStaking.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);
      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen, 0, stakeLeoxAmount);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: 0,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking, 'InvalidTime');
    });

    it('Should not allow staking with uninitialized pool', async function () {
      const GalileoStaking1 = await ethers.getContractFactory('GalileoStaking');
      const galileoStaking1 = await GalileoStaking1.deploy(leoxAddress);
      const galileoStakingAddress1 = await galileoStaking1.getAddress();

      const stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await (await galileoStaking1.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)).wait();

      const muliplier = [[stakeTime, stakingMultiplier]];

      await (await galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).wait();

      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      await galileoStaking1.connect(admin).grantRole(VALIDATOR_ROLE, admin.address);

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress1, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress1, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress1, nebulaAddress, tokenId, citizen, stakeTime, stakeLeoxAmount);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      await expect(galileoStaking1.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking1, 'PoolUninitialized');
    });

    it('Should not allow staking with stake max leox from configured leox', async function () {
      const stakeLeoxAmount = parseEther('6000');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking, 'InvalidTokensCount');
    });

    it('Should revert if signature is invalid', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: 2,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking, 'InvalidSignature');
    });

    it('Should not allow staking of NFT if staker does not own any NFT', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX

      await expect(galileoStaking.connect(staker2).stake(voucher)).to.be.revertedWithCustomError(erc721Token, 'ERC721IncorrectOwner'); // Specify the expected address in the error
    });

    it('Should stake with zero leox', async function () {
      // Mint NFT to staker2
      await erc721Token.mint(staker2.address);
      const tokenId = await erc721Token.totalSupply(); // Get the latest tokenId

      const stakeLeoxAmount = parseEther('0');
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker2).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker2).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX

      await expect(galileoStaking.connect(staker2).stake(voucher)).to.not.be.reverted;
    });

    it('Should revert if trying to stake the same tokenId again', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking, 'TokenAlreadyStaked');
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX

      await expect(galileoStaking.connect(staker1).stake(voucher)).to.be.revertedWithCustomError(galileoStaking, 'EnforcedPause');
    });
  });

  describe('Stake More Leox', function () {
    it('Should stake more LEOX if already tokens are staked', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await erc20Token.connect(staker1).approve(galileoStakingAddress, parseEther('200'));

      await galileoStaking.connect(staker1).stakeLeoxTokens(nebulaAddress, 1, parseEther('200'));
    });

    it('Should revert if collection address is zero address', async function () {
      await expect(galileoStaking.connect(staker1).stakeLeoxTokens(ethers.ZeroAddress, 1, parseEther('200'))).to.be.revertedWithCustomError(
        galileoStaking,
        'CollectionUninitialized'
      );
    });

    it('Should revert if leox token count is zero', async function () {
      await expect(galileoStaking.connect(staker1).stakeLeoxTokens(nebulaAddress, 1, 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidTokensCount'
      );
    });

    it('Should revert if NFT and LEOX are not staked previously', async function () {
      await expect(galileoStaking.connect(staker1).stakeLeoxTokens(nebulaAddress, 1, parseEther('200'))).to.be.revertedWithCustomError(
        galileoStaking,
        'TokenNotStaked'
      );
    });

    it('Should revert if stake more leox for the token id that staker does not own', async function () {
      await expect(galileoStaking.connect(staker1).stakeLeoxTokens(nebulaAddress, 2, parseEther('200'))).to.be.revertedWithCustomError(
        galileoStaking,
        'TokenNotStaked'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);
      await galileoStaking.connect(admin).pause();

      await expect(galileoStaking.connect(staker1).stakeLeoxTokens(nebulaAddress, 2, parseEther('200'))).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });

    it('Should revert if stake more leox count is greater than the configured amount', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await expect(galileoStaking.connect(staker1).stakeLeoxTokens(nebulaAddress, 1, parseEther('6000'))).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidTokensCount'
      );
    });
  });

  describe('Updating Reward Rate', function () {
    it('Should update the reward rate', async function () {
      let updateEmissionRate = await galileoStaking.updateEmissionRate(nebulaAddress, parseEther('10'), 0);
      updateEmissionRate = await updateEmissionRate.wait();

      const poolData = await galileoStaking.getPoolConfiguration(nebulaAddress);
      expect(poolData.rewardWindows[1].rewardRate).to.equal(parseEther('10'));
      expect(updateEmissionRate.logs[0].fragment.name).to.equal('UpdateEmissionRate');
      expect(updateEmissionRate.logs[0].args[1]).to.equal(parseEther('10'));
    });

    it('Should revert if collection is not configured', async function () {
      await expect(galileoStaking.updateEmissionRate(leoxAddress, parseEther('10'), 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'CollectionUninitialized'
      );
    });

    it('Should revert if reward rate is zero', async function () {
      await expect(galileoStaking.updateEmissionRate(nebulaAddress, 0, 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidRewardRate'
      );
    });

    it('Should revert if start time is less then the start time of previous reward window', async function () {
      let GalileoStakings = await ethers.getContractFactory('GalileoStaking');
      GalileoStakings = await GalileoStakings.deploy(leoxAddress);

      let currentTime = Math.floor(Date.now() / 1000) + 1000000000;
      const poolInfo = [[nebulaAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

      await (await GalileoStakings.connect(admin).configurePool(poolInfo)).wait();

      await expect(GalileoStakings.updateEmissionRate(nebulaAddress, parseEther('10'), 0)).to.be.revertedWithCustomError(
        GalileoStakings,
        'InvalidTime'
      );
    });

    it('Should revert if non-admin tries to update the reward rate', async function () {
      await expect(galileoStaking.connect(staker1).updateEmissionRate(nebulaAddress, parseEther('10'), 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      await expect(galileoStaking.connect(admin).updateEmissionRate(nebulaAddress, parseEther('10'), 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });
  });

  describe('Calculate the Points', async function () {
    it('Should calculate the collect points', async function () {
      const stakeTokens = 5000;
      const increment = 400;
      const points = await galileoStaking.calculatePoints(nebulaAddress, 1, parseEther(stakeTokens.toString()), stakeTime);

      let calculateLeoxPoints = stakeTokens / increment;

      let yieldBoost = yieldTraitPointC1 * Number(formatEther(stakingMultiplier));

      calculateLeoxPoints = calculateLeoxPoints + yieldBoost;
      expect(Number(formatEther(points))).to.be.equal(calculateLeoxPoints);
    });

    it('Should revert if collection is not registered', async function () {
      await expect(galileoStaking.calculatePoints(leoxAddress, 1, parseEther('5000'), 600)).to.be.reverted;
    });

    it('Should revert if stake time is invalid', async function () {
      await expect(galileoStaking.calculatePoints(nebulaAddress, 1, parseEther('5000'), 600)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidTime'
      );
    });
  });

  describe('Rewards Per Token', async function () {
    it('Should return rewards per token alloc', async function () {
      // Approve tokens for transfer
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await erc721Token.mint(staker2.address); // Mint NFT to staker1
      tokenId = await erc721Token.totalSupply();
      await erc20Token.transfer(staker2.address, parseEther('1000')); // Transfer LEOX to staker1

      // Approve tokens for transfer
      await erc721Token.connect(staker2).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker2).approve(galileoStakingAddress, stakeLeoxAmount);

      // Stake NFT and LEOX
      signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker2).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await galileoStaking.rewardPerToken(nebulaAddress);
    });

    it('Should return zero if collection is not registered or tokens are not staked in collection', async function () {
      let rewardPerTokenAcc = await galileoStaking.rewardPerToken(leoxAddress);
      expect(rewardPerTokenAcc).to.be.equal(0);
      rewardPerTokenAcc = await galileoStaking.rewardPerToken(leoxAddress);
      expect(rewardPerTokenAcc).to.be.equal(0);
    });
  });

  describe('Configure Collection', async function () {
    it('Should allow to configure new collection', async function () {
      const stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)).to.not
        .reverted;
    });

    it('Should allow to update configures of existing collection', async function () {
      let stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)).to.not
        .reverted;

      stakeInfo = [
        [parseEther('8000'), yieldTraitPointC1],
        [parseEther('6000'), yieldTraitPointC2],
      ];
      await expect(galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)).to.not
        .reverted;
    });

    it('Should revert if Leox hierarchy is invalid', async function () {
      const stakeInfo = [
        [parseEther('3000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(
        galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'InvalidLeoxHierarchy');
    });

    it('Should revert if Yeild Trait Points hierarchy is invalid', async function () {
      const stakeInfo = [
        [parseEther('5000'), 3],
        [parseEther('4000'), 4],
      ];
      await expect(
        galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'InvalidTraitPointsHierarchy');
    });

    it('Should revert if max leox is zero', async function () {
      const stakeInfo = [
        [0, yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(
        galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'InvalidInput');
    });

    it('Should revert if yeild trait point is zero', async function () {
      const stakeInfo = [
        [parseEther('5000'), 0],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(
        galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'InvalidInput');
    });

    it('Should revert if collection address is invalid', async function () {
      const stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(
        galileoStaking.connect(admin).configureNewCollection(ethers.ZeroAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'InvalidAddress');
    });

    it('Should revert if soul bound token address is invalid', async function () {
      const stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(
        galileoStaking.connect(admin).configureNewCollection(nebulaAddress, ethers.ZeroAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'InvalidAddress');
    });

    it('Should revert if non admin tries to configure new collection', async function () {
      const stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];
      await expect(
        galileoStaking.connect(staker1).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'AccessControlUnauthorizedAccount');
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      const stakeInfo = [
        [parseEther('5000'), yieldTraitPointC1],
        [parseEther('4000'), yieldTraitPointC2],
      ];

      await expect(
        galileoStaking.connect(admin).configureNewCollection(nebulaAddress, sbtAddress, totalNebulaSupply, stakeInfo)
      ).to.be.revertedWithCustomError(galileoStaking, 'EnforcedPause');
    });
  });

  describe('Set Multipliers', async function () {
    it('Should allow to configure new mulitplier against collection', async function () {
      const muliplier = [[stakeTime, stakingMultiplier]];
      await expect(galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).to.not.reverted;
    });

    it('Should allow to update configures of existing muliplier against collection', async function () {
      let muliplier = [[stakeTime, stakingMultiplier]];
      await expect(galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).to.not.reverted;

      muliplier = [[80, stakingMultiplier]];
      await expect(galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).to.not.reverted;
    });

    it('Should revert if collection address is invalid', async function () {
      let muliplier = [[stakeTime, stakingMultiplier]];

      await expect(galileoStaking.connect(admin).setMultipliers(ethers.ZeroAddress, muliplier)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if non admin tries to configure new collection', async function () {
      let muliplier = [[stakeTime, stakingMultiplier]];
      await expect(galileoStaking.connect(staker1).setMultipliers(nebulaAddress, muliplier)).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      const muliplier = [[stakeTime, stakingMultiplier]];

      await expect(galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });
  });

  describe('get Multipliers', async function () {
    it('Should allow to configure new mulitplier against collection', async function () {
      const muliplier = [[stakeTime, stakingMultiplier]];
      await expect(galileoStaking.connect(admin).setMultipliers(nebulaAddress, muliplier)).to.not.reverted;

      const getMultiplier = await galileoStaking.getMultipliers(nebulaAddress);

      expect(getMultiplier[0][0]).to.be.equal(stakeTime);
      expect(getMultiplier[0][1]).to.be.equal(stakingMultiplier);
    });

    it('Should revert if the collection is already not configured', async function () {
      await expect(galileoStaking.getMultipliers(leoxAddress)).to.be.revertedWithCustomError(galileoStaking, 'CollectionUninitialized');
    });

    it('Should revert if collection address is invalid', async function () {
      await expect(galileoStaking.getMultipliers(ethers.ZeroAddress)).to.be.revertedWithCustomError(galileoStaking, 'InvalidAddress');
    });
  });

  describe('Get Yield Trait Points', async function () {
    it('Should return the Yield Trait Points', async function () {
      const getYieldTraitPoints = await galileoStaking.getYieldTraitPoints(nebulaAddress, 1);
      expect(Number(formatEther(getYieldTraitPoints[0]))).to.be.equal(5000);
    });

    it('Should revert if collection address is not configured', async function () {
      await expect(galileoStaking.getYieldTraitPoints(leoxAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'CollectionUninitialized'
      );
    });

    it('Should revert if collection address is invalid', async function () {
      await expect(galileoStaking.getYieldTraitPoints(ethers.ZeroAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });
  });

  describe('Get Stakers position', async function () {
    it('Should return the stakers position', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      const getStakersPosition = await galileoStaking.getStakersPosition(staker1.address, nebulaAddress, 1);

      expect(getStakersPosition[0]).to.be.equal(nebulaAddress);
      expect(getStakersPosition[1]).to.be.equal(1);
      expect(getStakersPosition[2]).to.be.equal(1);
      expect(getStakersPosition[6]).to.be.equal(parseEther('100'));
    });

    it('Should revert if collection address is invalid', async function () {
      await expect(galileoStaking.getStakersPosition(ethers.ZeroAddress, nebulaAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if staker address is invalid', async function () {
      await expect(galileoStaking.getStakersPosition(nebulaAddress, ethers.ZeroAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if token is not staked against staker address', async function () {
      await expect(galileoStaking.getStakersPosition(staker1.address, nebulaAddress, 2)).to.be.revertedWithCustomError(
        galileoStaking,
        'TokenNotStaked'
      );
    });
  });

  describe('Configure Pool', async function () {
    it('Should configure pool by authorize address', async function () {
      let GalileoStakings = await ethers.getContractFactory('GalileoStaking');
      GalileoStakings = await GalileoStakings.deploy(leoxAddress);

      let currentTime = Math.floor(Date.now() / 1000);
      const poolInfo = [[nebulaAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

      await GalileoStakings.connect(admin).configurePool(poolInfo);
    });

    it('Should revert configures of pool if pool configurations are already exists', async function () {
      let GalileoStakings = await ethers.getContractFactory('GalileoStaking');
      GalileoStakings = await GalileoStakings.deploy(leoxAddress);

      let currentTime = Math.floor(Date.now() / 1000);
      const poolInfo = [[nebulaAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

      await GalileoStakings.connect(admin).configurePool(poolInfo);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await expect(GalileoStakings.connect(admin).configurePool(poolInfo)).to.be.revertedWithCustomError(
        galileoStaking,
        'PoolAlreadyInitialized'
      );
    });

    it('Should revert is collection address is invalid address', async function () {
      let currentTime = Math.floor(Date.now() / 1000);
      const poolInfo = [[ethers.ZeroAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

      await expect(galileoStaking.connect(admin).configurePool(poolInfo)).to.be.revertedWithCustomError(galileoStaking, 'InvalidAddress');
    });

    it('Should not configure pool by unauthorize address', async function () {
      let currentTime = Math.floor(Date.now() / 1000);
      const poolInfo = [[nebulaAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

      await expect(galileoStaking.connect(staker1).configurePool(poolInfo)).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      let currentTime = Math.floor(Date.now() / 1000);
      const poolInfo = [[nebulaAddress, parseEther('3'), [[rewardRate, currentTime, 0]]]];

      await expect(galileoStaking.connect(admin).configurePool(poolInfo)).to.be.revertedWithCustomError(galileoStaking, 'EnforcedPause');
    });

    it('Should revert if tax is greater then 10', async function () {
      let GalileoStakings = await ethers.getContractFactory('GalileoStaking');
      GalileoStakings = await GalileoStakings.deploy(leoxAddress);

      let currentTime = Math.floor(Date.now() / 1000);
      const poolInfo = [[nebulaAddress, parseEther('11'), [[rewardRate, currentTime, 0]]]];

      await expect(GalileoStakings.connect(admin).configurePool(poolInfo)).to.be.revertedWithCustomError(galileoStaking, 'InvalidTaxRate');
    });
  });

  describe('Update Tax Percentage', async function () {
    it('Should update the tax of already configured collection', async function () {
      let GalileoStakings = await ethers.getContractFactory('GalileoStaking');
      GalileoStakings = await GalileoStakings.deploy(leoxAddress);

      await galileoStaking.connect(admin).updateTax(nebulaAddress, parseEther('4'));
    });

    it('Should revert if input address is zero address', async function () {
      await expect(galileoStaking.connect(admin).updateTax(ethers.ZeroAddress, parseEther('2'))).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if input tax percentage is zero', async function () {
      await expect(galileoStaking.connect(admin).updateTax(nebulaAddress, parseEther('0'))).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAmount'
      );
    });

    it('Should revert if tax percentage is greater then 10%', async function () {
      await expect(galileoStaking.connect(admin).updateTax(nebulaAddress, parseEther('11'))).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidTaxRate'
      );
    });

    it('Should revert if collection address is not initialized in the pool', async function () {
      await expect(galileoStaking.connect(admin).updateTax(leoxAddress, parseEther('1'))).to.be.revertedWithCustomError(
        galileoStaking,
        'PoolUninitialized'
      );
    });

    it('Should revert if non ADMIN_ROLE tries to update tax percentage', async function () {
      await expect(galileoStaking.connect(staker1).updateTax(nebulaAddress, parseEther('11'))).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });

    it('Should revert if contract is paused', async function () {
      await galileoStaking.connect(admin).pause();
      await expect(galileoStaking.connect(staker1).updateTax(nebulaAddress, parseEther('11'))).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });
  });

  describe('Calculate Rewards', async function () {
    it('Should return the expected rewards if there is only one staker', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      let calculateRewards = await galileoStaking.calculateRewards(staker1.address, nebulaAddress, 1);
      calculateRewards = Number(formatEther(calculateRewards));
      expect(stakeTime).to.equal(Number(calculateRewards.toFixed(0)));
    });

    it('Should return the expected rewards if there are 2 stakers', async function () {
      const stakeTimeInPool = 10;
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await erc721Token.mint(staker2.address); // Mint NFT to staker1
      await erc20Token.transfer(staker2.address, parseEther('1000')); // Transfer LEOX to staker1

      tokenId = await erc721Token.totalSupply(); // Get the latest tokenId

      // Approve tokens for transfer
      await erc721Token.connect(staker2).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker2).approve(galileoStakingAddress, stakeLeoxAmount);
      signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker2).stake(voucher);
      await ethers.provider.send('evm_increaseTime', [stakeTimeInPool]);
      await ethers.provider.send('evm_mine');

      let [rewards1, rewards2] = await Promise.all([
        galileoStaking.calculateRewards(staker1.address, nebulaAddress, 1),
        galileoStaking.calculateRewards(staker2.address, nebulaAddress, tokenId),
      ]);

      rewards1 = Math.round(parseFloat(formatEther(rewards1)));
      rewards2 = Math.round(parseFloat(formatEther(rewards2)));

      // Fetch stakers' positions in parallel
      const [stakerPosition1, stakerPosition2] = await Promise.all([
        galileoStaking.getStakersPosition(staker1.address, nebulaAddress, 1),
        galileoStaking.getStakersPosition(staker2.address, nebulaAddress, tokenId),
      ]);

      // Calculate rewards for staker1 and staker2
      const rewardStaker1 = stakeTimeInPool; // Always results in stakeTimeInPool since (x + stakeTimeInPool - x) simplifies to stakeTimeInPool
      const rewardStaker2 = stakeTimeInPool + Number(stakerPosition1[3]) - Number(stakerPosition2[3]);

      // Assertions to compare calculated rewards
      expect(rewardStaker1).to.equal(rewards1);
      expect(rewardStaker2).to.equal(rewards2);
    });
  });

  describe('Withdrawing Rewards of all staked tokens', function () {
    it('Should allow user to withdraw rewards', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      const timeStake = 60;

      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));
      const remaingRewardTokensPoolBefore = await galileoStaking.getRewardPoolBalance(nebulaAddress);

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: timeStake,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [timeStake]);
      await ethers.provider.send('evm_mine');

      const rewards = await galileoStaking.calculateRewards(staker1.address, nebulaAddress, 1);
      let withdrawRewards = await (await galileoStaking.connect(staker1).withdrawAllRewards(nebulaAddress)).wait();

      withdrawRewards = Number(formatEther(withdrawRewards.logs[1].args[2])).toFixed(2);

      const rewardsInEther = parseFloat(formatEther(rewards)) + 1; // Convert to number

      const adjustedRewards = rewardsInEther - rewardsInEther * 0.03;

      const remaingRewardTokensPoolAfter = await galileoStaking.getRewardPoolBalance(nebulaAddress);

      let totalPoolRewardTokens = Number(formatEther(remaingRewardTokensPoolBefore)) - (Number(withdrawRewards) + adjustedRewards * 0.03);

      expect(Number(formatEther(remaingRewardTokensPoolAfter)).toFixed(0)).to.be.equal(Number(totalPoolRewardTokens).toFixed(0));
      expect(adjustedRewards).to.be.equal(Number(withdrawRewards));
    });

    it('Should allow user to withdraw rewards', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      const timeStake = 60;

      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: timeStake,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [timeStake]);
      await ethers.provider.send('evm_mine');

      await expect(galileoStaking.connect(staker1).withdrawAllRewards(nebulaAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAmountRewardPoolBalance'
      );
    });

    it('Should revert if collection address is invalid', async function () {
      await expect(galileoStaking.connect(staker1).withdrawAllRewards(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if no token id is staked', async function () {
      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));
      await expect(galileoStaking.connect(staker1).withdrawAllRewards(nebulaAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'TokenNotStaked'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      await expect(galileoStaking.connect(staker1).withdrawAllRewards(nebulaAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });
  });

  describe('Withdrawing Tax', function () {
    it('Should allow Admin to withdraw tax', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      // Mock reward setup and accumulation
      // await galileoStaking.updateEmissionRate(nebulaAddress, parseEther('10'), 0);
      const rewards = await galileoStaking.calculateRewards(staker1.address, nebulaAddress, 1);
      let withdrawRewards = await (await galileoStaking.connect(staker1).withdrawAllRewards(nebulaAddress)).wait();

      withdrawRewards = Number(formatEther(withdrawRewards.logs[1].args[2])).toFixed(2);

      const rewardsInEther = parseFloat(formatEther(rewards)) + 1; // Convert to number

      const adjustedRewards = rewardsInEther - rewardsInEther * 0.03;

      let taxAmount = rewardsInEther - adjustedRewards;
      taxAmount = Number(taxAmount.toFixed(2));

      let withdrawTax = await (await galileoStaking.connect(admin).withdrawTax(nebulaAddress)).wait();
      withdrawTax = parseFloat(formatEther(withdrawTax.logs[1].args[2]));
      expect(withdrawTax).to.be.equal(taxAmount);
    });

    it('Should revert Admin to withdraw tax and the smart contract does not have amount', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      // Mock reward setup and accumulation
      await galileoStaking.calculateRewards(staker1.address, nebulaAddress, 1);

      await expect(galileoStaking.connect(admin).withdrawTax(nebulaAddress)).to.be.revertedWithCustomError(galileoStaking, 'InvalidAmount');
    });

    it('Should revert if collection address is invalid', async function () {
      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));

      await expect(galileoStaking.connect(admin).withdrawTax(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if no tax available', async function () {
      await expect(galileoStaking.connect(admin).withdrawTax(nebulaAddress)).to.be.revertedWithCustomError(galileoStaking, 'InvalidAmount');
    });

    it('Should revert if non admin tries to withdraw tax', async function () {
      await expect(galileoStaking.connect(staker1).withdrawTax(nebulaAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      await expect(galileoStaking.connect(staker1).withdrawTax(nebulaAddress)).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });
  });

  describe('Deposit Rewards', function () {
    it('Should deposit tokens by Admin', async function () {
      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await expect(galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'))).to.not.be.reverted;
    });

    it('Should get the correct data after deposit tokens by Admin', async function () {
      const depositRewardTokens = parseEther('1000');
      await erc20Token.connect(admin).approve(galileoStakingAddress, depositRewardTokens);
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, depositRewardTokens);

      const getRewardTokensCount = await galileoStaking.getRewardPoolBalance(nebulaAddress);
      expect(getRewardTokensCount).to.be.equal(depositRewardTokens);
    });

    it('Should get the correct data after deposit tokens by Admin', async function () {
      const depositRewardTokens = parseEther('1000');
      await erc20Token.connect(admin).approve(galileoStakingAddress, depositRewardTokens);
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, depositRewardTokens);

      const getRewardTokensCount = await galileoStaking.getRewardPoolBalance(nebulaAddress);
      expect(getRewardTokensCount).to.be.equal(depositRewardTokens);
    });

    it('Should not deposit tokens by non-Admin', async function () {
      await expect(galileoStaking.connect(staker1).depositRewards(nebulaAddress, parseEther('1000'))).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });
  });

  describe('Unstake Tokens and get rewards', function () {
    it('Should allow user to unstake tokens get rewards', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      let citizen = 1;
      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await erc721Token.mint(staker1.address); // Mint NFT to staker1
      await erc20Token.transfer(staker1.address, parseEther('1000')); // Transfer LEOX to staker1

      tokenId = await erc721Token.totalSupply(); // Get the latest tokenId

      await erc721Token.connect(staker1).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      const rewardAmount = stakeTime + 6;
      await erc20Token.connect(admin).transfer(galileoStakingAddress, parseEther(rewardAmount.toString()));

      const rewards = await galileoStaking.calculateRewardsAllRewards(staker1.address, nebulaAddress);
      let unstake = await (await galileoStaking.connect(staker1).unstake(nebulaAddress, 1)).wait();

      unstake = Number(formatEther(unstake.logs[1].args[3])).toFixed(2);

      const rewardsInEther = parseFloat(formatEther(rewards)); // Convert to number

      const adjustedRewards = rewardsInEther - rewardsInEther * 0.03;

      expect(adjustedRewards).to.be.equal(Number(unstake));
    });

    it('Should revert if user tries to unstake tokens before stake time period ends', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      let citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await expect(galileoStaking.connect(staker1).unstake(nebulaAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'UnstakeBeforeLockPeriod'
      );
    });

    it('Should revert if smart contract does not have reward tokens', async function () {
      // Approve tokens for transfer
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await expect(galileoStaking.connect(staker1).unstake(nebulaAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAmountRewardPoolBalance'
      );
    });

    it('Should revert if collection address is invalid', async function () {
      await expect(galileoStaking.connect(staker1).unstake(ethers.ZeroAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if token id is invalid', async function () {
      await expect(galileoStaking.connect(staker1).unstake(nebulaAddress, 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidTokenId'
      );
    });

    it('Should revert if token id is not staked', async function () {
      await expect(galileoStaking.connect(staker1).unstake(nebulaAddress, 5)).to.be.revertedWithCustomError(
        galileoStaking,
        'TokenNotStaked'
      );
    });

    it('Should revert if staking contract is paused', async function () {
      await galileoStaking.connect(admin).pause();

      await expect(galileoStaking.connect(staker1).unstake(nebulaAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'EnforcedPause'
      );
    });
  });

  describe('Emergency Unstake Tokens and does not get rewards', function () {
    it('Should allow user to emergency unstake tokens without get rewards', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      let citizen = 1;
      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));

      await erc20Token.transfer(staker1.address, parseEther('1000')); // Transfer LEOX to staker1

      const stakerLeoxBalanceBefore = await erc20Token.balanceOf(staker1.address);

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await erc721Token.mint(staker1.address); // Mint NFT to staker1

      tokenId = await erc721Token.totalSupply(); // Get the latest tokenId

      await erc721Token.connect(staker1).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      let unstake = await (await galileoStaking.connect(staker1).emergencyUnstake(nebulaAddress, 1)).wait();

      const stakerLeoxBalanceAfter = await erc20Token.balanceOf(staker1.address);

      const stakerBalance = stakerLeoxBalanceBefore - stakeLeoxAmount; // unstake  nft, it minus the one nft
      expect(unstake.logs[3].args[4]).to.be.equal(stakeLeoxAmount);
      expect(stakerLeoxBalanceAfter).to.be.equal(stakerBalance);
    });

    it('Should allow user to emergency unstake tokens without get rewards', async function () {
      const stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      let citizen = 1;
      await erc20Token.connect(admin).approve(galileoStakingAddress, parseEther('1000'));
      await galileoStaking.connect(admin).depositRewards(nebulaAddress, parseEther('1000'));

      await erc20Token.transfer(staker1.address, parseEther('1000')); // Transfer LEOX to staker1

      const stakerLeoxBalanceBefore = await erc20Token.balanceOf(staker1.address);

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await ethers.provider.send('evm_increaseTime', [stakeTime]);
      await ethers.provider.send('evm_mine');

      await galileoStaking.connect(staker1).emergencyUnstake(nebulaAddress, 1);

      const calculateRewards = await galileoStaking.calculateRewards(staker1.address, nebulaAddress, 1);

      const stakerLeoxBalanceAfter = await erc20Token.balanceOf(staker1.address);

      expect(calculateRewards).to.be.equal(0);
      expect(stakerLeoxBalanceAfter).to.be.equal(stakerLeoxBalanceBefore);
    });

    it('Should revert if collection address is invalid', async function () {
      await expect(galileoStaking.connect(staker1).emergencyUnstake(ethers.ZeroAddress, 1)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidAddress'
      );
    });

    it('Should revert if token id is invalid', async function () {
      await expect(galileoStaking.connect(staker1).emergencyUnstake(nebulaAddress, 0)).to.be.revertedWithCustomError(
        galileoStaking,
        'InvalidTokenId'
      );
    });

    it('Should revert if token id is not staked', async function () {
      await expect(galileoStaking.connect(staker1).emergencyUnstake(nebulaAddress, 5)).to.be.revertedWithCustomError(
        galileoStaking,
        'TokenNotStaked'
      );
    });
  });

  describe('Get Staked information in pagination', function () {
    it('Should return the expected record in pagination', async function () {
      let stakeTimeInPool = 10;
      let stakeLeoxAmount = parseEther('100');
      let tokenId = 1;
      let citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      let signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      let voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);
      await erc721Token.mint(staker1.address); // Mint NFT to staker1
      await erc20Token.transfer(staker1.address, parseEther('1000')); // Transfer LEOX to staker1

      tokenId = await erc721Token.totalSupply(); // Get the latest tokenId

      await erc721Token.connect(staker1).approve(galileoStakingAddress, tokenId);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      const getStakedInfoPagination = await galileoStaking.getStakedInfoPagination(staker1.address, nebulaAddress, 1, 5);
      expect(getStakedInfoPagination[0].length).to.be.equal(2);
    });

    it('Should revert it page is zero', async function () {
      const stakeLeoxAmount = parseEther('100');
      const tokenId = 1;
      const citizen = 1;

      // Approve tokens for transfer
      await erc721Token.connect(staker1).approve(galileoStakingAddress, 1);
      await erc20Token.connect(staker1).approve(galileoStakingAddress, stakeLeoxAmount);
      const signature = await sign(admin, galileoStakingAddress, nebulaAddress, tokenId, citizen);

      const voucher = {
        collectionAddress: nebulaAddress,
        tokenId: tokenId,
        citizen: citizen,
        timelockEndTime: stakeTime,
        stakedLeox: stakeLeoxAmount,
        signature: signature,
      };

      // Stake NFT and LEOX
      await galileoStaking.connect(staker1).stake(voucher);

      await expect(galileoStaking.getStakedInfoPagination(staker1.address, nebulaAddress, 0, 5)).to.be.revertedWith(
        'Page number starts from 1'
      );
    });
  });

  describe('Pause Contract', async function () {
    it('Should pause staking contract by authorize address', async function () {
      await expect(galileoStaking.connect(admin).pause()).to.not.reverted;
    });

    it('Should not pause staking contract that is not unpaused', async function () {
      await expect(galileoStaking.connect(admin).pause()).to.not.reverted;

      await expect(galileoStaking.connect(admin).pause()).to.be.revertedWithCustomError(galileoStaking, 'EnforcedPause');
    });

    it('Should not pause staking contract by unauthorize address', async function () {
      await expect(galileoStaking.connect(staker1).pause()).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });
  });

  describe('Unpause Contract', async function () {
    it('Should unpause staking contract by authorize address', async function () {
      await expect(galileoStaking.connect(admin).pause()).to.not.reverted;
      await expect(galileoStaking.connect(admin).unpause()).to.not.reverted;
    });

    it('Should not unpause staking contract that is not paused', async function () {
      await expect(galileoStaking.connect(admin).unpause()).to.be.revertedWithCustomError(galileoStaking, 'ExpectedPause');
    });

    it('Should not unpause staking contract by unauthorize address', async function () {
      await expect(galileoStaking.connect(staker1).unpause()).to.be.revertedWithCustomError(
        galileoStaking,
        'AccessControlUnauthorizedAccount'
      );
    });
  });
});
