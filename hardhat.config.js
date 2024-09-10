require("@nomicfoundation/hardhat-toolbox");

require("dotenv").config();
const { POLYGON_KEY, MNEMONIC } = process.env;
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
    polygonTestnet: {
      url: "https://80002.rpc.thirdweb.com",
      accounts: [MNEMONIC],
    },
    matic: {
      url: "https://polygon-rpc.com",
      accounts: [MNEMONIC],
    },

  },

  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },

  // },
  paths: {
    artifacts: "./artifacts",
    sources: "./contracts",
    cache: "./cache",
    tests: "./test",
  },
  etherscan: {
    apiKey: {
      polygonMumbai: POLYGON_KEY,
    },
  },
};
