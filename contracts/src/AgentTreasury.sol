// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title stETH Agent Treasury
 * @author Hermes Agent (Synthesis Hackathon)
 * @notice A smart contract that enables AI agents to manage stETH and spend yield
 *         while keeping principal locked and secure.
 * 
 * Key Features:
 * - Deposit stETH and earn staking yield
 * - Spend accumulated yield for agent operations (API calls, compute, etc.)
 * - Principal withdrawal with time-lock security
 * - Permission-controlled spending with allowlists
 * - ERC-8004 agent identity integration
 */
interface IstETH is IERC20 {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 _pooledEthAmount) external view returns (uint256);
    function sharesOf(address _account) external view returns (uint256);
}

interface IWstETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function stETH() external view returns (address);
}

/**
 * @notice Events for transparency and tracking
 */
contract AgentTreasuryEvents {
    event Deposited(address indexed agent, uint256 stETHAmount, uint256 principalAmount);
    event YieldSpent(address indexed agent, address indexed recipient, uint256 amount, string purpose);
    event PrincipalWithdrawn(address indexed agent, uint256 amount);
    event WithdrawalInitiated(address indexed agent, uint256 amount, uint256 unlockTime);
    event SpendingAllowlisted(address indexed recipient, string service);
    event SpendingDelisted(address indexed recipient);
    event AgentRegistered(address indexed agent, uint256 erc8004Id);
}

/**
 * @notice Main Treasury Contract
 */
contract AgentTreasury is Ownable, ReentrancyGuard, AgentTreasuryEvents {
    
    // ============ State Variables ============
    
    /// @notice The wstETH token contract
    IWstETH public immutable wstETH;
    
    /// @notice The stETH token contract
    IstETH public immutable stETH;
    
    /// @notice Time lock duration for principal withdrawals (7 days)
    uint256 public constant WITHDRAWAL_LOCK = 7 days;
    
    /// @notice Minimum deposit to open a treasury (prevent dust)
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    
    /// @notice Mapping of agent addresses to their treasury info
    mapping(address => AgentTreasuryInfo) public treasuries;
    
    /// @notice Mapping of pending withdrawals
    mapping(address => PendingWithdrawal) public pendingWithdrawals;
    
    /// @notice Allowlisted recipients for yield spending
    mapping(address => bool) public spendingAllowlist;
    
    /// @notice Mapping for ERC-8004 agent identities
    mapping(address => uint256) public agentERC8004Id;
    
    /// @notice Total principal locked across all agents
    uint256 public totalPrincipal;
    
    // ============ Structs ============
    
    struct AgentTreasuryInfo {
        uint256 principalShares;    // wstETH shares representing principal
        uint256 lastYieldAccrued;   // wstETH balance at last interaction
        uint256 totalYieldSpent;    // cumulative yield spent
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
        require(treasuries[msg.sender].exists, "No treasury exists for agent");
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _wstETH,
        address _stETH
    ) Ownable(msg.sender) {
        wstETH = IWstETH(_wstETH);
        stETH = IstETH(_stETH);
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Deposit stETH to open or add to an agent treasury
     * @param amount The amount of stETH to deposit
     * @param erc8004Id Optional ERC-8004 agent identity
     */
    function deposit(uint256 amount, uint256 erc8004Id) external nonReentrant {
        require(amount >= MIN_DEPOSIT, "Amount below minimum deposit");
        
        // Transfer stETH from sender
        require(stETH.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Approve wstETH to spend our stETH for wrapping
        stETH.approve(address(wstETH), amount);
        
        // Wrap to wstETH for yield accumulation
        uint256 wstETHAmount = wstETH.wrap(amount);
        
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        if (!treasury.exists) {
            // New treasury
            treasury.principalShares = wstETHAmount;
            treasury.lastYieldAccrued = wstETHAmount;
            treasury.exists = true;
            treasury.depositTimestamp = block.timestamp;
            
            if (erc8004Id > 0) {
                agentERC8004Id[msg.sender] = erc8004Id;
                emit AgentRegistered(msg.sender, erc8004Id);
            }
        } else {
            // Existing treasury - check for accrued yield first
            _accrueYield(treasury);
            treasury.principalShares += wstETHAmount;
        }
        
        totalPrincipal += wstETHAmount;
        
        emit Deposited(msg.sender, amount, wstETHAmount);
    }
    
    /**
     * @notice Spend accumulated yield on allowlisted services
     * @param recipient The service provider address
     * @param amount Amount of yield to spend (in stETH)
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
        
        // Unwrap needed amount and transfer
        uint256 wstETHNeeded = wstETH.getWstETHByStETH(amount);
        
        // Approve wstETH for unwrapping (for our mock; real wstETH doesn't need this)
        wstETH.approve(address(wstETH), wstETHNeeded);
        
        uint256 stETHAmount = wstETH.unwrap(wstETHNeeded);
        require(stETH.transfer(recipient, stETHAmount), "Transfer failed");
        
        emit YieldSpent(msg.sender, recipient, amount, purpose);
    }
    
    /**
     * @notice Initiate a principal withdrawal (subject to time lock)
     * @param amount Amount of principal to withdraw
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
        
        uint256 sharesToWithdraw = withdrawal.amount;
        treasury.principalShares -= sharesToWithdraw;
        totalPrincipal -= sharesToWithdraw;
        
        // Approve for unwrap
        wstETH.approve(address(wstETH), sharesToWithdraw);
        
        // Unwrap and transfer
        uint256 stETHAmount = wstETH.unwrap(sharesToWithdraw);
        require(stETH.transfer(msg.sender, stETHAmount), "Transfer failed");
        
        emit PrincipalWithdrawn(msg.sender, stETHAmount);
        
        // Clear pending withdrawal
        delete pendingWithdrawals[msg.sender];
    }
    
    /**
     * @notice Cancel a pending withdrawal
     */
    function cancelWithdrawal() external hasTreasury {
        require(pendingWithdrawals[msg.sender].exists, "No pending withdrawal");
        delete pendingWithdrawals[msg.sender];
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Add address to spending allowlist
     * @param recipient Address to allowlist
     * @param service Description of the service
     */
    function allowlistSpending(address recipient, string calldata service) external onlyOwner {
        spendingAllowlist[recipient] = true;
        emit SpendingAllowlisted(recipient, service);
    }
    
    /**
     * @notice Remove address from spending allowlist
     * @param recipient Address to remove
     */
    function delistSpending(address recipient) external onlyOwner {
        spendingAllowlist[recipient] = false;
        emit SpendingDelisted(recipient);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get the available yield for an agent to spend
     * @param agent The agent address
     * @return Available yield in stETH terms
     */
    function getAvailableYield(address agent) public view returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        
        if (!treasury.exists) return 0;
        
        // Current wstETH balance attributed to this agent
        uint256 currentBalance = wstETH.balanceOf(address(this)) * treasury.principalShares / totalPrincipal;
        
        // Yield = current - principal - already spent
        if (currentBalance <= treasury.principalShares + treasury.totalYieldSpent) {
            return 0;
        }
        
        return wstETH.getStETHByWstETH(
            currentBalance - treasury.principalShares - treasury.totalYieldSpent
        );
    }
    
    /**
     * @notice Get treasury info for an agent
     * @param agent The agent address
     */
    function getTreasuryInfo(address agent) external view returns (
        uint256 principalShares,
        uint256 principalStETH,
        uint256 availableYield,
        uint256 totalYieldSpent,
        bool exists
    ) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        
        return (
            treasury.principalShares,
            wstETH.getStETHByWstETH(treasury.principalShares),
            getAvailableYield(agent),
            treasury.totalYieldSpent,
            treasury.exists
        );
    }
    
    /**
     * @notice Check if a withdrawal is ready
     * @param agent The agent address
     */
    function isWithdrawalReady(address agent) external view returns (bool) {
        PendingWithdrawal storage withdrawal = pendingWithdrawals[agent];
        return withdrawal.exists && block.timestamp >= withdrawal.unlockTime;
    }
    
    // ============ Internal Functions ============
    
    function _accrueYield(AgentTreasuryInfo storage treasury) internal {
        uint256 contractBalance = wstETH.balanceOf(address(this));
        
        // Calculate this agent's share of any yield
        uint256 agentShare = contractBalance * treasury.principalShares / totalPrincipal;
        
        if (agentShare > treasury.lastYieldAccrued) {
            // Yield has accumulated
            treasury.lastYieldAccrued = agentShare;
        }
    }
}
