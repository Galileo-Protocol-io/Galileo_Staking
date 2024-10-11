// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library GalileoStakingStorage {
  // Struct to store details of a single staked NFT by a citizen
  struct StakePerCitizen {
    // Address of the NFT collection
    address collectionAddress;
    // Token ID of the staked NFT
    uint256 tokenId;
    // Citizen ID associated with the staked NFT
    uint256 citizen;
    // Start time of the staking timelock
    uint256 timelockStartTime;
    // End time of the staking timelock
    uint256 timelockEndTime;
    // Points earned from staking
    uint256 points;
    // Amount of LEOX tokens staked
    uint256 stakedLEOX;
  }

  // Struct to store staking information for a collection
  struct StakeInfo {
    // Maximum LEOX tokens staked in this citizen
    uint256 maxLeox;
    // Points earned by staking in this citizen
    uint256 yieldTraitPoints;
    // Name of the NFT collection
    string collectionName;
  }

  struct StakeTokens {
    // Address of the NFT collection
    address collectionAddress;
    //  Token ID of the staked NFT
    uint256 tokenId;
    //Citizen ID associated with the staked NFT
    uint256 citizen;
    // The timestamp representing the end time of the staking period.
    uint256 timelockEndTime;
    // The amount of LEOX tokens staked along with the NFT.
    uint256 stakedLeox;
    // A cryptographic signature to verify the validity of the staked data, ensuring security and authenticity.
    bytes signature;
  }

  // Input struct for providing stake information
  struct StakeInfoInput {
    // Maximum LEOX tokens staked in this citizen
    uint256 maxLeox;
    // Points earned by staking in this citizen
    uint256 yieldTraitPoints;
  }

  // Struct to store multiplier data for staking boost calculations
  struct Multiplier {
    // Duration of staking
    uint256 stakingTime;
    // Boost percentage for staking
    uint256 stakingBoost;
  }

  // Struct to define a reward window in the staking contract
  struct RewardWindow {
    // The reward rate applicable during this window (e.g., tokens per second)
    uint256 rewardRate;
    // The start time of this reward window (in seconds since epoch)
    uint256 startTime;
    // The end time of this reward window (in seconds since epoch)
    uint256 endTime;
  }

  // Struct to store data of a staking pool
  struct PoolData {
    // Total points accumulated in the pool
    uint256 totalPoints;
    // Tax rate for staking
    uint256 tax;
    // Count of rewards in the pool
    uint256 rewardCount;
    // Array of reward windows
    RewardWindow[] rewardWindows;
  }

  // Input struct for configuring a staking pool
  struct PoolConfigurationInput {
    // Address of the NFT collection
    address collectionAddress;
    // Tax rate for staking
    uint256 tax;
    // Array of reward windows
    RewardWindow[] rewardWindows;
  }

  // Main state struct to store all staking-related data
  struct State {
    // Mapping from collection address to pool data
    mapping(address => PoolData) pools;
    // Mapping from store the tax amount against collection address
    mapping(address => uint256) tax;
    // Mapping to store staking positions
    mapping(address => mapping(address => mapping(uint256 => StakePerCitizen))) stakersPosition;
    // Mapping to store staked NFTs by user
    mapping(address => mapping(address => StakePerCitizen[])) stakedNFTs;
    // Mapping to store index of staked NFTs
    mapping(address => mapping(address => mapping(uint256 => uint256))) stakedNFTIndex;
    // Mapping to store LEOX staking info and token IDs by citizen
    mapping(address => StakeInfo[]) stakeTokensInfo;
    // Mapping to store staking boost multipliers by collection
    mapping(address => Multiplier[]) stakingBoostPerCollection;
    // Mapping to associate soulbound tokens to collections
    mapping(address => address) soulboundTokenToCollection;
    // Mapping to store ERC721 token supply
    mapping(address => uint256) erc721Supply;
    // Mapping to store last update time of collections
    mapping(address => uint256) lastUpdateTime;
    // Mapping to store reward per token stored
    mapping(address => uint256) rewardPerTokenStored;
    // Mapping to store reward per token stored
    mapping(address => uint256) rewardPerTokenStoredNewRewardWindow;
    // Mapping to store rewards paid per user per token
    mapping(address => mapping(address => mapping(uint256 => uint256))) userRewardPerTokenPaid;
    // Mapping to store rewards by user and token
    mapping(address => mapping(address => mapping(uint256 => uint256))) rewards;
    // Mapping to store the number of staked ERC721 tokens
    mapping(address => uint256) erc721Staked;
    // Mapping to store the last reward time for users
    mapping(address => mapping(address => mapping(uint256 => uint256))) lastRewardTime;
    // Tracks total rewards per collection
    mapping(address => uint256) rewardPool;
  }
}
