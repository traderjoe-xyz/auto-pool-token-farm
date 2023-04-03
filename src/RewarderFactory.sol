// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ImmutableClone} from "joe-v2-1/libraries/ImmutableClone.sol";

import {SimpleRewarderPerSec} from "./SimpleRewarderPerSec.sol";
import {IRewarderFactory} from "./interfaces/IRewarderFactory.sol";
import {IAPTFarm} from "./interfaces/IAPTFarm.sol";

contract RewarderFactory is AccessControl, Ownable2Step, IRewarderFactory {
    /**
     * @dev The role necessary to create rewarders.
     */
    bytes32 private constant REWARDER_CREATOR_ROLE = keccak256("REWARDER_CREATOR_ROLE");

    /**
     * @notice The address of the APTFarm contract.
     */
    IAPTFarm public immutable override aptFarm;

    /**
     * @notice The address of the SimpleRewarderPerSec implementation.
     */
    address public override simpleRewarderImplementation;

    /**
     * @notice The list of rewarders created by this factory.
     */
    address[] public override rewarders;

    /**
     * @notice The nounce used to create the deterministic address of the rewarder.
     */
    uint256 private _nounce;

    constructor(IAPTFarm _aptFarm) {
        if (!Address.isContract(address(_aptFarm))) {
            revert RewarderFactory__InvalidAddress();
        }

        simpleRewarderImplementation = address(new SimpleRewarderPerSec());
        aptFarm = _aptFarm;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARDER_CREATOR_ROLE, msg.sender);
    }

    /**
     * @notice Gets the number of existing rewarders.
     * @return The number of existing rewarders.
     */
    function getRewardersCount() external view override returns (uint256) {
        return rewarders.length;
    }

    /**
     * @notice Returns the list of rewarders created by this factory.
     * @return The list of rewarders created by this factory.
     */
    function getRewarders() external view override returns (address[] memory) {
        return rewarders;
    }

    /**
     * @notice Creates a new rewarder.
     * @param rewardToken Token to be rewarded.
     * @param apToken Token to be staked.
     * @param tokenPerSec Amount of reward token to be rewarded per second.
     * @param isNative Whether the reward token is the native token of the chain
     */
    function createRewarder(IERC20 rewardToken, IERC20 apToken, uint256 tokenPerSec, bool isNative)
        external
        override
        onlyRole(REWARDER_CREATOR_ROLE)
        returns (SimpleRewarderPerSec rewarder)
    {
        if (!Address.isContract(address(rewardToken)) || !Address.isContract(address(apToken))) {
            revert RewarderFactory__InvalidAddress();
        }

        address rewarderAddress = ImmutableClone.cloneDeterministic(
            simpleRewarderImplementation,
            abi.encodePacked(rewardToken, apToken, aptFarm, isNative),
            keccak256(abi.encode(_nounce++))
        );

        rewarder = SimpleRewarderPerSec(payable(rewarderAddress));
        rewarder.initialize(tokenPerSec, msg.sender);
        rewarders.push(rewarderAddress);

        emit RewarderCreated(rewarderAddress, address(rewardToken), address(apToken), isNative, msg.sender);
    }

    /**
     * @notice Sets the address of the SimpleRewarderPerSec implementation.
     * @param _simpleRewarderImplementation The address of the SimpleRewarderPerSec implementation.
     */
    function setSimpleRewarderImplementation(address _simpleRewarderImplementation) external override onlyOwner {
        if (!Address.isContract(_simpleRewarderImplementation)) {
            revert RewarderFactory__InvalidAddress();
        }

        simpleRewarderImplementation = _simpleRewarderImplementation;

        emit SimpleRewarderImplementationChanged(_simpleRewarderImplementation);
    }

    /**
     * @notice Grants the REWARDER_CREATOR_ROLE role to an account.
     * @param account The account to grant the REWARDER_CREATOR_ROLE role to.
     */
    function grantCreatorRole(address account) external override onlyOwner {
        _grantRole(REWARDER_CREATOR_ROLE, account);
    }
}
