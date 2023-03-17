// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../TestHelper.sol";

contract APTFarmHandler is Test {
    APTFarm _aptFarm;

    address[] internal _actors;
    address internal _currentActor;

    mapping(address => mapping(IERC20 => uint256)) public actorsTotalDeposits;
    uint256 public joeDistributed;

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(APTFarm aptFarm) {
        _aptFarm = aptFarm;

        _actors.push(makeAddr("alice"));
        _actors.push(makeAddr("bob"));
        _actors.push(makeAddr("carol"));
        _actors.push(makeAddr("dave"));
    }

    function getActors() public view returns (address[] memory) {
        return _actors;
    }

    function deposit(uint256 pid, uint256 amount, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        pid = bound(pid, 0, 2);
        amount = bound(amount, 0, 1e32);

        IERC20 apToken = _aptFarm.poolInfo(pid).apToken;

        if (amount > apToken.balanceOf(_currentActor)) {
            ERC20Mock(address(apToken)).mint(_currentActor, amount - apToken.balanceOf(_currentActor));
        }
        apToken.approve(address(_aptFarm), amount);

        _aptFarm.deposit(pid, amount);

        actorsTotalDeposits[_currentActor][apToken] += amount;
    }

    function withdraw(uint256 pid, uint256 amount, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        pid = bound(pid, 0, 2);
        amount = bound(amount, 0, _aptFarm.userInfo(pid, _currentActor).amount);

        _aptFarm.withdraw(pid, amount);
    }

    function emergencyWithdraw(uint256 pid, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        pid = bound(pid, 0, 2);

        _aptFarm.emergencyWithdraw(pid);
    }

    function set(uint256 pid, uint256 joePerSec) public {
        pid = bound(pid, 0, 2);
        joePerSec = bound(joePerSec, 0, 1e24);

        vm.prank(_aptFarm.owner());
        _aptFarm.set(pid, joePerSec, IRewarder(address(0)), false);
    }

    function skipTime(uint32 secondsToWarp) public {
        skip(secondsToWarp);

        joeDistributed += secondsToWarp * _aptFarm.poolInfo(0).joePerSec;
        joeDistributed += secondsToWarp * _aptFarm.poolInfo(1).joePerSec;
        joeDistributed += secondsToWarp * _aptFarm.poolInfo(2).joePerSec;
    }
}

contract APTFarmInvariantTest is TestHelper {
    APTFarmHandler handler;
    uint256 initialFarmBalance;

    function setUp() public override {
        super.setUp();

        handler = new APTFarmHandler(aptFarm);
        targetContract(address(handler));

        bytes4[] memory targetSelectors = new bytes4[](4);
        targetSelectors[0] = APTFarmHandler.deposit.selector;
        targetSelectors[1] = APTFarmHandler.withdraw.selector;
        targetSelectors[2] = APTFarmHandler.set.selector;
        targetSelectors[3] = APTFarmHandler.skipTime.selector;

        FuzzSelector memory fuzzSelector = FuzzSelector(address(handler), targetSelectors);
        targetSelector(fuzzSelector);

        _add(lpToken1, 0);
        _add(lpToken2, 0);
        _add(lpToken3, 0);

        initialFarmBalance = joe.balanceOf(address(aptFarm));
    }

    /**
     * Can't withdraw more than deposited
     */
    function invariant_A() public {
        address[] memory actors = handler.getActors();

        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];

            assertLe(lpToken1.balanceOf(actor), handler.actorsTotalDeposits(actor, lpToken1));
        }
    }

    /**
     * Won't ditribute more rewards than it is expected
     */
    function invariant_B() public {
        uint256 joeBalance = joe.balanceOf(address(aptFarm));

        assertGe(joeBalance, initialFarmBalance - handler.joeDistributed());
    }
}
