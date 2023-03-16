// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAPTFarm, IRewarder} from "./interfaces/IAPTFarm.sol";

/// @notice The (older) MasterChefJoeV2 contract gives out a constant number of joe tokens per block.
/// It is the only address with minting rights for joe.
/// The idea for this MasterChefJoeV3 (MCJV3) contract is therefore to be the owner of a dummy token
/// that is deposited into the MasterChefJoeV2 (MCJV2) contract.
/// The allocation point for this pool on MCJV3 is the total allocation point for all pools that receive double incentives.
contract APTFarm is Ownable2Step, ReentrancyGuard, IAPTFarm {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint256 private constant ACC_TOKEN_PRECISION = 1e18;

    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private _lpTokens;

    /// @notice Info of each MCJV3 pool.
    PoolInfo[] private _poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) private _userInfo;

    /// @notice Address of joe contract.
    IERC20 public immutable override joe;

    /// @param _joe The joe token contract address.
    constructor(IERC20 _joe) {
        joe = _joe;
    }

    /// @notice Returns the number of MCJV3 pools.
    function poolLength() external view override returns (uint256 pools) {
        pools = _poolInfo.length;
    }

    function poolInfo(uint256 index) external view override returns (PoolInfo memory pool) {
        pool = _poolInfo[index];
    }

    function userInfo(uint256 index, address user) external view override returns (UserInfo memory info) {
        info = _userInfo[index][user];
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param joePerSec AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint256 joePerSec, IERC20 _lpToken, IRewarder _rewarder) external override onlyOwner {
        require(!_lpTokens.contains(address(_lpToken)), "add: LP already added");
        // Sanity check to ensure _lpToken is an ERC20 token
        _lpToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(address(0), 0);
        }

        uint256 lastRewardTimestamp = block.timestamp;

        _poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                lastRewardTimestamp: lastRewardTimestamp,
                accJoePerShare: 0,
                joePerSec: joePerSec,
                rewarder: _rewarder
            })
        );

        _lpTokens.add(address(_lpToken));
        emit Add(_poolInfo.length - 1, joePerSec, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's joe allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `_poolInfo`.
    /// @param joePerSec New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(uint256 _pid, uint256 joePerSec, IRewarder _rewarder, bool overwrite) external override onlyOwner {
        _updatePool(_pid);

        PoolInfo storage pool = _poolInfo[_pid];
        pool.joePerSec = joePerSec;

        if (overwrite) {
            _rewarder.onJoeReward(address(0), 0); // sanity check
            pool.rewarder = _rewarder;
        }

        emit Set(_pid, joePerSec, overwrite ? _rewarder : pool.rewarder, overwrite);
    }

    /// @notice View function to see pending joe on frontend.
    /// @param _pid The index of the pool. See `_poolInfo`.
    /// @param _user Address of user.
    /// @return pendingJoe joe reward for a given user.
    //          bonusTokenAddress The address of the bonus reward.
    //          bonusTokenSymbol The symbol of the bonus token.
    //          pendingBonusToken The amount of bonus rewards pending.
    function pendingTokens(uint256 _pid, address _user)
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
        PoolInfo memory pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][_user];

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            pool = _getNewPoolState(pool);
        }

        pendingJoe = (user.amount * pool.accJoePerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;

        // If it's a double reward farm, we return info about the bonus token
        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            bonusTokenAddress = address(rewarder.rewardToken());
            bonusTokenSymbol = IERC20Metadata(bonusTokenAddress).symbol();
            pendingBonusToken = rewarder.pendingTokens(_user);
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external override {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            _updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `_poolInfo`.

    function updatePool(uint256 pid) external override {
        _updatePool(pid);
    }

    /// @notice Deposit LP tokens to MCJV3 for joe allocation.
    /// @param pid The index of the pool. See `_poolInfo`.
    /// @param amount LP token amount to deposit.
    function deposit(uint256 pid, uint256 amount) external override nonReentrant {
        _updatePool(pid);

        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 userAmount = user.amount;
        uint256 userRewardDebt = user.rewardDebt;

        if (userAmount > 0) {
            _harvest(userAmount, userRewardDebt, pid, pool.accJoePerShare);
            // Harvest joe
            // uint256 pending = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION - userRewardDebt;
            // joe.safeTransfer(msg.sender, pending);
            // emit Harvest(msg.sender, pid, pending);
        }

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)) - balanceBefore;

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

    /// @notice Withdraw LP tokens from MCJV3.
    /// @param pid The index of the pool. See `_poolInfo`.
    /// @param amount LP token amount to withdraw.
    function withdraw(uint256 pid, uint256 amount) external override nonReentrant {
        _updatePool(pid);

        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 userAmount = user.amount;
        uint256 userRewardDebt = user.rewardDebt;

        if (userAmount < amount) {
            revert APTFarm__InsufficientBalance(userAmount, amount);
        }

        if (userAmount > 0) {
            _harvest(userAmount, userRewardDebt, pid, pool.accJoePerShare);
        }

        userAmount = userAmount - amount; //@todo check test if commented
        userRewardDebt = (userAmount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;

        // Effects
        user.amount = userAmount;
        user.rewardDebt = userRewardDebt;

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, userAmount);
        }

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, pid, amount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `_poolInfo`.
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
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    function _getNewPoolState(PoolInfo memory pool) internal view returns (PoolInfo memory) {
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;
                uint256 joeReward = secondsElapsed * pool.joePerSec;
                pool.accJoePerShare = pool.accJoePerShare + (joeReward * ACC_TOKEN_PRECISION) / lpSupply;
            }
            pool.lastRewardTimestamp = block.timestamp;
        }

        return pool;
    }

    function _updatePool(uint256 pid) internal {
        PoolInfo memory pool = _poolInfo[pid];

        if (block.timestamp > pool.lastRewardTimestamp) {
            pool = _getNewPoolState(pool);
            _poolInfo[pid] = pool;

            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            emit UpdatePool(pid, pool.lastRewardTimestamp, lpSupply, pool.accJoePerShare);
        }
    }

    function _harvest(uint256 userAmount, uint256 userRewardDebt, uint256 pid, uint256 poolAccJoePerShare) internal {
        uint256 pending = (userAmount * poolAccJoePerShare) / ACC_TOKEN_PRECISION - userRewardDebt;

        uint256 contractBalance = joe.balanceOf(address(this));
        if (contractBalance < pending) {
            revert APTFarm__InsufficientBalance(contractBalance, pending);
        }
        joe.safeTransfer(msg.sender, pending);

        emit Harvest(msg.sender, pid, pending);
    }
}
