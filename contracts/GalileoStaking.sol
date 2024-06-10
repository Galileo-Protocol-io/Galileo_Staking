// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/Category.sol";
import "hardhat/console.sol";

error UnconfiguredCollection(uint256 collectionId);
error UnconfiguredPool(uint256 collectionId);
error RewardWindowTimesMustIncrease();
error InactivePool(uint256 collectionId);
error InvalidTokensCount(uint256 maxLeox);
error InvalidTime();
error InvalidCategory();
error InvalidTokenId();

contract GalileoStaking is Category, AccessControl, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes4 private constant _TRANSFER_FROM_SELECTOR = 0x23b872dd;
  bytes4 private constant _TRANSFER_SELECTOR = 0xa9059cbb;

  address public immutable LEOX;
  uint256 private nextCollectionId;
  uint256 private constant increment = 200e18;

  struct StakePerCategory {
    uint256 collectionId;
    uint256 tokenId;
    uint256 category;
    uint256 timelockStartTime;
    uint256 timelockEndTime;
    uint256 points;
    uint256 stakedLEOX;
  }

  struct LeoxInfo {
    uint256[] tokenIds;
    uint256 maxLeox;
    uint256 yieldTraitPoints;
  }

  struct Multiplier {
    uint256 stakingTime;
    uint256 stakingBoost;
  }

  struct CollectionInfo {
    address collectionAddress;
    string collectionName;
    mapping(uint256 => uint256) maxLeoxPerCategory;
  }

  struct RewardWindow {
    uint128 startTime;
    uint128 reward;
  }

  struct PoolData {
    uint256 totalPoints;
    uint256 tax;
    uint256 rewardCount;
    mapping(uint256 => RewardWindow) rewardWindows;
  }

  struct PoolConfigurationInput {
    uint256 collectionId;
    uint256 tax;
    RewardWindow[] rewardWindows;
  }

  mapping(uint256 => PoolData) public pools;
  mapping(uint256 => CollectionInfo) public collections;
  mapping(address => uint256) public collectionToCategory;
  mapping(address => mapping(uint256 => mapping(uint256 => StakePerCategory))) stakersPosition;
  mapping(uint256 => LeoxInfo[]) public leoxInfoByCategory;
  mapping(address => Multiplier[]) public stakingBoostPerCollection;
  mapping(uint256 => uint256) public categoriesPerCollection;
  mapping(uint256 => uint256) public categoryPerNFT;

  event ConfigureCollection(address collectionAddress, uint256 collectionId);

  event StakeToken(
    uint256 collectionId,
    uint256 tokenId,
    uint256 category,
    uint256 timelockEndTime,
    uint256 points,
    uint256 stakedLEOX
  );
  event MultipliersSet(uint256 collectionId, Multiplier[] multipliers);

  /**
   * @dev construstor function
   * @param _leox : LEOX ERC20 token address
   */
  constructor(address _leox) {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(ADMIN_ROLE, _msgSender());
    require(_leox != address(0), "Invalid Address - Address Zero");
    LEOX = _leox;
  }

  /**
   * @dev stake function
   * @param collectionId : collection Id of the pNFT collection
   * @param tokenId : token id of the collection
   * @param stakedLeox : amount of LEOX staked
   * @param timelockEndTime : stake time lock
   */
  function stake(
    uint256 collectionId,
    uint256 tokenId,
    uint256 category,
    uint256 stakedLeox,
    uint256 timelockEndTime
  ) public nonReentrant {
    address collectionAddress = getCollectionAddressById(collectionId);

    if (collectionAddress == address(0)) {
      revert UnconfiguredCollection(collectionId);
    }

    StakePerCategory memory _stakePerCategory = stakersPosition[_msgSender()][collectionId][category];

    require(_stakePerCategory.tokenId != tokenId, "NFT is already staked");

    _stakeTokens(collectionAddress, collectionId, tokenId, category, timelockEndTime, stakedLeox);
  }

  /**
   * @dev _stakeNFT internal function to stake NFTs
   * @param collectionAddress : collection address of the NFT collection
   * @param collectionId : collection Id of the pNFT collection
   * @param tokenId : token id of the collection
   * @param timelockEndTime : stake time lock
   */
  function _stakeTokens(
    address collectionAddress,
    uint256 collectionId,
    uint256 tokenId,
    uint256 category,
    uint256 timelockEndTime,
    uint256 stakedLeox
  ) internal {
    // Ensure the timelock end time is in the future
    if (timelockEndTime < block.timestamp) {
      revert InvalidTime();
    }

    // Ensure the pool is currently active
    if (pools[collectionId].rewardWindows[0].startTime >= block.timestamp) {
      revert InactivePool(uint256(collectionId));
    }

    // Get the maximum allowed Leox tokens per category for the given collection
    LeoxInfo memory _leoxInfo = getMaxLeoxPerCategory(collectionAddress, category);

    // Ensure the staked amount does not exceed the maximum allowed
    if (stakedLeox > _leoxInfo.maxLeox) {
      revert InvalidTokensCount(_leoxInfo.maxLeox);
    }

    // Initialize a flag to check if the tokenId exists in the allowed list
    bool tokenIdExists = false;
    uint256[] memory tokenIds = _leoxInfo.tokenIds;

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

    // Revert if the tokenId is not in the list of allowed tokenIds
    if (!tokenIdExists) {
      revert InvalidTokenId();
    }

    // Calculate the points for staking based on various factors
    uint256 points = calculatePoints(collectionId, timelockEndTime, stakedLeox, _leoxInfo);

    // Store the staking information in the stakersPosition mapping
    stakersPosition[_msgSender()][collectionId][tokenId] = StakePerCategory(
      collectionId,
      tokenId,
      category,
      block.timestamp,
      block.timestamp + timelockEndTime,
      points,
      stakedLeox
    );

    // Transfer the ERC-721 token from the staker to the contract
    _assetTransferFrom(collectionAddress, _msgSender(), address(this), tokenId);

    // Transfer the staked LEOX(ERC-20) tokens from the staker to the contract
    _assetTransferFrom(LEOX, _msgSender(), address(this), stakedLeox);

    // Emit an event to log the staking action
    emit StakeToken(collectionId, tokenId, category, block.timestamp + timelockEndTime, points, stakedLeox);
  }

  /**
   * @dev calculatePoints public function to calculate the staking points
   * @param collectionId : collection Id of the pNFT collection
   * @param stakedLeox : token id of the collection
   * @param timelockEndTime : stake time lock
   * @return total calculated points
   */
  function calculatePoints(
    uint256 collectionId,
    uint256 timelockEndTime,
    uint256 stakedLeox,
    LeoxInfo memory _leoxInfo
  ) public returns (uint256) {
    Multiplier[] memory _multiplier = getMultipliers(collectionId);

    uint256 stakingBoost = 0;
    for (uint128 i = 0; i < _multiplier.length; i++) {
      if (timelockEndTime == _multiplier[i].stakingTime) {
        stakingBoost = _multiplier[i].stakingBoost;
        break;
      }
    }

    if (stakingBoost == 0) {
      revert InvalidTime();
    }

    uint256 leoxPoints = calculateStakeLeoxPoints(stakedLeox);

    uint256 yeildPointBoost = _leoxInfo.yieldTraitPoints * stakingBoost;
    uint256 points = yeildPointBoost + leoxPoints;

    PoolData storage pool = pools[collectionId];
    pool.totalPoints += points;

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
   * @dev calculateStakeLeoxPoints internal function to calculate points against LEOX
   * @param stakedTokens : ERC20 tokens to be staked
   * @return leoxPoints : points as per staked LEOX
   */
  function calculateStakeLeoxPoints(uint256 stakedTokens) public pure returns (uint256) {
    uint256 points = stakedTokens / increment;
    if (stakedTokens % increment == 0) {
      return points * 10 ** 18;
    } else {
      return (points * 10 ** 18) / increment;
    }
  }

  /**
   * @dev configureCollection function to configure collection address
   * @param collectionAddress : collection address of NFT address
   * @param _LeoxInfo : token id of the collection
   */
  function configureCollection(address collectionAddress, LeoxInfo[] calldata _LeoxInfo) public onlyRole(ADMIN_ROLE) {
    string memory collectionName = ERC721(collectionAddress).name();
    (address _collectionAddress, string memory _collectionName, ) = getCollectionDetailsByAddress(collectionAddress);

    if (
      collectionAddress != _collectionAddress &&
      keccak256(abi.encodePacked(_collectionName)) != keccak256(abi.encodePacked(collectionName))
    ) {
      nextCollectionId++;
    }
    for (uint256 i = 0; i < _LeoxInfo.length; i++) {
      leoxInfoByCategory[nextCollectionId].push(
        LeoxInfo(_LeoxInfo[i].tokenIds, _LeoxInfo[i].maxLeox, _LeoxInfo[i].yieldTraitPoints)
      );
      categoriesPerCollection[i + 1] = _LeoxInfo.length - 1;
    }
    collections[nextCollectionId].collectionAddress = collectionAddress;
    collections[nextCollectionId].collectionName = collectionName;
    emit ConfigureCollection(collectionAddress, nextCollectionId);
  }

  /**
   * @dev setMultipliers function set the multipliers by the admin
   * @param collectionId : collection id of NFT address
   * @param multipliers : staking time and staking boost
   */
  function setMultipliers(uint256 collectionId, Multiplier[] calldata multipliers) public onlyRole(ADMIN_ROLE) {
    address collectionAddress = getCollectionAddressById(collectionId);

    if (collectionAddress == address(0)) {
      revert UnconfiguredCollection(collectionId);
    }

    for (uint16 i = 0; i < multipliers.length; i++) {
      stakingBoostPerCollection[collectionAddress].push(multipliers[i]);
    }

    emit MultipliersSet(collectionId, multipliers);
  }

  /**
   * @dev setMultipliers function set the multipliers by the admin
   * @param collectionId : collection id of NFT address
   * @return multipliers : staking time and staking boost
   */
  function getMultipliers(uint256 collectionId) public view returns (Multiplier[] memory) {
    address collectionAddress = getCollectionAddressById(collectionId);

    if (collectionAddress == address(0)) {
      revert UnconfiguredCollection(collectionId);
    }

    return stakingBoostPerCollection[collectionAddress];
  }

  /**
   * @dev getCollectionDetailsByAddress function to get data against collection address
   * @param collectionAddress : collection address of NFT address
   * @return _collectionAddress : ERC721 collection address
   * @return collectionName : ERC721 collection name
   * @return _collectionId : collection id
   */
  function getCollectionDetailsByAddress(
    address collectionAddress
  ) public view returns (address _collectionAddress, string memory collectionName, uint256 _collectionId) {
    uint256 collectionId = _getCollectionByAddress(collectionAddress);
    CollectionInfo storage collection = collections[collectionId];

    return (collection.collectionAddress, collection.collectionName, collectionId);
  }

  /**
   * @dev getMaxLeoxPerCategory function to get max leox against category
   * @param collectionAddress : collection address of NFT address
   * @param category : category id
   * @return LeoxInfo
   */
  function getMaxLeoxPerCategory(address collectionAddress, uint256 category) public view returns (LeoxInfo memory) {
    uint256 collectionId = _getCollectionByAddress(collectionAddress);
    LeoxInfo[] memory _leoxInfo = leoxInfoByCategory[collectionId];

    return _leoxInfo[category - 1];
  }

  /**
   * @dev _getCollectionByAddress internal function to configure collection address
   * @param collectionAddress : collection address of NFT address
   * @return collection id
   */
  function _getCollectionByAddress(address collectionAddress) internal view returns (uint256) {
    for (uint256 i = 0; i <= nextCollectionId; i++) {
      if (collections[i].collectionAddress == collectionAddress) {
        return i;
      }
    }
    return 0;
  }

  /**
   * @dev getCollectionAddressById function to get collection address by id
   * @param collectionId : collection id
   * @return collection address
   */
  function getCollectionAddressById(uint256 collectionId) public view returns (address) {
    if (collectionId <= nextCollectionId) {
      return collections[collectionId].collectionAddress;
    }
    return address(0);
  }

  /**
   * @dev getStakersPosition function to get staker's position
   * @param walletAddress : wallet address of staker
   * @param collectionId : collection id
   * @param tokenId : token id
   * @return staker's position
   */
  function getStakersPosition(
    address walletAddress,
    uint256 collectionId,
    uint256 tokenId
  ) public view returns (StakePerCategory memory) {
    return stakersPosition[walletAddress][collectionId][tokenId];
  }

  /**
   * @dev configurePool function to get information of staked LEOX
   * @param _inputs : configure the pool for staking
   */
  function configurePool(PoolConfigurationInput[] memory _inputs) public onlyRole(ADMIN_ROLE) {
    for (uint256 i; i < _inputs.length; ) {
      uint256 poolRewardWindowCount = _inputs[i].rewardWindows.length;
      pools[_inputs[i].collectionId].rewardCount = poolRewardWindowCount;
      pools[_inputs[i].collectionId].tax = _inputs[i].tax;

      uint256 lastTime;
      for (uint256 j; j < poolRewardWindowCount; ) {
        pools[_inputs[i].collectionId].rewardWindows[j] = _inputs[i].rewardWindows[j];

        if (j != 0 && _inputs[i].rewardWindows[j].startTime <= lastTime) {
          revert RewardWindowTimesMustIncrease();
        }
        lastTime = _inputs[i].rewardWindows[j].startTime;
        unchecked {
          j++;
        }
      }
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @dev getPoolConfiguration function to get the pool information and reward windows of a specific pool
   * @param collectionId : collection id of the pool
   * @return totalPoints : total points in the pool
   * @return rewardCount : number of reward windows in the pool
   * @return rewardWindows : array of RewardWindow structs
   */
  function getPoolConfiguration(
    uint256 collectionId
  ) public view returns (uint256 totalPoints, uint256 rewardCount, RewardWindow[] memory rewardWindows) {
    PoolData storage pool = pools[collectionId];
    totalPoints = pool.totalPoints;
    rewardCount = pool.rewardCount;

    rewardWindows = new RewardWindow[](rewardCount);

    for (uint256 i = 0; i < rewardCount; i++) {
      rewardWindows[i] = pool.rewardWindows[i];
    }
  }
}
