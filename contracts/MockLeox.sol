// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MockLeox is ERC20, AccessControl {
  // Define a constant for the admin role by hashing the string "ADMIN_ROLE".
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  /**
   * @dev Constructor that initializes the ERC20 token with the name "LEOX Token" and symbol "LEOX".
   * It also grants the deployer both the default admin role and the admin role for additional privileges.
   * Additionally, it mints 10 billion LEOX tokens to the deployer's address.
   */
  constructor() ERC20("LEOX Token", "LEOX") {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Grant the deployer the default admin role.
    _grantRole(ADMIN_ROLE, msg.sender); // Grant the deployer the admin role to manage minting.
    _mint(_msgSender(), 10000000000 * 10 ** 18); // Mint 10 billion LEOX tokens (with 18 decimals) to the deployer.
  }

  /**
   * @dev Allows accounts with the admin role to mint new LEOX tokens.
   * @param to The address to which the newly minted tokens will be sent.
   * @param amount The number of tokens to be minted (with 18 decimals).
   *
   * Only addresses with the `ADMIN_ROLE` are allowed to call this function.
   */
  function mint(address to, uint256 amount) public onlyRole(ADMIN_ROLE) {
    _mint(to, amount); // Mint the specified amount of tokens to the `to` address.
  }
}
