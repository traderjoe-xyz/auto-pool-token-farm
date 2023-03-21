// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAPTFarm} from "./IAPTFarm.sol";
import {SimpleRewarderPerSec} from "../SimpleRewarderPerSec.sol";

interface IRewarderFactory {
    error RewarderFactory__InvalidAddress();

    event RewarderCreated(
        address indexed rewarder, address indexed rewardToken, address indexed apToken, bool isNative, address owner
    );

    function simpleRewarderImplementation() external view returns (address);

    function aptFarm() external view returns (IAPTFarm);

    function createRewarder(IERC20 rewardToken, IERC20 apToken, uint256 tokenPerSec, bool isNative)
        external
        returns (SimpleRewarderPerSec rewarder);
}
