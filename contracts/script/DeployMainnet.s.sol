// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AgentTreasury} from "../src/AgentTreasury.sol";

/**
 * @title Deploy AgentTreasury to Ethereum Mainnet
 * @notice Uses real Lido stETH and wstETH contracts
 * @dev Run with: forge script script/DeployMainnet.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
 */
contract DeployMainnet is Script {
    // Real Lido mainnet addresses
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function run() external returns (AgentTreasury) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AgentTreasury treasury = new AgentTreasury(WSTETH, STETH);
        
        vm.stopBroadcast();
        
        return treasury;
    }
}