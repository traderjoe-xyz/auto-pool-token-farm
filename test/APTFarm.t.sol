// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

contract APTFarmTest is TestHelper {
    using stdStorage for StdStorage;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed apToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateFarm(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event BatchHarvest(address indexed user, uint256[] pids);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Skim(address indexed token, address indexed to, uint256 amount);

    function test_Deploy() public {
        aptFarm = new APTFarm(joe);

        assertTrue(address(aptFarm) != address(0));
        assertEq(address(aptFarm.joe()), address(joe));
        assertEq(aptFarm.farmLength(), 0);
    }

    function test_AddFarm(uint256 joePerSec1, uint256 joePerSec2) public {
        vm.expectEmit();
        emit Add(0, joePerSec1, IERC20(lpToken1), IRewarder(address(0)));
        aptFarm.add(joePerSec1, IERC20(lpToken1), IRewarder(address(0)));

        assertEq(aptFarm.farmLength(), 1, "test_AddFarm::1");
        assertEq(address(aptFarm.farmInfo(0).apToken), address(lpToken1), "test_AddFarm::2");
        assertEq(aptFarm.farmInfo(0).joePerSec, joePerSec1, "test_AddFarm::3");
        assertEq(aptFarm.farmInfo(0).lastRewardTimestamp, block.timestamp, "test_AddFarm::4");
        assertEq(aptFarm.farmInfo(0).accJoePerShare, 0, "test_AddFarm::5");
        assertTrue(aptFarm.hasFarm(address(lpToken1)), "test_AddFarm::6");

        vm.expectEmit();
        emit Add(1, joePerSec2, IERC20(lpToken2), IRewarder(address(0)));
        aptFarm.add(joePerSec2, IERC20(lpToken2), IRewarder(address(0)));

        assertEq(aptFarm.farmLength(), 2, "test_AddFarm::7");
        assertEq(address(aptFarm.farmInfo(1).apToken), address(lpToken2), "test_AddFarm::8");
        assertEq(aptFarm.farmInfo(1).joePerSec, joePerSec2, "test_AddFarm::9");
        assertEq(aptFarm.farmInfo(1).lastRewardTimestamp, block.timestamp, "test_AddFarm::10");
        assertEq(aptFarm.farmInfo(1).accJoePerShare, 0, "test_AddFarm::11");
        assertTrue(aptFarm.hasFarm(address(lpToken2)), "test_AddFarm::12");
    }

    function test_Revert_AddFarmWhenNotOwner(address alice) public {
        vm.assume(alice != address(this));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        aptFarm.add(1, IERC20(lpToken1), IRewarder(address(0)));
    }

    function test_Revert_AddAlreadyExistingFarm() public {
        aptFarm.add(1, IERC20(lpToken1), IRewarder(address(0)));

        vm.expectRevert(abi.encodeWithSelector(IAPTFarm.APTFarm__TokenAlreadyHasFarm.selector, lpToken1));
        aptFarm.add(1, IERC20(lpToken1), IRewarder(address(0)));
    }

    function test_Revert_AddJoeFarm() public {
        vm.expectRevert(abi.encodeWithSelector(IAPTFarm.APTFarm__InvalidAPToken.selector));
        aptFarm.add(1, joe, IRewarder(address(0)));
    }

    function test_Deposit(uint256 joePerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec = bound(joePerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);

        _add(lpToken1, joePerSec);

        lpToken1.mint(address(this), amountDeposited);
        lpToken1.approve(address(aptFarm), amountDeposited);

        vm.expectEmit();
        emit Deposit(address(this), 0, amountDeposited);
        aptFarm.deposit(0, amountDeposited);

        assertEq(lpToken1.balanceOf(address(aptFarm)), amountDeposited, "test_Deposit::1");
        assertEq(aptFarm.apTokenBalances(lpToken1), amountDeposited, "test_Deposit::2");

        skip(depositTime);

        (uint256 pendingJoe,,,) = aptFarm.pendingTokens(0, address(this));

        assertApproxEqRel(pendingJoe, joePerSec * depositTime, expectedPrecision, "test_Deposit::3");
    }

    function test_ConsecutiveDeposits(
        uint256 joePerSec,
        uint256 amountDepositedFirst,
        uint256 amountDepositedSecond,
        uint256 depositTime
    ) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec = bound(joePerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDepositedFirst = bound(amountDepositedFirst, apSupplyLowerBound, apSupplyUpperBound);
        amountDepositedSecond = bound(amountDepositedSecond, amountDepositedFirst / 1e12, amountDepositedFirst * 1e12);

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

        assertEq(
            aptFarm.apTokenBalances(lpToken1),
            amountDepositedFirst + amountDepositedSecond,
            "test_ConsecutiveDeposits::3"
        );
    }

    function test_Withdraw(uint256 joePerSec, uint256 amountDeposited, uint256 amountWithdrawn, uint256 depositTime)
        public
    {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec = bound(joePerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);
        amountWithdrawn = bound(amountWithdrawn, 0, amountDeposited);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);
        uint256 joeBalanceBefore = joe.balanceOf(address(this));

        vm.expectEmit();
        emit Withdraw(address(this), 0, amountWithdrawn);
        aptFarm.withdraw(0, amountWithdrawn);

        assertApproxEqRel(
            joe.balanceOf(address(this)) - joeBalanceBefore,
            joePerSec * depositTime,
            expectedPrecision,
            "test_Withdraw::1"
        );

        assertEq(aptFarm.apTokenBalances(lpToken1), amountDeposited - amountWithdrawn, "test_Withdraw::2");
    }

    function test_Revert_WithdrawMoreThanDeposited(
        uint256 joePerSec,
        uint256 amountDeposited,
        uint256 amountWithdrawn,
        uint256 depositTime
    ) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec = bound(joePerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);
        amountWithdrawn = bound(amountWithdrawn, amountDeposited + 1, type(uint256).max);

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
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec = bound(joePerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);

        (uint256 pendingRewards,,,) = aptFarm.pendingTokens(0, address(this));
        uint256 userJoeBalanceBefore = joe.balanceOf(address(this));

        joeBalance = bound(joeBalance, 0, pendingRewards - 1);
        stdstore.target(address(joe)).sig("balanceOf(address)").with_key(address(aptFarm)).checked_write(joeBalance);

        aptFarm.withdraw(0, amountDeposited);

        assertEq(lpToken1.balanceOf(address(this)), amountDeposited, "test_InsufficientRewardsOnTheContract::1");

        (uint256 pendingRewardsAfter,,,) = aptFarm.pendingTokens(0, address(this));
        assertEq(pendingRewardsAfter, pendingRewards - joeBalance, "test_InsufficientRewardsOnTheContract::2");

        assertEq(
            joe.balanceOf(address(this)) - userJoeBalanceBefore, joeBalance, "test_InsufficientRewardsOnTheContract::3"
        );

        deal(address(joe), address(aptFarm), pendingRewards);

        aptFarm.deposit(0, 0);

        (pendingRewardsAfter,,,) = aptFarm.pendingTokens(0, address(this));
        assertEq(pendingRewardsAfter, 0, "test_InsufficientRewardsOnTheContract::4");

        assertEq(
            joe.balanceOf(address(this)) - userJoeBalanceBefore,
            pendingRewards,
            "test_InsufficientRewardsOnTheContract::5"
        );
    }

    function test_SetFarm(uint256 oldJoePerSec, uint256 newJoePerSec, uint256 timePassed) public {
        oldJoePerSec = bound(oldJoePerSec, joePerSecLowerBound, joePerSecUpperBound);
        newJoePerSec = bound(newJoePerSec, joePerSecLowerBound, joePerSecUpperBound);
        timePassed = bound(timePassed, timePassedLowerBound, timePassedUpperBound);

        test_Deposit(oldJoePerSec, 1e18, 1e6);

        (uint256 pendingJoeBefore,,,) = aptFarm.pendingTokens(0, address(this));

        vm.expectEmit();
        emit Set(0, newJoePerSec, IRewarder(address(0)), false);
        aptFarm.set(0, newJoePerSec, IRewarder(address(0)), false);

        assertEq(aptFarm.farmInfo(0).joePerSec, newJoePerSec, "test_SetFarm::1");
        assertEq(aptFarm.farmInfo(0).lastRewardTimestamp, block.timestamp, "test_SetFarm::2");

        skip(timePassed);

        (uint256 pendingJoe,,,) = aptFarm.pendingTokens(0, address(this));

        assertEq(pendingJoe, pendingJoeBefore + newJoePerSec * timePassed, "test_SetFarm::3");
    }

    function test_Revert_SetPoolWhenNotOwner(address alice) public {
        vm.assume(alice != address(this));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        aptFarm.set(0, 1, IRewarder(address(0)), false);
    }

    function test_EmergencyWithdraw(uint256 joePerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec = bound(joePerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);

        _add(lpToken1, joePerSec);
        _deposit(0, amountDeposited);

        skip(depositTime);
        uint256 lpTokenBalanceBefore = lpToken1.balanceOf(address(this));

        vm.expectEmit();
        emit EmergencyWithdraw(address(this), 0, amountDeposited);
        aptFarm.emergencyWithdraw(0);

        assertEq(lpToken1.balanceOf(address(this)), lpTokenBalanceBefore + amountDeposited, "test_EmergencyWithdraw::1");
        assertEq(aptFarm.userInfo(0, address(this)).amount, 0, "test_EmergencyWithdraw::2");
        assertEq(aptFarm.userInfo(0, address(this)).rewardDebt, 0, "test_EmergencyWithdraw::3");
        assertEq(aptFarm.apTokenBalances(lpToken1), 0, "test_EmergencyWithdraw::4");
    }

    function test_Skim(uint256 amount) public {
        amount = bound(amount, 0, 1e32);

        _add(lpToken1, 200);
        _deposit(0, 2e18);

        uint256 lpToken1BalanceBefore = lpToken1.balanceOf(address(this));

        lpToken1.mint(address(aptFarm), amount);

        if (amount > 0) {
            vm.expectEmit();
            emit Skim(address(lpToken1), address(this), amount);
        }
        aptFarm.skim(lpToken1, address(this));

        assertEq(lpToken1.balanceOf(address(this)), lpToken1BalanceBefore + amount, "test_Skim::1");
        assertEq(aptFarm.apTokenBalances(lpToken1), 2e18, "test_Skim::2");
    }

    function test_Revert_SkimWhenNotOwner(address alice) public {
        vm.assume(alice != address(this));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        aptFarm.skim(lpToken1, address(this));
    }

    function test_HarvestRewards(
        uint256 joePerSec1,
        uint256 joePerSec2,
        uint256 amountDeposited1,
        uint256 amountDeposited2,
        uint256 depositTime
    ) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        joePerSec1 = bound(joePerSec1, joePerSecLowerBound, joePerSecUpperBound);
        joePerSec2 = bound(joePerSec2, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited1 = bound(amountDeposited1, apSupplyLowerBound, apSupplyUpperBound);
        amountDeposited2 = bound(amountDeposited2, apSupplyLowerBound, apSupplyUpperBound);

        _add(lpToken1, joePerSec1);
        _add(lpToken2, joePerSec2);
        _deposit(0, amountDeposited1);
        _deposit(1, amountDeposited2);

        skip(depositTime);

        (uint256 pendingJoe1,,,) = aptFarm.pendingTokens(0, address(this));
        (uint256 pendingJoe2,,,) = aptFarm.pendingTokens(1, address(this));

        uint256 userJoeBalanceBefore = joe.balanceOf(address(this));

        uint256[] memory pids = new uint256[](2);
        pids[0] = 0;
        pids[1] = 1;

        vm.expectEmit();
        emit BatchHarvest(address(this), pids);
        aptFarm.harvestRewards(pids);

        assertEq(
            joe.balanceOf(address(this)) - userJoeBalanceBefore, pendingJoe1 + pendingJoe2, "test_HarvestRewards::1"
        );
    }
}
