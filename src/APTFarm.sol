// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewarder {
    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}

/// @notice The (older) MasterChefJoeV2 contract gives out a constant number of JOE tokens per block.
/// It is the only address with minting rights for JOE.
/// The idea for this MasterChefJoeV3 (MCJV3) contract is therefore to be the owner of a dummy token
/// that is deposited into the MasterChefJoeV2 (MCJV2) contract.
/// The allocation point for this pool on MCJV3 is the total allocation point for all pools that receive double incentives.
contract APTFarm is Ownable2Step, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    error APTFarm__InsufficientBalance(uint256 contractBalance, uint256 amountNeeded);

    /// @notice Info of each MCJV3 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of JOE entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    /// @notice Info of each MCJV3 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of JOE to distribute per block.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 accJoePerShare;
        uint256 lastRewardTimestamp;
        uint256 joePerSec;
        IRewarder rewarder;
    }

    /// @notice Address of JOE contract.
    IERC20 public immutable JOE;
    /// @notice Info of each MCJV3 pool.
    PoolInfo[] private _poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) private _userInfo;

    uint256 private constant ACC_TOKEN_PRECISION = 1e18;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Init();

    /// @param _joe The JOE token contract address.
    constructor(IERC20 _joe) {
        JOE = _joe;
    }

    /// @notice Returns the number of MCJV3 pools.
    function poolLength() external view returns (uint256 pools) {
        pools = _poolInfo.length;
    }

    function poolInfo(uint256 index) external view returns (PoolInfo memory pool) {
        pool = _poolInfo[index];
    }

    function userInfo(uint256 index, address user) external view returns (UserInfo memory info) {
        info = _userInfo[index][user];
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param joePerSec AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint256 joePerSec, IERC20 _lpToken, IRewarder _rewarder) external onlyOwner {
        require(!lpTokens.contains(address(_lpToken)), "add: LP already added");
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
        lpTokens.add(address(_lpToken));
        emit Add(_poolInfo.length - 1, joePerSec, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's JOE allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `_poolInfo`.
    /// @param joePerSec New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(uint256 _pid, uint256 joePerSec, IRewarder _rewarder, bool overwrite) external onlyOwner {
        updatePool(_pid);

        PoolInfo memory pool = _poolInfo[_pid];
        pool.joePerSec = joePerSec;
        if (overwrite) {
            _rewarder.onJoeReward(address(0), 0); // sanity check
            pool.rewarder = _rewarder;
        }
        _poolInfo[_pid] = pool;
        emit Set(_pid, joePerSec, overwrite ? _rewarder : pool.rewarder, overwrite);
    }

    /// @notice View function to see pending JOE on frontend.
    /// @param _pid The index of the pool. See `_poolInfo`.
    /// @param _user Address of user.
    /// @return pendingJoe JOE reward for a given user.
    //          bonusTokenAddress The address of the bonus reward.
    //          bonusTokenSymbol The symbol of the bonus token.
    //          pendingBonusToken The amount of bonus rewards pending.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo memory pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][_user];
        uint256 accJoePerShare = pool.accJoePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;
            uint256 joeReward = secondsElapsed * pool.joePerSec;
            accJoePerShare = accJoePerShare + (joeReward * ACC_TOKEN_PRECISION) / lpSupply;
        }
        pendingJoe = (user.amount * accJoePerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20Metadata(address(pool.rewarder.rewardToken())).symbol();
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `_poolInfo`.
    function updatePool(uint256 pid) public {
        PoolInfo memory pool = _poolInfo[pid];
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;
                uint256 joeReward = secondsElapsed * pool.joePerSec;
                pool.accJoePerShare = pool.accJoePerShare + (joeReward * ACC_TOKEN_PRECISION) / lpSupply;
            }
            pool.lastRewardTimestamp = block.timestamp;
            _poolInfo[pid] = pool;
            emit UpdatePool(pid, pool.lastRewardTimestamp, lpSupply, pool.accJoePerShare);
        }
    }

    /// @notice Deposit LP tokens to MCJV3 for JOE allocation.
    /// @param pid The index of the pool. See `_poolInfo`.
    /// @param amount LP token amount to deposit.
    function deposit(uint256 pid, uint256 amount) external nonReentrant {
        // harvestFromMasterChef();
        updatePool(pid);
        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage user = _userInfo[pid][msg.sender];

        if (user.amount > 0) {
            // Harvest JOE
            uint256 pending = (user.amount * pool.accJoePerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;
            JOE.safeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, pid, pending);
        }

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)) - balanceBefore;

        // Effects
        user.amount = user.amount + receivedAmount;
        user.rewardDebt = (user.amount * pool.accJoePerShare) / ACC_TOKEN_PRECISION;

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, user.amount);
        }

        emit Deposit(msg.sender, pid, receivedAmount);
    }

    /// @notice Withdraw LP tokens from MCJV3.
    /// @param pid The index of the pool. See `_poolInfo`.
    /// @param amount LP token amount to withdraw.
    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        updatePool(pid);

        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage user = _userInfo[pid][msg.sender];

        if (user.amount < amount) {
            revert APTFarm__InsufficientBalance(user.amount, amount);
        }

        if (user.amount > 0) {
            // Harvest JOE
            uint256 contractBalance = JOE.balanceOf(address(this));
            if (contractBalance < amount) {
                revert APTFarm__InsufficientBalance(contractBalance, amount);
            }
            uint256 pending = (user.amount * pool.accJoePerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;
            JOE.safeTransfer(msg.sender, pending);

            emit Harvest(msg.sender, pid, pending);
        }

        // Effects
        user.amount = user.amount - amount;
        user.rewardDebt = user.amount * (pool.accJoePerShare) / (ACC_TOKEN_PRECISION);

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, pid, amount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `_poolInfo`.
    function emergencyWithdraw(uint256 pid) external nonReentrant {
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
}
