// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract APTFarmLensTest is TestHelper {
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant joeAvalanche = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    address constant wavax_usdc_20bp = 0xB5352A39C11a81FE6748993D586EC448A01f08b5;
    address constant usdt_usdc_1bp = 0x1D7A1a79e2b4Ef88D2323f3845246D24a3c20F1d;
    address constant joe_wavax_15bp = 0xc01961EdE437Bf0cC41D064B1a3F6F0ea6aa2a40;

    address constant dexLens = 0x16978e42a9b14A19878161A7EdE255637ce361e0;

    APTFarmLens aptFarmLens;
    VaultFactory vaultFactory;
    JoeDexLens joeDexLens;

    address strategy;
    address oracleVault;
    address simpleVault1;
    address simpleVault2;

    uint256 constant joePerSec = 1e18;

    function setUp() public override {
        vm.createSelectFork(StdChains.getChain("avalanche").rpcUrl, 26_179_802);
        super.setUp();

        address implementation = address(new VaultFactory(wavax));
        vm.prank(address(1));
        vaultFactory = VaultFactory(
            address(
                new TransparentUpgradeableProxy(implementation, address(1), abi.encodeWithSelector(VaultFactory.initialize.selector, address(this)))
            )
        );

        vaultFactory.setVaultImplementation(IVaultFactory.VaultType.Simple, address(new SimpleVault(vaultFactory)));
        vaultFactory.setVaultImplementation(IVaultFactory.VaultType.Oracle, address(new OracleVault(vaultFactory)));
        vaultFactory.setStrategyImplementation(IVaultFactory.StrategyType.Default, address(new Strategy(vaultFactory)));

        joeDexLens = JoeDexLens(dexLens);
        aptFarmLens = new APTFarmLens(vaultFactory, aptFarm, joeDexLens);

        IAggregatorV3 dfX = IAggregatorV3(address(new MockAggregator()));
        IAggregatorV3 dfY = IAggregatorV3(address(new MockAggregator()));

        oracleVault = vaultFactory.createOracleVault(ILBPair(usdt_usdc_1bp), dfX, dfY);
        simpleVault1 = vaultFactory.createSimpleVault(ILBPair(wavax_usdc_20bp));
        simpleVault2 = vaultFactory.createSimpleVault(ILBPair(joe_wavax_15bp));

        _add(ERC20Mock(oracleVault), joePerSec);
        _add(ERC20Mock(simpleVault1), joePerSec);

        strategy = vaultFactory.createDefaultStrategy(IBaseVault(simpleVault1));

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

        linkVaultToStrategy(simpleVault1, strategy);
        depositToVault(simpleVault1, address(this), 1e18, 20e6);
        _deposit(1, SimpleVault(payable(simpleVault1)).balanceOf(address(this)));
    }

    function test_GetAllVaults() public {
        APTFarmLens.VaultData[] memory vaultsData = aptFarmLens.getAllVaults();

        assertEq(vaultsData.length, 3, "test_GetAllVaults::1");

        assertEq(address(vaultsData[0].vault), simpleVault1, "test_GetAllVaults::2");
        assertEq(address(vaultsData[1].vault), simpleVault2, "test_GetAllVaults::3");
        assertEq(address(vaultsData[2].vault), oracleVault, "test_GetAllVaults::4");

        // simpleVault1
        assertEq(address(vaultsData[0].strategy), address(strategy), "test_GetAllVaults::5");
        assertEq(uint8(vaultsData[0].strategyType), uint8(IVaultFactory.StrategyType.Default), "test_GetAllVaults::6");
        assertEq(vaultsData[0].tokenX, wavax, "test_GetAllVaults::7");
        assertEq(vaultsData[0].tokenY, usdc, "test_GetAllVaults::8");
        assertEq(vaultsData[0].tokenXBalance, 1e18, "test_GetAllVaults::9");
        assertEq(vaultsData[0].tokenYBalance, 20e6, "test_GetAllVaults::10");
        assertApproxEqRel(vaultsData[0].vaultBalanceUSD, 38e6, 1e16, "test_GetAllVaults::11");
        assertEq(uint8(vaultsData[0].vaultType), uint8(IVaultFactory.VaultType.Simple), "test_GetAllVaults::12");
        assertTrue(vaultsData[0].hasFarm, "test_GetAllVaults::13");
        assertEq(vaultsData[0].farmData.farmId, 1, " test_GetAllVaults::14");
        assertEq(vaultsData[0].farmData.joePerSec, joePerSec, " test_GetAllVaults::15");
        assertEq(address(vaultsData[0].farmData.rewarder), address(0), " test_GetAllVaults::16");
        assertApproxEqRel(
            vaultsData[0].farmData.aptBalance,
            SimpleVault(payable(simpleVault1)).totalSupply(),
            1e16,
            " test_GetAllVaults::17"
        );
        assertApproxEqRel(vaultsData[0].farmData.aptBalanceUSD, 38e6, 1e16, " test_GetAllVaults::18");

        // simpleVault2
        assertEq(vaultsData[1].tokenX, joeAvalanche, "test_GetAllVaults::19");
        assertEq(vaultsData[1].tokenY, wavax, "test_GetAllVaults::20");
        assertEq(vaultsData[1].tokenXBalance, 0, "test_GetAllVaults::21");
        assertEq(vaultsData[1].tokenYBalance, 0, "test_GetAllVaults::22");
        assertApproxEqRel(vaultsData[1].vaultBalanceUSD, 0, 1e16, "test_GetAllVaults::23");
        assertEq(uint8(vaultsData[1].vaultType), uint8(IVaultFactory.VaultType.Simple), "test_GetAllVaults::24");
        assertFalse(vaultsData[1].hasFarm, "test_GetAllVaults::25");
        assertEq(vaultsData[1].farmData.farmId, 0, " test_GetAllVaults::26");
        assertEq(vaultsData[1].farmData.joePerSec, 0, " test_GetAllVaults::27");
        assertEq(address(vaultsData[1].farmData.rewarder), address(0), " test_GetAllVaults::28");
        assertApproxEqRel(vaultsData[1].farmData.aptBalance, 0, 1e16, " test_GetAllVaults::29");
        assertApproxEqRel(vaultsData[1].farmData.aptBalanceUSD, 0, 1e16, " test_GetAllVaults::30");

        // oracleVault
        assertEq(vaultsData[2].tokenX, usdt, "test_GetAllVaults::31");
        assertEq(vaultsData[2].tokenY, usdc, "test_GetAllVaults::32");
        assertEq(vaultsData[2].tokenXBalance, 0, "test_GetAllVaults::33");
        assertEq(vaultsData[2].tokenYBalance, 0, "test_GetAllVaults::34");
        assertApproxEqRel(vaultsData[2].vaultBalanceUSD, 0, 1e16, "test_GetAllVaults::35");
        assertEq(uint8(vaultsData[2].vaultType), uint8(IVaultFactory.VaultType.Oracle), "test_GetAllVaults::36");
        assertTrue(vaultsData[2].hasFarm, "test_GetAllVaults::37");
        assertEq(vaultsData[2].farmData.farmId, 0, " test_GetAllVaults::38");
        assertEq(vaultsData[2].farmData.joePerSec, joePerSec, " test_GetAllVaults::39");
        assertEq(address(vaultsData[2].farmData.rewarder), address(0), " test_GetAllVaults::40");
        assertApproxEqRel(vaultsData[2].farmData.aptBalance, 0, 1e16, " test_GetAllVaults::41");
        assertApproxEqRel(vaultsData[2].farmData.aptBalanceUSD, 0, 1e16, " test_GetAllVaults::42");
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
        APTFarmLens.VaultData[] memory farmsInfo = aptFarmLens.getAllFarms();

        assertEq(farmsInfo.length, 2, "test_GetAllFarms::1");

        assertEq(address(farmsInfo[0].vault), oracleVault, "test_GetAllFarms::2");
        assertEq(address(farmsInfo[1].vault), simpleVault1, "test_GetAllFarms::3");
    }

    function test_GetPaginatedFarms() public {
        APTFarmLens.VaultData[] memory farmsData = aptFarmLens.getPaginatedFarms(0, 10);

        assertEq(farmsData.length, 2, "test_GetPaginatedFarms::1");
        assertEq(address(farmsData[0].vault), oracleVault, "test_GetPaginatedFarms::2");
        assertEq(address(farmsData[1].vault), simpleVault1, "test_GetPaginatedFarms::3");

        farmsData = aptFarmLens.getPaginatedFarms(1, 1);
        assertEq(farmsData.length, 1, "test_GetPaginatedFarms::4");
        assertEq(address(farmsData[0].vault), simpleVault1, "test_GetPaginatedFarms::5");

        farmsData = aptFarmLens.getPaginatedFarms(10, 2);
        assertEq(farmsData.length, 0, "test_GetPaginatedFarms::6");
    }

    function test_GetAllVaultsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory vaultsDataWithUserInfo =
            aptFarmLens.getAllVaultsWithUserInfo(address(this));

        assertEq(vaultsDataWithUserInfo.length, 3, "test_GetAllVaultsWithUserInfo::1");

        assertEq(address(vaultsDataWithUserInfo[0].vaultData.vault), simpleVault1, "test_GetAllVaultsWithUserInfo::2");
        assertEq(address(vaultsDataWithUserInfo[1].vaultData.vault), simpleVault2, "test_GetAllVaultsWithUserInfo::3");
        assertEq(address(vaultsDataWithUserInfo[2].vaultData.vault), oracleVault, "test_GetAllVaultsWithUserInfo::4");

        assertApproxEqRel(
            vaultsDataWithUserInfo[0].vaultData.farmData.aptBalanceUSD, 38e6, 1e16, "test_GetAllVaultsWithUserInfo::5"
        );
        assertApproxEqRel(
            vaultsDataWithUserInfo[0].farmDataWithUserInfo.userBalanceUSD,
            38e6,
            1e16,
            "test_GetAllVaultsWithUserInfo::1"
        );
    }

    function test_GetPaginatedVaultsWithUSerInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsWithUserInfo(address(this), IVaultFactory.VaultType.Simple, 0, 10);

        assertEq(vaultsDataWithUserInfo.length, 2, "test_GetPaginatedVaultsWithUSerInfo::1");
        assertEq(
            address(vaultsDataWithUserInfo[0].vaultData.vault), simpleVault1, "test_GetPaginatedVaultsWithUSerInfo::2"
        );
        assertEq(
            address(vaultsDataWithUserInfo[1].vaultData.vault), simpleVault2, "test_GetPaginatedVaultsWithUSerInfo::3"
        );
        assertApproxEqRel(
            vaultsDataWithUserInfo[0].vaultData.farmData.aptBalanceUSD,
            38e6,
            1e16,
            "test_GetPaginatedVaultsWithUSerInfo::4"
        );

        vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsWithUserInfo(address(this), IVaultFactory.VaultType.Oracle, 0, 10);

        assertEq(vaultsDataWithUserInfo.length, 1, "test_GetPaginatedVaultsWithUSerInfo::5");
        assertEq(
            address(vaultsDataWithUserInfo[0].vaultData.vault), oracleVault, "test_GetPaginatedVaultsWithUSerInfo::6"
        );

        vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsWithUserInfo(address(this), IVaultFactory.VaultType.Simple, 1, 1);

        assertEq(vaultsDataWithUserInfo.length, 1, "test_GetPaginatedVaultsWithUSerInfo::7");
        assertEq(
            address(vaultsDataWithUserInfo[0].vaultData.vault), simpleVault2, "test_GetPaginatedVaultsWithUSerInfo::8"
        );

        vaultsDataWithUserInfo =
            aptFarmLens.getPaginatedVaultsWithUserInfo(address(this), IVaultFactory.VaultType.Oracle, 10, 10);

        assertEq(vaultsDataWithUserInfo.length, 0, "test_GetPaginatedVaultsWithUSerInfo::9");
    }

    function test_GetAllFarmsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory farmsDataWithUserInfo =
            aptFarmLens.getAllFarmsWithUserInfo(address(this));

        assertEq(farmsDataWithUserInfo.length, 2, "test_GetAllFarmsWithUserInfo::1");

        assertEq(address(farmsDataWithUserInfo[0].vaultData.vault), oracleVault, "test_GetAllFarmsWithUserInfo::2");
        assertEq(address(farmsDataWithUserInfo[1].vaultData.vault), simpleVault1, "test_GetAllFarmsWithUserInfo::3");

        assertApproxEqRel(
            farmsDataWithUserInfo[1].vaultData.farmData.aptBalanceUSD, 38e6, 1e16, "test_GetAllFarmsWithUserInfo::4"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[1].farmDataWithUserInfo.userBalanceUSD, 38e6, 1e16, "test_GetAllFarmsWithUserInfo::5"
        );
    }

    function test_GetPaginatedFarmsWithUserInfo() public {
        APTFarmLens.VaultDataWithUserInfo[] memory farmsDataWithUserInfo =
            aptFarmLens.getPaginatedFarmsWithUserInfo(address(this), 0, 10);

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
            38e6,
            1e16,
            "test_GetPaginatedFarmsWithUserInfo::6"
        );
        assertApproxEqRel(
            farmsDataWithUserInfo[1].farmDataWithUserInfo.userBalanceUSD,
            38e6,
            1e16,
            "test_GetPaginatedFarmsWithUserInfo::7"
        );

        farmsDataWithUserInfo = aptFarmLens.getPaginatedFarmsWithUserInfo(address(this), 1, 1);

        assertEq(farmsDataWithUserInfo.length, 1, "test_GetPaginatedFarmsWithUserInfo::8");
        assertEq(
            address(farmsDataWithUserInfo[0].vaultData.vault), simpleVault1, "test_GetPaginatedFarmsWithUserInfo::9"
        );

        farmsDataWithUserInfo = aptFarmLens.getPaginatedFarmsWithUserInfo(address(this), 10, 10);

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
