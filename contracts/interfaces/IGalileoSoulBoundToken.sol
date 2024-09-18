// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IGALILEOSOULBOUNDTOKEN {
  /**
   * @dev Issues a new Soulbound token to the specified address.
   * @param to The address of the recipient to whom the Soulbound token will be issued.
   *
   * Soulbound tokens are typically non-transferable and tied to the recipient forever.
   */
  function issue(address to) external;

  /**
   * @dev Burns the specified Soulbound token, removing it from existence.
   * @param _tokenId The unique identifier of the Soulbound token to be burned.
   *
   * Once a token is burned, it is permanently removed from the contract and can no longer be used.
   */
  function burn(uint256 _tokenId) external;
}
