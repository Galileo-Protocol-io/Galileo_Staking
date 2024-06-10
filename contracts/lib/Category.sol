// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Category {
  mapping(address => mapping(uint256 => uint256)) private tokenCategory;
  mapping(uint256 => mapping(address => bool)) private categoryNFTAddress;

  event CategorySet(uint256[] indexed tokenId, uint256 indexed category);
  event SetCollection(uint256 category, address indexed collectionAddress);

  modifier collectionConfigured(uint256 category, address _collectionAddress) {
    require(categoryNFTAddress[category][_collectionAddress], "Collection not configured");
    _;
  }

  function configureNFTsWithTokenIds(
    address collectionAddress,
    uint256[] calldata tokenIds,
    uint256 category
  ) internal {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      tokenCategory[collectionAddress][tokenIds[i]] = category;
      setCollection(category, collectionAddress);
    }
    emit CategorySet(tokenIds, category);
  }

  function setCollection(uint256 categories, address collectionAddress) internal {
    categoryNFTAddress[categories][collectionAddress] = true;
    emit SetCollection(categories, collectionAddress);
  }

  function getCategory(uint256 tokenId, address collectionAddress) public view returns (uint256) {
    require(categoryNFTAddress[tokenCategory[collectionAddress][tokenId]][collectionAddress], "Invalid address");
    return tokenCategory[collectionAddress][tokenId];
  }
}
