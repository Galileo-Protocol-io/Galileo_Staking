// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Nebula is ERC721 {
  uint256 private tokenId;

  constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

  function mint(address to) public returns (uint256) {
    tokenId++;
    _safeMint(to, tokenId);

    return tokenId;
  }

  function totalSupply() public view returns (uint256) {
    return tokenId;
  }
}
