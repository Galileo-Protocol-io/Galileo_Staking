const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('GalileoStaking', function () {
  let GalileoStaking, staking, stakingAddress, owner, addr1, addr2, LEOX, leoxAddress, NEBULA, nebulaAddress;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy mock LEOX token
    const MockERC20 = await ethers.getContractFactory('MockERC20');
    LEOX = await MockERC20.connect(owner).deploy();

    leoxAddress = await LEOX.getAddress();

    const MockERC721 = await ethers.getContractFactory('MockERC721');
    NEBULA = await MockERC721.connect(owner).deploy();

    nebulaAddress = await NEBULA.getAddress();

    // Deploy GalileoStaking contract
    GalileoStaking = await ethers.getContractFactory('GalileoStaking');
    staking = await GalileoStaking.connect(owner).deploy(leoxAddress);

    stakingAddress = await staking.getAddress();

    // Mint LEOX tokens to addr1 and addr2
    await LEOX.transfer(addr1.address, ethers.parseEther('1000'));
    await LEOX.transfer(addr2.address, ethers.parseEther('1000'));
  });

  describe('Stake', function () {
    it('Should allow users to stake tokens', async function () {
      await LEOX.connect(addr1).approve(stakingAddress, ethers.parseEther('100'));
      // await staking.connect(addr1).stake('0xCollectionAddress', 1, 1, ethers.parseEther('100'), 3600);
      // const stakeInfo = await staking.getStakersPosition(addr1.address, '0xCollectionAddress', 1);

      // expect(stakeInfo.stakedLEOX).to.equal(ethers.parseEther('100'));
    });

    // it('Should not allow users to stake tokens with invalid timelock', async function () {
    //   await leoxAddress.connect(addr1).approve(staking.address, ethers.parseEther('100'));
    //   await expect(
    //     staking.connect(addr1).stake('0xCollectionAddress', 1, 1, ethers.parseEther('100'), 0)
    //   ).to.be.revertedWith('InvalidTime');
    // });
  });
});
