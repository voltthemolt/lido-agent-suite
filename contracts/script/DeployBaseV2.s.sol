// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AgentTreasuryV2.sol";

/**
 * @title DeployBaseV2
 * @notice Deploy AgentTreasuryV2 to Base mainnet with Uniswap integration
 * 
 * Base mainnet addresses:
 * - wstETH (bridged from Ethereum): 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452
 * - Uniswap V3 SwapRouter: 0x2626664c2603336E57B271c5C0b26F421741e481
 * - WETH: 0x4200000000000000000000000000000000000006
 * 
 * Run with:
 * forge script script/DeployBaseV2.s.sol:DeployBaseV2 --rpc-url $BASE_RPC_URL --broadcast
 */
contract DeployBaseV2 is Script {
    // Base mainnet addresses
    address constant WSTETH_BASE = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    
    function run() external returns (AgentTreasuryV2) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AgentTreasuryV2 treasury = new AgentTreasuryV2(
            WSTETH_BASE,
            UNISWAP_ROUTER,
            WETH_BASE
        );
        
        vm.stopBroadcast();
        
        console.log("AgentTreasuryV2 deployed at:", address(treasury));
        console.log("wstETH (bridged):", WSTETH_BASE);
        console.log("Uniswap Router:", UNISWAP_ROUTER);
        console.log("WETH:", WETH_BASE);
        
        return treasury;
    }
}
