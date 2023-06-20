// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

contract SimpleRewarderPerSecTest is TestHelper {
    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    bool blockReceive;

    using stdStorage for StdStorage;

    function test_Deploy(uint256 tokenPerSec) public {
        tokenPerSec = bound(tokenPerSec, 0, 1e30);
        rewarder = rewarderFactory.createRewarder(rewardToken, lpToken1, tokenPerSec, false);

        assertTrue(address(rewarder) != address(0), "test_Deploy::1");
        assertEq(address(rewarder.rewardToken()), address(rewardToken), "test_Deploy::2");
        assertEq(address(rewarder.apToken()), address(lpToken1), "test_Deploy::3");
        assertEq(rewarder.tokenPerSec(), tokenPerSec, "test_Deploy::4");
        assertEq(address(rewarder.aptFarm()), address(aptFarm), "test_Deploy::5");
        assertFalse(rewarder.isNative(), "test_Deploy::6");
        assertEq(rewarder.owner(), address(this), "test_Deploy::7");

        rewarder = rewarderFactory.createRewarder(rewardToken, lpToken1, tokenPerSec, true);
        assertTrue(rewarder.isNative(), "test_Deploy::8");
    }

    function test_Revert_DeployWithTokenPerSecTooBig(uint256 tokenPerSec) public {
        vm.assume(tokenPerSec > 1e30);

        vm.expectRevert(ISimpleRewarderPerSec.SimpleRewarderPerSec__InvalidTokenPerSec.selector);
        rewarderFactory.createRewarder(rewardToken, lpToken1, tokenPerSec, false);
    }

    function test_Revert_DeployWithInvalidRewardToken(address rewardToken) public {
        vm.assume(rewardToken.code.length == 0);

        vm.expectRevert(IRewarderFactory.RewarderFactory__InvalidAddress.selector);
        rewarderFactory.createRewarder(IERC20(rewardToken), lpToken1, 1e18, false);
    }

    function test_Revert_DeployWithInvalidApToken(address apToken) public {
        vm.assume(apToken.code.length == 0);

        vm.expectRevert(IRewarderFactory.RewarderFactory__InvalidAddress.selector);
        rewarderFactory.createRewarder(rewardToken, IERC20(apToken), 1e18, false);
    }

    function test_Revert_DeployWithInvalidAptFarm(address aptFarm) public {
        vm.assume(aptFarm.code.length == 0);

        vm.expectRevert(IRewarderFactory.RewarderFactory__InvalidAddress.selector);
        rewarderFactory = new RewarderFactory(IAPTFarm(aptFarm),IWrappedNative(address(wNative)));
    }

    function test_Revert_DeployWithInvalidWrappedNative(address wNative) public {
        vm.assume(wNative.code.length == 0);

        vm.expectRevert(IRewarderFactory.RewarderFactory__InvalidAddress.selector);
        rewarderFactory = new RewarderFactory(aptFarm,IWrappedNative(address(wNative)));
    }

    function test_Receive(uint256 amount) public {
        deal(address(this), amount);

        deal(address(this), amount);
        (bool success,) = payable(rewarder).call{value: amount}("");

        assertTrue(success, "test_Receive::1");
        assertEq(address(rewarder).balance, amount, "test_Receive::2");
    }

    function test_Balance(uint256 amount) public {
        deal(address(rewardToken), address(rewarder), amount);

        assertEq(rewardToken.balanceOf(address(rewarder)), amount, "test_Balance::1");
        assertEq(rewarder.balance(), amount, "test_Balance::2");
    }

    function test_BalanceNative(uint256 amount) public {
        rewarder = rewarderFactory.createRewarder(rewardToken, lpToken1, 1e18, true);

        deal(address(this), amount);
        (bool success,) = payable(rewarder).call{value: amount}("");

        assertTrue(success, "test_BalanceNative::0");
        assertEq(address(rewarder).balance, amount, "test_BalanceNative::1");
        assertEq(rewarder.balance(), amount, "test_BalanceNative::2");
    }

    function test_OnReward(uint256 tokenPerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        tokenPerSec = bound(tokenPerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);

        rewarder = rewarderFactory.createRewarder(rewardToken, lpToken1, tokenPerSec, false);

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

    function test_OnRewardNative(uint256 tokenPerSec, uint256 amountDeposited, uint256 depositTime) public {
        depositTime = bound(depositTime, timePassedLowerBound, timePassedUpperBound);
        tokenPerSec = bound(tokenPerSec, joePerSecLowerBound, joePerSecUpperBound);
        amountDeposited = bound(amountDeposited, apSupplyLowerBound, apSupplyUpperBound);

        // TODO: change rewardToken address to wNative
        rewarder = rewarderFactory.createRewarder(IERC20(address(0)), lpToken1, tokenPerSec, true);

        deal(address(rewarder), 1e50);
        _add(lpToken1, 1e18, rewarder);
        _deposit(0, amountDeposited);

        (uint256 amount, uint256 rewardDebt, uint256 unpaidRewards) = rewarder.userInfo(address(this));
        assertEq(amount, amountDeposited, "test_OnReward::1");
        assertEq(rewardDebt, 0, "test_OnReward::2");
        assertEq(unpaidRewards, 0, "test_OnReward::3");

        skip(depositTime);

        uint256 balanceBefore = address(this).balance;

        aptFarm.withdraw(0, amountDeposited);

        uint256 balanceAfter = address(this).balance;
        uint256 rewards = tokenPerSec * depositTime;

        (amount, rewardDebt, unpaidRewards) = rewarder.userInfo(address(this));
        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::4");
        assertEq(amount, 0, "test_OnReward::5");
        assertEq(unpaidRewards, 0, "test_OnReward::6");

        aptFarm.withdraw(0, 0);

        assertEq(address(this).balance, balanceAfter, "test_OnReward::7");

        _deposit(0, amountDeposited);

        skip(depositTime);

        balanceBefore = address(this).balance;
        aptFarm.emergencyWithdraw(0);
        balanceAfter = address(this).balance;

        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::8");

        _deposit(0, amountDeposited);

        skip(depositTime);

        (, address bonusTokenAddress, string memory bonusTokenSymbol, uint256 pendingBonusToken) =
            aptFarm.pendingTokens(0, address(this));

        assertApproxEqRel(pendingBonusToken, rewards, expectedPrecision, "test_OnReward::9");
        assertEq(bonusTokenAddress, address(0), "test_OnReward::10");
        assertEq(bonusTokenSymbol, "", "test_OnReward::11");

        uint256[] memory pids = new uint256[](1);
        pids[0] = 0;

        balanceBefore = address(this).balance;
        aptFarm.harvestRewards(pids);
        balanceAfter = address(this).balance;

        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::12");

        // Test receive deposits with no receive function
        blockReceive = true;

        skip(depositTime);

        balanceBefore = wNative.balanceOf(address(this));
        aptFarm.harvestRewards(pids);
        balanceAfter = wNative.balanceOf(address(this));

        assertApproxEqRel(balanceAfter - balanceBefore, rewards, expectedPrecision, "test_OnReward::13");
    }

    function test_UpdateRewarder() public {
        _add(lpToken1, 1e18);

        assertEq(address(aptFarm.farmInfo(0).rewarder), address(0), "test_UpdateRewarder::1");

        aptFarm.set(0, 2e18, rewarder, true);

        assertEq(address(aptFarm.farmInfo(0).rewarder), address(rewarder), "test_UpdateRewarder::1");
    }

    function test_CreateRewardersWithSameParameters(uint256 tokenPerSec) public {
        tokenPerSec = bound(tokenPerSec, joePerSecLowerBound, joePerSecUpperBound);

        rewarderFactory.createRewarder(rewardToken, lpToken1, tokenPerSec, false);
        rewarderFactory.createRewarder(rewardToken, lpToken1, tokenPerSec, false);
        rewarderFactory.createRewarder(rewardToken, lpToken2, tokenPerSec, false);
        rewarderFactory.createRewarder(rewardToken, lpToken2, tokenPerSec, false);

        address[] memory rewarders = rewarderFactory.getRewarders();
        assertEq(rewarders.length, 5, "test_CreateRewardersWithSameParameters::1");
        assertEq(rewarders[0], address(rewarder), "test_CreateRewardersWithSameParameters::2");
        assertEq(rewarderFactory.getRewardersCount(), 5, "test_CreateRewardersWithSameParameters::3");
    }

    function test_SetRewardRate(uint256 oldTokenPerSec, uint256 newTokenPerSec) public {
        oldTokenPerSec = bound(oldTokenPerSec, joePerSecLowerBound, joePerSecUpperBound);
        newTokenPerSec = bound(newTokenPerSec, joePerSecLowerBound, joePerSecUpperBound);

        rewarder = rewarderFactory.createRewarder(rewardToken, lpToken1, oldTokenPerSec, false);

        rewarder.setRewardRate(newTokenPerSec);

        assertEq(rewarder.tokenPerSec(), newTokenPerSec, "test_SetRewardRate::1");
    }

    function test_Revert_CreateNewRewarderWithNoRole() public {
        address alice = makeAddr("alice");

        vm.expectRevert();
        vm.prank(alice);
        rewarderFactory.createRewarder(rewardToken, lpToken1, 1e18, false);

        vm.expectRevert();
        vm.prank(alice);
        rewarderFactory.grantCreatorRole(alice);

        vm.expectRevert();
        vm.prank(alice);
        rewarderFactory.grantRole(keccak256("REWARDER_CREATOR_ROLE"), alice);
    }

    function test_RoleManagement() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        bytes32 role = keccak256("REWARDER_CREATOR_ROLE");

        assertEq(rewarderFactory.owner(), address(this), "test_RoleManagement::1");
        assertTrue(rewarderFactory.hasRole(role, address(this)), "test_RoleManagement::2");
        assertFalse(rewarderFactory.hasRole(role, alice), "test_RoleManagement::3");

        rewarderFactory.grantRole(role, alice);

        assertTrue(rewarderFactory.hasRole(role, alice), "test_RoleManagement::4");

        rewarderFactory.revokeRole(role, alice);

        assertFalse(rewarderFactory.hasRole(role, alice), "test_RoleManagement::5");

        rewarderFactory.grantCreatorRole(bob);

        assertTrue(rewarderFactory.hasRole(role, bob), "test_RoleManagement::6");
    }

    receive() external payable {
        if (blockReceive) {
            revert("receive not allowed");
        }
    }
}
