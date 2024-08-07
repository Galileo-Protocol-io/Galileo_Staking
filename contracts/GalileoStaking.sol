// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/Citizen.sol";
import "./interfaces/IGalileoSoulBoundToken.sol";

//  ██████╗  █████╗ ██╗     ██╗██╗     ███████╗  ██████╗
// ██╔════╝ ██╔══██╗██║     ██║██║     ██╔════╝ ██╔═══██╗
// ██║  ██╗ ███████║██║     ██║██║     █████╗   ██║   ██║
// ██║   █║ ██╔══██║██║     ██║██║     ██╔══╝   ██║   ██║
// ╚██████║ ██║  ██║███████╗██║███████╗███████╗ ╚██████╔╝
//  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝  ╚═════╝

// ═══════════════════════ ERORRS ════════════════════════

// Error indicating an invalid address for a collection
error InvalidAddress(address collectionAddress);

// Error indicating that a collection has not been initialized
error CollectionUninitialized();

// Error indicating that reward window times must be in increasing order
error RewardWindowPercentMustIncrease();

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

// Error indicating that a token id is not staked
error TokenNotStaked();

contract GalileoStaking is Citizen, AccessControl, ReentrancyGuard {
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

  /// A constant multiplier to reduce overflow in staking calculations.
  uint256 private constant _PRECISION = 1e18;

  // ═══════════════════════ STRUCTS ════════════════════════

  // Struct to store information about a stake per citizen
  struct StakePerCitizen {
    address collectionAddress; // Address of the collection where the token is staked
    uint256 tokenId; // ID of the token being staked
    uint256 citizen; // Citizen of the token being staked
    uint256 timelockStartTime; // Start time of the timelock for the staked token
    uint256 timelockEndTime; // End time of the timelock for the staked token
    uint256 points; // Points associated with the staked token
    uint256 stakedLEOX; // Amount of LEOX tokens staked with the token
  }

  // Struct to store stake information for a citizen
  struct StakeInfo {
    uint256[] tokenIds; // Array of token IDs staked in this citizen
    uint256 maxLeox; // Maximum LEOX staked in this citizen
    uint256 yieldTraitPoints; // Points earned by staking in this citizen
    string collectionName; // Name of the collection associated with this citizen
  }

  struct StakeInfoInput {
    uint256[] tokenIds; // Array of token IDs staked in this citizen
    uint256 maxLeox; // Maximum LEOX staked in this citizen
    uint256 yieldTraitPoints; // Points earned by staking in this citizen
  }

  // Struct to store staking multipliers
  struct Multiplier {
    uint256 stakingTime; // Duration of staking
    uint256 stakingBoost; // Boost applied to staking rewards
  }

  // Struct to define a reward window
  struct RewardWindow {
    uint256 stakedPercent; // Percentage of ERC721 token staked
    uint256 startTime; // Start time of the reward window
    uint256 rewardRate; // Reward value for the window
  }

  // Struct to store data related to a pool
  struct PoolData {
    uint256 totalPoints; // Total points accumulated in the pool
    uint256 tax; // Tax applied to rewards
    uint256 rewardCount; // Number of rewards configured for the pool
    RewardWindow[] rewardWindows; // Mapping of reward windows by index
  }

  // Struct defining input for configuring a pool
  struct PoolConfigurationInput {
    address collectionAddress; // Address of the collection associated with the pool
    uint256 tax; // Tax applied to rewards in the pool
    RewardWindow[] rewardWindows; // Array of reward windows for the pool
  }

  // ═══════════════════════ MAPPINGS ════════════════════════

  // Stores pool data for each collection address
  mapping(address => PoolData) private pools;

  // Stores detailed staking information for each user, collection, and specific NFT
  mapping(address => mapping(address => mapping(uint256 => StakePerCitizen))) private stakersPosition;

  // Stores an array of currently staked NFTs for a user in a specific collection
  mapping(address => mapping(address => StakePerCitizen[])) private stakedNFTs;

  // Stores the index of a specific NFT within the stakedNFTs mapping for a user and collection
  mapping(address => mapping(address => mapping(uint256 => uint256))) private stakedNFTIndex;

  // Stores information about user's LEOX holdings and maximum allowed stake per NFT
  mapping(address => StakeInfo[]) private leoxInfoByCitizen;

  // Stores potential staking boosts for different traits within the collection
  mapping(address => Multiplier[]) private stakingBoostPerCollection;

  // Maps a soulbound token address to the corresponding collection address
  mapping(address => address) private soulboundTokenToCollection;

  // Total supply of ERC721 tokens staked by address.
  mapping(address => uint256) private erc721Supply;

  // The last time rewards were updated for a given collection address.
  mapping(address => uint256) private lastUpdateTime;

  // The accumulated reward per token stored for a given collection address.
  mapping(address => uint256) private rewardPerTokenStored;

  // Tracks the amount of reward per token already paid to a specific user for a specific token.
  mapping(address => mapping(address => mapping(uint256 => uint256))) private userRewardPerTokenPaid;

  // Tracks the rewards accumulated but not yet withdrawn by a specific user for a specific token.
  mapping(address => mapping(address => mapping(uint256 => uint256))) private rewards;
  // Stores the total supply of ERC721 tokens for a specific collection address

  // Stores the total number of ERC721 tokens currently staked for a specific collection address
  mapping(address => uint256) private erc721Staked;

  // Stores the timestamp of the last reward claimed for a user, collection, and NFT
  mapping(address => mapping(address => mapping(uint256 => uint256))) private lastRewardTime;

  // Stores the share of rewards allocated for a specific reward window for a collection
  mapping(address => mapping(uint256 => uint256)) private sharePerWindow;

  // ═══════════════════════ EVENTS ════════════════════════

  // Event emitted when a collection is configured with its address and total number of categories
  event ConfigureCollection(address indexed collectionAddress, uint256 totalCategories);

  // Event emitted when a token is staked within a collection
  event StakeTokens(
    address collectionAddress, // Address of the collection where the token is being staked
    uint256 tokenId, // ID of the token being staked
    uint256 citizen, // Citizen of the token being staked
    uint256 timelockEndTime, // End time of the timelock for the staked token
    uint256 points, // Points associated with the staked token
    uint256 stakedLEOX // Amount of LEOX tokens staked with the token
  );

  /**
   * @dev Event emitted when more LEOX tokens are added to an existing stake.
   *
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token to which more tokens are staked.
   * @param citizen The citizen of the token.
   * @param newPoints The updated points after adding more tokens.
   * @param totalLeox The total amount of LEOX tokens staked after adding more tokens.
   */
  event StakeLeoxTokens(
    address indexed collectionAddress,
    uint256 indexed tokenId,
    uint256 indexed citizen,
    uint256 newPoints,
    uint256 totalLeox
  );

  // Event emitted when multipliers are set for a collection
  event SetMultipliers(address collectionAddress, Multiplier[] multipliers);

  // Event emitted when a user withdraws rewards for a staked NFT

  event WithdrawRewards(
    address indexed collectionAddress, // Address of the collection the NFT belongs to
    address indexed recipient, // Address of the user who withdrew the rewards
    uint256 tokenId, // Token ID of the NFT for which rewards were withdrawn
    uint256 rewardAmount, // Amount of rewards withdrawn
    uint256 currentTime // Timestamp of the withdrawal
  );

  // Event for unstaking tokens
  event UnstakeToken(
    address indexed collectionAddress,
    uint256 indexed tokenId,
    address indexed user,
    uint256 points,
    uint256 stakedLeox
  );

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

  /**
   * @dev Modifier to update the reward information for a specific token, collection address, and recipient.
   * This ensures that the reward calculations are up-to-date before executing the main function logic.
   *
   * @param tokenId The ID of the staked token.
   * @param collectionAddress The address of the NFT collection.
   * @param recipient The address of the staker.
   */
  modifier updateReward(
    uint256 tokenId,
    address collectionAddress,
    address recipient
  ) {
    // Update the stored reward per token for the collection to the current value.
    rewardPerTokenStored[collectionAddress] = rewardPerToken(collectionAddress);

    // Update the last update time for the collection to the current block timestamp.
    lastUpdateTime[collectionAddress] = block.timestamp;

    // If the recipient address is not zero, update their reward information.
    if (recipient != address(0)) {
      // Calculate and update the rewards for the recipient's specific token.
      rewards[recipient][collectionAddress][tokenId] = calculateRewards(recipient, collectionAddress, tokenId);

      // Update the amount of reward per token already paid to the recipient for the specific token.
      userRewardPerTokenPaid[recipient][collectionAddress][tokenId] = rewardPerTokenStored[collectionAddress];
    }

    // Continue with the execution of the main function.
    _;
  }

  // ═══════════════════════ FUNCTIONS ════════════════════════

  /**
   * @dev Function to stake tokens.
   *
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token to be staked.
   * @param citizen The citizen of the token.
   * @param stakedLeox The amount of LEOX tokens to be staked.
   * @param timelockEndTime The end time of the timelock for the stake.
   */
  function stake(
    address collectionAddress,
    uint256 tokenId,
    uint256 citizen,
    uint256 stakedLeox,
    uint256 timelockEndTime
  ) public nonReentrant updateReward(tokenId, collectionAddress, _msgSender()) {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) revert CollectionUninitialized();

    // Retrieve staker's position for the citizen within the collection
    StakePerCitizen memory _stakePerCitizen = stakersPosition[_msgSender()][collectionAddress][citizen];

    // Ensure that the token is not already staked by the staker
    if (_stakePerCitizen.tokenId == tokenId) {
      revert TokenAlreadyStaked();
    }

    // Stake the tokens
    _stakeTokens(collectionAddress, tokenId, citizen, timelockEndTime, stakedLeox);
  }

  /**
   * @dev Internal function to stake tokens.
   *
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token to be staked.
   * @param citizen The citizen of the token.
   * @param timelockEndTime The end time of the timelock for the stake.
   * @param stakedLeox The amount of LEOX tokens to be staked.
   */
  function _stakeTokens(
    address collectionAddress,
    uint256 tokenId,
    uint256 citizen,
    uint256 timelockEndTime,
    uint256 stakedLeox
  ) internal {
    // Check if the timelock end time is in the future
    if (timelockEndTime + block.timestamp < block.timestamp) {
      revert InvalidTime();
    }

    // Check if the pool is initialized
    if (pools[collectionAddress].rewardWindows[0].startTime >= block.timestamp) {
      revert PoolUninitialized(collectionAddress);
    }

    // Get the maximum LEOX information for the specified citizen
    StakeInfo memory _stakeInfo = getYieldTraitPoints(collectionAddress, citizen);

    // Check if the collection is initialized
    if (bytes(_stakeInfo.collectionName).length == 0) {
      revert CollectionUninitialized();
    }

    // Check if the staked LEOX tokens exceed the maximum allowed
    if (stakedLeox > _stakeInfo.maxLeox) {
      revert InvalidTokensCount(_stakeInfo.maxLeox);
    }

    // Check if the token ID exists in the specified citizen
    bool tokenIdExists = false;
    uint256[] memory tokenIds = _stakeInfo.tokenIds;

    // Check if the provided tokenId exists in the tokenIds array against citizen using assembly
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

    // Revert if the token ID does not exist in the specified citizen
    if (!tokenIdExists) {
      revert InvalidTokenId();
    }

    // Calculate the points for the stake
    uint256 points = calculatePoints(collectionAddress, citizen, stakedLeox, timelockEndTime);

    uint256 currentTime = block.timestamp;

    // Update the total points for the pool
    PoolData storage pool = pools[collectionAddress];
    pool.totalPoints += points;

    // Create a StakePerCitizen struct to store staking information
    StakePerCitizen memory stakePerCitizen = StakePerCitizen(
      collectionAddress,
      tokenId,
      citizen,
      currentTime,
      timelockEndTime,
      points,
      stakedLeox
    );

    // Store staking information for the user, collection, and token ID
    stakersPosition[_msgSender()][collectionAddress][tokenId] = stakePerCitizen;

    // Record the last reward time for this specific stake
    lastRewardTime[_msgSender()][collectionAddress][tokenId] = currentTime;

    // Update emission rate and reward window (likely triggered by a new stake)
    _updateEmissionRateAndRewardWindow(collectionAddress);

    // Add the StakePerCitizen struct to the user's staked NFTs list for this collection
    stakedNFTs[_msgSender()][collectionAddress].push(stakePerCitizen);

    // Store the index of the newly added stake within the stakedNFTs list
    stakedNFTIndex[_msgSender()][collectionAddress][tokenId] = stakedNFTs[_msgSender()][collectionAddress].length - 1;

    // // Transfer the token to this contract
    _assetTransferFrom(collectionAddress, _msgSender(), address(this), tokenId);

    // // Transfer the staked LEOX tokens to this contract
    _assetTransferFrom(LEOX, _msgSender(), address(this), stakedLeox);

    // Issue Sould Bound Token to the staker
    _issueSoulBoundToken(collectionAddress, _msgSender());

    // Emit an event to signify the staking of tokens
    emit StakeTokens(collectionAddress, tokenId, citizen, currentTime + timelockEndTime, points, stakedLeox);
  }

  /**
   * @dev Internal function to update share per window and update new emission rate
   *
   * @param collectionAddress The address of the collection contract.
   */
  function _updateEmissionRateAndRewardWindow(address collectionAddress) internal {
    // Get storage reference to the pool data for the provided collection address
    PoolData storage pool = pools[collectionAddress];

    // Calculate the staked percentage before the update
    uint256 previousStakedPercent = getStakedPercentage(collectionAddress);

    // Increment the total staked amount for the collection (likely ERC721 tokens)
    erc721Staked[collectionAddress] += _PRECISION;

    // Calculate the staked percentage after the update
    uint256 currentStakedPercent = getStakedPercentage(collectionAddress);

    // Get the current timestamp from the blockchain
    uint256 currentTime = block.timestamp;

    // Flags to track if updates were made during the loop
    bool sharePerWindowUpdated = false;
    // Flags to track if start time is updated during the loop
    bool startTimeUpdated = false;

    // Initialize updateIndex to the current length of the reward windows array
    uint256 updateIndex = pool.rewardWindows.length;

    // Loop through all reward windows for the collection
    for (uint256 i = 0; i < pool.rewardWindows.length; i++) {
      // Check if a new reward window needs to be started based on staked percentage increase

      if (
        !startTimeUpdated && // Start time wasn't updated yet
        currentStakedPercent >= pool.rewardWindows[i].stakedPercent && // Current stake meets threshold
        previousStakedPercent < pool.rewardWindows[i].stakedPercent && // Previous stake was below threshold
        pool.rewardWindows[i].startTime == 0
      ) {
        // Start time not yet set for this window
        pool.rewardWindows[i].startTime = currentTime; // Set the start time for the current window
        sharePerWindow[collectionAddress][updateIndex + 1] = pool.totalPoints; // Update sharePerWindow for the next window
        startTimeUpdated = true; // Mark start time update

        // Update updateIndex if not at the last window
        if (i + 1 < pool.rewardWindows.length) {
          updateIndex = i + 1;
        }
      }

      // Check if sharePerWindow needs update for an existing window
      if (
        !sharePerWindowUpdated && // SharePerWindow not updated yet
        pool.rewardWindows[i].startTime > 0 && // Start time is already set
        pool.rewardWindows[i].startTime < currentTime && // Current time is within the window
        (i == pool.rewardWindows.length - 1 || pool.rewardWindows[i + 1].startTime == 0)
      ) {
        // Last window or next window hasn't started
        if (!startTimeUpdated) {
          // Update updateIndex only if start time wasn't updated earlier
          updateIndex = i;
        }
        sharePerWindowUpdated = true; // Mark sharePerWindow update to exit loop after this iteration
      }
    }

    // Update sharePerWindow if an updateIndex was set but no start time update happened
    if (!startTimeUpdated) {
      sharePerWindow[collectionAddress][updateIndex] = pool.totalPoints;
    }
  }

  /**
   * @dev Function to add more LEOX tokens to an existing stake.
   *
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token to be staked.
   * @param stakeMoreLeox The additional amount of LEOX tokens to be staked.
   */
  function stakeLeoxTokens(
    address collectionAddress,
    uint256 tokenId,
    uint256 stakeMoreLeox
  ) public nonReentrant updateReward(tokenId, collectionAddress, _msgSender()) {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) revert CollectionUninitialized();

    // Check if the additional LEOX tokens to be staked are valid
    if (stakeMoreLeox == 0) revert InvalidTokensCount(0);

    // Retrieve staker's position for the token within the collection
    StakePerCitizen storage stakePerCitizen = stakersPosition[_msgSender()][collectionAddress][tokenId];

    // Ensure that the token is already staked by the staker
    if (stakePerCitizen.tokenId != tokenId) {
      revert TokenNotStaked();
    }

    // Check if the staked LEOX tokens exceed the maximum allowed after adding the new tokens
    StakeInfo memory _stakeInfo = getYieldTraitPoints(collectionAddress, stakePerCitizen.citizen);
    uint256 totalLeox = stakePerCitizen.stakedLEOX + stakeMoreLeox;
    if (totalLeox > _stakeInfo.maxLeox) {
      revert InvalidTokensCount(_stakeInfo.maxLeox);
    }

    // Calculate the new points for the stake
    uint256 newPoints = calculatePoints(
      collectionAddress,
      stakePerCitizen.citizen,
      totalLeox,
      stakePerCitizen.timelockEndTime
    );

    // Update the total points for the pool
    PoolData storage pool = pools[collectionAddress];
    pool.totalPoints = pool.totalPoints - stakePerCitizen.points + newPoints;

    // Update the staker's position with the new points and additional LEOX tokens
    stakePerCitizen.points = newPoints;
    stakePerCitizen.stakedLEOX = totalLeox;

    // Update the stakedNFTs list and the index if needed
    uint256 index = stakedNFTIndex[_msgSender()][collectionAddress][tokenId];
    stakedNFTs[_msgSender()][collectionAddress][index] = stakePerCitizen;

    // Transfer the additional LEOX tokens to this contract
    // _assetTransferFrom(LEOX, _msgSender(), address(this), stakeMoreLeox);

    // Emit an event to signify the addition of more tokens to the stake
    emit StakeLeoxTokens(collectionAddress, tokenId, stakePerCitizen.citizen, newPoints, totalLeox);
  }

  /**
   * @dev Function to get the percentage of staked tokens
   * @param collectionAddress : collection address of the pNFT collection
   */
  function getStakedPercentage(address collectionAddress) public view returns (uint256) {
    // Get the total supply of ERC721 tokens for the collection
    uint256 supply = erc721Supply[collectionAddress];

    // Get the total number of ERC721 tokens currently staked for the collection
    uint256 staked = erc721Staked[collectionAddress];

    // Handle division by zero (no tokens in supply)
    if (supply == 0) {
      return 0;
    }

    // Calculate the staked percentage with high precision (using 100e18 for 100%)
    return (staked * 100e18) / supply;
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
    uint256 citizen, // Citizen Id
    uint256 stakedLeox, // Amount of staked LEOX tokens
    uint256 timelockEndTime // The end time of the timelock
  ) public view returns (uint256) {
    // Get the multipliers for the given collection address
    Multiplier[] memory _multiplier = _getMultipliers(collectionAddress);

    StakeInfo memory _stakeInfo = getYieldTraitPoints(collectionAddress, citizen);

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
    uint256 leoxPoints = _calculateStakeLeoxPoints(stakedLeox);

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
    // Encode function call data for the asset's transferFrom function
    bytes memory data = abi.encodeWithSelector(_TRANSFER_FROM_SELECTOR, _from, _to, _idOrAmount);

    // Call the transferFrom function of the asset contract
    (bool success, bytes memory returnData) = _asset.call(data);

    // Check if the transfer was successful
    if (!success) {
      // If transfer failed, revert the transaction with the reason provided by the asset contract
      revert(string(returnData));
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
    // Encode function call data for the asset's transfer function
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
  function _calculateStakeLeoxPoints(uint256 stakedTokens) internal pure returns (uint256) {
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
   * @dev Calculates the reward per token for a given collection address.
   * @param collectionAddress The address of the NFT collection.
   * @return The reward per token for the specified collection.
   */
  function rewardPerToken(address collectionAddress) public view returns (uint256) {
    // Retrieve the pool data for the specified collection address
    PoolData storage pool = pools[collectionAddress];

    // If there are no points staked in the pool, return the stored reward per token value
    if (pool.totalPoints == 0) {
      return rewardPerTokenStored[collectionAddress];
    }

    // Initialize rewardPerTokenAcc with the stored reward per token value
    uint256 rewardPerTokenAcc = rewardPerTokenStored[collectionAddress];

    // Set the period start time to the last update time of the specified collection
    uint256 periodStart = lastUpdateTime[collectionAddress];

    // Iterate through the reward windows in reverse order
    for (uint256 i = pool.rewardCount; i > 0; i--) {
      // Get the current reward window
      RewardWindow memory rewardWindows = pool.rewardWindows[i - 1];

      // Check if the reward window start time is within the last update time and is greater than 0
      if (rewardWindows.startTime <= lastUpdateTime[collectionAddress] && rewardWindows.startTime > 0) {
        // Calculate the time period for the current reward window
        uint256 timePeriod = block.timestamp - periodStart;

        // Calculate the accumulated reward per token
        rewardPerTokenAcc += (rewardWindows.rewardRate * timePeriod * 1e18) / pool.totalPoints;

        // Update the period start time to the reward window start time
        periodStart = rewardWindows.startTime;

        // Break the loop if the reward window start time is within the last update time
        if (rewardWindows.startTime <= lastUpdateTime[collectionAddress]) {
          break;
        }
      }
    }

    // Return the accumulated reward per token
    return rewardPerTokenAcc;
  }

  /**
   * @dev Calculates the rewards earned by a staker for a specific token in a collection.
   * @param recipient The address of the staker.
   * @param collectionAddress The address of the NFT collection.
   * @param tokenId The ID of the staked token.
   * @return The calculated reward for the staker.
   */
  function calculateRewards(
    address recipient,
    address collectionAddress,
    uint256 tokenId
  ) public view returns (uint256) {
    // Fetching the staker's position information for the specified token in the collection.
    StakePerCitizen storage stakeInfo = stakersPosition[recipient][collectionAddress][tokenId];

    // Calculating the reward based on the staked points, reward per token, and previously paid reward per token.
    return
      (stakeInfo.points *
        (rewardPerToken(collectionAddress) - userRewardPerTokenPaid[recipient][collectionAddress][tokenId])) /
      1e18 +
      rewards[recipient][collectionAddress][tokenId];
  }

  /**
   * @dev Withdraws the accumulated rewards for a staked token.
   * The function ensures the caller has a valid collection address and token ID.
   * It updates the reward before processing the withdrawal.
   *
   * @param collectionAddress The address of the NFT collection.
   * @param tokenId The ID of the staked token.
   */
  function withdrawRewards(
    address collectionAddress,
    uint256 tokenId
  ) public nonReentrant updateReward(tokenId, collectionAddress, _msgSender()) {
    // Input Validation: Ensure the collection address is not the zero address.
    if (collectionAddress == address(0)) revert CollectionUninitialized();

    // Input Validation: Ensure the token ID is not zero.
    if (tokenId == 0) revert InvalidTokenId();

    // Fetch the address of the recipient (caller).
    address recipient = _msgSender();

    // Process the withdrawal of rewards for the recipient.
    _withdrawRewards(recipient, collectionAddress, tokenId);
  }

  /**
   * @dev Internal function to withdraw the accumulated rewards for a staked token.
   * It calculates the rewards, resets the reward balance, transfers the reward, and emits an event.
   *
   * @param recipient The address of the staker withdrawing the rewards.
   * @param collectionAddress The address of the NFT collection.
   * @param tokenId The ID of the staked token.
   */
  function _withdrawRewards(address recipient, address collectionAddress, uint256 tokenId) internal {
    // Calculate the rewards for the recipient, collection address, and token ID.
    uint256 rewardAmount = calculateRewards(recipient, collectionAddress, tokenId);

    // Check if there are rewards to withdraw.
    if (rewardAmount > 0) {
      // Reset the reward balance to zero after calculating.
      rewards[recipient][collectionAddress][tokenId] = 0;

      // Transfer the reward amount to the recipient.
      _assetTransfer(LEOX, recipient, rewardAmount);
    }
    // Emit an event indicating the withdrawal of rewards.
    emit WithdrawRewards(recipient, collectionAddress, tokenId, rewardAmount, block.timestamp);
  }

  /**
   * @dev Function to withdraw reward tokens.
   *
   * @param collectionAddress The address of the collection address.
   * @param tokenId The staked token id.
   */
  function unstake(address collectionAddress, uint256 tokenId) public {
    if (collectionAddress == address(0)) revert CollectionUninitialized(); // Ensure valid collection address
    if (tokenId == 0) revert InvalidTokenId(); // Ensure valid token ID
    _unstake(collectionAddress, tokenId);
  }

  /**
   * @dev Internal Function to withdraw reward tokens.
   *
   * @param collectionAddress The address of the collection address.
   * @param tokenId The staked token id.
   */
  function _unstake(address collectionAddress, uint256 tokenId) internal {
    address recipient = _msgSender();
    StakePerCitizen storage stakeInfo = stakersPosition[recipient][collectionAddress][tokenId];

    if (stakeInfo.tokenId != tokenId) revert TokenNotStaked();

    // Calculate the points to be subtracted from the pool
    uint256 points = stakeInfo.points;

    // Update the total points for the pool
    PoolData storage pool = pools[collectionAddress];
    pool.totalPoints -= points;

    // Remove the staker's position for the token
    delete stakersPosition[recipient][collectionAddress][tokenId];
    delete lastRewardTime[recipient][collectionAddress][tokenId];

    // Remove the staked NFT information from the array and update the index mapping
    uint256 index = stakedNFTIndex[recipient][collectionAddress][tokenId];
    uint256 lastIndex = stakedNFTs[recipient][collectionAddress].length - 1;

    if (index != lastIndex) {
      // Swap with the last element
      StakePerCitizen memory lastStakeInfo = stakedNFTs[recipient][collectionAddress][lastIndex];
      stakedNFTs[recipient][collectionAddress][index] = lastStakeInfo;
      stakedNFTIndex[recipient][collectionAddress][lastStakeInfo.tokenId] = index;
    }

    // Remove the last element
    stakedNFTs[recipient][collectionAddress].pop();
    delete stakedNFTIndex[recipient][collectionAddress][tokenId];

    _withdrawRewards(recipient, collectionAddress, tokenId);

    // Burn Soul Bound Token
    _burnSoulBoundToken(collectionAddress, tokenId);

    // Transfer the token back to the user
    _assetTransfer(collectionAddress, _msgSender(), tokenId);

    // Transfer the staked LEOX tokens back to the staker
    _assetTransfer(LEOX, _msgSender(), stakeInfo.stakedLEOX);

    // Emit an event to signify the unstaking of tokens
    emit UnstakeToken(collectionAddress, tokenId, recipient, points, stakeInfo.stakedLEOX);
  }

  /**
   * @dev Function to issue the SBT to the staker at stake time.
   *
   * @param stakerAddress The address of the staker's wallet.
   */
  function _issueSoulBoundToken(address collectionAddress, address stakerAddress) internal {
    // Get the address of the SBT contract associated with the collection
    address soulboundToken = soulboundTokenToCollection[collectionAddress];
    // Call the Galileo Sould Bound Token contract to issue the token
    IGALILEOSOULBOUNDTOKEN(soulboundToken).issue(stakerAddress);
  }

  /**
   * @dev Function to burn the SBT of the staker at unstake time.
   *
   * @param tokenId The token id that is burn.
   */
  function _burnSoulBoundToken(address collectionAddress, uint256 tokenId) internal {
    // Get the address of the SBT contract associated with the collection
    address soulboundToken = soulboundTokenToCollection[collectionAddress];
    // Call the Galileo Sould Bound Token contract to burn the token
    IGALILEOSOULBOUNDTOKEN(soulboundToken).burn(tokenId);
  }

  /**
   * @dev Function to configure a collection with stake information for LEOX tokens.
   *
   * @param collectionAddress The address of the collection contract.
   * @param soulboundToken The address of the Soul Bound Token.
   * @param _stakeInfo An array of StakeInfo structs containing information about LEOX tokens.
   */
  function configureCollection(
    address collectionAddress,
    address soulboundToken,
    StakeInfoInput[] calldata _stakeInfo
  ) public onlyRole(ADMIN_ROLE) {
    if (collectionAddress == address(0) && soulboundToken == address(0)) revert InvalidAddress(collectionAddress);
    // Get the collection's name from the ERC721 contract
    string memory collectionName = ERC721(collectionAddress).name();

    // Associate the collection with its corresponding SBT contract
    soulboundTokenToCollection[collectionAddress] = soulboundToken;
    uint256 totalSupply;
    // Loop through the provided staking details
    for (uint256 i = 0; i < _stakeInfo.length; i++) {
      StakeInfo memory stakeInfo = StakeInfo(
        _stakeInfo[i].tokenIds, // Array of token IDs for this citizen tier
        _stakeInfo[i].maxLeox, // Maximum LEOX reward for this tier
        _stakeInfo[i].yieldTraitPoints, // Yield trait points associated with this tier
        collectionName // Name of the collection (fetched earlier)
      );
      totalSupply += _stakeInfo[i].tokenIds.length;
      // Add the staking details for this citizen tier to the collection configuration
      leoxInfoByCitizen[collectionAddress].push(stakeInfo);
    }

    // Store the total supply of the collection (converted to 18 decimals)
    erc721Supply[collectionAddress] = totalSupply * 10 ** 18;
    // Emit an event to record the collection configuration
    emit ConfigureCollection(collectionAddress, _stakeInfo.length);
  }

  /**
   * @dev Function to set staking multipliers for a collection.
   *
   * @param collectionAddress The address of the collection contract.
   * @param multipliers An array of Multiplier structs containing staking time and boost information.
   */
  function setMultipliers(address collectionAddress, Multiplier[] calldata multipliers) public onlyRole(ADMIN_ROLE) {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) revert CollectionUninitialized();

    delete stakingBoostPerCollection[collectionAddress];

    // Loop through each Multiplier in the array and add them to the stakingBoostPerCollection mapping
    for (uint16 i = 0; i < multipliers.length; i++) {
      // Push the Multiplier struct to the stakingBoostPerCollection mapping
      stakingBoostPerCollection[collectionAddress].push(multipliers[i]);
    }

    // Emit an event to signify the successful setting of multipliers for the collection
    emit SetMultipliers(collectionAddress, multipliers);
  }

  /**
   * @dev Function to get staking multipliers for a collection.
   *
   * @param collectionAddress The address of the collection contract.
   * @return An array of Multiplier structs containing staking time and boost information.
   */
  function _getMultipliers(address collectionAddress) internal view returns (Multiplier[] memory) {
    // Check if the collection address is valid
    if (collectionAddress == address(0)) revert CollectionUninitialized();

    // Return the array of multipliers for the specified collection address
    return stakingBoostPerCollection[collectionAddress];
  }

  /**
   * @dev Function to get the maximum LEOX information for a specific citizen within a collection.
   *
   * @param collectionAddress The address of the collection contract.
   * @param citizen The citizen for which to get the maximum LEOX information.
   * @return A StakeInfo struct containing the maximum LEOX information for the specified citizen.
   */
  function getYieldTraitPoints(address collectionAddress, uint256 citizen) public view returns (StakeInfo memory) {
    // Retrieve the array of StakeInfo structs for the specified collection address
    StakeInfo[] memory _stakeInfo = leoxInfoByCitizen[collectionAddress];

    // Return the StakeInfo struct corresponding to the specified citizen
    return _stakeInfo[citizen - 1];
  }

  /**
   * @dev Function to get the staker's position for a specific token within a collection.
   *
   * @param stakerAddress The address of the staker's wallet.
   * @param collectionAddress The address of the collection contract.
   * @param tokenId The ID of the token.
   * @return A StakePerCitizen struct containing the staker's position for the specified token.
   */
  function getStakersPosition(
    address stakerAddress,
    address collectionAddress,
    uint256 tokenId
  ) public view returns (StakePerCitizen memory) {
    // Retrieve and return the staker's position for the specified token
    return stakersPosition[stakerAddress][collectionAddress][tokenId];
  }

  /**
   * @dev Function to configure pools with reward windows and tax information.
   *
   * @param _inputs An array of PoolConfigurationInput structs containing pool configuration information.
   */
  function configurePool(PoolConfigurationInput[] memory _inputs) public onlyRole(ADMIN_ROLE) {
    // Iterate through each input in the array
    for (uint256 i; i < _inputs.length; ) {
      // Get the collection address
      address collectionAddress = _inputs[i].collectionAddress;

      // Set the tax for the pool
      pools[collectionAddress].tax = _inputs[i].tax;

      // Clear the existing reward windows
      delete pools[collectionAddress].rewardWindows;

      // Get the number of reward windows for the current input
      uint256 poolRewardWindowCount = _inputs[i].rewardWindows.length;

      // Set the reward count for the pool
      pools[collectionAddress].rewardCount = poolRewardWindowCount;

      // Iterate through each reward window for the current input
      for (uint256 j; j < poolRewardWindowCount; ) {
        // Add the reward window to the pool's reward windows
        pools[collectionAddress].rewardWindows.push(_inputs[i].rewardWindows[j]);

        // Increment the index for the next reward window
        unchecked {
          j++;
        }
      }

      // Increment the index for the next input
      unchecked {
        i++;
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
    // Set the total points and reward count from the pool data
    rewardCount = pool.rewardCount;

    // Initialize an array to store reward windows
    rewardWindows = new RewardWindow[](rewardCount);

    // Copy each reward window from the pool data to the array
    for (uint256 i = 0; i < rewardCount; i++) {
      rewardWindows[i] = pool.rewardWindows[i];
    }
  }

  /**
   * @dev Function to get the all the staked nft information.
   *
   * @param recipient The wallet address of the staker
   * @param collectionAddress The address of the collection contract.
   * @param pageNumber Page Number.
   * @param pageSize Page size.
   * @return paginatedStakes returns all the information of nfts staked by staker against collection address.
   */
  function getStakedInfoPagination(
    address recipient, // Address of the user for whom to retrieve staked NFTs
    address collectionAddress, // Address of the specific collection to query
    uint256 pageNumber, // Page number for pagination (starts from 1)
    uint256 pageSize // Number of NFTs per page
  ) public view returns (StakePerCitizen[] memory, uint256, uint256) {
    // Input validation to ensure page number starts from 1
    require(pageNumber > 0, "Page number should start from 1");

    // Get the total number of staked NFTs for the user and collection
    uint256 totalStaked = stakedNFTs[recipient][collectionAddress].length;

    // Calculate the starting index for pagination based on page number and page size
    uint256 startIndex = (pageNumber - 1) * pageSize;

    // Calculate the ending index for pagination, ensuring it doesn't exceed total staked NFTs
    uint256 endIndex = startIndex + pageSize;
    if (endIndex > totalStaked) {
      endIndex = totalStaked;
    }

    // Calculate the number of NFTs to be returned in the current page
    uint256 itemsCount = endIndex - startIndex;

    // Create an array to store the paginated staked NFTs
    StakePerCitizen[] memory paginatedStakes = new StakePerCitizen[](itemsCount);

    // Loop through the requested items and populate the paginatedStakes array
    for (uint256 i = 0; i < itemsCount; i++) {
      paginatedStakes[i] = stakedNFTs[recipient][collectionAddress][startIndex + i];
    }

    // Calculate the total number of pages based on total staked NFTs and page size
    uint256 totalPages = (totalStaked + pageSize - 1) / pageSize;

    // Return the paginated list of staked NFTs, current page number, and total number of pages
    return (paginatedStakes, pageNumber, totalPages);
  }
}
