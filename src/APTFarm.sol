// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAPTFarm, IRewarder} from "./interfaces/IAPTFarm.sol";

/**
 * @notice Unlike MasterChefJoeV3, the APTFarm contract gives out a set number of joe tokens per seconds to every pool configured
 * These Joe tokens needs to be deposited on the contract first.
 */
contract APTFarm is Ownable2Step, ReentrancyGuard, IAPTFarm {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /**
     * @dev Set of all APT tokens that have been added as pools
     *
     */
    EnumerableSet.AddressSet private _apTokens;

    /**
     * @dev Info of each APTFarm pool.
     */
    PoolInfo[] private _poolInfo;

    /**
     * @dev Info of each user that stakes APT tokens.
     */
    mapping(uint256 => mapping(address => UserInfo)) private _userInfo;

    /**
     * @notice Address of the joe token.
     */
    IERC20 public immutable override joe;

    /**
     * @param _joe The joe token contract address.
     */
    constructor(IERC20 _joe) {
        joe = _joe;
    }

    /**
     * @notice Returns the number of APTFarm pools.
     */
    function poolLength() external view override returns (uint256 pools) {
        pools = _poolInfo.length;
    }

    /**
     * @notice Returns informations about the pool at the given index.
     * @param index The index of the pool.
     * @return pool The pool informations.
     */
    function poolInfo(uint256 index) external view override returns (PoolInfo memory pool) {
        pool = _poolInfo[index];
    }

    /**
     * @notice Returns informations about the user in the given pool.
     * @param index The index of the pool.
     * @param user The address of the user.
     * @return info The user informations.
     */
    function userInfo(uint256 index, address user) external view override returns (UserInfo memory info) {
        info = _userInfo[index][user];
    }

    /**
     * @notice Add a new APT to the pool set. Can only be called by the owner.
     * @param joePerSec Initial number of joe tokens per second streamed to the pool.
     * @param apToken Address of the APT ERC-20 token.
     * @param rewarder Address of the rewarder delegate.
     */
    function add(uint256 joePerSec, IERC20 apToken, IRewarder rewarder) external override onlyOwner {
        if (!_apTokens.add(address(apToken))) {
            revert APTFarm__TokenAlreadyHasPool(address(apToken));
        }

        _poolInfo.push(
            PoolInfo({
                apToken: apToken,
                lastRewardTimestamp: block.timestamp,
                accJoePerShare: 0,
                joePerSec: joePerSec,
                rewarder: rewarder
            })
        );

        // Sanity check to ensure apToken is an ERC20 token
        apToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(rewarder) != address(0)) {
            rewarder.onJoeReward(address(0), 0);
        }

        emit Add(_poolInfo.length - 1, joePerSec, apToken, rewarder);
    }

    /**
     * @notice Update the given pool's joe allocation point and `IRewarder` contract. Can only be called by the owner.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param joePerSec New joe per sec streamed to the pool.
     * @param rewarder Address of the rewarder delegate.
     * @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
     */
    function set(uint256 pid, uint256 joePerSec, IRewarder rewarder, bool overwrite) external override onlyOwner {
        PoolInfo memory pool = _updatePool(pid);
        pool.joePerSec = joePerSec;

        _poolInfo[pid] = pool;

        if (overwrite) {
            pool.rewarder = rewarder;
            rewarder.onJoeReward(address(0), 0); // sanity check
        }

        emit Set(pid, joePerSec, overwrite ? rewarder : pool.rewarder, overwrite);
    }

    /**
     * @notice View function to see pending joe on frontend.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param user Address of user.
     * @return pendingJoe joe reward for a given user.
     * @return bonusTokenAddress The address of the bonus reward.
     * @return bonusTokenSymbol The symbol of the bonus token.
     * @return pendingBonusToken The amount of bonus rewards pending.
     */
    function pendingTokens(uint256 pid, address user)
        external
        view
        override
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage userInfoCached = _userInfo[pid][user];

        if (block.timestamp > pool.lastRewardTimestamp) {
            _refreshPoolState(pool);
        }

        pendingJoe = (userInfoCached.amount * pool.accJoePerShare) / ACC_TOKEN_PRECISION - userInfoCached.rewardDebt;

        // If it's a double reward farm, we return info about the bonus token
        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            bonusTokenAddress = address(rewarder.rewardToken());
            bonusTokenSymbol = IERC20Metadata(bonusTokenAddress).symbol();
            pendingBonusToken = rewarder.pendingTokens(user);
        }
    }

    /**
     * @notice Deposit APT tokens to the APTFarm for joe allocation.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param amount APT token amount to deposit.
     */
    function deposit(uint256 pid, uint256 amount) external override nonReentrant {
        PoolInfo memory pool = _updatePool(pid);

        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 userAmount = user.amount;
        uint256 userRewardDebt = user.rewardDebt;

        if (userAmount > 0) {
            _harvest(userAmount, userRewardDebt, pid, pool.accJoePerShare);
        }

        uint256 balanceBefore = pool.apToken.balanceOf(address(this));
        pool.apToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = pool.apToken.balanceOf(address(this)) - balanceBefore;

        // Effects
        userAmount = userAmount + receivedAmount;
        userRewardDebt = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;

        user.amount = userAmount;
        user.rewardDebt = userRewardDebt;

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, userAmount);
        }

        emit Deposit(msg.sender, pid, receivedAmount);
    }

    /**
     * @notice Withdraw APT tokens from the APTFarm.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param amount APT token amount to withdraw.
     */
    function withdraw(uint256 pid, uint256 amount) external override nonReentrant {
        PoolInfo memory pool = _updatePool(pid);

        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 userAmount = user.amount;
        uint256 userRewardDebt = user.rewardDebt;

        if (userAmount < amount) {
            revert APTFarm__InsufficientDeposit(userAmount, amount);
        }

        if (userAmount > 0) {
            _harvest(userAmount, userRewardDebt, pid, pool.accJoePerShare);
        }

        userAmount = userAmount - amount;
        userRewardDebt = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;

        // Effects
        user.amount = userAmount;
        user.rewardDebt = userRewardDebt;

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, userAmount);
        }

        pool.apToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     * @param pid The index of the pool. See `_poolInfo`.
     */
    function emergencyWithdraw(uint256 pid) external override nonReentrant {
        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        pool.apToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Withdraw all rewards from the APTFarm.
     * @param to The address to send the rewards to.
     * @param amount The amount of rewards to withdraw. Put 0 to withdraw all rewards.
     */
    function withdrawRewards(address to, uint256 amount) external override onlyOwner {
        if (amount == 0) {
            amount = joe.balanceOf(address(this));
        }

        joe.safeTransfer(to, amount);

        emit RewardsWithdrawn(to, amount);
    }

    /**
     * @dev Get the new pool state if time passed since last update.
     * @dev View function that needs to be commited if effectively updating the pool.
     * @param pool The pool to update.
     */
    function _refreshPoolState(PoolInfo memory pool) internal view {
        uint256 lpSupply = pool.apToken.balanceOf(address(this));

        if (lpSupply > 0) {
            uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;
            uint256 joeReward = secondsElapsed * pool.joePerSec;
            pool.accJoePerShare = pool.accJoePerShare + (joeReward * ACC_TOKEN_PRECISION) / lpSupply;
        }

        pool.lastRewardTimestamp = block.timestamp;
    }

    /**
     * @dev Updates the pool's state if time passed since last update.
     * @dev Uses `_getNewPoolState` and commit the new pool state.
     * @param pid The index of the pool. See `_poolInfo`.
     */
    function _updatePool(uint256 pid) internal returns (PoolInfo memory) {
        PoolInfo memory pool = _poolInfo[pid];

        if (block.timestamp > pool.lastRewardTimestamp) {
            _refreshPoolState(pool);
            _poolInfo[pid] = pool;

            uint256 lpSupply = pool.apToken.balanceOf(address(this));
            emit UpdatePool(pid, pool.lastRewardTimestamp, lpSupply, pool.accJoePerShare);
        }

        return pool;
    }

    /**
     * @dev Harvests the pending JOE rewards for the given pool.
     * @param userAmount The amount of APT tokens staked by the user.
     * @param userRewardDebt The reward debt of the user.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param poolAccJoePerShare The accumulated JOE per share of the pool.
     */
    function _harvest(uint256 userAmount, uint256 userRewardDebt, uint256 pid, uint256 poolAccJoePerShare) internal {
        uint256 pending = (userAmount * poolAccJoePerShare) / ACC_TOKEN_PRECISION - userRewardDebt;

        uint256 contractBalance = joe.balanceOf(address(this));
        if (contractBalance < pending) {
            revert APTFarm__InsufficientRewardBalance(contractBalance, pending);
        }
        joe.safeTransfer(msg.sender, pending);

        emit Harvest(msg.sender, pid, pending);
    }
}
