// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IRewarder} from "./IRewarder.sol";

interface IAPTFarm {
    error APTFarm__InsufficientDeposit(uint256 deposit, uint256 amountWithdrawn);
    error APTFarm__InsufficientRewardBalance(uint256 contractBalance, uint256 amountNeeded);

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardsWithdrawn(address indexed to, uint256 amount);

    /**
     * @notice Info of each APTFarm user.
     * `amount` LP token amount the user has provided.
     * `rewardDebt` The amount of JOE entitled to the user.
     */
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    /**
     * @notice Info of each APTFarm pool.
     * `lpToken` Address of the LP token.
     * `accJoePerShare` Accumulated JOE per share.
     * `lastRewardTimestamp` Last timestamp that JOE distribution occurs.
     * `joePerSec` JOE tokens distributed per second.
     * `rewarder` Address of the rewarder contract that handles the distribution of bonus tokens.
     */
    struct PoolInfo {
        IERC20 lpToken;
        uint256 accJoePerShare;
        uint256 lastRewardTimestamp;
        uint256 joePerSec;
        IRewarder rewarder;
    }

    function joe() external view returns (IERC20 joe);

    function poolLength() external view returns (uint256 poolLength);

    function poolInfo(uint256 pid) external view returns (PoolInfo memory poolInfo);

    function userInfo(uint256 pid, address user) external view returns (UserInfo memory userInfo);

    function add(uint256 joePerSec, IERC20 lpToken, IRewarder rewarder) external;

    function set(uint256 pid, uint256 joePerSec, IRewarder rewarder, bool overwrite) external;

    function pendingTokens(uint256 pid, address user)
        external
        view
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        );

    function massUpdatePools(uint256[] calldata pids) external;

    function updatePool(uint256 pid) external;

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;

    function withdrawRewards(address to, uint256 amount) external;
}
