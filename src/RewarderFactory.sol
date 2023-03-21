// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {SimpleRewarderPerSec, ISimpleRewarderPerSec} from "./SimpleRewarderPerSec.sol";
import {IRewarderFactory} from "./interfaces/IRewarderFactory.sol";
import {IAPTFarm} from "./interfaces/IAPTFarm.sol";

contract RewarderFactory is IRewarderFactory {
    address public immutable override simpleRewarderImplementation;
    IAPTFarm public immutable override aptFarm;

    event RewarderCreated(
        address indexed rewarder, address indexed rewardToken, address indexed apToken, bool isNative
    );

    constructor(IAPTFarm _aptFarm) {
        simpleRewarderImplementation = address(new SimpleRewarderPerSec());
        aptFarm = _aptFarm;
    }

    function createRewarder(IERC20 rewardToken, IERC20 apToken, uint256 tokenPerSec, bool isNative)
        external
        override
        returns (SimpleRewarderPerSec rewarder)
    {
        address rewarderAddress = Clones.cloneDeterministic(
            simpleRewarderImplementation,
            keccak256(abi.encodePacked(rewardToken, apToken, tokenPerSec, aptFarm, isNative))
        );

        rewarder = SimpleRewarderPerSec(payable(rewarderAddress));

        rewarder.initialize(rewardToken, apToken, tokenPerSec, aptFarm, isNative, msg.sender);

        emit RewarderCreated(rewarderAddress, address(rewardToken), address(apToken), isNative);
    }
}
