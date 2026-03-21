// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AgentTreasuryV4} from "../src/AgentTreasuryV4.sol";

contract DeployBaseV4 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Base mainnet addresses
        address wstETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
        address swapRouter = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02
        address weth = 0x4200000000000000000000000000000000000006;
        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        // Current L1 stEthPerToken rate (queried from mainnet)
        uint256 initialRate = 1229900097456171436; // ~1.2299 stETH per wstETH

        vm.startBroadcast(deployerPrivateKey);

        AgentTreasuryV4 treasury = new AgentTreasuryV4(
            wstETH,
            swapRouter,
            weth,
            usdc,
            initialRate
        );

        vm.stopBroadcast();
    }
}
