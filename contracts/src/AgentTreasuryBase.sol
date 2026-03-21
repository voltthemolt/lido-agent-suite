// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title wstETH Agent Treasury (Base L2 Version)
 * @author Hermes Agent (Synthesis Hackathon)
 * @notice A smart contract that enables AI agents to manage wstETH and spend yield
 *         while keeping principal locked and secure.
 * 
 * This version is for L2s (Base, Arbitrum, Optimism) where only bridged wstETH
 * exists - no stETH. Users deposit wstETH directly.
 * 
 * Key Features:
 * - Deposit wstETH directly and earn staking yield (wstETH appreciates vs stETH)
 * - Spend accumulated yield for agent operations (API calls, compute, etc.)
 * - Principal withdrawal with time-lock security
 * - Permission-controlled spending with allowlists
 * - ERC-8004 agent identity integration
 */
interface IWstETH is IERC20 {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}

/**
 * @notice Events for transparency and tracking
 */
contract AgentTreasuryBaseEvents {
    event Deposited(address indexed agent, uint256 wstETHAmount);
    event YieldSpent(address indexed agent, address indexed recipient, uint256 amount, string purpose);
    event PrincipalWithdrawn(address indexed agent, uint256 amount);
    event WithdrawalInitiated(address indexed agent, uint256 amount, uint256 unlockTime);
    event WithdrawalCancelled(address indexed agent);
    event SpendingAllowlisted(address indexed recipient, string service);
    event SpendingDelisted(address indexed recipient);
    event AgentRegistered(address indexed agent, uint256 erc8004Id);
}

/**
 * @notice Main Treasury Contract for Base L2
 */
contract AgentTreasuryBase is Ownable, ReentrancyGuard, AgentTreasuryBaseEvents {
    
    // ============ State Variables ============
    
    /// @notice The wstETH token contract (bridged from Ethereum)
    IWstETH public immutable wstETH;
    
    /// @notice Time lock duration for principal withdrawals (7 days)
    uint256 public constant WITHDRAWAL_LOCK = 7 days;
    
    /// @notice Minimum deposit to open a treasury (prevent dust)
    uint256 public constant MIN_DEPOSIT = 0.001 ether; // 0.001 wstETH
    
    /// @notice Mapping of agent addresses to their treasury info
    mapping(address => AgentTreasuryInfo) public treasuries;
    
    /// @notice Mapping of pending withdrawals
    mapping(address => PendingWithdrawal) public pendingWithdrawals;
    
    /// @notice Allowlisted recipients for yield spending
    mapping(address => bool) public spendingAllowlist;
    
    /// @notice Service names for allowlisted recipients
    mapping(address => string) public serviceProviderNames;
    
    /// @notice Mapping for ERC-8004 agent identities
    mapping(address => uint256) public agentERC8004Id;
    
    /// @notice Total principal locked across all agents (in wstETH)
    uint256 public totalPrincipal;
    
    // ============ Structs ============
    
    struct AgentTreasuryInfo {
        uint256 principalShares;    // wstETH amount representing principal
        uint256 lastYieldAccrued;   // wstETH value at last interaction
        uint256 totalYieldSpent;    // cumulative yield spent (in wstETH)
        uint256 depositTimestamp;   // when deposit was made
        bool exists;
    }
    
    struct PendingWithdrawal {
        uint256 amount;
        uint256 unlockTime;
        bool exists;
    }
    
    // ============ Modifiers ============
    
    modifier onlyAllowlisted(address recipient) {
        require(spendingAllowlist[recipient], "Recipient not allowlisted");
        _;
    }
    
    modifier hasTreasury() {
        require(treasuries[msg.sender].exists, "No treasury found");
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _wstETH) Ownable(msg.sender) {
        require(_wstETH != address(0), "Invalid wstETH address");
        wstETH = IWstETH(_wstETH);
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Add a recipient to the spending allowlist
     * @param recipient Address to allowlist
     * @param serviceName Name of the service provider
     */
    function allowlistSpending(address recipient, string calldata serviceName) 
        external 
        onlyOwner 
    {
        spendingAllowlist[recipient] = true;
        serviceProviderNames[recipient] = serviceName;
        emit SpendingAllowlisted(recipient, serviceName);
    }
    
    /**
     * @notice Remove a recipient from the spending allowlist
     * @param recipient Address to remove
     */
    function delistSpending(address recipient) external onlyOwner {
        spendingAllowlist[recipient] = false;
        emit SpendingDelisted(recipient);
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Deposit wstETH to open or add to an agent treasury
     * @param amount The amount of wstETH to deposit
     * @param erc8004Id Optional ERC-8004 agent identity
     */
    function deposit(uint256 amount, uint256 erc8004Id) external nonReentrant {
        require(amount >= MIN_DEPOSIT, "Amount below minimum deposit");
        
        // Transfer wstETH directly from sender
        require(wstETH.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        if (!treasury.exists) {
            // New treasury
            treasury.principalShares = amount;
            treasury.lastYieldAccrued = amount;
            treasury.exists = true;
            treasury.depositTimestamp = block.timestamp;
            
            if (erc8004Id > 0) {
                agentERC8004Id[msg.sender] = erc8004Id;
                emit AgentRegistered(msg.sender, erc8004Id);
            }
        } else {
            // Existing treasury - check for accrued yield first
            _accrueYield(treasury);
            treasury.principalShares += amount;
        }
        
        totalPrincipal += amount;
        
        emit Deposited(msg.sender, amount);
    }
    
    /**
     * @notice Spend accumulated yield on allowlisted services
     * @param recipient The service provider address
     * @param amount Amount of yield to spend (in wstETH)
     * @param purpose Description of what's being paid for
     */
    function spendYield(
        address recipient,
        uint256 amount,
        string calldata purpose
    ) 
        external 
        nonReentrant 
        hasTreasury 
        onlyAllowlisted(recipient) 
    {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        // Calculate available yield
        uint256 availableYield = getAvailableYield(msg.sender);
        require(availableYield >= amount, "Insufficient yield");
        
        // Update yield tracking
        treasury.lastYieldAccrued = wstETH.balanceOf(address(this)) - totalPrincipal + treasury.totalYieldSpent;
        treasury.totalYieldSpent += amount;
        
        // Transfer wstETH directly to recipient
        require(wstETH.transfer(recipient, amount), "Transfer failed");
        
        emit YieldSpent(msg.sender, recipient, amount, purpose);
    }
    
    /**
     * @notice Initiate a principal withdrawal (subject to time lock)
     * @param amount Amount of principal to withdraw (in wstETH)
     */
    function initiateWithdrawal(uint256 amount) external nonReentrant hasTreasury {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        require(treasury.principalShares >= amount, "Insufficient principal");
        require(!pendingWithdrawals[msg.sender].exists, "Withdrawal already pending");
        
        uint256 unlockTime = block.timestamp + WITHDRAWAL_LOCK;
        
        pendingWithdrawals[msg.sender] = PendingWithdrawal({
            amount: amount,
            unlockTime: unlockTime,
            exists: true
        });
        
        emit WithdrawalInitiated(msg.sender, amount, unlockTime);
    }
    
    /**
     * @notice Complete a pending withdrawal after time lock
     */
    function completeWithdrawal() external nonReentrant hasTreasury {
        PendingWithdrawal storage withdrawal = pendingWithdrawals[msg.sender];
        
        require(withdrawal.exists, "No pending withdrawal");
        require(block.timestamp >= withdrawal.unlockTime, "Time lock not expired");
        
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        uint256 amount = withdrawal.amount;
        treasury.principalShares -= amount;
        totalPrincipal -= amount;
        
        // Clear pending withdrawal
        delete pendingWithdrawals[msg.sender];
        
        // Transfer wstETH directly
        require(wstETH.transfer(msg.sender, amount), "Transfer failed");
        
        emit PrincipalWithdrawn(msg.sender, amount);
    }
    
    /**
     * @notice Cancel a pending withdrawal
     */
    function cancelWithdrawal() external nonReentrant hasTreasury {
        require(pendingWithdrawals[msg.sender].exists, "No pending withdrawal");
        
        emit WithdrawalCancelled(msg.sender);
        delete pendingWithdrawals[msg.sender];
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get available yield for an agent
     * @param agent Agent address
     * @return Available yield in wstETH
     */
    function getAvailableYield(address agent) public view returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists) return 0;
        
        // Current contract balance minus total principal = total yield
        uint256 contractBalance = wstETH.balanceOf(address(this));
        uint256 totalYield = contractBalance - totalPrincipal;
        
        // Agent's share of yield based on their principal ratio
        if (totalPrincipal == 0) return 0;
        uint256 agentShare = (totalYield * treasury.principalShares) / totalPrincipal;
        
        // Add back their spent yield (they already "spent" it, so don't double count)
        return agentShare + treasury.totalYieldSpent - (treasury.lastYieldAccrued - treasury.principalShares);
    }
    
    /**
     * @notice Get full treasury info for an agent
     * @param agent Agent address
     * @return principal Principal amount in wstETH
     * @return availableYield Available yield in wstETH
     * @return totalYieldSpent Total yield spent
     * @return depositTime Timestamp of initial deposit
     * @return exists Whether treasury exists
     */
    function getTreasuryInfo(address agent) external view returns (
        uint256 principal,
        uint256 availableYield,
        uint256 totalYieldSpent,
        uint256 depositTime,
        bool exists
    ) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        return (
            treasury.principalShares,
            getAvailableYield(agent),
            treasury.totalYieldSpent,
            treasury.depositTimestamp,
            treasury.exists
        );
    }
    
    /**
     * @notice Check if a withdrawal is ready
     * @param agent Agent address
     * @return ready Whether withdrawal can be completed
     */
    function isWithdrawalReady(address agent) external view returns (bool) {
        PendingWithdrawal storage withdrawal = pendingWithdrawals[agent];
        return withdrawal.exists && block.timestamp >= withdrawal.unlockTime;
    }
    
    /**
     * @notice Get withdrawal info
     * @param agent Agent address
     * @return amount Amount pending
     * @return unlockTime When it can be withdrawn
     * @return ready Whether it's ready
     */
    function getWithdrawalInfo(address agent) external view returns (
        uint256 amount,
        uint256 unlockTime,
        bool ready
    ) {
        PendingWithdrawal storage withdrawal = pendingWithdrawals[agent];
        return (
            withdrawal.amount,
            withdrawal.unlockTime,
            withdrawal.exists && block.timestamp >= withdrawal.unlockTime
        );
    }
    
    // ============ Internal Functions ============
    
    /**
     * @dev Accrue yield for an existing treasury
     */
    function _accrueYield(AgentTreasuryInfo storage treasury) internal {
        uint256 contractBalance = wstETH.balanceOf(address(this));
        uint256 totalYield = contractBalance - totalPrincipal;
        
        if (totalPrincipal > 0 && totalYield > 0) {
            // Update last accrued to reflect current state
            uint256 agentShare = (totalYield * treasury.principalShares) / totalPrincipal;
            treasury.lastYieldAccrued = treasury.principalShares + agentShare;
        }
    }
}
