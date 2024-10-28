// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GalileoSoulBoundToken is ERC721, ERC721Burnable, AccessControl, Ownable {
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  uint256 private tokensCount;
  string private _baseTokenURI;

  event SetBaseURI(string indexed baseTokenURI);

  constructor(string memory name, string memory symbol, string memory baseTokenURI) ERC721(name, symbol) Ownable(_msgSender()) {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(ADMIN_ROLE, _msgSender());
    _baseTokenURI = baseTokenURI;
  }

  function issue(address to, uint256 tokenId) external onlyRole(ADMIN_ROLE) {
    tokensCount++;
    _safeMint(to, tokenId);
  }

  // Override the _baseURI function to return the base URI
  function _baseURI() internal view override returns (string memory) {
    return _baseTokenURI;
  }

  // Function to set a new base URI
  function setBaseURI(string memory baseTokenURI) external onlyOwner {
    _baseTokenURI = baseTokenURI;
    emit SetBaseURI(baseTokenURI);
  }

  function burn(uint256 _tokenId) public override onlyRole(ADMIN_ROLE) {
    tokensCount--;
    super._burn(_tokenId);
  }

  function totalSupply() public view returns (uint256) {
    return tokensCount;
  }

  // Override the _transfer function to prevent transfers
  function transferFrom(address from, address to, uint256 tokenId) public virtual override {
    revert("SoulBoundToken: transfer not allowed");
  }

  // Override the approve function to prevent approvals
  function approve(address to, uint256 tokenId) public virtual override {
    revert("SoulBoundToken: approval not allowed");
  }

  // Override the setApprovalForAll function to prevent approvals for all
  function setApprovalForAll(address operator, bool approved) public virtual override {
    revert("SoulBoundToken: set approval for all not allowed");
  }

  // The following functions are overrides required by Solidity.

  function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
