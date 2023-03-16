// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IRewarder} from "./IRewarder.sol";

interface ISimpleRewarderPerSec is IRewarder {
    error SimpleRewarderPerSec__OnlyAPTFarm();
    error SimpleRewarderPerSec__InvalidAddress();
    error SimpleRewarderPerSec__TransferFailed();
    error SimpleRewarderPerSec__InvalidTokenPerSec();

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Info of each APTFarm user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each APTFarm poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }
}
