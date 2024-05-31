// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
  uint256 private tokenId;

  constructor() ERC721("GalileoNFT", "GNFT") {}

  function mint(address to) public returns (uint256) {
    tokenId++;
    _safeMint(to, tokenId);

    return tokenId;
  }

  function totalSupply() public view returns (uint256) {
    return tokenId;
  }
}
