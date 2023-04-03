// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../TestHelper.sol";

contract APTFarmHandler is TestHelper {
    APTFarm _aptFarm;

    address[] internal _actors;
    address internal _currentActor;

    uint256 public currentTimestamp;
    mapping(bytes32 => uint256) public calls;
    mapping(address => mapping(IERC20 => uint256)) public actorsTotalDeposits;
    uint256 public joeDistributed;

    modifier useActor(uint256 randomnessSeed) {
        _currentActor = _actors[bound(randomnessSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier useCurrentTimestamp() {
        vm.warp(currentTimestamp);
        _;
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

    uint256 depositCalls;

    // Trick to make more deposit/withdraw calls than the rest of the functions
    function deposit1(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _deposit(pid, amount, randomnessSeed);
    }

    function deposit2(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _deposit(pid, amount, randomnessSeed);
    }

    function deposit3(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _deposit(pid, amount, randomnessSeed);
    }

    function deposit4(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _deposit(pid, amount, randomnessSeed);
    }

    function deposit5(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _deposit(pid, amount, randomnessSeed);
    }

    function withdraw1(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _withdraw(pid, amount, randomnessSeed);
    }

    function withdraw2(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _withdraw(pid, amount, randomnessSeed);
    }

    function withdraw3(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _withdraw(pid, amount, randomnessSeed);
    }

    function withdraw4(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _withdraw(pid, amount, randomnessSeed);
    }

    function withdraw5(uint256 pid, uint256 amount, uint256 randomnessSeed) public {
        _withdraw(pid, amount, randomnessSeed);
    }

    function _deposit(uint256 pid, uint256 amount, uint256 randomnessSeed)
        internal
        useActor(randomnessSeed)
        useCurrentTimestamp
        countCall("deposit")
    {
        pid = bound(pid, 0, 2);
        amount = bound(amount, 0, apSupplyUpperBound);

        IERC20 apToken = _aptFarm.farmInfo(pid).apToken;

        if (amount > apToken.balanceOf(_currentActor)) {
            ERC20Mock(address(apToken)).mint(_currentActor, amount - apToken.balanceOf(_currentActor));
        }
        apToken.approve(address(_aptFarm), amount);

        _aptFarm.deposit(pid, amount);

        actorsTotalDeposits[_currentActor][apToken] += amount;

        _warpRandom(randomnessSeed);
    }

    function _withdraw(uint256 pid, uint256 amount, uint256 randomnessSeed)
        internal
        useActor(randomnessSeed)
        useCurrentTimestamp
        countCall("withdraw")
    {
        pid = bound(pid, 0, 2);
        amount = bound(amount, 0, _aptFarm.userInfo(pid, _currentActor).amount);

        _aptFarm.withdraw(pid, amount);

        _warpRandom(randomnessSeed);
    }

    function emergencyWithdraw(uint256 pid, uint256 randomnessSeed)
        public
        useActor(randomnessSeed)
        useCurrentTimestamp
        countCall("emergencyWithdraw")
    {
        pid = bound(pid, 0, 2);

        _aptFarm.emergencyWithdraw(pid);

        _warpRandom(randomnessSeed);
    }

    function harvestRewards(uint256 randomnessSeed)
        public
        useActor(randomnessSeed)
        useCurrentTimestamp
        countCall("harvestRewards")
    {
        uint256[] memory pids = new uint256[](3);
        pids[0] = 0;
        pids[1] = 1;
        pids[2] = 2;

        _aptFarm.harvestRewards(pids);

        _warpRandom(randomnessSeed);
    }

    function set(uint256 pid, uint256 joePerSec, uint256 randomnessSeed) public useCurrentTimestamp countCall("set") {
        pid = bound(pid, 0, 2);
        joePerSec = bound(joePerSec, 0, joePerSecUpperBound);

        vm.prank(_aptFarm.owner());
        _aptFarm.set(pid, joePerSec, IRewarder(address(0)), false);

        _warpRandom(randomnessSeed);
    }

    /**
     * @dev Skips a random amount of time. 1 chance out of 5 to be skipped.
     */
    function _warpRandom(uint256 randomnessSeed) internal {
        if (randomnessSeed % 10 > 1) {
            uint256 secondsToWarp = bound(randomnessSeed, 0, timePassedUpperBound);
            currentTimestamp += secondsToWarp;

            joeDistributed += secondsToWarp * _aptFarm.farmInfo(0).joePerSec;
            joeDistributed += secondsToWarp * _aptFarm.farmInfo(1).joePerSec;
            joeDistributed += secondsToWarp * _aptFarm.farmInfo(2).joePerSec;
        }
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", calls["deposit"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("harvestRewards", calls["harvestRewards"]);
        console.log("emergencyWithdraw", calls["emergencyWithdraw"]);
        console.log("set", calls["set"]);
    }
}

contract APTFarmInvariantTest is TestHelper {
    APTFarmHandler handler;
    uint256 initialFarmBalance;

    function setUp() public override {
        super.setUp();

        handler = new APTFarmHandler(aptFarm);
        targetContract(address(handler));

        bytes4[] memory targetSelectors = new bytes4[](13);
        targetSelectors[0] = APTFarmHandler.deposit1.selector;
        targetSelectors[1] = APTFarmHandler.deposit2.selector;
        targetSelectors[2] = APTFarmHandler.deposit3.selector;
        targetSelectors[3] = APTFarmHandler.deposit4.selector;
        targetSelectors[4] = APTFarmHandler.deposit5.selector;
        targetSelectors[5] = APTFarmHandler.withdraw1.selector;
        targetSelectors[6] = APTFarmHandler.withdraw2.selector;
        targetSelectors[7] = APTFarmHandler.withdraw3.selector;
        targetSelectors[8] = APTFarmHandler.withdraw4.selector;
        targetSelectors[9] = APTFarmHandler.withdraw5.selector;
        targetSelectors[10] = APTFarmHandler.set.selector;
        targetSelectors[11] = APTFarmHandler.emergencyWithdraw.selector;
        targetSelectors[12] = APTFarmHandler.harvestRewards.selector;

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

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
