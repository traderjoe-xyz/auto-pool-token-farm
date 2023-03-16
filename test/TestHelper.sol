// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {APTFarm, IAPTFarm} from "src/APTFarm.sol";
import {IRewarder} from "src/interfaces/IRewarder.sol";
import {ERC20Mock} from "./mocks/ERC20.sol";

abstract contract TestHelper is Test {
    APTFarm aptFarm;
    ERC20Mock joe;

    ERC20Mock lpToken1;
    ERC20Mock lpToken2;
    ERC20Mock lpToken3;

    function setUp() public virtual {
        joe = new ERC20Mock(18);
        lpToken1 = new ERC20Mock(18);
        lpToken2 = new ERC20Mock(18);
        lpToken3 = new ERC20Mock(18);

        aptFarm = new APTFarm(joe);

        vm.label(address(joe), "joe");
        vm.label(address(lpToken1), "lpToken1");
        vm.label(address(lpToken2), "lpToken2");
        vm.label(address(lpToken2), "lpToken3");
        vm.label(address(aptFarm), "aptFarm");

        deal(address(joe), address(aptFarm), 1e38);
    }

    function _add(ERC20Mock lpToken, uint256 joePerSec) internal returns (uint256 pid) {
        pid = _add(lpToken, joePerSec, IRewarder(address(0)));
    }

    function _add(ERC20Mock lpToken, uint256 joePerSec, IRewarder rewarder) internal returns (uint256 pid) {
        pid = aptFarm.poolLength();
        aptFarm.add(joePerSec, IERC20(lpToken), rewarder);
    }

    function _deposit(uint256 pid, uint256 amount) internal {
        ERC20Mock lpToken = ERC20Mock(address(aptFarm.poolInfo(pid).lpToken));

        deal(address(lpToken), address(this), amount);
        lpToken.approve(address(aptFarm), amount);
        aptFarm.deposit(pid, amount);
    }
}
