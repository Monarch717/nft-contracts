// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../ownership/ProjectOwnable.sol";

abstract contract Subscribable is ProjectOwnable {
    Subscriber[] subscribers;
    mapping(Subscriber => bool) subscriberExist;

    constructor(ProjectOwnership _ownership) ProjectOwnable(_ownership) {}

    function addSubscriber(Subscriber sub) external onlyProject {
        require(
            subscriberExist[sub] == false,
            "StakingSubscriber can't subscribe twice"
        );
        subscribers.push(sub);
        subscriberExist[sub] = true;
    }

    function removeSubscriber(Subscriber sub) external onlyProject {
        require(
            subscriberExist[sub] == true,
            "StakingSubscriber must be subscriber of this contract."
        );
        for (uint256 i = 0; i < subscribers.length; i++) {
            if (subscribers[i] == sub) {
                delete subscribers[i];
            }
        }
        subscriberExist[sub] = false;
    }
}

abstract contract Subscriber {}
