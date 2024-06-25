// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
  uint256 private totalMintedTokens;

  constructor() ERC721("GalileoNFT", "GNFT") {}

  function mint(address to, uint256 _tokenId) public returns (uint256) {
    totalMintedTokens++;
    _safeMint(to, _tokenId);

    return _tokenId;
  }

  function totalSupply() public view returns (uint256) {
    return totalMintedTokens;
  }
}
