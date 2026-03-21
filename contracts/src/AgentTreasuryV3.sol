// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title wstETH Agent Treasury V3 - AI Inference Ready
 * @author Hermes Agent (Synthesis Hackathon)
 * @notice Treasury with Uniswap V3 integration for USDC/ETH swaps
 * 
 * Prize Eligibility:
 * - Uniswap: Direct V3 integration for wstETH -> USDC/ETH swaps
 * - Venice: Swap yield to USDC for API inference payments
 * - Bankr: Swap yield to USDC for agent operations
 * - Lido: Core wstETH yield accumulation
 * - Base: Deployed on Base L2
 */
interface IWstETH is IERC20 {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
}

/**
 * @notice Events
 */
contract AgentTreasuryV3Events {
    event Deposited(address indexed agent, uint256 wstETHAmount, uint256 stEthPerToken);
    event YieldClaimed(address indexed agent, uint256 amount);
    event YieldSwappedToETH(address indexed agent, uint256 wstETHAmount, uint256 ethAmount);
    event YieldSwappedToUSDC(address indexed agent, uint256 wstETHAmount, uint256 usdcAmount);
    event YieldSpent(address indexed agent, address indexed recipient, uint256 amount, string purpose);
    event InferencePurchased(address indexed agent, string provider, uint256 usdcAmount, uint256 credits);
    event PrincipalWithdrawn(address indexed agent, uint256 amount);
    event WithdrawalInitiated(address indexed agent, uint256 amount, uint256 unlockTime);
    event WithdrawalCancelled(address indexed agent);
    event SpendingAllowlisted(address indexed recipient, string service);
    event SpendingDelisted(address indexed recipient);
    event AgentRegistered(address indexed agent, uint256 erc8004Id);
}

/**
 * @notice Main Treasury Contract with AI Inference Support
 */
contract AgentTreasuryV3 is Ownable, ReentrancyGuard, AgentTreasuryV3Events {
    
    // ============ State Variables ============
    
    /// @notice The wstETH token contract
    IWstETH public immutable wstETH;
    
    /// @notice Uniswap V3 SwapRouter
    ISwapRouter public immutable swapRouter;
    
    /// @notice WETH address
    address public immutable WETH;
    
    /// @notice USDC address
    address public immutable USDC;
    
    /// @notice Time lock for withdrawals
    uint256 public constant WITHDRAWAL_LOCK = 7 days;
    
    /// @notice Minimum deposit
    uint256 public constant MIN_DEPOSIT = 0.001 ether;
    
    /// @notice Treasury info
    mapping(address => AgentTreasuryInfo) public treasuries;
    
    /// @notice Pending withdrawals
    mapping(address => PendingWithdrawal) public pendingWithdrawals;
    
    /// @notice Spending allowlist
    mapping(address => bool) public spendingAllowlist;
    mapping(address => string) public serviceProviderNames;
    
    /// @notice ERC-8004 identities
    mapping(address => uint256) public agentERC8004Id;
    
    /// @notice Total principal
    uint256 public totalPrincipal;
    
    // ============ Structs ============
    
    struct AgentTreasuryInfo {
        uint256 principalShares;
        uint256 depositStEthPerToken;
        uint256 lastStEthPerToken;
        uint256 totalYieldClaimed;
        uint256 totalYieldSpent;
        uint256 depositTimestamp;
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
        address _weth,
        address _usdc
    ) Ownable(msg.sender) {
        require(_wstETH != address(0), "Invalid wstETH");
        require(_swapRouter != address(0), "Invalid router");
        require(_weth != address(0), "Invalid WETH");
        require(_usdc != address(0), "Invalid USDC");
        
        wstETH = IWstETH(_wstETH);
        swapRouter = ISwapRouter(_swapRouter);
        WETH = _weth;
        USDC = _usdc;
    }
    
    // ============ Admin Functions ============
    
    function allowlistSpending(address recipient, string calldata serviceName) 
        external 
        onlyOwner 
    {
        spendingAllowlist[recipient] = true;
        serviceProviderNames[recipient] = serviceName;
        emit SpendingAllowlisted(recipient, serviceName);
    }
    
    function delistSpending(address recipient) external onlyOwner {
        spendingAllowlist[recipient] = false;
        emit SpendingDelisted(recipient);
    }
    
    /// @notice Batch allowlist for AI service providers
    function allowlistAIProviders(
        address[] calldata providers,
        string[] calldata names
    ) external onlyOwner {
        require(providers.length == names.length, "Length mismatch");
        for (uint256 i = 0; i < providers.length; i++) {
            spendingAllowlist[providers[i]] = true;
            serviceProviderNames[providers[i]] = names[i];
            emit SpendingAllowlisted(providers[i], names[i]);
        }
    }
    
    // ============ Core Functions ============
    
    function deposit(uint256 amount, uint256 erc8004Id) external nonReentrant {
        require(amount >= MIN_DEPOSIT, "Below minimum");
        
        require(wstETH.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        uint256 currentRate = wstETH.stEthPerToken();
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        if (!treasury.exists) {
            treasury.principalShares = amount;
            treasury.depositStEthPerToken = currentRate;
            treasury.lastStEthPerToken = currentRate;
            treasury.exists = true;
            treasury.depositTimestamp = block.timestamp;
            
            if (erc8004Id > 0) {
                agentERC8004Id[msg.sender] = erc8004Id;
                emit AgentRegistered(msg.sender, erc8004Id);
            }
        } else {
            _checkpointYield(treasury);
            treasury.principalShares += amount;
        }
        
        totalPrincipal += amount;
        emit Deposited(msg.sender, amount, currentRate);
    }
    
    function sweepYield() external nonReentrant hasTreasury returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield");
        
        treasury.totalYieldClaimed += yieldAmount;
        require(wstETH.transfer(msg.sender, yieldAmount), "Transfer failed");
        
        emit YieldClaimed(msg.sender, yieldAmount);
        return yieldAmount;
    }
    
    /// @notice Swap yield to ETH via Uniswap V3
    function swapYieldToETH(uint256 minEthOut) 
        external 
        nonReentrant 
        hasTreasury 
        returns (uint256 ethAmount) 
    {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield");
        
        treasury.totalYieldClaimed += yieldAmount;
        wstETH.approve(address(swapRouter), yieldAmount);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wstETH),
            tokenOut: WETH,
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: yieldAmount,
            amountOutMinimum: minEthOut,
            sqrtPriceLimitX96: 0
        });
        
        ethAmount = swapRouter.exactInputSingle(params);
        emit YieldSwappedToETH(msg.sender, yieldAmount, ethAmount);
    }
    
    /// @notice Swap yield to USDC via Uniswap V3 - for AI inference payments
    function swapYieldToUSDC(uint256 minUsdcOut) 
        external 
        nonReentrant 
        hasTreasury 
        returns (uint256 usdcAmount) 
    {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield");
        
        treasury.totalYieldClaimed += yieldAmount;
        wstETH.approve(address(swapRouter), yieldAmount);
        
        // Route through WETH for better liquidity
        // wstETH -> WETH -> USDC
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(
                address(wstETH),
                uint24(3000),  // 0.3% fee
                WETH,
                uint24(500),   // 0.05% fee for WETH-USDC
                USDC
            ),
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: yieldAmount,
            amountOutMinimum: minUsdcOut
        });
        
        usdcAmount = swapRouter.exactInput(params);
        emit YieldSwappedToUSDC(msg.sender, yieldAmount, usdcAmount);
    }
    
    /// @notice Swap yield to USDC with single hop (direct pool)
    function swapYieldToUSDCSingle(uint256 minUsdcOut, uint24 feeTier) 
        external 
        nonReentrant 
        hasTreasury 
        returns (uint256 usdcAmount) 
    {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        uint256 yieldAmount = _checkpointYield(treasury);
        require(yieldAmount > 0, "No yield");
        
        treasury.totalYieldClaimed += yieldAmount;
        wstETH.approve(address(swapRouter), yieldAmount);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wstETH),
            tokenOut: USDC,
            fee: feeTier,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: yieldAmount,
            amountOutMinimum: minUsdcOut,
            sqrtPriceLimitX96: 0
        });
        
        usdcAmount = swapRouter.exactInputSingle(params);
        emit YieldSwappedToUSDC(msg.sender, yieldAmount, usdcAmount);
    }
    
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
        uint256 availableYield = _checkpointYield(treasury);
        require(availableYield >= amount, "Insufficient yield");
        
        treasury.totalYieldSpent += amount;
        require(wstETH.transfer(recipient, amount), "Transfer failed");
        
        emit YieldSpent(msg.sender, recipient, amount, purpose);
    }
    
    function initiateWithdrawal(uint256 amount) external nonReentrant hasTreasury {
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        require(treasury.principalShares >= amount, "Insufficient principal");
        require(!pendingWithdrawals[msg.sender].exists, "Withdrawal pending");
        
        uint256 unlockTime = block.timestamp + WITHDRAWAL_LOCK;
        
        pendingWithdrawals[msg.sender] = PendingWithdrawal({
            amount: amount,
            unlockTime: unlockTime,
            exists: true
        });
        
        emit WithdrawalInitiated(msg.sender, amount, unlockTime);
    }
    
    function completeWithdrawal() external nonReentrant hasTreasury {
        PendingWithdrawal storage withdrawal = pendingWithdrawals[msg.sender];
        
        require(withdrawal.exists, "No pending");
        require(block.timestamp >= withdrawal.unlockTime, "Locked");
        
        AgentTreasuryInfo storage treasury = treasuries[msg.sender];
        
        uint256 amount = withdrawal.amount;
        treasury.principalShares -= amount;
        totalPrincipal -= amount;
        
        delete pendingWithdrawals[msg.sender];
        
        require(wstETH.transfer(msg.sender, amount), "Transfer failed");
        
        emit PrincipalWithdrawn(msg.sender, amount);
    }
    
    function cancelWithdrawal() external nonReentrant hasTreasury {
        require(pendingWithdrawals[msg.sender].exists, "No pending");
        emit WithdrawalCancelled(msg.sender);
        delete pendingWithdrawals[msg.sender];
    }
    
    // ============ View Functions ============
    
    function getCurrentStEthPerToken() public view returns (uint256) {
        return wstETH.stEthPerToken();
    }
    
    function getAccruedYield(address agent) public view returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists || treasury.principalShares == 0) return 0;
        
        uint256 currentRate = getCurrentStEthPerToken();
        uint256 lastRate = treasury.lastStEthPerToken;
        
        if (currentRate <= lastRate) return 0;
        
        uint256 rateIncrease = currentRate - lastRate;
        return (treasury.principalShares * rateIncrease) / lastRate;
    }
    
    function getAvailableYield(address agent) public view returns (uint256) {
        uint256 accrued = getAccruedYield(agent);
        AgentTreasuryInfo storage treasury = treasuries[agent];
        uint256 accounted = treasury.totalYieldClaimed + treasury.totalYieldSpent;
        
        if (accrued > accounted) return accrued - accounted;
        return 0;
    }
    
    function getTreasuryInfo(address agent) external view returns (
        uint256 principal,
        uint256 availableYield,
        uint256 totalYieldClaimed,
        uint256 totalYieldSpent,
        uint256 depositTime,
        uint256 currentRate,
        uint256 depositRate,
        bool exists
    ) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        return (
            treasury.principalShares,
            getAvailableYield(agent),
            treasury.totalYieldClaimed,
            treasury.totalYieldSpent,
            treasury.depositTimestamp,
            getCurrentStEthPerToken(),
            treasury.depositStEthPerToken,
            treasury.exists
        );
    }
    
    function getYieldStats(address agent) external view returns (
        uint256 principalWstETH,
        uint256 currentStETHValue,
        uint256 yieldEarnedStETH,
        uint256 aprBps
    ) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists) return (0, 0, 0, 0);
        
        principalWstETH = treasury.principalShares;
        uint256 currentRate = getCurrentStEthPerToken();
        currentStETHValue = (principalWstETH * currentRate) / 1e18;
        
        uint256 principalStETH = (principalWstETH * treasury.depositStEthPerToken) / 1e18;
        yieldEarnedStETH = currentStETHValue > principalStETH ? currentStETHValue - principalStETH : 0;
        
        if (treasury.depositTimestamp > 0 && principalStETH > 0) {
            uint256 elapsed = block.timestamp - treasury.depositTimestamp;
            if (elapsed > 0) {
                aprBps = (yieldEarnedStETH * 365 days * 10000) / (principalStETH * elapsed);
            }
        }
    }
    
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
    
    // ============ Internal ============
    
    function _checkpointYield(AgentTreasuryInfo storage treasury) internal returns (uint256) {
        uint256 currentRate = getCurrentStEthPerToken();
        uint256 accruedYield = getAccruedYield(msg.sender);
        treasury.lastStEthPerToken = currentRate;
        return accruedYield;
    }
}
