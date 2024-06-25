//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IGALILEOSOULBOUNDTOKEN {
  function issue(address to) external;

  function burn(uint256 _tokenId) external;
}
