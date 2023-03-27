// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./TestHelper.sol";

import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract APTFarmLensTest is TestHelper {
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant joeAvalanche = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    address wavax_usdc_20bp = 0xB5352A39C11a81FE6748993D586EC448A01f08b5;
    address usdt_usdc_1bp = 0x1D7A1a79e2b4Ef88D2323f3845246D24a3c20F1d;
    address joe_wavax_15bp = 0xc01961EdE437Bf0cC41D064B1a3F6F0ea6aa2a40;

    APTFarmLens aptFarmLens;
    VaultFactory vaultFactory;
    JoeDexLens joeDexLens;

    address strategy;
    address oracleVault;
    address simpleVault1;
    address simpleVault2;

    function setUp() public override {
        vm.createSelectFork(StdChains.getChain("avalanche").rpcUrl, 26_179_802);
        super.setUp();

        address implementation = address(new VaultFactory(wavax));
        vaultFactory = VaultFactory(address(new TransparentUpgradeableProxy(implementation, address(1), "")));
        vaultFactory.initialize(address(this));

        vaultFactory.setVaultImplementation(IVaultFactory.VaultType.Simple, address(new SimpleVault(vaultFactory)));
        vaultFactory.setVaultImplementation(IVaultFactory.VaultType.Oracle, address(new OracleVault(vaultFactory)));
        vaultFactory.setStrategyImplementation(IVaultFactory.StrategyType.Default, address(new Strategy(vaultFactory)));

        joeDexLens = new JoeDexLens(ILBFactory(address(0)),ILBLegacyFactory(address(1)),IJoeFactory(address(2)),wavax);
        aptFarmLens = new APTFarmLens(vaultFactory, aptFarm, joeDexLens);

        IAggregatorV3 dfX = IAggregatorV3(address(new MockAggregator()));
        IAggregatorV3 dfY = IAggregatorV3(address(new MockAggregator()));

        oracleVault = vaultFactory.createOracleVault(ILBPair(usdt_usdc_1bp), dfX, dfY);
        simpleVault1 = vaultFactory.createSimpleVault(ILBPair(wavax_usdc_20bp));
        simpleVault2 = vaultFactory.createSimpleVault(ILBPair(joe_wavax_15bp));

        _add(ERC20Mock(oracleVault), 1e18);
        _add(ERC20Mock(simpleVault1), 1e18);
        _add(ERC20Mock(simpleVault2), 1e18);

        strategy = vaultFactory.createDefaultStrategy(IBaseVault(simpleVault1));

        vm.mockCall(
            address(joeDexLens), abi.encodeWithSelector(JoeDexLens.getTokenPriceUSD.selector, wavax), abi.encode(20e18)
        );
        vm.mockCall(
            address(joeDexLens), abi.encodeWithSelector(JoeDexLens.getTokenPriceUSD.selector, usdc), abi.encode(1e18)
        );
        vm.mockCall(
            address(joeDexLens), abi.encodeWithSelector(JoeDexLens.getTokenPriceUSD.selector, usdt), abi.encode(1e18)
        );
    }

    function test_GetAllPoolsData() public {
        APTFarmLens.PoolVaultData[] memory poolsData = aptFarmLens.getAllPoolInfos();

        assertEq(poolsData.length, 3);

        assertEq(address(poolsData[0].vault), oracleVault);
        assertEq(address(poolsData[1].vault), simpleVault1);
        assertEq(address(poolsData[2].vault), simpleVault2);
    }

    function test_GetAllPoolsWithUserData() public {
        linkVaultToStrategy(simpleVault1, strategy);
        depositToVault(simpleVault1, address(this), 1e18, 20e6);
        _deposit(1, SimpleVault(payable(simpleVault1)).balanceOf(address(this)));

        APTFarmLens.PoolVaultDataWithUserInfo memory farmInfosWithUserData =
            aptFarmLens.getPoolWithUserInfo(1, address(this));

        (uint256 amountX, uint256 amountY) = SimpleVault(payable(simpleVault1)).previewAmounts(
            SimpleVault(payable(simpleVault1)).balanceOf(address(aptFarm))
        );

        console.log(amountX, amountY);

        console.log(farmInfosWithUserData.userBalanceUSD);
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
