// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Nebula is ERC721, Ownable {
  uint256 private _nextTokenId;
  string tokenUri;

  constructor(string memory _tokenUri) ERC721("Nebula", "NBL") Ownable(_msgSender()) {
    tokenUri = _tokenUri;
  }

  function _baseURI() internal view override returns (string memory) {
    return tokenUri;
  }

  function mint(address to) public onlyOwner {
    uint256 tokenId = ++_nextTokenId;
    _safeMint(to, tokenId);
  }

  function totalSupply() public view returns(uint256){
    return _nextTokenId;
  }
}
