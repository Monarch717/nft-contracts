// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../util/ownership/ProjectOwnable.sol";

contract Whitelist is ProjectOwnable {
    mapping(address => bool) private isWhitelisted;

    constructor(ProjectOwnership _ownership) ProjectOwnable(_ownership) {}

    function setWhitelistStatus(address anyAddress, bool value)
        external
        onlyProject
    {
        isWhitelisted[anyAddress] = value;
    }

    function setWhitelistStatusBatch(address[] memory array, bool value)
    external
        onlyProject
    {
        for (uint256 i = 0; i < array.length; i++) {
            isWhitelisted[array[i]] = value;
        }
    }

    function getWhitelistStatus(address anyAddress) external view returns (bool) {
        return isWhitelisted[anyAddress];
    }
}