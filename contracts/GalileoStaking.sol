// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/Category.sol";
import "hardhat/console.sol";

// ═══════════════════════ ERORRS ════════════════════════

// Error indicating an invalid address for a collection
error InvalidAddress(address collectionAddress);

// Error indicating that a collection has not been initialized
error CollectionUninitialized();

// Error indicating that reward window times must be in increasing order
error RewardWindowTimesMustIncrease();

// Error indicating that a pool associated with a collection has not been initialized
error PoolUninitialized(address collectionAddress);

// Error indicating an invalid count of tokens
error InvalidTokensCount(uint256 maxLeox);

// Error indicating an invalid time
error InvalidTime();

// Error indicating an invalid token ID
error InvalidTokenId();

// Error indicating that a token is already staked
error TokenAlreadyStaked();

contract GalileoStaking is Category, AccessControl, ReentrancyGuard {
  // ═══════════════════════ VARIABLES ════════════════════════

  // Constant variable defining the ADMIN_ROLE using keccak256 hash
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  // Constants for function selectors
  bytes4 private constant _TRANSFER_FROM_SELECTOR = 0x23b872dd; // Selector for transferFrom function
  bytes4 private constant _TRANSFER_SELECTOR = 0xa9059cbb; // Selector for transfer function

  // Immutable variable storing the address of the LEOX token
  address public immutable LEOX;

  // Constant for increment value
  uint256 private constant increment = 200e18; // 200 * 10^18

  // ═══════════════════════ STRUCTS ════════════════════════

  // Struct to store information about a stake per category
  struct StakePerCategory {
    address collectionAddress; // Address of the collection where the token is staked
    uint256 tokenId; // ID of the token being staked
    uint256 category; // Category of the token being staked
    uint256 timelockStartTime; // Start time of the timelock for the staked token
    uint256 timelockEndTime; // End time of the timelock for the staked token
    uint256 points; // Points associated with the staked token
    uint256 stakedLEOX; // Amount of LEOX tokens staked with the token
  }

  // Struct to store stake information for a category
  struct StakeInfo {
    uint256[] tokenIds; // Array of token IDs staked in this category
    uint256 maxLeox; // Maximum LEOX staked in this category
    uint256 yieldTraitPoints; // Points earned by staking in this category
    string collectionName; // Name of the collection associated with this category
  }

  // Struct to store staking multipliers
  struct Multiplier {
    uint256 stakingTime; // Duration of staking
    uint256 stakingBoost; // Boost applied to staking rewards
  }

  // Struct to define a reward window
  struct RewardWindow {
    uint128 startTime; // Start time of the reward window
    uint128 reward; // Reward value for the window
  }

  // Struct to store data related to a pool
  struct PoolData {
    uint256 totalPoints; // Total points accumulated in the pool
    uint256 tax; // Tax applied to rewards
    uint256 rewardCount; // Number of rewards configured for the pool
    mapping(uint256 => RewardWindow) rewardWindows; // Mapping of reward windows by index
  }

  // Struct defining input for configuring a pool
  struct PoolConfigurationInput {
    address collectionAddress; // Address of the collection associated with the pool
    uint256 tax; // Tax applied to rewards in the pool
    RewardWindow[] rewardWindows; // Array of reward windows for the pool
  }

  // ═══════════════════════ MAPPINGS ════════════════════════

  // Mapping to store PoolData for each collection address
  mapping(address => PoolData) private pools;

  // Mapping to store stakers' positions by collection, staker address, and category
  mapping(address => mapping(address => mapping(uint256 => StakePerCategory))) stakersPosition;

  // Mapping to store stake information by category for each collection
  mapping(address => StakeInfo[]) public leoxInfoByCategory;

  // Mapping to store staking boost multipliers for each collection
  mapping(address => Multiplier[]) public stakingBoostPerCollection;

  // ═══════════════════════ EVENTS ════════════════════════

  // Event emitted when a collection is configured with its address and total number of categories
  event ConfigureCollection(address collectionAddress, uint256 totalCategories);

  // Event emitted when a token is staked within a collection
  event StakeToken(
    address collectionAddress, // Address of the collection where the token is being staked
    uint256 tokenId, // ID of the token being staked
    uint256 category, // Category of the token being staked
    uint256 timelockEndTime, // End time of the timelock for the staked token
    uint256 points, // Points associated with the staked token
    uint256 stakedLEOX // Amount of LEOX tokens staked with the token
  );

  // Event emitted when multipliers are set for a collection
  event MultipliersSet(address collectionAddress, Multiplier[] multipliers);

  // ═══════════════════════ CONSTRUCTOR ════════════════════════

  /**
   * @dev Constructor to initialize the contract.
   *
   * @param _leox The address of the LEOX token contract.
   */
  constructor(address _leox) {
    // Ensure that the LEOX token address is not zero
    require(_leox != address(0), "Invalid Address - Address Zero");

    // Grant the default admin role to the deploying address
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

    // Grant the admin role to the deploying address
    _grantRole(ADMIN_ROLE, _msgSender());

    // Set the LEOX token address
    LEOX = _leox;
  }

  // ═══════════════════════ FUNCTIONS ════════════════════════

  /**
   * @dev Function to stake tokens.
   *
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token to be staked.
   * @param category The category of the token.
   * @param stakedLeox The amount of LEOX tokens to be staked.
   * @param timelockEndTime The end time of the timelock for the stake.
   */
  function stake(
    address collectionAddress,
    uint256 tokenId,
    uint256 category,
    uint256 stakedLeox,
    uint256 timelockEndTime
  ) public nonReentrant {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) {
      revert InvalidAddress(collectionAddress);
    }

    // Retrieve staker's position for the category within the collection
    StakePerCategory memory _stakePerCategory = stakersPosition[_msgSender()][collectionAddress][category];

    // Ensure that the token is not already staked by the staker
    if (_stakePerCategory.tokenId != tokenId) {
      revert TokenAlreadyStaked();
    }

    // Stake the tokens
    _stakeTokens(collectionAddress, tokenId, category, timelockEndTime, stakedLeox);
  }

  /**
   * @dev Internal function to stake tokens.
   *
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token to be staked.
   * @param category The category of the token.
   * @param timelockEndTime The end time of the timelock for the stake.
   * @param stakedLeox The amount of LEOX tokens to be staked.
   */
  function _stakeTokens(
    address collectionAddress,
    uint256 tokenId,
    uint256 category,
    uint256 timelockEndTime,
    uint256 stakedLeox
  ) internal {
    // Check if the timelock end time is in the future
    if (timelockEndTime < block.timestamp) {
      revert InvalidTime();
    }

    // Check if the pool is initialized
    if (pools[collectionAddress].rewardWindows[0].startTime >= block.timestamp) {
      revert PoolUninitialized(collectionAddress);
    }

    // Get the maximum LEOX information for the specified category
    StakeInfo memory _stakeInfo = getMaxLeoxPerCategory(collectionAddress, category);

    // Check if the collection is initialized
    if (bytes(_stakeInfo.collectionName).length == 0) {
      revert CollectionUninitialized();
    }

    // Check if the staked LEOX tokens exceed the maximum allowed
    if (stakedLeox > _stakeInfo.maxLeox) {
      revert InvalidTokensCount(_stakeInfo.maxLeox);
    }

    // Check if the token ID exists in the specified category
    bool tokenIdExists = false;
    uint256[] memory tokenIds = _stakeInfo.tokenIds;

    // Check if the provided tokenId exists in the tokenIds array against category using assembly
    assembly {
      let length := mload(tokenIds)
      let data := add(tokenIds, 0x20)
      for {
        let i := 0
      } lt(i, length) {
        i := add(i, 1)
      } {
        if eq(mload(data), tokenId) {
          tokenIdExists := 1
          break
        }
        data := add(data, 0x20)
      }
    }

    // Revert if the token ID does not exist in the specified category
    if (!tokenIdExists) {
      revert InvalidTokenId();
    }

    // Calculate the points for the stake
    uint256 points = calculatePoints(collectionAddress, timelockEndTime, stakedLeox, _stakeInfo);

    // Update the total points for the pool
    PoolData storage pool = pools[collectionAddress];
    pool.totalPoints += points;

    // Store the staker's position for the token
    stakersPosition[_msgSender()][collectionAddress][tokenId] = StakePerCategory(
      collectionAddress,
      tokenId,
      category,
      block.timestamp,
      block.timestamp + timelockEndTime,
      points,
      stakedLeox
    );

    // Transfer the token to this contract
    _assetTransferFrom(collectionAddress, _msgSender(), address(this), tokenId);

    // Transfer the staked LEOX tokens to this contract
    _assetTransferFrom(LEOX, _msgSender(), address(this), stakedLeox);

    // Emit an event to signify the staking of tokens
    emit StakeToken(collectionAddress, tokenId, category, block.timestamp + timelockEndTime, points, stakedLeox);
  }

  /**
   * @dev calculatePoints public function to calculate the staking points
   * @param collectionAddress : collection address of the pNFT collection
   * @param stakedLeox : token id of the collection
   * @param timelockEndTime : stake time lock
   * @return total calculated points
   */
  function calculatePoints(
    address collectionAddress, // Address of the collection
    uint256 timelockEndTime, // The end time of the timelock
    uint256 stakedLeox, // Amount of staked LEOX tokens
    StakeInfo memory _stakeInfo // Stake information struct
  ) public view returns (uint256) {
    // Get the multipliers for the given collection address
    Multiplier[] memory _multiplier = getMultipliers(collectionAddress);

    // Initialize the staking boost to zero
    uint256 stakingBoost = 0;

    // Iterate over the multipliers to find the matching staking time
    for (uint128 i = 0; i < _multiplier.length; i++) {
      if (timelockEndTime == _multiplier[i].stakingTime) {
        // Set the staking boost if the timelock end time matches
        stakingBoost = _multiplier[i].stakingBoost;
        break;
      }
    }

    // Revert the transaction if no matching staking boost is found
    if (stakingBoost == 0) {
      revert InvalidTime();
    }

    // Calculate the points for the staked LEOX tokens
    uint256 leoxPoints = calculateStakeLeoxPoints(stakedLeox);

    // Calculate the yield point boost based on the yield trait points and staking boost
    uint256 yieldPointBoost = _stakeInfo.yieldTraitPoints * stakingBoost;

    // Calculate the total points by adding yield point boost and LEOX points
    uint256 points = yieldPointBoost + leoxPoints;

    // Return the total points
    return points;
  }

  /**
		A private helper function for performing the low-level call to 
		`transferFrom` on either a specific ERC-721 token or some amount of ERC-20 
		tokens.

		@param _asset The address of the asset to perform the transfer call on.
		@param _from The address to attempt to transfer the asset from.
		@param _to The address to attempt to transfer the asset to.
		@param _idOrAmount This parameter encodes either an ERC-721 token ID or an 
			amount of ERC-20 tokens to attempt to transfer, depending on what 
			interface is implemented by `_asset`.
	*/
  function _assetTransferFrom(address _asset, address _from, address _to, uint256 _idOrAmount) private {
    (bool success, bytes memory data) = _asset.call(
      abi.encodeWithSelector(_TRANSFER_FROM_SELECTOR, _from, _to, _idOrAmount)
    );

    // Revert if the low-level call fails.
    if (!success) {
      revert(string(data));
    }
  }

  /**
		A private helper function for performing the low-level call to `transfer` 
		on some amount of ERC-20 tokens or ERC-721 token.

		@param _asset The address of the asset to perform the transfer call on.
		@param _to The address to attempt to transfer the asset to.
		@param _amount The amount of ERC-20 tokens or ERC-721 token to attempt to transfer.
	*/
  function _assetTransfer(address _asset, address _to, uint256 _amount) private {
    (bool success, bytes memory data) = _asset.call(abi.encodeWithSelector(_TRANSFER_SELECTOR, _to, _amount));

    // Revert if the low-level call fails.
    if (!success) {
      revert(string(data));
    }
  }

  /**
   * @dev Function to calculate the points for staked LEOX tokens.
   *
   * @param stakedTokens The number of staked LEOX tokens.
   * @return The calculated points for the staked tokens.
   */
  function calculateStakeLeoxPoints(uint256 stakedTokens) public pure returns (uint256) {
    // Calculate the base points by dividing the staked tokens by the increment
    uint256 points = stakedTokens / increment;

    // Check if there's a remainder after division
    if (stakedTokens % increment == 0) {
      // If no remainder, return points multiplied by 10^18 (to adjust decimals)
      return points * 10 ** 18;
    } else {
      // If there's a remainder, return points adjusted by the remainder and the increment
      return (points * 10 ** 18) / increment;
    }
  }

  /**
   * @dev Function to configure a collection with stake information for LEOX tokens.
   *
   * @param collectionAddress The address of the collection contract.
   * @param _LeoxInfo An array of StakeInfo structs containing information about LEOX tokens.
   */
  // [[[1,2,3,4,5,6,7,8,9],5000000000000000000000,5],[[10,11,12,13,14,15,17,18,19,20],4000000000000000000000,4]]
  function configureCollection(address collectionAddress, StakeInfo[] calldata _LeoxInfo) public onlyRole(ADMIN_ROLE) {
    // Get the name of the collection using the ERC721 interface
    string memory collectionName = ERC721(collectionAddress).name();

    // Loop through each StakeInfo in the array and add them to the leoxInfoByCategory mapping
    for (uint256 i = 0; i < _LeoxInfo.length; i++) {
      // Push the StakeInfo struct to the leoxInfoByCategory mapping
      leoxInfoByCategory[collectionAddress].push(
        StakeInfo(_LeoxInfo[i].tokenIds, _LeoxInfo[i].maxLeox, _LeoxInfo[i].yieldTraitPoints, collectionName)
      );
    }

    // Emit an event to signify the successful configuration of the collection
    emit ConfigureCollection(collectionAddress, _LeoxInfo.length);
  }

  /**
   * @dev Function to set staking multipliers for a collection.
   *
   * @param collectionAddress The address of the collection contract.
   * @param multipliers An array of Multiplier structs containing staking time and boost information. [[6000,1500000000000000000]]
   */
  function setMultipliers(address collectionAddress, Multiplier[] calldata multipliers) public onlyRole(ADMIN_ROLE) {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) {
      revert InvalidAddress(collectionAddress);
    }

    // Loop through each Multiplier in the array and add them to the stakingBoostPerCollection mapping
    for (uint16 i = 0; i < multipliers.length; i++) {
      // Push the Multiplier struct to the stakingBoostPerCollection mapping
      stakingBoostPerCollection[collectionAddress].push(multipliers[i]);
    }

    // Emit an event to signify the successful setting of multipliers for the collection
    emit MultipliersSet(collectionAddress, multipliers);
  }

  /**
   * @dev Function to get staking multipliers for a collection.
   *
   * @param collectionAddress The address of the collection contract.
   * @return An array of Multiplier structs containing staking time and boost information.
   */
  function getMultipliers(address collectionAddress) public view returns (Multiplier[] memory) {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) {
      revert InvalidAddress(collectionAddress);
    }

    // Return the array of multipliers for the specified collection address
    return stakingBoostPerCollection[collectionAddress];
  }

  /**
   * @dev Function to get the maximum LEOX information for a specific category within a collection.
   *
   * @param collectionAddress The address of the collection contract.
   * @param category The category for which to get the maximum LEOX information.
   * @return A StakeInfo struct containing the maximum LEOX information for the specified category.
   */
  function getMaxLeoxPerCategory(address collectionAddress, uint256 category) public view returns (StakeInfo memory) {
    // Retrieve the array of StakeInfo structs for the specified collection address
    StakeInfo[] memory _stakeInfo = leoxInfoByCategory[collectionAddress];

    // Return the StakeInfo struct corresponding to the specified category
    return _stakeInfo[category - 1];
  }

  /**
   * @dev Function to get the staker's position for a specific token within a collection.
   *
   * @param walletAddress The address of the staker's wallet.
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token.
   * @return A StakePerCategory struct containing the staker's position for the specified token.
   */
  function getStakersPosition(
    address walletAddress,
    address collectionAddress,
    uint256 tokenId
  ) public view returns (StakePerCategory memory) {
    // Retrieve and return the staker's position for the specified token
    return stakersPosition[walletAddress][collectionAddress][tokenId];
  }

  /**
   * @dev Function to configure pools with reward windows and tax information.
   *
   * @param _inputs An array of PoolConfigurationInput structs containing pool configuration information.
   */
  // [["0xd7Ca4e99F7C171B9ea2De80d3363c47009afaC5F",3000000000000000000,[[12,2500]]]]
  function configurePool(PoolConfigurationInput[] memory _inputs) public onlyRole(ADMIN_ROLE) {
    // Iterate through each input in the array
    for (uint256 i; i < _inputs.length; ) {
      // Get the number of reward windows for the current input
      uint256 poolRewardWindowCount = _inputs[i].rewardWindows.length;

      // Set the reward count and tax for the pool
      pools[_inputs[i].collectionAddress].rewardCount = poolRewardWindowCount;
      pools[_inputs[i].collectionAddress].tax = _inputs[i].tax;

      // Initialize a variable to store the last time for checking window times
      uint256 lastTime;

      // Iterate through each reward window for the current input
      for (uint256 j; j < poolRewardWindowCount; ) {
        // Set the reward window for the pool
        pools[_inputs[i].collectionAddress].rewardWindows[j] = _inputs[i].rewardWindows[j];

        // Check if the window start time is in increasing order
        if (j != 0 && _inputs[i].rewardWindows[j].startTime <= lastTime) {
          // Revert if the window start times are not in increasing order
          revert RewardWindowTimesMustIncrease();
        }

        // Update the last time to the current window's start time for the next iteration
        lastTime = _inputs[i].rewardWindows[j].startTime;

        // Increment the index for the next reward window
        unchecked {
          j++;
        }
      }

      // Increment the index for the next input
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @dev Function to get the configuration of a pool.
   *
   * @param collectionAddress The address of the collection contract.
   * @return totalPoints The total points of the pool.
   * @return rewardCount The count of reward windows in the pool.
   * @return rewardWindows An array of RewardWindow structs containing information about reward windows.
   */
  function getPoolConfiguration(
    address collectionAddress
  ) public view returns (uint256 totalPoints, uint256 rewardCount, RewardWindow[] memory rewardWindows) {
    // Retrieve the pool data for the specified collection address
    PoolData storage pool = pools[collectionAddress];

    // Set the total points and reward count from the pool data
    totalPoints = pool.totalPoints;
    rewardCount = pool.rewardCount;

    // Initialize an array to store reward windows
    rewardWindows = new RewardWindow[](rewardCount);

    // Copy each reward window from the pool data to the array
    for (uint256 i = 0; i < rewardCount; i++) {
      rewardWindows[i] = pool.rewardWindows[i];
    }
  }
}
