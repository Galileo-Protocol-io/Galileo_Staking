// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

error UninitilizedCollection(address collectionAddress);

contract Citizen {
  // Mapping to store citizen ID associated with a specific token ID within a collection
  mapping(address => mapping(uint256 => uint256)) private tokenCitizen;

  // Mapping to track whether a collection address is configured for a citizen ID
  mapping(uint256 => mapping(address => bool)) private citizenNFTAddress;

  // Event emitted when NFTs are configured for a citizen
  event CitizenSet(uint256[] indexed tokenIds, uint256 indexed citizen);

  // Event emitted when a collection address is configured for a citizen
  event SetCollection(uint256 citizen, address indexed collectionAddress);

  // Modifier to ensure a collection is configured for a citizen before function execution
  modifier collectionConfigured(uint256 citizen, address _collectionAddress) {
    if (!citizenNFTAddress[citizen][_collectionAddress]) revert UninitilizedCollection(_collectionAddress);
    _;
  }

  /**
   * @dev Function to configure ownership of multiple NFTs for a citizen within a collection (internal for restricted access)
   *
   * @param collectionAddress The address of the ERC721 contract.
   * @param tokenIds The array of token ids
   * @param citizen The id of the ERC721
   */
  function configureNFTsWithTokenIds(address collectionAddress, uint256[] calldata tokenIds, uint256 citizen) internal {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      tokenCitizen[collectionAddress][tokenIds[i]] = citizen;
      setCollection(citizen, collectionAddress);
    }
    emit CitizenSet(tokenIds, citizen);
  }

  /**
   * @dev Function to mark a collection address as configured for a citizen (internal for restricted access)
   *
   * @param citizen The id of the ERC721
   * @param collectionAddress The address of the ERC721 contract.
   */
  function setCollection(uint256 citizen, address collectionAddress) internal {
    citizenNFTAddress[citizen][collectionAddress] = true;
    emit SetCollection(citizen, collectionAddress);
  }

  /**
   * @dev Function to retrieve the citizen ID associated with a token ID within a collection (publicly viewable)
   *
   * @param tokenId The token id of ERC721
   * @param collectionAddress The address of the ERC721 contract.
   */
  function getCitizen(uint256 tokenId, address collectionAddress) public view returns (uint256) {
    // Double-check collection configuration (potentially redundant with modifier)
    if (!citizenNFTAddress[tokenCitizen[collectionAddress][tokenId]][collectionAddress])
      revert UninitilizedCollection(collectionAddress);
    return tokenCitizen[collectionAddress][tokenId];
  }
}
