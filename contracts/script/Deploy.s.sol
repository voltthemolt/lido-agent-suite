// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AgentTreasury} from "../src/AgentTreasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Deploy.s.sol
 * @notice Deployment script for Base Sepolia testnet
 * Deploys mock stETH/wstETH and AgentTreasury
 */
contract DeployScript is Script {
    
    // Mock contracts for testnet (Lido doesn't exist on Base Sepolia)
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy mock stETH
        MockStETH stETH = new MockStETH();
        console.log("MockStETH deployed at:", address(stETH));
        
        // 2. Deploy mock wstETH
        MockWstETH wstETH = new MockWstETH(address(stETH));
        console.log("MockWstETH deployed at:", address(wstETH));
        
        // 3. Deploy AgentTreasury
        AgentTreasury treasury = new AgentTreasury(address(wstETH), address(stETH));
        console.log("AgentTreasury deployed at:", address(treasury));
        
        vm.stopBroadcast();
    }
}

// ============ Mock Contracts ============

contract MockStETH is IERC20 {
    string public name = "Liquid staked Ether 2.0";
    string public symbol = "stETH";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockWstETH is IERC20 {
    string public name = "Wrapped liquid staked Ether 2.0";
    string public symbol = "wstETH";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    
    MockStETH public stETH;
    
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(address _stETH) {
        stETH = MockStETH(_stETH);
    }
    
    function mintTo(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function wrap(uint256 _stETHAmount) external returns (uint256) {
        stETH.transferFrom(msg.sender, address(this), _stETHAmount);
        uint256 wstETHAmount = _stETHAmount;
        balanceOf[msg.sender] += wstETHAmount;
        totalSupply += wstETHAmount;
        emit Transfer(address(0), msg.sender, wstETHAmount);
        return wstETHAmount;
    }
    
    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        balanceOf[msg.sender] -= _wstETHAmount;
        totalSupply -= _wstETHAmount;
        uint256 stETHAmount = _wstETHAmount;
        stETH.transfer(msg.sender, stETHAmount);
        emit Transfer(msg.sender, address(0), _wstETHAmount);
        return stETHAmount;
    }
    
    function getStETHByWstETH(uint256 _wstETHAmount) external pure returns (uint256) {
        return _wstETHAmount;
    }
    
    function getWstETHByStETH(uint256 _stETHAmount) external pure returns (uint256) {
        return _stETHAmount;
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
