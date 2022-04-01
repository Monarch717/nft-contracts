// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestCoin is ERC20, Ownable {
    constructor() ERC20("TestCoin", "TC") {}

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}
