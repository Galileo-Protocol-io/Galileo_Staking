// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require('hardhat');

async function main() {
  // const MockLeox = await hre.ethers.deployContract('QRC20', [
  //   'Leox',
  //   'LEOX',
  //   18,
  //   hre.ethers.parseEther('10000000000'),
  //   '0x30cfa2dd6b79Bc800B0b8cbF89534Aa4D02D548A',
  //   '0x30cfa2dd6b79Bc800B0b8cbF89534Aa4D02D548A',
  //   hre.ethers.parseEther('10000000000'),
  //   true,
  // ]);
  // await MockLeox.waitForDeployment();
  // console.log(`Deployed to ${MockLeox.target}`);

  const MockNebula = await hre.ethers.deployContract('QRC721', [
    'Nebula Odysee',
    'NEBULA',
    'https://nebula-metadata-mainnet.s3.ap-southeast-2.amazonaws.com/nebula-odyssey-metadata/',
    '0x30cfa2dd6b79Bc800B0b8cbF89534Aa4D02D548A',
  ]);
  await MockNebula.waitForDeployment();
  console.log(`Nebula Deployed to ${MockNebula.target}`);

  const GalileoSoulBoundToken = await hre.ethers.deployContract('GalileoSoulBoundToken', [
    'NebulaSBT',
    'NSBT',
    'https://nebula-metadata-mainnet.s3.ap-southeast-2.amazonaws.com/nebula-odyssey-metadata/',
  ]);
  await GalileoSoulBoundToken.waitForDeployment();
  console.log(`Soul Bound Tokem Deployed to ${GalileoSoulBoundToken.target}`);

  const GalileoStaking = await hre.ethers.deployContract('GalileoStaking', [
    '0x191C907746d2FfffE0d524289bAf82e538776587',
    hre.ethers.parseEther('400'),
  ]);
  await GalileoStaking.waitForDeployment();
  console.log(`Staking Contract Deployed to ${GalileoStaking.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// npx hardhat run scripts/deploy.js --network polygonTestnet

// npx hardhat verify --network polygonTestnet 0xdd09DEE3d7C14a4aD90DFa9a0531f3F42ed49DD1 0x191C907746d2FfffE0d524289bAf82e538776587 400000000000000000000
