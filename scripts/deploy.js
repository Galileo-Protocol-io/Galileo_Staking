// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  // const MockLeox =  await hre.ethers.deployContract("MockLeox");
  // await MockLeox.waitForDeployment();
  // console.log(
  //   `Deployed to ${MockLeox.target}`
  // );

  // const MockNebula =  await hre.ethers.deployContract("MockNebula", ["https://nebula-metadata-mainnet.s3.ap-southeast-2.amazonaws.com/nebula-odyssey-metadata/"]);
  // await MockNebula.waitForDeployment();
  // console.log(
  //   `Deployed to ${MockNebula.target}`
  // );

  // const GalileoSoulBoundToken =  await hre.ethers.deployContract("GalileoSoulBoundToken", ["NebulaSBT", "NSBT", "https://tokenUri/"]);
  // await GalileoSoulBoundToken.waitForDeployment();
  // console.log(
  //   `Deployed to ${GalileoSoulBoundToken.target}`
  // );

  const GalileoStaking =  await hre.ethers.deployContract("GalileoStaking", ["0x94A13A56497CDE65b5B6D7843484fa2287197c4a"]);
  await GalileoStaking.waitForDeployment();
  console.log(
    `Deployed to ${GalileoStaking.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// npx hardhat run scripts/deploy.js --network polygonTestnet

// npx hardhat verify --network polygonTestnet 0x94A13A56497CDE65b5B6D7843484fa2287197c4a