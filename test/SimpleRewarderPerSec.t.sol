// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

contract SimpleRewarderPerSecTest is TestHelper {
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
}
