// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IWrappedNative is IERC20 {
    function deposit() external payable;
}
