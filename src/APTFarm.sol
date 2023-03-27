// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {EnumerableMap} from "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAPTFarm, IRewarder} from "./interfaces/IAPTFarm.sol";

/**
 * @notice Unlike MasterChefJoeV3, the APTFarm contract gives out a set number of joe tokens per seconds to every pool configured
 * These Joe tokens needs to be deposited on the contract first.
 */
contract APTFarm is Ownable2Step, ReentrancyGuard, IAPTFarm {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeERC20 for IERC20;

    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /**
     * @notice Whether if the given token already has a pool or not.
     */
    EnumerableMap.AddressToUintMap private _vaultsWithPools;

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
     * @notice Accounted balances of AP tokens in the farm.
     */
    mapping(IERC20 => uint256) public override apTokenBalances;

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

    function hasPool(address apToken) external view override returns (bool) {
        return _vaultsWithPools.contains(apToken);
    }

    function vaultPoolId(address apToken) external view override returns (uint256) {
        return _vaultsWithPools.get(apToken);
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
        uint256 newPid = _poolInfo.length;

        if (!_vaultsWithPools.set(address(apToken), newPid)) {
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

        emit Add(newPid, joePerSec, apToken, rewarder);
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

        if (overwrite) {
            pool.rewarder = rewarder;
            rewarder.onJoeReward(address(0), 0); // sanity check
        }

        _poolInfo[pid] = pool;

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
            uint256 apTokenSupply = apTokenBalances[pool.apToken];
            _refreshPoolState(pool, apTokenSupply);
        }

        pendingJoe = (userInfoCached.amount * pool.accJoePerShare) / ACC_TOKEN_PRECISION - userInfoCached.rewardDebt
            + userInfoCached.unpaidRewards;

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

        (uint256 userAmountBefore, uint256 userRewardDebt, uint256 userUnpaidRewards) =
            (user.amount, user.rewardDebt, user.unpaidRewards);

        uint256 balanceBefore = pool.apToken.balanceOf(address(this));
        pool.apToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = pool.apToken.balanceOf(address(this)) - balanceBefore;

        uint256 userAmount = userAmountBefore + receivedAmount;

        user.rewardDebt = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;
        user.amount = userAmount;
        apTokenBalances[pool.apToken] += receivedAmount;

        if (userAmountBefore > 0 || userUnpaidRewards > 0) {
            user.unpaidRewards = _harvest(userAmountBefore, userRewardDebt, userUnpaidRewards, pid, pool.accJoePerShare);
        }

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

        (uint256 userAmountBefore, uint256 userRewardDebt, uint256 userUnpaidRewards) =
            (user.amount, user.rewardDebt, user.unpaidRewards);

        if (userAmountBefore < amount) {
            revert APTFarm__InsufficientDeposit(userAmountBefore, amount);
        }

        uint256 userAmount = userAmountBefore - amount;
        user.rewardDebt = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;
        user.amount = userAmount;
        apTokenBalances[pool.apToken] -= amount;

        if (userAmountBefore > 0 || userUnpaidRewards > 0) {
            user.unpaidRewards = _harvest(userAmountBefore, userRewardDebt, userUnpaidRewards, pid, pool.accJoePerShare);
        }

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
        apTokenBalances[pool.apToken] -= amount;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        pool.apToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Harvest rewards from the APTFarm for all the given pools.
     * @param pids The indices of the pools to harvest from.
     */
    function harvestRewards(uint256[] calldata pids) external override nonReentrant {
        uint256 length = pids.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 pid = pids[i];

            PoolInfo memory pool = _updatePool(pid);
            UserInfo storage user = _userInfo[pid][msg.sender];

            (uint256 userAmount, uint256 userRewardDebt, uint256 userUnpaidRewards) =
                (user.amount, user.rewardDebt, user.unpaidRewards);

            user.rewardDebt = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;

            if (userAmount > 0 || userUnpaidRewards > 0) {
                user.unpaidRewards = _harvest(userAmount, userRewardDebt, userUnpaidRewards, pid, pool.accJoePerShare);
            }

            IRewarder rewarder = pool.rewarder;
            if (address(rewarder) != address(0)) {
                rewarder.onJoeReward(msg.sender, userAmount);
            }
        }

        emit BatchHarvest(msg.sender, pids);
    }

    /**
     * @notice Allows owner to withdraw any tokens that have been sent to the APTFarm by mistake.
     * @param token The address of the AP token to skim.
     * @param to The address to send the AP token to.
     */
    function skim(IERC20 token, address to) external override onlyOwner {
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 totalDeposits = apTokenBalances[token];

        if (contractBalance > totalDeposits) {
            uint256 amount = contractBalance - totalDeposits;
            token.safeTransfer(to, amount);
            emit Skim(address(token), to, amount);
        }
    }

    /**
     * @dev Get the new pool state if time passed since last update.
     * @dev View function that needs to be commited if effectively updating the pool.
     * @param pool The pool to update.
     * @param apTokenSupply The total amount of APT tokens in the pool.
     */
    function _refreshPoolState(PoolInfo memory pool, uint256 apTokenSupply) internal view {
        if (apTokenSupply > 0) {
            uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;
            uint256 joeReward = secondsElapsed * pool.joePerSec;
            pool.accJoePerShare = pool.accJoePerShare + (joeReward * ACC_TOKEN_PRECISION) / apTokenSupply;
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
            uint256 apTokenSupply = apTokenBalances[pool.apToken];

            _refreshPoolState(pool, apTokenSupply);
            _poolInfo[pid] = pool;

            emit UpdatePool(pid, pool.lastRewardTimestamp, apTokenSupply, pool.accJoePerShare);
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
    function _harvest(
        uint256 userAmount,
        uint256 userRewardDebt,
        uint256 userUnpaidRewards,
        uint256 pid,
        uint256 poolAccJoePerShare
    ) internal returns (uint256) {
        uint256 pending = (userAmount * poolAccJoePerShare) / ACC_TOKEN_PRECISION - userRewardDebt + userUnpaidRewards;

        uint256 contractBalance = joe.balanceOf(address(this));
        if (contractBalance < pending) {
            userUnpaidRewards = pending - contractBalance;
            pending = contractBalance;
        } else {
            userUnpaidRewards = 0;
        }

        joe.safeTransfer(msg.sender, pending);

        emit Harvest(msg.sender, pid, pending, userUnpaidRewards);

        return userUnpaidRewards;
    }
}
