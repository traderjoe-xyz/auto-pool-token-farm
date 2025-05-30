// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {BaseVault, IBaseVault, IERC20Upgradeable} from "joe-v2-vault/BaseVault.sol";
import {SimpleVault} from "joe-v2-vault/SimpleVault.sol";
import {OracleVault, IAggregatorV3} from "joe-v2-vault/OracleVault.sol";
import {VaultFactory, IVaultFactory, ILBPair} from "joe-v2-vault/VaultFactory.sol";
import {Strategy} from "joe-v2-vault/Strategy.sol";
import {MockAggregator} from "joe-v2-vault/../test/mocks/MockAggregator.sol";
import {JoeDexLens, ILBFactory, ILBLegacyFactory, IJoeFactory} from "joe-dex-lens/JoeDexLens.sol";

import {APTFarm, IAPTFarm} from "src/APTFarm.sol";
import {SimpleRewarderPerSec, ISimpleRewarderPerSec} from "src/SimpleRewarderPerSec.sol";
import {RewarderFactory, IRewarderFactory} from "src/RewarderFactory.sol";
import {APTFarmLens} from "src/APTFarmLens.sol";
import {IRewarder} from "src/interfaces/IRewarder.sol";
import {IWrappedNative} from "src/interfaces/IWrappedNative.sol";
import {ERC20Mock} from "./mocks/ERC20.sol";
import {WrappedNative} from "./mocks/WrappedNative.sol";

abstract contract TestHelper is Test {
    APTFarm aptFarm;
    RewarderFactory rewarderFactory;
    SimpleRewarderPerSec rewarder;
    ERC20Mock joe;
    WrappedNative wNative;

    ERC20Mock lpToken1;
    ERC20Mock lpToken2;
    ERC20Mock lpToken3;
    ERC20Mock rewardToken;

    ERC20Mock tokenX1;
    ERC20Mock tokenX2;
    ERC20Mock tokenX3;
    ERC20Mock tokenY1;
    ERC20Mock tokenY2;

    uint256 timePassedLowerBound = 10;
    uint256 timePassedUpperBound = 100 days;

    // 8 JOE per day
    uint256 joePerSecLowerBound = 1e14;
    // 8_640_000 JOE per day
    uint256 joePerSecUpperBound = 100e18;

    // Auto Pool Token will have a minimum of 12 decimals (for tokenY.decimals = 6)
    uint256 apSupplyLowerBound = 1e12;
    // Upper bound needs to be sufficiently high to test very high supply tokens
    uint256 apSupplyUpperBound = 1e50;

    uint256 expectedPrecision = 1e17;

    function setUp() public virtual {
        joe = new ERC20Mock(18);
        lpToken1 = new ERC20Mock(18);
        lpToken2 = new ERC20Mock(18);
        lpToken3 = new ERC20Mock(18);
        rewardToken = new ERC20Mock(18);

        tokenX1 = new ERC20Mock(18);
        tokenX2 = new ERC20Mock(18);
        tokenX3 = new ERC20Mock(18);
        tokenY1 = new ERC20Mock(18);
        tokenY2 = new ERC20Mock(18);

        wNative = new WrappedNative();

        aptFarm = new APTFarm(joe);
        rewarderFactory = new RewarderFactory(aptFarm,IWrappedNative(address(wNative)) );
        rewarder = rewarderFactory.createRewarder(rewardToken, lpToken1, 1e18, false);

        vm.label(address(joe), "joe");
        vm.label(address(lpToken1), "lpToken1");
        vm.label(address(lpToken2), "lpToken2");
        vm.label(address(lpToken3), "lpToken3");
        vm.label(address(rewardToken), "rewardToken");
        vm.label(address(tokenX1), "tokenX1");
        vm.label(address(tokenX2), "tokenX2");
        vm.label(address(tokenX3), "tokenX3");
        vm.label(address(tokenY1), "tokenY1");
        vm.label(address(tokenY2), "tokenY2");
        vm.label(address(wNative), "wNative");
        vm.label(address(aptFarm), "aptFarm");
        vm.label(address(rewarder), "rewarder");

        deal(address(joe), address(aptFarm), 1e38);
        deal(address(rewardToken), address(rewarder), 1e38);
    }

    function _add(ERC20Mock apToken, uint256 joePerSec) internal returns (uint256 pid) {
        pid = _add(apToken, joePerSec, IRewarder(address(0)));
    }

    function _add(ERC20Mock lpToken, uint256 joePerSec, IRewarder _rewarder) internal returns (uint256 pid) {
        pid = aptFarm.farmLength();
        aptFarm.add(joePerSec, IERC20(lpToken), _rewarder);
    }

    function _deposit(uint256 pid, uint256 amount) internal {
        ERC20Mock apToken = ERC20Mock(address(aptFarm.farmInfo(pid).apToken));

        deal(address(apToken), address(this), amount);
        apToken.approve(address(aptFarm), amount);
        aptFarm.deposit(pid, amount);
    }
}
