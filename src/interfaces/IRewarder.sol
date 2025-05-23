// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onJoeReward(address user, uint256 newLpAmount, uint256 aptSupply) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}
