// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {IAPTFarm} from "./interfaces/IAPTFarm.sol";
import {ISimpleRewarderPerSec} from "./interfaces/ISimpleRewarderPerSec.sol";

/**
 * This is a sample contract to be used in the APTFarm contract for partners to reward
 * stakers with their native token alongside JOE.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 *
 * Issue with the previous version is that this fraction, `tokenReward*(ACC_TOKEN_PRECISION)/(lpSupply)`,
 * can return 0 or be very inacurate with some tokens:
 *      uint256 timeElapsed = block.timestamp-(pool.lastRewardTimestamp);
 *      uint256 tokenReward = timeElapsed*(tokenPerSec);
 *      accTokenPerShare = accTokenPerShare+(
 *          tokenReward*(ACC_TOKEN_PRECISION)/(lpSupply)
 *      );
 *  The goal is to set ACC_TOKEN_PRECISION high enough to prevent this without causing overflow too.
 */
contract SimpleRewarderPerSec is Ownable2Step, ReentrancyGuard, ISimpleRewarderPerSec {
    using SafeERC20 for IERC20;

    IERC20 public immutable override rewardToken;
    IERC20 public immutable lpToken;
    bool public immutable isNative;
    IAPTFarm public immutable aptFarm;
    uint256 public tokenPerSec;

    // Given the fraction, tokenReward * ACC_TOKEN_PRECISION / lpSupply, we consider
    // several edge cases.
    //
    // Edge case n1: maximize the numerator, minimize the denominator.
    // `lpSupply` = 1 WEI
    // `tokenPerSec` = 1e(30)
    // `timeElapsed` = 31 years, i.e. 1e9 seconds
    // result = 1e9 * 1e30 * 1e36 / 1
    //        = 1e75
    // (No overflow as max uint256 is 1.15e77).
    // PS: This will overflow when `timeElapsed` becomes greater than 1e11, i.e. in more than 3_000 years
    // so it should be fine.
    //
    // Edge case n2: minimize the numerator, maximize the denominator.
    // `lpSupply` = max(uint112) = 1e34
    // `tokenPerSec` = 1 WEI
    // `timeElapsed` = 1 second
    // result = 1 * 1 * 1e36 / 1e34
    //        = 1e2
    // (Not rounded to zero, therefore ACC_TOKEN_PRECISION = 1e36 is safe)
    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    modifier onlyAPTFarm() {
        if (msg.sender != address(aptFarm)) {
            revert SimpleRewarderPerSec__OnlyAPTFarm();
        }
        _;
    }

    constructor(IERC20 _rewardToken, IERC20 _lpToken, uint256 _tokenPerSec, IAPTFarm _MCJ, bool _isNative) {
        if (
            !Address.isContract(address(_rewardToken)) || !Address.isContract(address(_lpToken))
                || !Address.isContract(address(_MCJ))
        ) {
            revert SimpleRewarderPerSec__InvalidAddress();
        }

        if (_tokenPerSec > 1e30) {
            revert SimpleRewarderPerSec__InvalidTokenPerSec();
        }

        rewardToken = _rewardToken;
        lpToken = _lpToken;
        tokenPerSec = _tokenPerSec;
        aptFarm = _MCJ;
        isNative = _isNative;
        poolInfo = PoolInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice payable function needed to receive AVAX
    receive() external payable {}

    /// @notice Function called by MasterChefJoe whenever staker claims JOE harvest. Allows staker to also receive a 2nd reward token.
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onJoeReward(address _user, uint256 _lpAmount) external override onlyAPTFarm nonReentrant {
        updatePool();

        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 pending;
        if (user.amount > 0) {
            pending = (user.amount * pool.accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt + user.unpaidRewards;

            uint256 rewardBalance = _balance();
            if (isNative) {
                if (pending > rewardBalance) {
                    _transferNative(_user, rewardBalance);
                    user.unpaidRewards = pending - rewardBalance;
                } else {
                    _transferNative(_user, pending);
                    user.unpaidRewards = 0;
                }
            } else {
                if (pending > rewardBalance) {
                    rewardToken.safeTransfer(_user, rewardBalance);
                    user.unpaidRewards = pending - rewardBalance;
                } else {
                    rewardToken.safeTransfer(_user, pending);
                    user.unpaidRewards = 0;
                }
            }
        }

        user.amount = _lpAmount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / ACC_TOKEN_PRECISION;
        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(aptFarm));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTimestamp;
            uint256 tokenReward = timeElapsed * tokenPerSec;
            accTokenPerShare = accTokenPerShare + (tokenReward * ACC_TOKEN_PRECISION) / lpSupply;
        }

        pending = (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt + user.unpaidRewards;
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        return _balance();
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = lpToken.balanceOf(address(aptFarm));

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp - pool.lastRewardTimestamp;
                uint256 tokenReward = timeElapsed * tokenPerSec;
                pool.accTokenPerShare = pool.accTokenPerShare + (tokenReward * ACC_TOKEN_PRECISION) / lpSupply;
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw(address token) public onlyOwner {
        if (token == address(0)) {
            _transferNative(msg.sender, address(this).balance);
        } else {
            IERC20(token).safeTransfer(address(msg.sender), IERC20(token).balanceOf(address(this)));
        }
    }

    function _balance() internal view returns (uint256) {
        if (isNative) {
            return address(this).balance;
        } else {
            return rewardToken.balanceOf(address(this));
        }
    }

    function _transferNative(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        if (!success) {
            revert SimpleRewarderPerSec__TransferFailed();
        }
    }
}
