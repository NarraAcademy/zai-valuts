// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NarraLayerVault.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNarraLayerVault is Script {
    function run() external {
        vm.startBroadcast();

        // 部署 NarraLayerVault 实现合约
        NarraLayerVault implementation = new NarraLayerVault();
        console2.log(
            "NarraLayerVault implementation deployed at:",
            address(implementation)
        );

        // 初始化合约
        NarraLayerVault.InitParams memory settings = NarraLayerVault
            .InitParams({
                defaultAdmin: vm.envAddress("DEFAULT_ADMIN_ADDRESS"),
                rewardVaultFactory: vm.envAddress(
                    "REWARD_VAULT_FACTORY_ADDRESS"
                )
            });

        console2.log(
            "Default admin address:",
            vm.envAddress("DEFAULT_ADMIN_ADDRESS")
        );
        console2.log(
            "Reward vault factory address:",
            vm.envAddress("REWARD_VAULT_FACTORY_ADDRESS")
        );

        // 准备初始化数据
        bytes memory initData = abi.encodeWithSelector(
            NarraLayerVault.initialize.selector,
            settings
        );

        // 部署 UUPS 代理合约
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        // 获取代理合约的 NarraLayerVault 实例
        NarraLayerVault narraLayerVault = NarraLayerVault(address(proxy));

        // 设置质押和操作者
        narraLayerVault.setupStakingToken();

        // 输出部署的合约地址
        console2.log(
            "NarraLayerVault proxy deployed at:",
            address(narraLayerVault)
        );

        // staking token address
        console2.log(
            "Staking token address:",
            narraLayerVault.stakingTokenAddress()
        );

        // reward vault address
        console2.log("Reward vault address:", narraLayerVault.rewardVault());

        vm.stopBroadcast();
    }
}
