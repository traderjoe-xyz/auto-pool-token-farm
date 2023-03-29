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

    struct VaultData {
        IBaseVault vault;
        IVaultFactory.VaultType vaultType;
        address tokenX;
        address tokenY;
        uint256 tokenXBalance;
        uint256 tokenYBalance;
        uint256 totalSupply;
        uint256 vaultBalanceUSD;
        bool hasFarm;
        FarmData farmData;
    }

    struct FarmData {
        uint256 farmId;
        uint256 joePerSec;
        IRewarder rewarder;
        uint256 aptBalance;
        uint256 aptBalanceUSD;
    }

    struct VaultDataWithUserInfo {
        VaultData vaultData;
        uint256 userBalance;
        uint256 userBalanceUSD;
        FarmDataWithUserInfo farmDataWithUserInfo;
    }

    struct FarmDataWithUserInfo {
        FarmData farmData;
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

    function getAllVaults() external view returns (VaultData[] memory vaultsData) {
        vaultsData = _getAllVaults();
    }

    function getAllPools() external view returns (VaultData[] memory farmsData) {
        farmsData = _getAllPools();
    }

    function getAllVaultsWithUserInfo(address user)
        external
        view
        returns (VaultDataWithUserInfo[] memory vaultsDataWithUserInfo)
    {
        VaultData[] memory vaultsData = _getAllVaults();
        vaultsDataWithUserInfo = new VaultDataWithUserInfo[](vaultsData.length);

        for (uint256 i = 0; i < vaultsData.length; i++) {
            vaultsDataWithUserInfo[i] = _getVaultUserInfo(vaultsData[i], user);
        }
    }

    function getAllPoolsWithUserInfo(address user)
        external
        view
        returns (VaultDataWithUserInfo[] memory farmsDataWithUserInfo)
    {
        VaultData[] memory farmsData = _getAllPools();
        farmsDataWithUserInfo = new VaultDataWithUserInfo[](farmsData.length);

        for (uint256 i = 0; i < farmsData.length; i++) {
            farmsDataWithUserInfo[i] = _getVaultUserInfo(farmsData[i], user);
        }
    }

    function _getAllVaults() internal view returns (VaultData[] memory vaultsData) {
        uint256 totalSimpleVaults = vaultFactory.getNumberOfVaults(IVaultFactory.VaultType.Simple);
        uint256 totalOracleVaults = vaultFactory.getNumberOfVaults(IVaultFactory.VaultType.Oracle);

        vaultsData = new VaultData[](totalSimpleVaults + totalOracleVaults);

        for (uint256 i = 0; i < totalSimpleVaults; i++) {
            vaultsData[i] = _getVaultAt(IVaultFactory.VaultType.Simple, i);
        }

        for (uint256 i = 0; i < totalOracleVaults; i++) {
            vaultsData[totalSimpleVaults + i] = _getVaultAt(IVaultFactory.VaultType.Oracle, i);
        }
    }

    function _getVaultAt(IVaultFactory.VaultType vaultType, uint256 vaultId)
        internal
        view
        returns (VaultData memory vaultData)
    {
        IBaseVault vault = IBaseVault(vaultFactory.getVaultAt(vaultType, vaultId));
        vaultData = _getVault(vault, vaultType);
    }

    function _getVault(IBaseVault vault) internal view returns (VaultData memory vaultData) {
        (bool success,) = address(vault).staticcall(abi.encodeWithSelector(vault.getBalances.selector));

        vaultData = _getVault(vault, success ? IVaultFactory.VaultType.Oracle : IVaultFactory.VaultType.Simple);
    }

    function _getVault(IBaseVault vault, IVaultFactory.VaultType vaultType)
        internal
        view
        returns (VaultData memory vaultData)
    {
        FarmData memory farmInfo;
        if (aptFarm.hasPool(address(vault))) {
            uint256 poolId = aptFarm.vaultPoolId(address(vault));
            farmInfo = _getPool(poolId);
        }

        address tokenX = address(vault.getTokenX());
        address tokenY = address(vault.getTokenY());

        (uint256 tokenXBalance, uint256 tokenYBalance) = vault.getBalances();

        vaultData = VaultData({
            vault: vault,
            vaultType: vaultType,
            tokenX: tokenX,
            tokenY: tokenY,
            tokenXBalance: tokenXBalance,
            tokenYBalance: tokenYBalance,
            totalSupply: vault.totalSupply(),
            vaultBalanceUSD: _getVaultTokenUSDValue(vault, vault.totalSupply()),
            hasFarm: aptFarm.hasPool(address(vault)),
            farmData: farmInfo
        });
    }

    function _getVaultUserInfo(VaultData memory vaultData, address user)
        internal
        view
        returns (VaultDataWithUserInfo memory vaultDataWithUserInfo)
    {
        uint256 userBalance = vaultData.vault.balanceOf(user);
        uint256 userBalanceUSD = _getVaultTokenUSDValue(vaultData.vault, userBalance);

        FarmDataWithUserInfo memory farmDataWithUserInfo;

        if (vaultData.hasFarm) {
            farmDataWithUserInfo = _getFarmUserInfo(vaultData.vault, vaultData.farmData, user);
        }

        vaultDataWithUserInfo = VaultDataWithUserInfo({
            vaultData: vaultData,
            userBalance: userBalance,
            userBalanceUSD: userBalanceUSD,
            farmDataWithUserInfo: farmDataWithUserInfo
        });
    }

    function _getAllPools() internal view returns (VaultData[] memory farmsData) {
        uint256 totalPools = aptFarm.poolLength();
        farmsData = new VaultData[](totalPools);

        for (uint256 i = 0; i < totalPools; i++) {
            IBaseVault vault = IBaseVault(address(aptFarm.poolInfo(i).apToken));
            farmsData[i] = _getVault(vault);
        }
    }

    function _getPool(uint256 poolId) internal view returns (FarmData memory farmData) {
        IAPTFarm.PoolInfo memory poolInfo = aptFarm.poolInfo(poolId);

        IBaseVault vault = IBaseVault(address(poolInfo.apToken));

        farmData = FarmData({
            farmId: poolId,
            joePerSec: poolInfo.joePerSec,
            rewarder: IRewarder(poolInfo.rewarder),
            aptBalance: poolInfo.apToken.balanceOf(address(aptFarm)),
            aptBalanceUSD: _getVaultTokenUSDValue(vault, poolInfo.apToken.balanceOf(address(aptFarm)))
        });
    }

    function _getFarmUserInfo(IBaseVault vault, FarmData memory farmData, address user)
        internal
        view
        returns (FarmDataWithUserInfo memory farmDataWithUserInfo)
    {
        uint256 userBalance = aptFarm.userInfo(farmData.farmId, user).amount;
        uint256 userBalanceUSD = _getVaultTokenUSDValue(vault, userBalance);

        (uint256 pendingJoe,,, uint256 pendingBonusToken) = aptFarm.pendingTokens(farmData.farmId, user);

        farmDataWithUserInfo = FarmDataWithUserInfo({
            farmData: farmData,
            userBalance: userBalance,
            userBalanceUSD: userBalanceUSD,
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
