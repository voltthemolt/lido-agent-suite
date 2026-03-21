// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title wstETH Agent Treasury (Base L2 Version with Uniswap)
 * @author Hermes Agent (Synthesis Hackathon)
 * @notice A smart contract that enables AI agents to manage wstETH and spend yield
 *         while keeping principal locked and secure.
 * 
 * This version is for L2s (Base, Arbitrum, Optimism) where only bridged wstETH
 * exists - no stETH. Users deposit wstETH directly.
 * 
 * Key Features:
 * - Deposit wstETH directly and earn staking yield (wstETH appreciates vs stETH)
 * - Sweep/claim accumulated yield to wallet
 * - Swap yield to ETH via Uniswap V3 (bypass withdrawal delay)
 * - Spend yield for agent operations (API calls, compute, etc.)
 * - Principal withdrawal with time-lock security
 * - Permission-controlled spending with allowlists
 */
interface IWstETH is IERC20 {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
}

/**
 * @notice Events for transparency and tracking
 */
contract AgentTreasuryV2Events {
    event Deposited(address indexed agent, uint256 wstETHAmount, uint256 stEthPerToken);
    event YieldClaimed(address indexed agent, uint256 amount);
    event YieldSwappedToETH(address indexed agent, uint256 wstETHAmount, uint256 ethAmount);
    event YieldSpent(address indexed agent, address indexed recipient, uint256 amount, string purpose);
    event PrincipalWithdrawn(address indexed agent, uint256 amount);
    event WithdrawalInitiated(address indexed agent, uint256 amount, uint256 unlockTime);
    event WithdrawalCancelled(address indexed agent);
    event SpendingAllowlisted(address indexed recipient, string service);
    event SpendingDelisted(address indexed recipient);
    event AgentRegistered(address indexed agent, uint256 erc8004Id);
    event YieldCheckpoint(address indexed agent, uint256 stEthPerToken, uint256 accruedYield);
}

/**
 * @notice Main Treasury Contract for Base L2 with Uniswap
 */
contract AgentTreasuryV2 is Ownable, ReentrancyGuard, AgentTreasuryV2Events {
    
    // ============ State Variables ============
    
    /// @notice The wstETH token contract (bridged from Ethereum)
    IWstETH public immutable wstETH;
    
    /// @notice Uniswap V3 SwapRouter on Base
    ISwapRouter public immutable swapRouter;
    
    /// @notice WETH address on Base (for Uniswap swaps)
    address public immutable WETH;
    
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
        uint256 principalShares;      // wstETH amount representing principal
        uint256 depositStEthPerToken; // stETH per wstETH at deposit time
        uint256 lastStEthPerToken;    // stETH per wstETH at last checkpoint
        uint256 totalYieldClaimed;    // cumulative yield claimed/swept
        uint256 totalYieldSpent;      // cumulative yield spent on services
        uint256 depositTimestamp;     // when deposit was made
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
    
    constructor(
        address _wstETH,
        address _swapRouter,
        address _weth
    ) Ownable(msg.sender) {
        require(_wstETH != address(0), "Invalid wstETH address");
        require(_swapRouter != address(0), "Invalid swap router");
        require(_weth != address(0), "Invalid WETH");
        
        wstETH = IWstETH(_wstETH);
        swapRouter = ISwapRouter(_swapRouter);
        WETH = _weth;
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
        
        uint256 currentStEthPerToken = wstETH.stEthPerToken();
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        if (!treasury.exists) {
            // New treasury
            treasury.principalShares = amount;
            treasury.depositStEthPerToken = currentStEthPerToken;
            treasury.lastStEthPerToken = currentStEthPerToken;
            treasury.exists = true;
            treasury.depositTimestamp = block.timestamp;
            
            if (erc8004Id > 0) {
                agentERC8004Id[msg.sender] = erc8004Id;
                emit AgentRegistered(msg.sender, erc8004Id);
            }
        } else {
            // Existing treasury - checkpoint yield first
            _checkpointYield(treasury);
            treasury.principalShares += amount;
        }
        
        totalPrincipal += amount;
        
        emit Deposited(msg.sender, amount, currentStEthPerToken);
    }
    
    /**
     * @notice Claim accumulated yield to your wallet (sweep)
     * @dev This transfers just the yield, principal stays locked
     */
    function sweepYield() external nonReentrant hasTreasury returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        // Calculate and checkpoint yield
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield to claim");
        
        // Update tracking
        treasury.totalYieldClaimed += yieldAmount;
        
        // Transfer wstETH yield to user
        require(wstETH.transfer(msg.sender, yieldAmount), "Transfer failed");
        
        emit YieldClaimed(msg.sender, yieldAmount);
        
        return yieldAmount;
    }
    
    /**
     * @notice Swap accumulated yield to ETH via Uniswap V3
     * @param minEthOut Minimum ETH to receive (slippage protection)
     * @dev Bypasses withdrawal delay by swapping yield, not principal
     */
    function swapYieldToETH(uint256 minEthOut) 
        external 
        nonReentrant 
        hasTreasury 
        returns (uint256 ethAmount) 
    {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        // Calculate and checkpoint yield
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield to swap");
        
        // Update tracking
        treasury.totalYieldClaimed += yieldAmount;
        
        // Approve Uniswap router
        wstETH.approve(address(swapRouter), yieldAmount);
        
        // Execute swap via Uniswap V3
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wstETH),
            tokenOut: WETH,
            fee: 3000, // 0.3% fee tier
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: yieldAmount,
            amountOutMinimum: minEthOut,
            sqrtPriceLimitX96: 0
        });
        
        ethAmount = swapRouter.exactInputSingle(params);
        
        emit YieldSwappedToETH(msg.sender, yieldAmount, ethAmount);
        
        return ethAmount;
    }
    
    /**
     * @notice Swap accumulated yield to ETH with custom fee tier
     * @param minEthOut Minimum ETH to receive
     * @param feeTier Uniswap fee tier (500, 3000, or 10000)
     */
    function swapYieldToETHWithFee(
        uint256 minEthOut, 
        uint24 feeTier
    ) 
        external 
        nonReentrant 
        hasTreasury 
        returns (uint256 ethAmount) 
    {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield to swap");
        
        treasury.totalYieldClaimed += yieldAmount;
        
        wstETH.approve(address(swapRouter), yieldAmount);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wstETH),
            tokenOut: WETH,
            fee: feeTier,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: yieldAmount,
            amountOutMinimum: minEthOut,
            sqrtPriceLimitX96: 0
        });
        
        ethAmount = swapRouter.exactInputSingle(params);
        
        emit YieldSwappedToETH(msg.sender, yieldAmount, ethAmount);
        
        return ethAmount;
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
        
        // Checkpoint and verify yield
        uint256 availableYield = _checkpointYield(treasury);
        require(availableYield >= amount, "Insufficient yield");
        
        // Update tracking
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
     * @notice Get current stETH per wstETH rate
     */
    function getCurrentStEthPerToken() public view returns (uint256) {
        return wstETH.stEthPerToken();
    }
    
    /**
     * @notice Calculate accrued yield for an agent
     * @dev Yield = principal * (currentRate - lastRate) / lastRate
     */
    function getAccruedYield(address agent) public view returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists || treasury.principalShares == 0) return 0;
        
        uint256 currentRate = getCurrentStEthPerToken();
        uint256 lastRate = treasury.lastStEthPerToken;
        
        if (currentRate <= lastRate) return 0;
        
        // Calculate yield: principal * (rateIncrease / lastRate)
        // This gives the additional wstETH value from staking rewards
        uint256 rateIncrease = currentRate - lastRate;
        uint256 yieldInWstETH = (treasury.principalShares * rateIncrease) / lastRate;
        
        return yieldInWstETH;
    }
    
    /**
     * @notice Get total yield earned since deposit (gross)
     */
    function getTotalYieldEarned(address agent) external view returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists || treasury.principalShares == 0) return 0;
        
        uint256 currentRate = getCurrentStEthPerToken();
        uint256 depositRate = treasury.depositStEthPerToken;
        
        if (currentRate <= depositRate) return 0;
        
        uint256 rateIncrease = currentRate - depositRate;
        uint256 totalYield = (treasury.principalShares * rateIncrease) / depositRate;
        
        return totalYield;
    }
    
    /**
     * @notice Get available yield (accrued - already claimed/spent)
     */
    function getAvailableYield(address agent) public view returns (uint256) {
        uint256 accrued = getAccruedYield(agent);
        AgentTreasuryInfo storage treasury = treasuries[agent];
        
        // Subtract any yield already accounted for
        uint256 accounted = treasury.totalYieldClaimed + treasury.totalYieldSpent;
        
        if (accrued > accounted) {
            return accrued - accounted;
        }
        return 0;
    }
    
    /**
     * @notice Get full treasury info for an agent
     */
    function getTreasuryInfo(address agent) external view returns (
        uint256 principal,
        uint256 availableYield,
        uint256 totalYieldEarned,
        uint256 totalYieldClaimed,
        uint256 totalYieldSpent,
        uint256 depositTime,
        uint256 currentStEthPerToken,
        uint256 depositStEthPerToken,
        bool exists
    ) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        
        return (
            treasury.principalShares,
            getAvailableYield(agent),
            this.getTotalYieldEarned(agent),
            treasury.totalYieldClaimed,
            treasury.totalYieldSpent,
            treasury.depositTimestamp,
            getCurrentStEthPerToken(),
            treasury.depositStEthPerToken,
            treasury.exists
        );
    }
    
    /**
     * @notice Check if a withdrawal is ready
     */
    function isWithdrawalReady(address agent) external view returns (bool) {
        PendingWithdrawal storage withdrawal = pendingWithdrawals[agent];
        return withdrawal.exists && block.timestamp >= withdrawal.unlockTime;
    }
    
    /**
     * @notice Get withdrawal info
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
    
    /**
     * @notice Get yield stats for display
     */
    function getYieldStats(address agent) external view returns (
        uint256 principalWstETH,
        uint256 principalStETH,
        uint256 currentStETHValue,
        uint256 yieldEarnedStETH,
        uint256 apr
    ) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists) return (0, 0, 0, 0, 0);
        
        principalWstETH = treasury.principalShares;
        uint256 currentRate = getCurrentStEthPerToken();
        
        // Current stETH value of principal
        currentStETHValue = (principalWstETH * currentRate) / 1e18;
        
        // Original stETH value at deposit
        principalStETH = (principalWstETH * treasury.depositStEthPerToken) / 1e18;
        
        // Yield earned
        yieldEarnedStETH = currentStETHValue > principalStETH ? 
            currentStETHValue - principalStETH : 0;
        
        // Calculate APR (simplified)
        if (treasury.depositTimestamp > 0 && principalStETH > 0) {
            uint256 timeElapsed = block.timestamp - treasury.depositTimestamp;
            if (timeElapsed > 0) {
                // APR = (yield / principal) * (365 days / timeElapsed) * 100
                apr = (yieldEarnedStETH * 365 days * 100) / (principalStETH * timeElapsed);
            }
        }
    }
    
    // ============ Internal Functions ============
    
    /**
     * @dev Checkpoint yield - updates lastStEthPerToken and returns accrued yield
     */
    function _checkpointYield(AgentTreasuryInfo storage treasury) internal returns (uint256) {
        uint256 currentRate = getCurrentStEthPerToken();
        uint256 accruedYield = getAccruedYield(msg.sender);
        
        treasury.lastStEthPerToken = currentRate;
        
        emit YieldCheckpoint(msg.sender, currentRate, accruedYield);
        
        return accruedYield;
    }
}
