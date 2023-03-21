// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

contract SimpleRewarderPerSecTest is TestHelper {
    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    using stdStorage for StdStorage;

    function test_Deploy(uint256 tokenPerSec) public {
        tokenPerSec = bound(tokenPerSec, 0, 1e30);
        rewarder = new SimpleRewarderPerSec(rewardToken, lpToken1, tokenPerSec, aptFarm, false);

        assertTrue(address(rewarder) != address(0), "test_Deploy::1");
        assertEq(address(rewarder.rewardToken()), address(rewardToken), "test_Deploy::2");
        assertEq(address(rewarder.apToken()), address(lpToken1), "test_Deploy::3");
        assertEq(rewarder.tokenPerSec(), tokenPerSec, "test_Deploy::4");
        assertEq(address(rewarder.aptFarm()), address(aptFarm), "test_Deploy::5");
        assertFalse(rewarder.isNative(), "test_Deploy::6");
        assertEq(rewarder.owner(), address(this), "test_Deploy::7");
    }

    function test_Revert_DeployWithTokenPerSecTooBig(uint256 tokenPerSec) public {
        vm.assume(tokenPerSec > 1e30);

        vm.expectRevert(ISimpleRewarderPerSec.SimpleRewarderPerSec__InvalidTokenPerSec.selector);
        rewarder = new SimpleRewarderPerSec(rewardToken, lpToken1, tokenPerSec, aptFarm, false);
    }

    function test_Revert_DeployWithInvalidRewardToken(address rewardToken) public {
        vm.assume(rewardToken.code.length == 0);

        vm.expectRevert(ISimpleRewarderPerSec.SimpleRewarderPerSec__InvalidAddress.selector);
        rewarder = new SimpleRewarderPerSec(IERC20(rewardToken), lpToken1, 1e18, aptFarm, false);
    }

    function test_Revert_DeployWithInvalidApToken(address apToken) public {
        vm.assume(apToken.code.length == 0);

        vm.expectRevert(ISimpleRewarderPerSec.SimpleRewarderPerSec__InvalidAddress.selector);
        rewarder = new SimpleRewarderPerSec(rewardToken, IERC20(apToken), 1e18, aptFarm, false);
    }

    function test_Revert_DeployWithInvalidAptFarm(address aptFarm) public {
        vm.assume(aptFarm.code.length == 0);

        vm.expectRevert(ISimpleRewarderPerSec.SimpleRewarderPerSec__InvalidAddress.selector);
        rewarder = new SimpleRewarderPerSec(rewardToken, lpToken1, 1e18, IAPTFarm(aptFarm), false);
    }

    function test_Receive(uint256 amount) public {
        deal(address(this), amount);

        (bool success,) = address(rewarder).call{value: amount}("");
        assertTrue(success, "test_Receive::1");
        assertEq(address(rewarder).balance, amount, "test_Receive::2");
    }

    function test_Balance(uint256 amount) public {
        deal(address(rewardToken), address(rewarder), amount);

        assertEq(rewardToken.balanceOf(address(rewarder)), amount, "test_Balance::1");
        assertEq(rewarder.balance(), amount, "test_Balance::2");
    }

    function test_BalanceNative(uint256 amount) public {
        rewarder = new SimpleRewarderPerSec(rewardToken, lpToken1, 1e18, aptFarm, true);

        deal(address(rewarder), amount);

        assertEq(address(rewarder).balance, amount, "test_BalanceNative::1");
        assertEq(rewarder.balance(), amount, "test_BalanceNative::2");
    }

    function test_OnReward(uint256 tokenPerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        tokenPerSec = bound(tokenPerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);

        rewarder = new SimpleRewarderPerSec(rewardToken, lpToken1,tokenPerSec,aptFarm, false);
        deal(address(rewardToken), address(rewarder), 1e50);
        _add(lpToken1, 1e18, rewarder);
        _deposit(0, amountDeposited);

        (uint256 amount, uint256 rewardDebt, uint256 unpaidRewards) = rewarder.userInfo(address(this));
        assertEq(amount, amountDeposited, "test_OnReward::1");
        assertEq(rewardDebt, 0, "test_OnReward::2");
        assertEq(unpaidRewards, 0, "test_OnReward::3");

        skip(depositTime);

        uint256 balanceBefore = rewardToken.balanceOf(address(this));

        aptFarm.withdraw(0, amountDeposited);

        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        uint256 rewards = tokenPerSec * depositTime;

        (amount, rewardDebt, unpaidRewards) = rewarder.userInfo(address(this));
        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::4");
        assertEq(amount, 0, "test_OnReward::5");
        assertEq(unpaidRewards, 0, "test_OnReward::6");

        aptFarm.withdraw(0, 0);

        assertEq(rewardToken.balanceOf(address(this)), balanceAfter, "test_OnReward::7");

        _deposit(0, amountDeposited);

        skip(depositTime);

        balanceBefore = rewardToken.balanceOf(address(this));
        aptFarm.emergencyWithdraw(0);
        balanceAfter = rewardToken.balanceOf(address(this));

        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::8");

        _deposit(0, amountDeposited);

        skip(depositTime);

        (, address bonusTokenAddress, string memory bonusTokenSymbol, uint256 pendingBonusToken) =
            aptFarm.pendingTokens(0, address(this));

        assertApproxEqRel(pendingBonusToken, rewards, expectedPrecision, "test_OnReward::9");
        assertEq(bonusTokenAddress, address(rewardToken), "test_OnReward::10");
        assertEq(bonusTokenSymbol, "ERC20Mock", "test_OnReward::11");

        uint256[] memory pids = new uint256[](1);
        pids[0] = 0;

        balanceBefore = rewardToken.balanceOf(address(this));
        aptFarm.harvestRewards(pids);
        balanceAfter = rewardToken.balanceOf(address(this));

        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::12");
    }

    function test_UpdateRewarder() public {
        _add(lpToken1, 1e18);

        assertEq(address(aptFarm.poolInfo(0).rewarder), address(0), "test_UpdateRewarder::1");

        aptFarm.set(0, 2e18, rewarder, true);

        assertEq(address(aptFarm.poolInfo(0).rewarder), address(rewarder), "test_UpdateRewarder::1");
    }
}
