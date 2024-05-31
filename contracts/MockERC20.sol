// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MockERC20 is ERC20, AccessControl {
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  constructor() ERC20("Mock", "MOCK") {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _mint(_msgSender(), 10000000000 * 10 ** 18);
  }

  function mint(address to, uint256 amount) public onlyRole(ADMIN_ROLE) {
    _mint(to, amount);
  }
}
