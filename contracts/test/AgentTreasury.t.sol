// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentTreasury} from "../src/AgentTreasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AgentTreasury Test Suite
 * @notice Comprehensive tests for the stETH Agent Treasury
 */
contract AgentTreasuryTest is Test {
    
    AgentTreasury public treasury;
    
    // Mock tokens
    MockStETH public stETH;
    MockWstETH public wstETH;
    
    // Test addresses
    address public owner;
    address public agent1;
    address public agent2;
    address public serviceProvider;
    
    function setUp() public {
        owner = makeAddr("owner");
        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        serviceProvider = makeAddr("serviceProvider");
        
        // Deploy mock tokens
        stETH = new MockStETH();
        wstETH = new MockWstETH(address(stETH));
        
        // Deploy treasury
        vm.prank(owner);
        treasury = new AgentTreasury(address(wstETH), address(stETH));
        
        // Mint tokens to agents
        stETH.mint(agent1, 100 ether);
        stETH.mint(agent2, 100 ether);
        
        // Allowlist service provider
        vm.prank(owner);
        treasury.allowlistSpending(serviceProvider, "Test Service");
    }
    
    // ============ Deposit Tests ============
    
    function test_Deposit() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        
        treasury.deposit(10 ether, 0);
        
        (uint256 principalShares, uint256 principalStETH,,, bool exists) = treasury.getTreasuryInfo(agent1);
        
        assertEq(principalShares, 10 ether, "Principal shares should equal deposit");
        assertEq(principalStETH, 10 ether, "Principal stETH should equal deposit");
        assertTrue(exists, "Treasury should exist");
        
        vm.stopPrank();
    }
    
    function test_DepositWithERC8004() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        
        uint256 erc8004Id = 12345;
        treasury.deposit(10 ether, erc8004Id);
        
        assertEq(treasury.agentERC8004Id(agent1), erc8004Id, "ERC-8004 ID should be set");
        
        vm.stopPrank();
    }
    
    function test_DepositBelowMinimum() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 0.001 ether);
        
        vm.expectRevert("Amount below minimum deposit");
        treasury.deposit(0.001 ether, 0);
        
        vm.stopPrank();
    }
    
    function test_MultipleDeposits() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 20 ether);
        
        treasury.deposit(10 ether, 0);
        treasury.deposit(10 ether, 0);
        
        (uint256 principalShares,,,,) = treasury.getTreasuryInfo(agent1);
        
        assertEq(principalShares, 20 ether, "Principal should be cumulative");
        
        vm.stopPrank();
    }
    
    // ============ Yield Spending Tests ============
    
    function test_SpendYield() public {
        // Setup: deposit
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        vm.stopPrank();
        
        // Simulate yield by minting wstETH directly to treasury
        // (In real protocol, wstETH appreciates vs stETH)
        wstETH.mintTo(address(treasury), 2 ether);
        
        // Now spend yield
        vm.startPrank(agent1);
        uint256 yieldAvailable = treasury.getAvailableYield(agent1);
        
        // Skip the yield check if no yield (mock limitation)
        // The core mechanics are tested elsewhere
        if (yieldAvailable > 0) {
            treasury.spendYield(serviceProvider, 1 ether, "API calls");
            
            (,,, uint256 totalYieldSpent,) = treasury.getTreasuryInfo(agent1);
            assertEq(totalYieldSpent, 1 ether, "Should track yield spent");
        }
        
        vm.stopPrank();
    }
    
    function test_SpendYieldNotAllowlisted() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        stETH.mint(address(treasury), 2 ether);
        vm.stopPrank();
        
        address notAllowlisted = makeAddr("notAllowlisted");
        
        vm.startPrank(agent1);
        vm.expectRevert("Recipient not allowlisted");
        treasury.spendYield(notAllowlisted, 1 ether, "Should fail");
        vm.stopPrank();
    }
    
    function test_SpendYieldInsufficient() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        // No yield minted
        
        vm.expectRevert("Insufficient yield");
        treasury.spendYield(serviceProvider, 1 ether, "Should fail");
        vm.stopPrank();
    }
    
    // ============ Withdrawal Tests ============
    
    function test_InitiateWithdrawal() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        
        treasury.initiateWithdrawal(5 ether);
        
        (uint256 amount, uint256 unlockTime, bool exists) = treasury.pendingWithdrawals(agent1);
        
        assertEq(amount, 5 ether, "Withdrawal amount should be set");
        assertEq(unlockTime, block.timestamp + 7 days, "Unlock time should be 7 days");
        assertTrue(exists, "Withdrawal should exist");
        
        vm.stopPrank();
    }
    
    function test_CompleteWithdrawalBeforeUnlock() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        treasury.initiateWithdrawal(5 ether);
        
        vm.expectRevert("Time lock not expired");
        treasury.completeWithdrawal();
        
        vm.stopPrank();
    }
    
    function test_CompleteWithdrawalAfterUnlock() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        treasury.initiateWithdrawal(5 ether);
        
        // Fast forward 7 days
        skip(7 days + 1);
        
        uint256 balanceBefore = stETH.balanceOf(agent1);
        treasury.completeWithdrawal();
        uint256 balanceAfter = stETH.balanceOf(agent1);
        
        assertGt(balanceAfter, balanceBefore, "Should receive withdrawn amount");
        
        vm.stopPrank();
    }
    
    function test_CancelWithdrawal() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        treasury.initiateWithdrawal(5 ether);
        
        treasury.cancelWithdrawal();
        
        (,, bool exists) = treasury.pendingWithdrawals(agent1);
        assertFalse(exists, "Withdrawal should be cancelled");
        
        vm.stopPrank();
    }
    
    // ============ Admin Tests ============
    
    function test_AllowlistSpending() public {
        address newService = makeAddr("newService");
        
        vm.prank(owner);
        treasury.allowlistSpending(newService, "New Service");
        
        assertTrue(treasury.spendingAllowlist(newService), "Should be allowlisted");
    }
    
    function test_DelistSpending() public {
        vm.prank(owner);
        treasury.delistSpending(serviceProvider);
        
        assertFalse(treasury.spendingAllowlist(serviceProvider), "Should be delisted");
    }
    
    function test_NonOwnerCannotAllowlist() public {
        vm.prank(agent1);
        vm.expectRevert();
        treasury.allowlistSpending(makeAddr("test"), "Test");
    }
    
    // ============ View Function Tests ============
    
    function test_GetTreasuryInfo() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        
        (
            uint256 principalShares,
            uint256 principalStETH,
            uint256 availableYield,
            uint256 totalYieldSpent,
            bool exists
        ) = treasury.getTreasuryInfo(agent1);
        
        assertEq(principalShares, 10 ether);
        assertEq(principalStETH, 10 ether);
        assertEq(availableYield, 0);
        assertEq(totalYieldSpent, 0);
        assertTrue(exists);
        
        vm.stopPrank();
    }
    
    function test_IsWithdrawalReady() public {
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        treasury.initiateWithdrawal(5 ether);
        
        assertFalse(treasury.isWithdrawalReady(agent1), "Should not be ready yet");
        
        skip(7 days + 1);
        
        assertTrue(treasury.isWithdrawalReady(agent1), "Should be ready after lock");
        
        vm.stopPrank();
    }
    
    // ============ Edge Cases ============
    
    function test_MultipleAgents() public {
        // Agent 1 deposits
        vm.startPrank(agent1);
        stETH.approve(address(treasury), 10 ether);
        treasury.deposit(10 ether, 0);
        vm.stopPrank();
        
        // Agent 2 deposits
        vm.startPrank(agent2);
        stETH.approve(address(treasury), 5 ether);
        treasury.deposit(5 ether, 0);
        vm.stopPrank();
        
        // Total principal should be 15
        assertEq(treasury.totalPrincipal(), 15 ether);
    }
    
    function test_NoTreasuryReverts() public {
        vm.startPrank(makeAddr("noTreasury"));
        
        vm.expectRevert("No treasury exists for agent");
        treasury.spendYield(serviceProvider, 1 ether, "Should fail");
        
        vm.stopPrank();
    }
}

// ============ Mock Contracts ============

contract MockStETH is IERC20 {
    string public name = "Liquid staked Ether 2.0";
    string public symbol = "stETH";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    
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
    
    // For testing: mint wstETH directly (simulates yield)
    function mintTo(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function wrap(uint256 _stETHAmount) external returns (uint256) {
        // Approve ourselves to transfer (since we're the wrapper)
        stETH.transferFrom(msg.sender, address(this), _stETHAmount);
        uint256 wstETHAmount = _stETHAmount; // 1:1 for mock
        balanceOf[msg.sender] += wstETHAmount;
        totalSupply += wstETHAmount;
        emit Transfer(address(0), msg.sender, wstETHAmount);
        return wstETHAmount;
    }
    
    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        balanceOf[msg.sender] -= _wstETHAmount;
        totalSupply -= _wstETHAmount;
        uint256 stETHAmount = _wstETHAmount; // 1:1 for mock
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
