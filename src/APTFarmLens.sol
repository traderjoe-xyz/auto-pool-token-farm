// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {
    IAPTFarmLens, IVaultFactory, IBaseVault, IAPTFarm, IRewarder, IJoeDexLens
} from "./interfaces/IAPTFarmLens.sol";

contract APTFarmLens is IAPTFarmLens {
    /**
     * @notice The vault factory contract
     */
    IVaultFactory public immutable override vaultFactory;

    /**
     * @notice The APT farm contract
     */
    IAPTFarm public immutable override aptFarm;

    /**
     * @notice The Joe Dex Lens contract
     */
    IJoeDexLens public immutable override dexLens;

    constructor(IVaultFactory _vaultFactory, IAPTFarm _aptFarm, IJoeDexLens _dexLens) {
        vaultFactory = _vaultFactory;
        aptFarm = _aptFarm;
        dexLens = _dexLens;
    }

    /**
     * @notice Returns the vault data for every vault created by the vault factory
     * @return vaultsData The vault data for every vault created by the vault factory
     */
    function getAllVaults() external view override returns (VaultData[] memory vaultsData) {
        vaultsData = _getAllVaults();
    }

    /**
     * @notice Returns the vault data for every vault that has a farm
     *  @return farmsData The vault data for every vault that has a farm
     */
    function getAllPools() external view override returns (VaultData[] memory farmsData) {
        farmsData = _getAllPools();
    }

    /**
     * @notice Returns the vault for every vault created by the vault factory with the user's info
     * @param user The user's address
     * @return vaultsDataWithUserInfo The vault data with the user's info
     */
    function getAllVaultsWithUserInfo(address user)
        external
        view
        override
        returns (VaultDataWithUserInfo[] memory vaultsDataWithUserInfo)
    {
        VaultData[] memory vaultsData = _getAllVaults();

        vaultsDataWithUserInfo = new VaultDataWithUserInfo[](vaultsData.length);

        for (uint256 i = 0; i < vaultsData.length; i++) {
            vaultsDataWithUserInfo[i] = _getVaultUserInfo(vaultsData[i], user);
        }
    }

    /**
     * @notice Returns the vault for every vault that has a farm with the user's info
     * @param user The user's address
     * @return farmsDataWithUserInfo The vault data with the user's info
     */
    function getAllPoolsWithUserInfo(address user)
        external
        view
        override
        returns (VaultDataWithUserInfo[] memory farmsDataWithUserInfo)
    {
        VaultData[] memory farmsData = _getAllPools();

        farmsDataWithUserInfo = new VaultDataWithUserInfo[](farmsData.length);

        for (uint256 i = 0; i < farmsData.length; i++) {
            farmsDataWithUserInfo[i] = _getVaultUserInfo(farmsData[i], user);
        }
    }

    /**
     * @dev Gets all the vaults created by the vault factory
     * @return vaultsData The vault data for every vault created by the vault factory
     */
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

    /**
     * @dev Gets all the vault of the specified type created at the specified index
     * @param vaultType The vault type
     * @param vaultId The vault id
     * @return vaultData The vault data
     */
    function _getVaultAt(IVaultFactory.VaultType vaultType, uint256 vaultId)
        internal
        view
        returns (VaultData memory vaultData)
    {
        IBaseVault vault = IBaseVault(vaultFactory.getVaultAt(vaultType, vaultId));
        vaultData = _getVault(vault, vaultType);
    }

    /**
     * @dev Gets the vault information
     * @param vault The vault address
     * @return vaultData The vault data
     */
    function _getVault(IBaseVault vault) internal view returns (VaultData memory vaultData) {
        (bool success,) = address(vault).staticcall(abi.encodeWithSelector(vault.getBalances.selector)); // TODO add a way to get the vault type in the vault factory

        vaultData = _getVault(vault, success ? IVaultFactory.VaultType.Oracle : IVaultFactory.VaultType.Simple);
    }

    /**
     * @dev Gets the vault information, considering that we already know the vault type
     * @param vault The vault address
     * @param vaultType The vault type
     * @return vaultData The vault data
     */
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

    /**
     * @dev Appends the user's info to the vault data
     * @param vaultData The vault data
     * @param user The user's address
     * @return vaultDataWithUserInfo The vault data with the user's info
     */
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

    /**
     * @dev Gets the farm information for every vault that has a farm
     * @return farmsData The farm data for every vault that has a farm
     */
    function _getAllPools() internal view returns (VaultData[] memory farmsData) {
        uint256 totalPools = aptFarm.poolLength();

        farmsData = new VaultData[](totalPools);

        for (uint256 i = 0; i < totalPools; i++) {
            IBaseVault vault = IBaseVault(address(aptFarm.poolInfo(i).apToken));
            farmsData[i] = _getVault(vault);
        }
    }

    /**
     * @dev Gets the farm information for the specified pool
     * @param poolId The pool id
     * @return farmData The farm data
     */
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

    /**
     * @dev Appends the user's info to the farm data
     * @param vault The vault address
     * @param farmData The farm data
     * @param user The user's address
     * @return farmDataWithUserInfo The farm data with the user's info
     */
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

    /**
     * @dev Gets the vault token USD value
     * @param vault The vault address
     * @param amount The amount of vault tokens
     * @return tokenUSDValue The vault token USD value
     */
    function _getVaultTokenUSDValue(IBaseVault vault, uint256 amount) internal view returns (uint256 tokenUSDValue) {
        (address tokenX, address tokenY) = (address(vault.getTokenX()), address(vault.getTokenY()));
        (uint256 amountX, uint256 amountY) = vault.previewAmounts(amount);

        (uint256 tokenXPrice, uint256 tokenYPrice) =
            (dexLens.getTokenPriceUSD(tokenX), dexLens.getTokenPriceUSD(tokenY));

        tokenUSDValue = (amountX * tokenXPrice / (10 ** IERC20Metadata(tokenX).decimals()))
            + (amountY * tokenYPrice / (10 ** IERC20Metadata(tokenY).decimals()));
    }
}
