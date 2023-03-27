// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IBaseVault} from "joe-v2-vault/interfaces/IBaseVault.sol";
import {IVaultFactory} from "joe-v2-vault/interfaces/IVaultFactory.sol";
import {IJoeDexLens} from "joe-dex-lens/interfaces/IJoeDexLens.sol";

import {IAPTFarm} from "./interfaces/IAPTFarm.sol";
import {IRewarder} from "./interfaces/IRewarder.sol";

import "forge-std/console.sol";

contract APTFarmLens {
    IVaultFactory public immutable vaultFactory;
    IAPTFarm public immutable aptFarm;
    IJoeDexLens public immutable dexLens;

    struct PoolVaultData {
        uint256 farmPoolId;
        uint256 joePerSec;
        IBaseVault vault;
        IRewarder rewarder;
    }

    struct PoolVaultDataWithUserInfo {
        PoolVaultData poolVaultData;
        uint256 userBalance;
        uint256 userBalanceUSD;
        uint256 pendingJoe;
        uint256 pendingBonusToken;
    }

    constructor(IVaultFactory _vaultFactory, IAPTFarm _aptFarm, IJoeDexLens _dexLens) {
        vaultFactory = _vaultFactory;
        aptFarm = _aptFarm;
        dexLens = _dexLens;
    }

    function getAllPoolInfos() external view returns (PoolVaultData[] memory farmInfos) {
        farmInfos = _getAllPoolInfos();
    }

    function getPoolWithUserInfo(uint256 poolId, address user)
        external
        view
        returns (PoolVaultDataWithUserInfo memory farmInfosWithUserData)
    {
        farmInfosWithUserData = _getPoolWithUserInfo(poolId, user);
    }

    function _getAllPoolInfos() internal view returns (PoolVaultData[] memory farmInfos) {
        uint256 totalPools = aptFarm.poolLength();
        farmInfos = new PoolVaultData[](totalPools);

        for (uint256 i = 0; i < totalPools; i++) {
            farmInfos[i] = _getPoolInfo(i);
        }
    }

    function _getPoolInfo(uint256 poolId) internal view returns (PoolVaultData memory farmInfos) {
        IAPTFarm.PoolInfo memory poolInfo = aptFarm.poolInfo(poolId);

        IBaseVault vault = IBaseVault(address(poolInfo.apToken));
        farmInfos = PoolVaultData({
            farmPoolId: poolId,
            joePerSec: poolInfo.joePerSec,
            vault: vault,
            rewarder: IRewarder(poolInfo.rewarder)
        });
    }

    function _getPoolWithUserInfo(uint256 poolId, address user)
        internal
        view
        returns (PoolVaultDataWithUserInfo memory farmInfosWithUserData)
    {
        PoolVaultData memory farmInfos = _getPoolInfo(poolId);
        uint256 userBalance = aptFarm.userInfo(poolId, user).amount;

        (uint256 pendingJoe,,, uint256 pendingBonusToken) = aptFarm.pendingTokens(poolId, user);

        farmInfosWithUserData = PoolVaultDataWithUserInfo({
            poolVaultData: farmInfos,
            userBalance: userBalance,
            userBalanceUSD: _getVaultTokenUSDValue(farmInfos.vault, userBalance),
            pendingJoe: pendingJoe,
            pendingBonusToken: pendingBonusToken
        });
    }

    function _getVaultTokenUSDValue(IBaseVault vault, uint256 balance) internal view returns (uint256 tokenUSDValue) {
        (address tokenX, address tokenY) = (address(vault.getTokenX()), address(vault.getTokenY()));
        (uint256 amountX, uint256 amountY) = vault.previewAmounts(balance);

        (uint256 tokenXPrice, uint256 tokenYPrice) =
            (dexLens.getTokenPriceUSD(tokenX), dexLens.getTokenPriceUSD(tokenY));

        tokenUSDValue = (amountX * tokenXPrice / (10 ** IERC20Metadata(tokenX).decimals()))
            + (amountY * tokenYPrice / (10 ** IERC20Metadata(tokenY).decimals()));
    }
}
