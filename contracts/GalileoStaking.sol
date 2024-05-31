// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/Category.sol";

error UnconfiguredCollection(uint256 collectionId);
error UnconfiguredPool(uint256 collectionId);
error RewardWindowTimesMustIncrease();

contract GalileoStaking is Category, AccessControl, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  address public LEOX;
  uint256 private nextCollectionId;

  struct StakedCollectionInfo {
    uint256 collectionId;
    uint256 timelockEndTime;
    uint256 points;
  }

  struct StakedTokenInfo {
    uint256 amount;
    uint256 timelockEndTime;
    uint256 points;
  }

  struct LeoxInfo {
    uint256 category;
    uint256[] tokenIds;
    uint256 maxLeox;
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
    uint256 daoTax;
    uint256 rewardCount;
    mapping(uint256 => RewardWindow) rewardWindows;
  }

  struct PoolConfigurationInput {
    uint256 collectionId;
    RewardWindow[] rewardWindows;
  }

  mapping(uint256 => PoolData) private pools;
  mapping(uint256 => CollectionInfo) private collections;
  mapping(address => mapping(uint256 => mapping(uint256 => StakedTokenInfo))) private stakedTokenInfo;
  mapping(address => mapping(uint256 => mapping(uint256 => StakedCollectionInfo))) private stakedCollectionInfo;

  event ConfigureCollection(address collectionAddress, uint256 collectionId);
  event StakeNFT(uint256 collectionId, uint256 tokenId, uint256 timelock, uint256 points);
  event StakeLEOX(uint256 collectionId, uint256 tokens, uint256 timelock, uint256 points);

  /**
   * @dev construstor function
   * @param _leox : LEOX ERC20 token address
   */

  constructor(address _leox) {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(ADMIN_ROLE, _msgSender());
    LEOX = _leox;
  }

  /**
   * @dev stake function
   * @param collectionId : collection Id of the pNFT collection
   * @param tokenId : token id of the collection
   * @param tokens : amount of ERC20 tokens
   * @param timeLock : stake time lock
   */

  function stake(uint256 collectionId, uint256 tokenId, uint256 tokens, uint256 timeLock) public nonReentrant {
    address collectionAddress = getCollectionAddressById(collectionId);

    if (collectionAddress == address(0)) {
      revert UnconfiguredCollection(collectionId);
    }

    _stakeNFT(collectionAddress, collectionId, tokenId, timeLock);
    _stakeLEOX(collectionId, tokenId, tokens, timeLock);
  }

  /**
   * @dev _stakeNFT internal function to stake NFTs
   * @param collectionAddress : collection address of the NFT collection
   * @param collectionId : collection Id of the pNFT collection
   * @param tokenId : token id of the collection
   * @param timeLock : stake time lock
   */

  function _stakeNFT(address collectionAddress, uint256 collectionId, uint256 tokenId, uint256 timeLock) internal {
    stakedCollectionInfo[_msgSender()][collectionId][tokenId] = StakedCollectionInfo(collectionId, timeLock, 20);
    IERC721(collectionAddress).transferFrom(_msgSender(), address(this), tokenId);

    emit StakeNFT(collectionId, tokenId, timeLock, 20);
  }

  /**
   * @dev _stakeLEOX internal function to stake LEOX tokens
   * @param collectionId : collection Id of the pNFT collection
   * @param tokenId : token id of the collection
   * @param tokens : amount of ERC20 tokens
   * @param timeLock : stake time lock
   */

  function _stakeLEOX(uint256 collectionId, uint256 tokenId, uint256 tokens, uint256 timeLock) internal {
    stakedTokenInfo[_msgSender()][collectionId][tokenId] = StakedTokenInfo(tokens, timeLock, 20);
    IERC20(LEOX).transferFrom(_msgSender(), address(this), tokens);

    emit StakeLEOX(collectionId, tokens, timeLock, 20);
  }

  /**
   * @dev configureCollection function to configure collection address
   * @param collectionAddress : collection address of NFT address
   * @param _LeoxInfo : token id of the collection
   */

  function configureCollection(address collectionAddress, LeoxInfo[] calldata _LeoxInfo) public onlyRole(ADMIN_ROLE) {
    string memory collectionName = ERC721(collectionAddress).name();
    (address _collectionAddress, string memory _collectionName, uint256 _collectionId) = getCollectionDetailsByAddress(
      collectionAddress
    );

    if (
      collectionAddress != collectionAddress &&
      keccak256(abi.encodePacked(_collectionName)) != keccak256(abi.encodePacked(collectionName))
    ) {
      nextCollectionId++;
    }
    for (uint256 i = 0; i < _LeoxInfo.length; i++) {
      collections[nextCollectionId].maxLeoxPerCategory[_LeoxInfo[i].category] = _LeoxInfo[i].maxLeox;
      configureNFTsWithTokenIds(collectionAddress, _LeoxInfo[i].tokenIds, _LeoxInfo[i].category);
    }
    collections[nextCollectionId].collectionAddress = collectionAddress;
    collections[nextCollectionId].collectionName = collectionName;
    emit ConfigureCollection(collectionAddress, nextCollectionId);
  }

  /**
   * @dev getCollectionDetailsByAddress function to get data against collection address
   * @param collectionAddress : collection address of NFT address
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
   */
  function getMaxLeoxPerCategory(address collectionAddress, uint256 category) public view returns (uint256 maxLeox) {
    uint256 collectionId = _getCollectionByAddress(collectionAddress);
    CollectionInfo storage collection = collections[collectionId];
    return collection.maxLeoxPerCategory[category];
  }

  /**
   * @dev _getCollectionByAddress internal function to configure collection address
   * @param collectionAddress : collection address of NFT address
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
   */
  function getCollectionAddressById(uint256 collectionId) public view returns (address) {
    if (collectionId <= nextCollectionId) {
      return collections[collectionId].collectionAddress;
    }
    return address(0);
  }

  /**
   * @dev getStakedCollectionInfo function to get information of staked collection
   * @param collectionId : collection id
   * @param tokenId : tokenId of the collection
   */
  function getStakedCollectionInfo(
    uint256 collectionId,
    uint256 tokenId
  ) public view returns (StakedCollectionInfo memory) {
    return stakedCollectionInfo[_msgSender()][collectionId][tokenId];
  }

  /**
   * @dev getStakedTokenInfo function to get information of staked LEOX
   * @param collectionId : collection id
   * @param tokenId : tokenId of the collection
   */
  function getStakedTokenInfo(uint256 collectionId, uint256 tokenId) public view returns (StakedTokenInfo memory) {
    return stakedTokenInfo[_msgSender()][collectionId][tokenId];
  }

  /**
   * @dev configurePool function to get information of staked LEOX
   * @param _inputs : configure the pool for staking
   */
  function configurePool(PoolConfigurationInput[] memory _inputs) public onlyRole(ADMIN_ROLE) {
    for (uint256 i; i < _inputs.length; ) {
      uint256 poolRewardWindowCount = _inputs[i].rewardWindows.length;
      pools[_inputs[i].collectionId].rewardCount = poolRewardWindowCount;

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
}
