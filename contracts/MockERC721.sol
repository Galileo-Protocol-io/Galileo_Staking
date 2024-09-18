// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockNebula is ERC721, Ownable {
  // Variable to keep track of the next token ID to be minted.
  uint256 private _nextTokenId;

  // Base URI for the token metadata.
  string tokenUri;

  /**
   * @dev Constructor that initializes the contract by setting the base token URI and setting the contract owner.
   * @param _tokenUri The base URI for token metadata.
   */
  constructor(string memory _tokenUri) ERC721("MockNebula", "NBL") Ownable(_msgSender()) {
    tokenUri = _tokenUri; // Initialize the base URI for all tokens.
  }

  /**
   * @dev Internal function to return the base URI for the token metadata.
   * Overrides the _baseURI function in the ERC721 contract.
   * @return The base URI as a string.
   */
  function _baseURI() internal view override returns (string memory) {
    return tokenUri; // Return the base URI for the metadata.
  }

  /**
   * @dev Allows the contract owner to mint a new NFT to a specified address.
   * Only the owner of the contract can call this function.
   * @param to The address that will receive the newly minted NFT.
   */
  function mint(address to) public onlyOwner {
    uint256 tokenId = ++_nextTokenId; // Increment the token ID and assign it to the new token.
    _safeMint(to, tokenId); // Mint the token to the specified address with safety checks.
  }

  /**
   * @dev Returns the total supply of NFTs that have been minted.
   * @return The total number of minted NFTs as a uint256.
   */
  function totalSupply() public view returns (uint256) {
    return _nextTokenId; // Return the current total number of minted NFTs.
  }
}
