// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./ProjectOwnership.sol";

abstract contract ProjectOwnable {
    modifier onlyProject() {
        require(
            ownership.owner() == msg.sender,
            "ProjectOwnership: Caller is not the project owner."
        );
        _;
    }

    // Not changeable
    ProjectOwnership private ownership;

    /// @param _ownership Clarifies ownership of this contract
    constructor(ProjectOwnership _ownership) {
        ownership = _ownership;
    }
}
