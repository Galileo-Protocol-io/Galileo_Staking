// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IGalileoSoulBoundToken.sol";
import "./libraries/GalileoStakingStorage.sol";
import "./libraries/GalileoStakingErrors.sol";

contract GalileoStaking is AccessControl, ReentrancyGuard {
    //  ██████╗  █████╗ ██╗     ██╗██╗     ███████╗  ██████╗
    // ██╔════╝ ██╔══██╗██║     ██║██║     ██╔════╝ ██╔═══██╗
    // ██║  ██╗ ███████║██║     ██║██║     █████╗   ██║   ██║
    // ██║   █║ ██╔══██║██║     ██║██║     ██╔══╝   ██║   ██║
    // ╚██████║ ██║  ██║███████╗██║███████╗███████╗ ╚██████╔╝
    //  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝  ╚═════╝

    // ═══════════════════════ VARIABLES ════════════════════════

    // Constant variable defining the ADMIN_ROLE using keccak256 hash
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Constants for function selectors
    // Selector for transferFrom function
    bytes4 private constant _TRANSFER_FROM_SELECTOR = 0x23b872dd;
    // Selector for transfer function
    bytes4 private constant _TRANSFER_SELECTOR = 0xa9059cbb;

    // Importing the GalileoStakingStorage library for the State struct
    using GalileoStakingStorage for GalileoStakingStorage.State;

    // Declaring a private state variable of type GalileoStakingStorage.State
    GalileoStakingStorage.State private state;

    // Importing the GalileoStakingErrors library for all types (*)
    using GalileoStakingErrors for *;

    // Immutable variable storing the address of the LEOX token
    address public immutable LEOX;

    // Constant for increment value
    uint256 private constant increment = 200 ether; // 200 * 10^18

    /// A constant multiplier to reduce overflow in staking calculations.
    uint256 private constant PRECISION = 1 ether;

    // ═══════════════════════ EVENTS ════════════════════════

    /**
     * @dev Event emitted when a collection is configured with its address and total number of categories.
     *
     * @param collectionAddress The address of the collection contract.
     * @param totalCitizens Total number of citizens in the collection.
     */
    event ConfigureCollection(address indexed collectionAddress, uint256 totalCitizens);

    /**
     * @dev Event emitted when a token is staked within a collection
     *
     * @param collectionAddress The address of the collection contract.
     * @param tokenId The ID of the token to which more tokens are staked.
     * @param citizen The citizen of the token.
     * @param timelockEndTime End time of the timelock for the staked token.
     * @param points Points associated with the staked token.
     * @param stakedLEOX  Amount of LEOX tokens staked with the token.
     */
    event StakeTokens(address collectionAddress, uint256 tokenId, uint256 citizen, uint256 timelockEndTime, uint256 points, uint256 stakedLEOX);

    /**
     * @dev Event emitted when more LEOX tokens are added to an existing stake.
     *
     * @param collectionAddress The address of the collection contract.
     * @param tokenId The ID of the token to which more tokens are staked.
     * @param citizen The citizen of the token.
     * @param newPoints The updated points after adding more tokens.
     * @param totalLeox The total amount of LEOX tokens staked after adding more tokens.
     */
    event StakeLeoxTokens(address indexed collectionAddress, uint256 indexed tokenId, uint256 indexed citizen, uint256 newPoints, uint256 totalLeox);

    /**
     * @dev  Event emitted when multipliers are set for a collection.
     *
     * @param collectionAddress The address of the collection contract.
     * @param multipliers Multipliers based on staking time period.
     */
    event SetMultipliers(address collectionAddress, GalileoStakingStorage.Multiplier[] multipliers);

    /**
     * @dev Event emitted when a recipient withdraws rewards for a staked NFT
     *
     * @param collectionAddress Address of the collection the NFT belongs to.
     * @param recipient Address of the recipient who withdrew the rewards
     * @param tokenId The ID of the token to which more tokens are staked.
     * @param rewardAmount Amount of rewards withdrawn.
     * @param currentTime Timestamp of the withdrawal.
     */
    event WithdrawRewards(address indexed collectionAddress, address indexed recipient, uint256 tokenId, uint256 rewardAmount, uint256 currentTime);

    /**
     * @dev Event emitted when a recipient unstake Tokens and get rewards for a staked NFT
     *
     * @param collectionAddress Address of the collection the NFT belongs to.
     * @param recipient Address of the recipient who withdrew the rewards
     * @param tokenId The ID of the token to which more tokens are staked.
     * @param points Points associated with the staked token.
     * @param totalLeox Amount of LEOX tokens unstaked with the token.
     */
    event UnstakeToken(address indexed collectionAddress, address indexed recipient, uint256 indexed tokenId, uint256 points, uint256 totalLeox);

    // ═══════════════════════ CONSTRUCTOR ════════════════════════

    /**
     * @dev Constructor to initialize the contract.
     *
     * @param newLeox The address of the LEOX token contract.
     */
    constructor(address newLeox) {
        // Ensure that the LEOX token address is not zero
        require(newLeox != address(0), "Invalid Address - Address Zero");

        address deployer = _msgSender();

        // Grant the default admin role to the deploying address
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);

        // Grant the admin role to the deploying address
        _grantRole(ADMIN_ROLE, deployer);

        // Set the LEOX token address
        LEOX = newLeox;
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
        state.rewardPerTokenStored[collectionAddress] = rewardPerToken(collectionAddress);

        // Update the last update time for the collection to the current block timestamp.
        state.lastUpdateTime[collectionAddress] = block.timestamp;

        // If the recipient address is not zero, update their reward information.
        if (recipient != address(0)) {
            // Calculate and update the rewards for the recipient's specific token.
            state.rewards[recipient][collectionAddress][tokenId] = calculateRewards(recipient, collectionAddress, tokenId);

            // Update the amount of reward per token already paid to the recipient for the specific token.
            state.userRewardPerTokenPaid[recipient][collectionAddress][tokenId] = state.rewardPerTokenStored[collectionAddress];
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
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized();

        // Retrieve staker's position for the citizen within the collection
        GalileoStakingStorage.StakePerCitizen memory _stakePerCitizen = state.stakersPosition[_msgSender()][collectionAddress][citizen];

        // Ensure that the token is not already staked by the staker
        if (_stakePerCitizen.tokenId == tokenId) {
            revert GalileoStakingErrors.TokenAlreadyStaked();
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
    function _stakeTokens(address collectionAddress, uint256 tokenId, uint256 citizen, uint256 timelockEndTime, uint256 stakedLeox) internal {
        // Check if the timelock end time is in the future
        uint256 currentTime = block.timestamp;
        if (timelockEndTime + currentTime < currentTime) {
            revert GalileoStakingErrors.InvalidTime();
        }

        // Check if the pool is initialized
        if (state.pools[collectionAddress].rewardWindows[0].startTime >= currentTime) {
            revert GalileoStakingErrors.PoolUninitialized(collectionAddress);
        }

        // Get the maximum LEOX information for the specified citizen
        GalileoStakingStorage.StakeInfo memory _stakeInfo = getYieldTraitPoints(collectionAddress, citizen);

        // Check if the collection is initialized
        if (bytes(_stakeInfo.collectionName).length == 0) {
            revert GalileoStakingErrors.CollectionUninitialized();
        }

        // Check if the staked LEOX tokens exceed the maximum allowed
        if (stakedLeox > _stakeInfo.maxLeox) {
            revert GalileoStakingErrors.InvalidTokensCount(_stakeInfo.maxLeox);
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
            revert GalileoStakingErrors.InvalidTokenId();
        }

        // Calculate the points for the stake
        uint256 points = calculatePoints(collectionAddress, citizen, stakedLeox, timelockEndTime);

        // Update the total points for the pool
        GalileoStakingStorage.PoolData storage pool = state.pools[collectionAddress];
        pool.totalPoints += points;

        // Create a StakePerCitizen struct to store staking information
        GalileoStakingStorage.StakePerCitizen memory stakePerCitizen = GalileoStakingStorage.StakePerCitizen(
            collectionAddress,
            tokenId,
            citizen,
            currentTime,
            timelockEndTime,
            points,
            stakedLeox
        );

        // Store staking information for the recipient, collection, and token ID
        state.stakersPosition[_msgSender()][collectionAddress][tokenId] = stakePerCitizen;

        // Record the last reward time for this specific stake
        state.lastRewardTime[_msgSender()][collectionAddress][tokenId] = currentTime;

        // Update emission rate and reward window (likely triggered by a new stake)
        _updateEmissionRateAndRewardWindow(collectionAddress);

        // Add the StakePerCitizen struct to the recipient's staked NFTs list for this collection
        state.stakedNFTs[_msgSender()][collectionAddress].push(stakePerCitizen);

        // Store the index of the newly added stake within the stakedNFTs list
        state.stakedNFTIndex[_msgSender()][collectionAddress][tokenId] = state.stakedNFTs[_msgSender()][collectionAddress].length - 1;

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
        GalileoStakingStorage.PoolData storage pool = state.pools[collectionAddress];

        // Calculate the staked percentage before the update
        uint256 previousStakedPercent = getStakedPercentage(collectionAddress);

        // Increment the total staked amount for the collection (likely ERC721 tokens)
        state.erc721Staked[collectionAddress] += PRECISION;

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
        for (uint256 i = 0; i < pool.rewardWindows.length; ) {
            // Check if a new reward window needs to be started based on staked percentage increase

            if (
                // Start time wasn't updated yet
                !startTimeUpdated &&
                // Current stake meets threshold
                currentStakedPercent >= pool.rewardWindows[i].stakedPercent &&
                // Previous stake was below threshold
                previousStakedPercent < pool.rewardWindows[i].stakedPercent &&
                pool.rewardWindows[i].startTime == 0
            ) {
                // Start time not yet set for this window
                pool.rewardWindows[i].startTime = currentTime; // Set the start time for the current window
                state.sharePerWindow[collectionAddress][updateIndex + 1] = pool.totalPoints; // Update sharePerWindow for the next window
                startTimeUpdated = true; // Mark start time update

                // Update updateIndex if not at the last window
                if (i + 1 < pool.rewardWindows.length) {
                    updateIndex = i + 1;
                }
            }

            // Check if sharePerWindow needs update for an existing window
            if (
                // SharePerWindow not updated yet
                !sharePerWindowUpdated &&
                // Start time is already set
                pool.rewardWindows[i].startTime > 0 &&
                // Current time is within the window
                pool.rewardWindows[i].startTime < currentTime &&
                (i == pool.rewardWindows.length - 1 || pool.rewardWindows[i + 1].startTime == 0)
            ) {
                // Last window or next window hasn't started
                if (!startTimeUpdated) {
                    // Update updateIndex only if start time wasn't updated earlier
                    updateIndex = i;
                }
                // Mark sharePerWindow update to exit loop after this iteration
                sharePerWindowUpdated = true;
            }

            unchecked {
                i++;
            }
        }

        // Update sharePerWindow if an updateIndex was set but no start time update happened
        if (!startTimeUpdated) {
            state.sharePerWindow[collectionAddress][updateIndex] = pool.totalPoints;
        }
    }

    /**
     * @dev Function to add more LEOX tokens to an existing stake.
     *
     * @param collectionAddress The address of the collection contract.
     * @param tokenId The ID of the token to be staked.
     * @param stakeMoreLeox The additional amount of LEOX tokens to be staked.
     */
    function stakeLeoxTokens(address collectionAddress, uint256 tokenId, uint256 stakeMoreLeox) public nonReentrant updateReward(tokenId, collectionAddress, _msgSender()) {
        // Check if the collection address is valid
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized();

        // Check if the additional LEOX tokens to be staked are valid
        if (stakeMoreLeox == 0) revert GalileoStakingErrors.InvalidTokensCount(0);

        // Retrieve staker's position for the token within the collection
        GalileoStakingStorage.StakePerCitizen storage stakePerCitizen = state.stakersPosition[_msgSender()][collectionAddress][tokenId];

        // Ensure that the token is already staked by the staker
        if (stakePerCitizen.tokenId != tokenId) {
            revert GalileoStakingErrors.TokenNotStaked();
        }

        // Check if the staked LEOX tokens exceed the maximum allowed after adding the new tokens
        GalileoStakingStorage.StakeInfo memory _stakeInfo = getYieldTraitPoints(collectionAddress, stakePerCitizen.citizen);
        uint256 totalLeox = stakePerCitizen.stakedLEOX + stakeMoreLeox;
        if (totalLeox > _stakeInfo.maxLeox) {
            revert GalileoStakingErrors.InvalidTokensCount(_stakeInfo.maxLeox);
        }

        // Calculate the new points for the stake
        uint256 newPoints = calculatePoints(collectionAddress, stakePerCitizen.citizen, totalLeox, stakePerCitizen.timelockEndTime);

        // Update the total points for the pool
        GalileoStakingStorage.PoolData storage pool = state.pools[collectionAddress];
        pool.totalPoints = pool.totalPoints - stakePerCitizen.points + newPoints;

        // Update the staker's position with the new points and additional LEOX tokens
        stakePerCitizen.points = newPoints;
        stakePerCitizen.stakedLEOX = totalLeox;

        // Update the stakedNFTs list and the index if needed
        uint256 index = state.stakedNFTIndex[_msgSender()][collectionAddress][tokenId];
        state.stakedNFTs[_msgSender()][collectionAddress][index] = stakePerCitizen;

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
        uint256 supply = state.erc721Supply[collectionAddress];

        // Get the total number of ERC721 tokens currently staked for the collection
        uint256 staked = state.erc721Staked[collectionAddress];

        // Handle division by zero (no tokens in supply)
        if (supply == 0) {
            return 0;
        }

        // Calculate the staked percentage with high PRECISION (using 100e18 for 100%)
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
        GalileoStakingStorage.Multiplier[] memory _multiplier = _getMultipliers(collectionAddress);

        GalileoStakingStorage.StakeInfo memory _stakeInfo = getYieldTraitPoints(collectionAddress, citizen);

        // Initialize the staking boost to zero
        uint256 stakingBoost = 0;

        // Iterate over the multipliers to find the matching staking time
        for (uint128 i = 0; i < _multiplier.length; ) {
            if (timelockEndTime == _multiplier[i].stakingTime) {
                // Set the staking boost if the timelock end time matches
                stakingBoost = _multiplier[i].stakingBoost;
                break;
            }
            unchecked {
                i++;
            }
        }

        // Revert the transaction if no matching staking boost is found
        if (stakingBoost == 0) {
            revert GalileoStakingErrors.InvalidTime();
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
        if (stakedTokens == 0) revert GalileoStakingErrors.InvalidInput();
        // Calculate the base points by dividing the staked tokens by the increment
        uint256 points = stakedTokens / increment;

        // Check if there's a remainder after division
        if (stakedTokens % increment == 0) {
            // If no remainder, return points multiplied by 10^18 (to adjust decimals)
            return points * PRECISION;
        } else {
            // If there's a remainder, return points adjusted by the remainder and the increment
            return (points * PRECISION) / increment;
        }
    }

    /**
     * @dev Calculates the reward per token for a given collection address.
     * @param collectionAddress The address of the NFT collection.
     * @return The reward per token for the specified collection.
     */
    function rewardPerToken(address collectionAddress) public view returns (uint256) {
        // Retrieve the pool data for the specified collection address
        GalileoStakingStorage.PoolData storage pool = state.pools[collectionAddress];

        // If there are no points staked in the pool, return the stored reward per token value
        if (pool.totalPoints == 0) {
            return state.rewardPerTokenStored[collectionAddress];
        }

        // Initialize rewardPerTokenAcc with the stored reward per token value
        uint256 rewardPerTokenAcc = state.rewardPerTokenStored[collectionAddress];

        // Set the period start time to the last update time of the specified collection
        uint256 periodStart = state.lastUpdateTime[collectionAddress];

        // Iterate through the reward windows in reverse order
        for (uint256 i = pool.rewardCount; i > 0; ) {
            // Get the current reward window
            GalileoStakingStorage.RewardWindow memory rewardWindows = pool.rewardWindows[i - 1];

            // Check if the reward window start time is within the last update time and is greater than 0
            if (rewardWindows.startTime <= state.lastUpdateTime[collectionAddress] && rewardWindows.startTime > 0) {
                // Log the period start time and current time for debugging purposes

                // Calculate the time period for the current reward window
                uint256 timePeriod = block.timestamp - periodStart;

                // Calculate the accumulated reward per token
                rewardPerTokenAcc += (rewardWindows.rewardRate * timePeriod * 1e18) / pool.totalPoints;

                // Update the period start time to the reward window start time
                periodStart = rewardWindows.startTime;

                // Break the loop if the reward window start time is within the last update time
                if (rewardWindows.startTime <= state.lastUpdateTime[collectionAddress]) {
                    break;
                }

                unchecked {
                    i--;
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
    function calculateRewards(address recipient, address collectionAddress, uint256 tokenId) public view returns (uint256) {
        // Fetching the staker's position information for the specified token in the collection.
        GalileoStakingStorage.StakePerCitizen storage stakeInfo = state.stakersPosition[recipient][collectionAddress][tokenId];

        // Calculating the reward based on the staked points, reward per token, and previously paid reward per token.
        return
            (stakeInfo.points * (rewardPerToken(collectionAddress) - state.userRewardPerTokenPaid[recipient][collectionAddress][tokenId])) /
            1e18 +
            state.rewards[recipient][collectionAddress][tokenId];
    }

    /**
     * @dev Withdraws the accumulated rewards for a staked token.
     * The function ensures the caller has a valid collection address and token ID.
     * It updates the reward before processing the withdrawal.
     *
     * @param collectionAddress The address of the NFT collection.
     * @param tokenId The ID of the staked token.
     */
    function withdrawRewards(address collectionAddress, uint256 tokenId) public nonReentrant updateReward(tokenId, collectionAddress, _msgSender()) {
        // Input Validation: Ensure the collection address is not the zero address.
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized();

        // Input Validation: Ensure the token ID is not zero.
        if (tokenId == 0) revert GalileoStakingErrors.InvalidTokenId();

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
            state.rewards[recipient][collectionAddress][tokenId] = 0;

            // Transfer the reward amount to the recipient.
            // _assetTransfer(LEOX, recipient, rewardAmount);
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
    function unstake(address collectionAddress, uint256 tokenId) public nonReentrant {
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized(); // Ensure valid collection address
        if (tokenId == 0) revert GalileoStakingErrors.InvalidTokenId(); // Ensure valid token ID
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
        GalileoStakingStorage.StakePerCitizen storage stakeInfo = state.stakersPosition[recipient][collectionAddress][tokenId];

        if (stakeInfo.tokenId != tokenId) revert GalileoStakingErrors.TokenNotStaked();

        // Calculate the points to be subtracted from the pool
        uint256 points = stakeInfo.points;

        // Update the total points for the pool
        GalileoStakingStorage.PoolData storage pool = state.pools[collectionAddress];
        pool.totalPoints -= points;

        // Remove the staker's position for the token
        delete state.stakersPosition[recipient][collectionAddress][tokenId];
        delete state.lastRewardTime[recipient][collectionAddress][tokenId];

        // Remove the staked NFT information from the array and update the index mapping
        uint256 index = state.stakedNFTIndex[recipient][collectionAddress][tokenId];
        uint256 lastIndex = state.stakedNFTs[recipient][collectionAddress].length - 1;

        if (index != lastIndex) {
            // Swap with the last element
            GalileoStakingStorage.StakePerCitizen memory lastStakeInfo = state.stakedNFTs[recipient][collectionAddress][lastIndex];
            state.stakedNFTs[recipient][collectionAddress][index] = lastStakeInfo;
            state.stakedNFTIndex[recipient][collectionAddress][lastStakeInfo.tokenId] = index;
        }

        // Remove the last element
        state.stakedNFTs[recipient][collectionAddress].pop();
        delete state.stakedNFTIndex[recipient][collectionAddress][tokenId];

        _withdrawRewards(recipient, collectionAddress, tokenId);

        // Burn Soul Bound Token
        // _burnSoulBoundToken(collectionAddress, tokenId);

        // Transfer the token back to the recipient
        // _assetTransfer(collectionAddress, _msgSender(), tokenId);

        // Transfer the staked LEOX tokens back to the staker
        // _assetTransfer(LEOX, _msgSender(), stakeInfo.stakedLEOX);

        // Emit an event to signify the unstaking of tokens
        emit UnstakeToken(collectionAddress, recipient, tokenId, points, stakeInfo.stakedLEOX);
    }

    /**
     * @dev Function to issue the SBT to the staker at stake time.
     *
     * @param stakerAddress The address of the staker's wallet.
     */
    function _issueSoulBoundToken(address collectionAddress, address stakerAddress) internal {
        // Get the address of the SBT contract associated with the collection
        address soulboundToken = state.soulboundTokenToCollection[collectionAddress];
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
        address soulboundToken = state.soulboundTokenToCollection[collectionAddress];
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
    function configureNewCollection(address collectionAddress, address soulboundToken, GalileoStakingStorage.StakeInfoInput[] calldata _stakeInfo) public onlyRole(ADMIN_ROLE) {
        if (collectionAddress == address(0) && soulboundToken == address(0)) revert GalileoStakingErrors.InvalidAddress(collectionAddress);
        // Get the collection's name from the ERC721 contract
        string memory collectionName = ERC721(collectionAddress).name();

        // Check if the collection address has changed
        bool isNewCollection = (state.soulboundTokenToCollection[collectionAddress] == address(0));

        // If the collection address already exists, delete the existing stake token information
        if (!isNewCollection) {
            delete state.stakeTokensInfo[collectionAddress];
            delete state.soulboundTokenToCollection[collectionAddress];
        }

        // Associate the collection with its corresponding SBT contract
        state.soulboundTokenToCollection[collectionAddress] = soulboundToken;
        uint256 totalSupply;
        // Loop through the provided staking details
        for (uint256 i = 0; i < _stakeInfo.length; ) {
            if (_stakeInfo[i].tokenIds.length == 0 || _stakeInfo[i].maxLeox == 0 || _stakeInfo[i].yieldTraitPoints == 0) revert GalileoStakingErrors.InvalidInput();

            GalileoStakingStorage.StakeInfo memory stakeInfo = GalileoStakingStorage.StakeInfo(
                _stakeInfo[i].tokenIds, // Array of token IDs for this citizen tier
                _stakeInfo[i].maxLeox, // Maximum LEOX reward for this tier
                _stakeInfo[i].yieldTraitPoints, // Yield trait points associated with this tier
                collectionName // Name of the collection (fetched earlier)
            );
            totalSupply += _stakeInfo[i].tokenIds.length;
            // Add the staking details for this citizen tier to the collection configuration
            state.stakeTokensInfo[collectionAddress].push(stakeInfo);

            unchecked {
                i++;
            }
        }

        // Store the total supply of the collection (converted to 18 decimals)
        state.erc721Supply[collectionAddress] = totalSupply * PRECISION;
        // Emit an event to record the collection configuration
        emit ConfigureCollection(collectionAddress, _stakeInfo.length);
    }

    /**
     * @dev Function to set staking multipliers for a collection.
     *
     * @param collectionAddress The address of the collection contract.
     * @param multipliers An array of Multiplier structs containing staking time and boost information.
     */
    function setMultipliers(address collectionAddress, GalileoStakingStorage.Multiplier[] calldata multipliers) public onlyRole(ADMIN_ROLE) {
        // Check if the collection address is valid
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized();

        delete state.stakingBoostPerCollection[collectionAddress];

        // Loop through each Multiplier in the array and add them to the stakingBoostPerCollection mapping
        for (uint16 i = 0; i < multipliers.length; ) {
            // Push the Multiplier struct to the stakingBoostPerCollection mapping
            state.stakingBoostPerCollection[collectionAddress].push(multipliers[i]);

            unchecked {
                i++;
            }
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
    function _getMultipliers(address collectionAddress) internal view returns (GalileoStakingStorage.Multiplier[] memory) {
        // Check if the collection address is valid
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized();

        // Return the array of multipliers for the specified collection address
        return state.stakingBoostPerCollection[collectionAddress];
    }

    /**
     * @dev Function to get the maximum LEOX information for a specific citizen within a collection.
     *
     * @param collectionAddress The address of the collection contract.
     * @param citizen The citizen for which to get the maximum LEOX information.
     * @return A StakeInfo struct containing the maximum LEOX information for the specified citizen.
     */
    function getYieldTraitPoints(address collectionAddress, uint256 citizen) public view returns (GalileoStakingStorage.StakeInfo memory) {
        if (collectionAddress == address(0)) revert GalileoStakingErrors.CollectionUninitialized(); // Ensure valid collection address

        // Retrieve the array of StakeInfo structs for the specified collection address
        GalileoStakingStorage.StakeInfo[] memory _stakeInfo = state.stakeTokensInfo[collectionAddress];

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
    function getStakersPosition(address stakerAddress, address collectionAddress, uint256 tokenId) public view returns (GalileoStakingStorage.StakePerCitizen memory) {
        // Retrieve and return the staker's position for the specified token
        return state.stakersPosition[stakerAddress][collectionAddress][tokenId];
    }

    /**
     * @dev Function to configure pools with reward windows and tax information.
     *
     * @param _inputs An array of PoolConfigurationInput structs containing pool configuration information.
     */

    function configurePool(GalileoStakingStorage.PoolConfigurationInput[] memory _inputs) public onlyRole(ADMIN_ROLE) {
        // Iterate through each input in the array
        for (uint256 i; i < _inputs.length; ) {
            // Get the collection address
            address collectionAddress = _inputs[i].collectionAddress;

            // Set the tax for the pool
            state.pools[collectionAddress].tax = _inputs[i].tax;

            // Clear the existing reward windows
            delete state.pools[collectionAddress].rewardWindows;

            // Get the number of reward windows for the current input
            uint256 poolRewardWindowCount = _inputs[i].rewardWindows.length;

            // Set the reward count for the pool
            state.pools[collectionAddress].rewardCount = poolRewardWindowCount;

            // Iterate through each reward window for the current input
            for (uint256 j; j < poolRewardWindowCount; ) {
                // Add the reward window to the pool's reward windows
                state.pools[collectionAddress].rewardWindows.push(_inputs[i].rewardWindows[j]);

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
    ) public view returns (uint256 totalPoints, uint256 rewardCount, GalileoStakingStorage.RewardWindow[] memory rewardWindows) {
        // Retrieve the pool data for the specified collection address
        GalileoStakingStorage.PoolData storage pool = state.pools[collectionAddress];

        // Set the total points and reward count from the pool data
        totalPoints = pool.totalPoints;
        // Set the total points and reward count from the pool data
        rewardCount = pool.rewardCount;

        // Initialize an array to store reward windows
        rewardWindows = new GalileoStakingStorage.RewardWindow[](rewardCount);

        // Copy each reward window from the pool data to the array
        for (uint256 i = 0; i < rewardCount; ) {
            rewardWindows[i] = pool.rewardWindows[i];
            unchecked {
                i++;
            }
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
        address recipient, // Address of the recipient for whom to retrieve staked NFTs
        address collectionAddress, // Address of the specific collection to query
        uint256 pageNumber, // Page number for pagination (starts from 1)
        uint256 pageSize // Number of NFTs per page
    ) public view returns (GalileoStakingStorage.StakePerCitizen[] memory, uint256, uint256) {
        // Input validation to ensure page number starts from 1
        require(pageNumber > 0, "Page number should start from 1");

        // Get the total number of staked NFTs for the recipient and collection
        uint256 totalStaked = state.stakedNFTs[recipient][collectionAddress].length;

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
        GalileoStakingStorage.StakePerCitizen[] memory paginatedStakes = new GalileoStakingStorage.StakePerCitizen[](itemsCount);

        // Loop through the requested items and populate the paginatedStakes array
        for (uint256 i = 0; i < itemsCount; ) {
            paginatedStakes[i] = state.stakedNFTs[recipient][collectionAddress][startIndex + i];
            unchecked {
                i++;
            }
        }

        // Calculate the total number of pages based on total staked NFTs and page size
        uint256 totalPages = (totalStaked + pageSize - 1) / pageSize;

        // Return the paginated list of staked NFTs, current page number, and total number of pages
        return (paginatedStakes, pageNumber, totalPages);
    }
}
