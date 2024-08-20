// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

library GalileoStakingErrors {
  // ═══════════════════════ ERORRS ════════════════════════

  // Error indicating an invalid address for a collection
  error InvalidAddress(address collectionAddress);

  // Error indicating an input is invalid
  error InvalidInput();

  // Error indicating that a collection has not been initialized
  error CollectionUninitialized();

  // Error indicating that reward window times must be in increasing order
  error RewardWindowPercentMustIncrease();

  // Error indicating that a pool associated with a collection has not been initialized
  error PoolUninitialized(address collectionAddress);

  // Error indicating an invalid count of tokens
  error InvalidTokensCount(uint256 maxLeox);

  // Error indicating an invalid time
  error InvalidTime();

  // Error indicating an invalid token ID
  error InvalidTokenId();

  // Error indicating that a token is already staked
  error TokenAlreadyStaked();

  // Error indicating that a token id is not staked
  error TokenNotStaked();
}
