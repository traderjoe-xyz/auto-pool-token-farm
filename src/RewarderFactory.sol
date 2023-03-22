// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ImmutableClone} from "joe-v2/libraries/ImmutableClone.sol";

import {SimpleRewarderPerSec, ISimpleRewarderPerSec} from "./SimpleRewarderPerSec.sol";
import {IRewarderFactory} from "./interfaces/IRewarderFactory.sol";
import {IAPTFarm} from "./interfaces/IAPTFarm.sol";

contract RewarderFactory is IRewarderFactory {
    address public immutable override simpleRewarderImplementation;
    IAPTFarm public immutable override aptFarm;

    uint256 private _nounce;

    constructor(IAPTFarm _aptFarm) {
        if (!Address.isContract(address(_aptFarm))) {
            revert RewarderFactory__InvalidAddress();
        }

        simpleRewarderImplementation = address(new SimpleRewarderPerSec());
        aptFarm = _aptFarm;
    }

    function createRewarder(IERC20 rewardToken, IERC20 apToken, uint256 tokenPerSec, bool isNative)
        external
        override
        returns (SimpleRewarderPerSec rewarder)
    {
        if (!Address.isContract(address(rewardToken)) || !Address.isContract(address(apToken))) {
            revert RewarderFactory__InvalidAddress();
        }

        address rewarderAddress = ImmutableClone.cloneDeterministic(
            simpleRewarderImplementation,
            abi.encodePacked(rewardToken, apToken, aptFarm, isNative),
            keccak256(abi.encode(_nounce++))
        );

        rewarder = SimpleRewarderPerSec(payable(rewarderAddress));

        rewarder.initialize(tokenPerSec, msg.sender);

        emit RewarderCreated(rewarderAddress, address(rewardToken), address(apToken), isNative, msg.sender);
    }
}
