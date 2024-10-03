// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library GalileoStakingErrors {
  // ═══════════════════════ ERORRS ════════════════════════

  // Error indicating an invalid address for a collection
  error InvalidAddress();

  // Error indicating an input is invalid
  error InvalidInput();

  // Error indicating that a collection has not been initialized
  error CollectionUninitialized();

  // Error indicating that a pool associated with a collection has not been initialized
  error PoolUninitialized(address collectionAddress);

  // Error indicating an invalid count of tokens
  error InvalidTokensCount(uint256 maxLeox);

  // Error indicating an invalid time
  error InvalidTime();

  // Error indicating that stake time is not completed yet
  error UnstakeBeforeLockPeriod(uint256 lockPeriodEnd);

  // Error indicating an invalid reward rate
  error InvalidRewardRate();

  // Error indicating an invalid token ID
  error InvalidTokenId();

  // Error indicating that a token is already staked
  error TokenAlreadyStaked();

  // Error indicating that the amount is zero
  error InvalidAmount(uint256 amount);

  // Error indicating that the owner is incorrect
  error IncorrectOwner();

  // Error indicating that the staker has not enough LEOX tokens
  error InsufficientLEOXTokens(address staker);

  // Error indicating that a token ID is not staked
  error TokenNotStaked();

  // Error indicating that the citizen index is invalid
  error InvalidCitizenIndex();

  // Error indicating that signature is invalid
  error InvalidSignature();
}
