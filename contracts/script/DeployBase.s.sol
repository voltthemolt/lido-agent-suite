// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AgentTreasuryBase.sol";

/**
 * @title DeployBase
 * @notice Deploy AgentTreasuryBase to Base mainnet with bridged wstETH
 * 
 * Base mainnet addresses:
 * - wstETH (bridged from Ethereum): 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452
 * 
 * Run with:
 * forge script script/DeployBase.s.sol:DeployBase --rpc-url $BASE_RPC_URL --broadcast --verify
 */
contract DeployBase is Script {
    // Base mainnet addresses
    address constant WSTETH_BASE = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    
    function run() external returns (AgentTreasuryBase) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AgentTreasuryBase treasury = new AgentTreasuryBase(WSTETH_BASE);
        
        vm.stopBroadcast();
        
        console.log("AgentTreasuryBase deployed at:", address(treasury));
        console.log("wstETH (bridged):", WSTETH_BASE);
        
        return treasury;
    }
}
