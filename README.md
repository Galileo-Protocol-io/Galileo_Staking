# Galileo-Staking

## Overview

The Galileo Staking Platform is a groundbreaking solution offering a dynamic reward system and unparalleled flexibility. It supports multiple ERC721 collections, allowing admin to configure and users to stake a wide variety of NFTs. With its innovative approach, Galileo redefines NFT staking by providing customizable and rewarding experiences for users.

## Installation

To get started with the Galileo-Protocol project, follow these installation steps:

1. Clone the repository:

    ```bash
    git clone https://github.com/Galileo-Protocol-io/Galileo_Staking.git
    cd Galileo_Staking
    ```

2. Install dependencies using either Yarn or npm:

    ```bash
    # Using Yarn
    yarn

    # Using npm
    npm install
    ```


#### Deploy Contracts

Deploy contracts using Hardhat:

```bash
npx hardhat run scripts/deploy.js --network <network name>
```

#### Verify Contracts

Verify deployed contracts on the blockchain with Hardhat:

```bash
npx hardhat verify --network <chain name> <contract address> <param 1> <param 2>
```

## Running Tests

To ensure the functionality and integrity of the Galileo-Staking smart contracts, you can run test cases using the following commands:

### Hardhat Tests

To run tests using Hardhat, follow these steps:

1. Run the test cases:

```bash
npx hardhat test
```

## License

This project is licensed under the [MIT License](LICENSE).
