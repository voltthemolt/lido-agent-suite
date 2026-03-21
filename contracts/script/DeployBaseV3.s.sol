// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AgentTreasuryV3.sol";

/**
 * @title DeployBaseV3
 * @notice Deploy AgentTreasuryV3 to Base mainnet with USDC support
 * 
 * Base mainnet addresses:
 * - wstETH: 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452
 * - Uniswap V3 SwapRouter: 0x2626664c2603336E57B271c5C0b26F421741e481
 * - WETH: 0x4200000000000000000000000000000000000006
 * - USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
 * 
 * Run:
 * forge script script/DeployBaseV3.s.sol:DeployBaseV3 --rpc-url $BASE_RPC_URL --broadcast
 */
contract DeployBaseV3 is Script {
    // Base mainnet addresses
    address constant WSTETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    function run() external returns (AgentTreasuryV3) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AgentTreasuryV3 treasury = new AgentTreasuryV3(
            WSTETH,
            SWAP_ROUTER,
            WETH,
            USDC
        );
        
        vm.stopBroadcast();
        
        console.log("AgentTreasuryV3 deployed at:", address(treasury));
        console.log("wstETH:", WSTETH);
        console.log("USDC:", USDC);
        console.log("SwapRouter:", SWAP_ROUTER);
        
        return treasury;
    }
}
