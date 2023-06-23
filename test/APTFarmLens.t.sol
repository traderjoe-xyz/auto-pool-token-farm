// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract APTFarmLensTest is TestHelper {
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant joeAvalanche = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    address constant wavax_usdc_20bp = 0xD446eb1660F766d533BeCeEf890Df7A69d26f7d1;
    address constant usdt_usdc_1bp = 0x9B2Cc8E6a2Bbb56d6bE4682891a91B0e48633c72;
    address constant joe_wavax_15bp = 0x9f8973FB86b35C307324eC31fd81Cf565E2F4a63;

    JoeDexLens constant dexLens = JoeDexLens(0x441eF20e39DfE886AAb99a6E1bb64f43E45bD973);
    VaultFactory constant vaultFactory = VaultFactory(0xA3D87597fDAfC3b8F3AC6B68F90CD1f4c05Fa960);

    APTFarmLens aptFarmLens;

    address strategy;
    address simpleVault1;
    address simpleVault2;

    /**
     * From the analytics, at bloc 31_692_540
     * TokenX: 70,732 + 8,694 AVAX = 79,426 AVAX deposited
     * TokenY: 718,855 + 30,612 USDC = 749,467 USDC deposited
     * 1 AVAX = 12.78 USD
     * Total TVL: 1,622,900 USD
     */
    address oracleVault = 0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d; // The General

    uint256 constant joePerSec = 1e18;

    function setUp() public override {
        vm.createSelectFork(StdChains.getChain("avalanche").rpcUrl, 31_692_540);
        super.setUp();

        aptFarmLens = new APTFarmLens(vaultFactory, aptFarm, dexLens);

        vm.startPrank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2);
        simpleVault1 = vaultFactory.createSimpleVault(ILBPair(joe_wavax_15bp));
        simpleVault2 = vaultFactory.createSimpleVault(ILBPair(usdt_usdc_1bp));

        strategy = vaultFactory.createDefaultStrategy(IBaseVault(simpleVault1));
        linkVaultToStrategy(simpleVault1, strategy);
        vm.stopPrank();

        _add(ERC20Mock(oracleVault), joePerSec);
        _add(ERC20Mock(simpleVault1), joePerSec);

        vm.label(wavax, "wavax");
        vm.label(usdc, "usdc");
        vm.label(usdt, "usdt");
        vm.label(joeAvalanche, "joeAvalanche");

        vm.label(wavax_usdc_20bp, "wavax_usdc_20bp");
        vm.label(usdt_usdc_1bp, "usdt_usdc_1bp");
        vm.label(joe_wavax_15bp, "joe_wavax_15bp");

        vm.label(oracleVault, "oracleVault");
        vm.label(simpleVault1, "simpleVault1");
        vm.label(simpleVault2, "simpleVault2");

        vm.label(strategy, "strategy");
        vm.label(address(aptFarmLens), "aptFarmLens");

        depositToVault(simpleVault1, address(this), 1e18, 20e6);
        _deposit(1, SimpleVault(payable(simpleVault1)).balanceOf(address(this)));
    }

    function test_GetAllVaults() public {
        APTFarmLens.VaultData[] memory vaultsData = aptFarmLens.getAllVaults();

        assertEq(vaultsData.length, 3, "test_GetAllVaults::1");

        assertEq(address(vaultsData[0].vault), oracleVault, "test_GetAllVaults::2");
        assertEq(address(vaultsData[1].vault), simpleVault1, "test_GetAllVaults::3");
        assertEq(address(vaultsData[2].vault), simpleVault2, "test_GetAllVaults::4");

        // oracleVault
        assertEq(vaultsData[0].tokenX, wavax, "test_GetAllVaults::oracleVault::1");
        assertEq(vaultsData[0].tokenY, usdc, "test_GetAllVaults::oracleVault::2");
        assertApproxEqRel(vaultsData[0].tokenXBalance, 69_000e18, 1e18, "test_GetAllVaults::oracleVault::3");
        assertApproxEqRel(vaultsData[0].tokenYBalance, 7_300_000e6, 1e18, "test_GetAllVaults::oracleVault::4");
        assertApproxEqRel(vaultsData[0].vaultBalanceUSD, 1_622_900e18, 1e16, "test_GetAllVaults::oracleVault::5");
        assertEq(
            uint8(vaultsData[0].vaultType), uint8(IVaultFactory.VaultType.Oracle), "test_GetAllVaults::oracleVault::6"
        );
        assertTrue(vaultsData[0].hasFarm, "test_GetAllVaults::oracleVault::7");
        assertEq(vaultsData[0].farmData.farmId, 0, " test_GetAllVaults::oracleVault::8");
        assertEq(vaultsData[0].farmData.joePerSec, joePerSec, " test_GetAllVaults::oracleVault::9");
        assertEq(address(vaultsData[0].farmData.rewarder), address(0), " test_GetAllVaults::oracleVault::10");
        assertApproxEqRel(vaultsData[0].farmData.aptBalance, 0, 1e16, " test_GetAllVaults::oracleVault::11");
        assertApproxEqRel(vaultsData[0].farmData.aptBalanceUSD, 0, 1e16, " test_GetAllVaults::oracleVault::12");

        // simpleVault1
        assertEq(address(vaultsData[1].strategy), address(strategy), "test_GetAllVaults::simpleVault1::1");
        assertEq(
            uint8(vaultsData[1].strategyType),
            uint8(IVaultFactory.StrategyType.Default),
            "test_GetAllVaults::simpleVault1::2"
        );
        assertEq(vaultsData[1].tokenX, joeAvalanche, "test_GetAllVaults::simpleVault1::3");
        assertEq(vaultsData[1].tokenY, wavax, "test_GetAllVaults::simpleVault1::4");
        assertEq(vaultsData[1].tokenXBalance, 1e18, "test_GetAllVaults::simpleVault1::5");
        assertEq(vaultsData[1].tokenYBalance, 20e6, "test_GetAllVaults::simpleVault1::6");
        assertApproxEqRel(vaultsData[1].vaultBalanceUSD, 407e15, 1e16, "test_GetAllVaults::simpleVault1::7");
        assertEq(
            uint8(vaultsData[1].vaultType), uint8(IVaultFactory.VaultType.Simple), "test_GetAllVaults::simpleVault1::8"
        );
        assertTrue(vaultsData[1].hasFarm, "test_GetAllVaults::simpleVault1::9");
        assertEq(vaultsData[1].farmData.farmId, 1, " test_GetAllVaults::simpleVault1::10");
        assertEq(vaultsData[1].farmData.joePerSec, joePerSec, " test_GetAllVaults::simpleVault1::11");
        assertEq(address(vaultsData[1].farmData.rewarder), address(0), " test_GetAllVaults::simpleVault1::12");
        assertApproxEqRel(
            vaultsData[1].farmData.aptBalance,
            SimpleVault(payable(simpleVault1)).totalSupply(),
            1e16,
            " test_GetAllVaults::simpleVault1::13"
        );
        assertApproxEqRel(vaultsData[1].farmData.aptBalanceUSD, 407e15, 1e16, " test_GetAllVaults::simpleVault1::4");

        // simpleVault2
        assertEq(vaultsData[2].tokenX, usdt, "test_GetAllVaults::simpleVault2::1");
        assertEq(vaultsData[2].tokenY, usdc, "test_GetAllVaults::simpleVault2::2");
        assertEq(vaultsData[2].tokenXBalance, 0, "test_GetAllVaults:simpleVault2:::3");
        assertEq(vaultsData[2].tokenYBalance, 0, "test_GetAllVaults::simpleVault2::4");
        assertApproxEqRel(vaultsData[2].vaultBalanceUSD, 0, 1e16, "test_GetAllVaults::simpleVault2::5");
        assertEq(
            uint8(vaultsData[2].vaultType), uint8(IVaultFactory.VaultType.Simple), "test_GetAllVaults::simpleVault2::6"
        );
        assertFalse(vaultsData[2].hasFarm, "test_GetAllVaults::simpleVault2::7");
        assertEq(vaultsData[2].farmData.farmId, 0, " test_GetAllVaults::simpleVault2::8");
        assertEq(vaultsData[2].farmData.joePerSec, 0, " test_GetAllVaults::simpleVault2::9");
        assertEq(address(vaultsData[2].farmData.rewarder), address(0), " test_GetAllVaults::simpleVault2::10");
        assertApproxEqRel(vaultsData[2].farmData.aptBalance, 0, 1e16, " test_GetAllVaults::simpleVault2::11");
        assertApproxEqRel(vaultsData[2].farmData.aptBalanceUSD, 0, 1e16, " test_GetAllVaults::simpleVault2::12");
    }

    function test_GetPaginatedVaults() public {
        APTFarmLens.VaultData[] memory vaultsData =
            aptFarmLens.getPaginatedVaultsFromType(IVaultFactory.VaultType.Simple, 0, 10);

        assertEq(vaultsData.length, 2, "test_GetPaginatedVaults::1");

        assertEq(address(vaultsData[0].vault), simpleVault1, "test_GetPaginatedVaults::2");
        assertEq(address(vaultsData[1].vault), simpleVault2, "test_GetPaginatedVaults::3");

        vaultsData = aptFarmLens.getPaginatedVaultsFromType(IVaultFactory.VaultType.Oracle, 0, 10);

        assertEq(vaultsData.length, 1, "test_GetPaginatedVaults::4");

        assertEq(address(vaultsData[0].vault), oracleVault, "test_GetPaginatedVaults::5");

        // Test odd values
        vaultsData = aptFarmLens.getPaginatedVaultsFromType(IVaultFactory.VaultType.Simple, 0, 1);
        assertEq(vaultsData.length, 1, "test_GetPaginatedVaults::6");

        vaultsData = aptFarmLens.getPaginatedVaultsFromType(IVaultFactory.VaultType.Simple, 1, 1);
        assertEq(vaultsData.length, 1, "test_GetPaginatedVaults::7");

        vaultsData = aptFarmLens.getPaginatedVaultsFromType(IVaultFactory.VaultType.Simple, 10, 2);
        assertEq(vaultsData.length, 0, "test_GetPaginatedVaults::8");
    }

    function test_GetAllFarms() public {
        APTFarmLens.VaultData[] memory farmsInfo = aptFarmLens.getAllVaultsWithFarms();

        assertEq(farmsInfo.length, 2, "test_GetAllFarms::1");

        assertEq(address(farmsInfo[0].vault), oracleVault, "test_GetAllFarms::2");
        assertEq(address(farmsInfo[1].vault), simpleVault1, "test_GetAllFarms::3");
    }

    function test_GetPaginatedFarms() public {
        APTFarmLens.VaultData[] memory farmsData = aptFarmLens.getPaginatedVaultsWithFarms(0, 10);

        assertEq(farmsData.length, 2, "test_GetPaginatedFarms::1");
        assertEq(address(farmsData[0].vault), oracleVault, "test_GetPaginatedFarms::2");
        assertEq(address(farmsData[1].vault), simpleVault1, "test_GetPaginatedFarms::3");

        farmsData = aptFarmLens.getPaginatedVaultsWithFarms(1, 1);
        assertEq(farmsData.length, 1, "test_GetPaginatedFarms::4");
        assertEq(address(farmsData[0].vault), simpleVault1, "test_GetPaginatedFarms::5");

        farmsData = aptFarmLens.getPaginatedVaultsWithFarms(10, 2);
        assertEq(farmsData.length, 0, "test_GetPaginatedFarms::6");
    }

    function test_GetAllVaultsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory vaultsDataWithUserInfo =
            aptFarmLens.getAllVaultsIncludingUserInfo(address(this));

        assertEq(vaultsDataWithUserInfo.length, 3, "test_GetAllVaultsWithUserInfo::1");

        assertEq(address(vaultsDataWithUserInfo[0].vaultData.vault), oracleVault, "test_GetAllVaultsWithUserInfo::2");
        assertEq(address(vaultsDataWithUserInfo[1].vaultData.vault), simpleVault1, "test_GetAllVaultsWithUserInfo::3");
        assertEq(address(vaultsDataWithUserInfo[2].vaultData.vault), simpleVault2, "test_GetAllVaultsWithUserInfo::4");

        assertApproxEqRel(
            vaultsDataWithUserInfo[1].vaultData.farmData.aptBalanceUSD, 407e15, 1e16, "test_GetAllVaultsWithUserInfo::5"
        );
        assertApproxEqRel(
            vaultsDataWithUserInfo[1].farmDataWithUserInfo.userBalanceUSD,
            407e15,
            1e16,
            "test_GetAllVaultsWithUserInfo::1"
        );
    }

    function test_GetPaginatedVaultsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsIncludingUserInfo(address(this), IVaultFactory.VaultType.Simple, 0, 10);

        assertEq(vaultsDataWithUserInfo.length, 2, "test_GetPaginatedVaultsWithUSerInfo::1");
        assertEq(
            address(vaultsDataWithUserInfo[0].vaultData.vault), simpleVault1, "test_GetPaginatedVaultsWithUSerInfo::2"
        );
        assertEq(
            address(vaultsDataWithUserInfo[1].vaultData.vault), simpleVault2, "test_GetPaginatedVaultsWithUSerInfo::3"
        );
        assertApproxEqRel(
            vaultsDataWithUserInfo[0].vaultData.farmData.aptBalanceUSD,
            407e15,
            1e16,
            "test_GetPaginatedVaultsWithUSerInfo::4"
        );

        vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsIncludingUserInfo(address(this), IVaultFactory.VaultType.Oracle, 0, 10);

        assertEq(vaultsDataWithUserInfo.length, 1, "test_GetPaginatedVaultsWithUSerInfo::5");
        assertEq(
            address(vaultsDataWithUserInfo[0].vaultData.vault), oracleVault, "test_GetPaginatedVaultsWithUSerInfo::6"
        );

        vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsIncludingUserInfo(address(this), IVaultFactory.VaultType.Simple, 1, 1);

        assertEq(vaultsDataWithUserInfo.length, 1, "test_GetPaginatedVaultsWithUSerInfo::7");
        assertEq(
            address(vaultsDataWithUserInfo[0].vaultData.vault), simpleVault2, "test_GetPaginatedVaultsWithUSerInfo::8"
        );

        vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsIncludingUserInfo(address(this), IVaultFactory.VaultType.Oracle, 10, 10);

        assertEq(vaultsDataWithUserInfo.length, 0, "test_GetPaginatedVaultsWithUSerInfo::9");
    }

    function test_GetAllFarmsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory farmsDataWithUserInfo =
            aptFarmLens.getAllVaultsWithFarmsIncludingUserInfo(address(this));

        assertEq(farmsDataWithUserInfo.length, 2, "test_GetAllFarmsWithUserInfo::1");

        assertEq(address(farmsDataWithUserInfo[0].vaultData.vault), oracleVault, "test_GetAllFarmsWithUserInfo::2");
        assertEq(address(farmsDataWithUserInfo[1].vaultData.vault), simpleVault1, "test_GetAllFarmsWithUserInfo::3");

        assertApproxEqRel(
            farmsDataWithUserInfo[1].vaultData.farmData.aptBalanceUSD, 407e15, 1e16, "test_GetAllFarmsWithUserInfo::4"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[1].farmDataWithUserInfo.userBalanceUSD,
            407e15,
            1e16,
            "test_GetAllFarmsWithUserInfo::5"
        );
    }

    function test_GetPaginatedFarmsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory farmsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsWithFarmsIncludingUserInfo(address(this), 0, 10);

        assertEq(farmsDataWithUserInfo.length, 2, "test_GetPaginatedFarmsWithUserInfo::1");
        assertEq(
            address(farmsDataWithUserInfo[0].vaultData.vault), oracleVault, "test_GetPaginatedFarmsWithUserInfo::2"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[0].vaultData.farmData.aptBalanceUSD, 0, 1e16, "test_GetPaginatedFarmsWithUserInfo::3"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[0].farmDataWithUserInfo.userBalanceUSD,
            0,
            1e16,
            "test_GetPaginatedFarmsWithUserInfo::4"
        );
        assertEq(
            address(farmsDataWithUserInfo[1].vaultData.vault), simpleVault1, "test_GetPaginatedFarmsWithUserInfo::5"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[1].vaultData.farmData.aptBalanceUSD,
            407e15,
            1e16,
            "test_GetPaginatedFarmsWithUserInfo::6"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[1].farmDataWithUserInfo.userBalanceUSD,
            407e15,
            1e16,
            "test_GetPaginatedFarmsWithUserInfo::7"
        );

        farmsDataWithUserInfo = aptFarmLens.getPaginatedVaultsWithFarmsIncludingUserInfo(address(this), 1, 1);

        assertEq(farmsDataWithUserInfo.length, 1, "test_GetPaginatedFarmsWithUserInfo::8");
        assertEq(
            address(farmsDataWithUserInfo[0].vaultData.vault), simpleVault1, "test_GetPaginatedFarmsWithUserInfo::9"
        );

        farmsDataWithUserInfo = aptFarmLens.getPaginatedVaultsWithFarmsIncludingUserInfo(address(this), 10, 10);

        assertEq(farmsDataWithUserInfo.length, 0, "test_GetPaginatedFarmsWithUserInfo::10");
    }

    function depositToVault(address newVault, address from, uint256 amountX, uint256 amountY) public {
        IERC20Upgradeable tokenX = IBaseVault(newVault).getTokenX();
        IERC20Upgradeable tokenY = IBaseVault(newVault).getTokenY();

        deal(address(tokenX), from, amountX);
        deal(address(tokenY), from, amountY);

        vm.prank(from);
        tokenX.approve(newVault, amountX);

        vm.prank(from);
        tokenY.approve(newVault, amountY);

        vm.prank(from);
        IBaseVault(newVault).deposit(amountX, amountY);
    }

    function linkVaultToStrategy(address newVault, address newStrategy) public {
        vaultFactory.linkVaultToStrategy(IBaseVault(newVault), newStrategy);
    }
}
