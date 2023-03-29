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
        vaultFactory = VaultFactory(address(new TransparentUpgradeableProxy(implementation, address(1), "")));
        vaultFactory.initialize(address(this));

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
        APTFarmLens.VaultData[] memory poolsData = aptFarmLens.getAllVaults();

        assertEq(poolsData.length, 3, "test_GetAllVaults::1");

        assertEq(address(poolsData[0].vault), simpleVault1, "test_GetAllVaults::2");
        assertEq(address(poolsData[1].vault), simpleVault2, "test_GetAllVaults::3");
        assertEq(address(poolsData[2].vault), oracleVault, "test_GetAllVaults::4");

        // simpleVault1
        assertEq(poolsData[0].tokenX, wavax, "test_GetAllVaults::5");
        assertEq(poolsData[0].tokenY, usdc, "test_GetAllVaults::6");
        assertEq(poolsData[0].tokenXBalance, 1e18, "test_GetAllVaults::7");
        assertEq(poolsData[0].tokenYBalance, 20e6, "test_GetAllVaults::8");
        assertApproxEqRel(poolsData[0].vaultBalanceUSD, 38e6, 1e16, "test_GetAllVaults::9");
        assertEq(uint8(poolsData[0].vaultType), uint8(IVaultFactory.VaultType.Simple), "test_GetAllVaults::10");
        assertTrue(poolsData[0].hasFarm, "test_GetAllVaults::11");
        assertEq(poolsData[0].farmData.farmId, 1, " test_GetAllVaults::12 ");
        assertEq(poolsData[0].farmData.joePerSec, joePerSec, " test_GetAllVaults::13 ");
        assertEq(address(poolsData[0].farmData.rewarder), address(0), " test_GetAllVaults::14 ");
        assertApproxEqRel(
            poolsData[0].farmData.aptBalance,
            SimpleVault(payable(simpleVault1)).totalSupply(),
            1e16,
            " test_GetAllVaults::15 "
        );
        assertApproxEqRel(poolsData[0].farmData.aptBalanceUSD, 38e6, 1e16, " test_GetAllVaults::16 ");

        // simpleVault2
        assertEq(poolsData[1].tokenX, joeAvalanche, "test_GetAllVaults::17");
        assertEq(poolsData[1].tokenY, wavax, "test_GetAllVaults::18");
        assertEq(poolsData[1].tokenXBalance, 0, "test_GetAllVaults::19");
        assertEq(poolsData[1].tokenYBalance, 0, "test_GetAllVaults::20");
        assertApproxEqRel(poolsData[1].vaultBalanceUSD, 0, 1e16, "test_GetAllVaults::21");
        assertEq(uint8(poolsData[1].vaultType), uint8(IVaultFactory.VaultType.Simple), "test_GetAllVaults::22");
        assertFalse(poolsData[1].hasFarm, "test_GetAllVaults::23");
        assertEq(poolsData[1].farmData.farmId, 0, " test_GetAllVaults::24 ");
        assertEq(poolsData[1].farmData.joePerSec, 0, " test_GetAllVaults::25 ");
        assertEq(address(poolsData[1].farmData.rewarder), address(0), " test_GetAllVaults::26 ");
        assertApproxEqRel(poolsData[1].farmData.aptBalance, 0, 1e16, " test_GetAllVaults::27 ");
        assertApproxEqRel(poolsData[1].farmData.aptBalanceUSD, 0, 1e16, " test_GetAllVaults::28 ");

        // oracleVault
        assertEq(poolsData[2].tokenX, usdt, "test_GetAllVaults::29");
        assertEq(poolsData[2].tokenY, usdc, "test_GetAllVaults::30");
        assertEq(poolsData[2].tokenXBalance, 0, "test_GetAllVaults::31");
        assertEq(poolsData[2].tokenYBalance, 0, "test_GetAllVaults::32");
        assertApproxEqRel(poolsData[2].vaultBalanceUSD, 0, 1e16, "test_GetAllVaults::33");
        assertEq(uint8(poolsData[2].vaultType), uint8(IVaultFactory.VaultType.Oracle), "test_GetAllVaults::34");
        assertTrue(poolsData[2].hasFarm, "test_GetAllVaults::35");
        assertEq(poolsData[2].farmData.farmId, 0, " test_GetAllVaults::36 ");
        assertEq(poolsData[2].farmData.joePerSec, joePerSec, " test_GetAllVaults::37 ");
        assertEq(address(poolsData[2].farmData.rewarder), address(0), " test_GetAllVaults::38 ");
        assertApproxEqRel(poolsData[2].farmData.aptBalance, 0, 1e16, " test_GetAllVaults::39 ");
        assertApproxEqRel(poolsData[2].farmData.aptBalanceUSD, 0, 1e16, " test_GetAllVaults::40 ");
    }

    function test_GetAllPools() public {
        APTFarmLens.VaultData[] memory farmInfos = aptFarmLens.getAllPools();

        assertEq(farmInfos.length, 2, "test_GetAllPools::1");

        assertEq(address(farmInfos[0].vault), oracleVault, "test_GetAllPools::2");
        assertEq(address(farmInfos[1].vault), simpleVault1, "test_GetAllPools::3");
    }

    function test_GetAllVaultsWithUserData() public {
        APTFarmLens.VaultDataWithUserInfo[] memory farmInfosWithUserData =
            aptFarmLens.getAllVaultsWithUserInfo(address(this));

        assertEq(farmInfosWithUserData.length, 3, "test_GetAllVaultsWithUserData::1");

        assertEq(address(farmInfosWithUserData[0].vaultData.vault), simpleVault1, "test_GetAllVaultsWithUserData::2");
        assertEq(address(farmInfosWithUserData[1].vaultData.vault), simpleVault2, "test_GetAllVaultsWithUserData::3");
        assertEq(address(farmInfosWithUserData[2].vaultData.vault), oracleVault, "test_GetAllVaultsWithUserData::4");

        assertApproxEqRel(
            farmInfosWithUserData[0].vaultData.farmData.aptBalanceUSD, 38e6, 1e16, "test_GetAllVaultsWithUserData::5"
        );
        assertApproxEqRel(
            farmInfosWithUserData[0].farmDataWithUserInfo.userBalanceUSD, 38e6, 1e16, "test_GetAllPoolsWithUserData::1"
        );
    }

    function test_GetAllPoolsWithUserData() public {
        APTFarmLens.VaultDataWithUserInfo[] memory farmInfosWithUserData =
            aptFarmLens.getAllPoolsWithUserInfo(address(this));

        assertEq(farmInfosWithUserData.length, 2, "test_GetAllPoolsWithUserData::1");

        assertEq(address(farmInfosWithUserData[0].vaultData.vault), oracleVault, "test_GetAllPoolsWithUserData::2");
        assertEq(address(farmInfosWithUserData[1].vaultData.vault), simpleVault1, "test_GetAllPoolsWithUserData::3");

        assertApproxEqRel(
            farmInfosWithUserData[1].vaultData.farmData.aptBalanceUSD, 38e6, 1e16, "test_GetAllPoolsWithUserData::4"
        );
        assertApproxEqRel(
            farmInfosWithUserData[1].farmDataWithUserInfo.userBalanceUSD, 38e6, 1e16, "test_GetAllPoolsWithUserData::5"
        );
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
