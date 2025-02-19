// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract PToken is ERC20, ERC20Burnable {
    constructor() ERC20("Payment Token", "PToken") {
        _mint(msg.sender, 100_000_000_000 * 10 ** 18);
    }
}
