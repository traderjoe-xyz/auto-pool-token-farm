// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

contract APTFarmTest is TestHelper {
    using stdStorage for StdStorage;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardsWithdrawn(address indexed to, uint256 amount);

    function test_Deploy() public {
        aptFarm = new APTFarm(joe);

        assertTrue(address(aptFarm) != address(0));
        assertEq(address(aptFarm.joe()), address(joe));
        assertEq(aptFarm.poolLength(), 0);
    }

    function test_AddPool(uint256 joePerSec1, uint256 joePerSec2) public {
        vm.expectEmit();
        emit Add(0, joePerSec1, IERC20(lpToken1), IRewarder(address(0)));
        aptFarm.add(joePerSec1, IERC20(lpToken1), IRewarder(address(0)));

        assertEq(aptFarm.poolLength(), 1, "test_AddPool::1");
        assertEq(address(aptFarm.poolInfo(0).lpToken), address(lpToken1), "test_AddPool::2");
        assertEq(aptFarm.poolInfo(0).joePerSec, joePerSec1, "test_AddPool::3");
        assertEq(aptFarm.poolInfo(0).lastRewardTimestamp, block.timestamp, "test_AddPool::4");
        assertEq(aptFarm.poolInfo(0).accJoePerShare, 0, "test_AddPool::5");

        vm.expectEmit();
        emit Add(1, joePerSec2, IERC20(lpToken2), IRewarder(address(0)));
        aptFarm.add(joePerSec2, IERC20(lpToken2), IRewarder(address(0)));

        assertEq(aptFarm.poolLength(), 2, "test_AddPool::6");
        assertEq(address(aptFarm.poolInfo(1).lpToken), address(lpToken2), "test_AddPool::7");
        assertEq(aptFarm.poolInfo(1).joePerSec, joePerSec2, "test_AddPool::8");
        assertEq(aptFarm.poolInfo(1).lastRewardTimestamp, block.timestamp, "test_AddPool::9");
        assertEq(aptFarm.poolInfo(1).accJoePerShare, 0, "test_AddPool::10");
    }

    function test_Revert_AddPoolWhenNotOwner(address alice) public {
        vm.assume(alice != address(this));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        aptFarm.add(1, IERC20(lpToken1), IRewarder(address(0)));
    }

    function test_Deposit(uint256 joePerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, 100, 1e8 days);
        joePerSec = bound(joePerSec, 1e12, 1e24);
        amountDeposited = bound(amountDeposited, 1e10, 1e28);

        _add(lpToken1, joePerSec);

        lpToken1.mint(address(this), amountDeposited);
        lpToken1.approve(address(aptFarm), amountDeposited);

        vm.expectEmit();
        emit Deposit(address(this), 0, amountDeposited);
        aptFarm.deposit(0, amountDeposited);

        assertEq(lpToken1.balanceOf(address(aptFarm)), amountDeposited, "test_Deposit::1");

        skip(depositTime);

        (uint256 pendingJoe,,,) = aptFarm.pendingTokens(0, address(this));

        assertApproxEqRel(pendingJoe, joePerSec * depositTime, 1e14);
    }

    function test_ConsecutiveDeposits(
        uint256 joePerSec,
        uint256 amountDepositedFirst,
        uint256 amountDepositedSecond,
        uint256 depositTime
    ) public {
        depositTime = bound(depositTime, 100, 1e8 days);
        joePerSec = bound(joePerSec, 1e12, 1e24);
        amountDepositedFirst = bound(amountDepositedFirst, 1e10, 1e28);
        amountDepositedSecond = bound(amountDepositedSecond, 1e10, 1e28);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDepositedFirst);

        skip(depositTime);

        _deposit(0, amountDepositedSecond);

        assertEq(
            lpToken1.balanceOf(address(aptFarm)),
            amountDepositedFirst + amountDepositedSecond,
            "test_ConsecutiveDeposits::1"
        );
        assertEq(
            aptFarm.userInfo(0, address(this)).amount,
            amountDepositedFirst + amountDepositedSecond,
            "test_ConsecutiveDeposits::2"
        );
    }

    function test_Withdraw(uint256 joePerSec, uint256 amountDeposited, uint256 amountWithdrawn, uint256 depositTime)
        public
    {
        depositTime = bound(depositTime, 100, 1e8 days);
        joePerSec = bound(joePerSec, 1e12, 1e24);
        amountDeposited = bound(amountDeposited, 1e10, 1e28);
        amountWithdrawn = bound(amountWithdrawn, 1e10, amountDeposited);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);
        uint256 joeBalanceBefore = joe.balanceOf(address(this));

        vm.expectEmit();
        emit Withdraw(address(this), 0, amountWithdrawn);
        aptFarm.withdraw(0, amountWithdrawn);

        assertApproxEqRel(
            joe.balanceOf(address(this)) - joeBalanceBefore, joePerSec * depositTime, 1e14, "test_Withdraw::1"
        );
    }

    function test_Revert_WithdrawMoreThanDeposited(
        uint256 joePerSec,
        uint256 amountDeposited,
        uint256 amountWithdrawn,
        uint256 depositTime
    ) public {
        depositTime = bound(depositTime, 100, 1e8 days);
        joePerSec = bound(joePerSec, 1e12, 1e24);
        amountDeposited = bound(amountDeposited, 0, 1e28);
        amountWithdrawn = bound(amountWithdrawn, amountDeposited + 1, 1e28 + 1);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);

        vm.expectRevert(
            abi.encodeWithSelector(IAPTFarm.APTFarm__InsufficientDeposit.selector, amountDeposited, amountWithdrawn)
        );
        aptFarm.withdraw(0, amountWithdrawn);
    }

    function test_InsufficientRewardsOnTheContract(
        uint256 joePerSec,
        uint256 amountDeposited,
        uint256 depositTime,
        uint256 joeBalance
    ) public {
        depositTime = bound(depositTime, 100, 1e8 days);
        joePerSec = bound(joePerSec, 1e12, 1e24);
        amountDeposited = bound(amountDeposited, 1e10, 1e28);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);

        (uint256 pendingRewards,,,) = aptFarm.pendingTokens(0, address(this));

        joeBalance = bound(joeBalance, 0, pendingRewards - 1);
        stdstore.target(address(joe)).sig("balanceOf(address)").with_key(address(aptFarm)).checked_write(joeBalance);

        vm.expectRevert(
            abi.encodeWithSelector(IAPTFarm.APTFarm__InsufficientRewardBalance.selector, joeBalance, pendingRewards)
        );
        aptFarm.withdraw(0, amountDeposited);

        aptFarm.emergencyWithdraw(0);

        assertEq(lpToken1.balanceOf(address(this)), amountDeposited, "test_InsufficientRewardsOnTheContract::1");
    }

    function test_SetPool(uint256 oldJoePerSec, uint256 newJoePerSec, uint256 timePassed) public {
        oldJoePerSec = bound(oldJoePerSec, 1e12, 1e24);
        newJoePerSec = bound(newJoePerSec, 1e12, 1e24);
        timePassed = bound(timePassed, 100, 1e8 days);

        test_Deposit(oldJoePerSec, 1e18, 1e6);
        aptFarm.updatePool(0);

        (uint256 pendingJoeBefore,,,) = aptFarm.pendingTokens(0, address(this));

        vm.expectEmit();
        emit Set(0, newJoePerSec, IRewarder(address(0)), false);
        aptFarm.set(0, newJoePerSec, IRewarder(address(0)), false);

        assertEq(aptFarm.poolInfo(0).joePerSec, newJoePerSec, "test_SetPool::1");
        assertEq(aptFarm.poolInfo(0).lastRewardTimestamp, block.timestamp, "test_SetPool::2");

        skip(timePassed);

        (uint256 pendingJoe,,,) = aptFarm.pendingTokens(0, address(this));

        assertEq(pendingJoe, pendingJoeBefore + newJoePerSec * timePassed, "test_SetPool::3");
    }

    function test_Revert_SetPoolWhenNotOwner(address alice) public {
        vm.assume(alice != address(this));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        aptFarm.set(0, 1, IRewarder(address(0)), false);
    }

    function test_MassUpdatePool() public {
        uint256[] memory pids = new uint256[](2);
        pids[0] = _add(lpToken1, 1e18);
        pids[1] = _add(lpToken2, 1e18);

        _deposit(0, 1e18);
        _deposit(1, 1e18);

        skip(1e6);

        aptFarm.massUpdatePools(pids);

        assertEq(aptFarm.poolInfo(0).lastRewardTimestamp, block.timestamp, "test_MassUpdatePool::1");
        assertEq(aptFarm.poolInfo(1).lastRewardTimestamp, block.timestamp, "test_MassUpdatePool::2");
    }

    function test_EmergencyWithdraw(uint256 joePerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, 100, 1e8 days);
        joePerSec = bound(joePerSec, 1e12, 1e24);
        amountDeposited = bound(amountDeposited, 1e10, 1e28);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);
        uint256 lpTokenBalanceBefore = lpToken1.balanceOf(address(this));

        vm.expectEmit();
        emit EmergencyWithdraw(address(this), 0, amountDeposited);
        aptFarm.emergencyWithdraw(0);

        assertEq(lpToken1.balanceOf(address(this)), lpTokenBalanceBefore + amountDeposited, "test_EmergencyWithdraw::1");
        assertEq(aptFarm.userInfo(0, address(this)).amount, 0, "test_EmergencyWithdraw::2");
        assertEq(aptFarm.userInfo(0, address(this)).rewardDebt, 0, "test_EmergencyWithdraw::2");
    }

    function test_WithdrawRewards(uint256 amount) public {
        uint256 rewardsOnContracts = joe.balanceOf(address(aptFarm));

        amount = bound(amount, 0, rewardsOnContracts);

        uint256 joeBalanceBefore = joe.balanceOf(address(this));

        if (amount == 0) {
            vm.expectEmit();
            emit RewardsWithdrawn(address(this), rewardsOnContracts);
        } else {
            vm.expectEmit();
            emit RewardsWithdrawn(address(this), amount);
        }
        aptFarm.withdrawRewards(address(this), amount);

        if (amount == 0) {
            assertEq(joe.balanceOf(address(this)) - joeBalanceBefore, rewardsOnContracts, "test_WithdrawRewards::1");
        } else {
            assertEq(joe.balanceOf(address(this)) - joeBalanceBefore, amount, "test_WithdrawRewards::2");
        }
    }

    function test_Revert_WithdrawRewardsWhenNotOwner(address alice) public {
        vm.assume(alice != address(this));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        aptFarm.withdrawRewards(address(this), 0);
    }
}
