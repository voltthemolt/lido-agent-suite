// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title wstETH Agent Treasury V4 - Base L2 Compatible
 * @author Hermes Agent + Claude (Synthesis Hackathon)
 * @notice Treasury for Base L2 where wstETH is a bridged ERC20 without rate functions.
 *         Uses an owner-updatable stEthPerToken rate synced from L1.
 *
 * Key difference from V3: Base's bridged wstETH lacks stEthPerToken() and
 * getStETHByWstETH(). This version uses an admin-updatable rate oracle that
 * can be called by the owner (or an automated keeper) to sync the L1 rate.
 *
 * Prize Eligibility:
 * - Lido: Core wstETH yield accumulation
 * - Uniswap: V3 SwapRouter for wstETH → ETH/USDC swaps
 * - Venice: USDC swap for AI inference payments
 * - Base: Deployed on Base L2
 */

/// @notice Minimal Uniswap V3 SwapRouter02 interface (Base version - no deadline in struct)
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

contract AgentTreasuryV4Events {
    event Deposited(address indexed agent, uint256 wstETHAmount, uint256 stEthPerToken);
    event YieldClaimed(address indexed agent, uint256 amount);
    event YieldSwappedToETH(address indexed agent, uint256 wstETHAmount, uint256 ethAmount);
    event YieldSwappedToUSDC(address indexed agent, uint256 wstETHAmount, uint256 usdcAmount);
    event YieldSpent(address indexed agent, address indexed recipient, uint256 amount, string purpose);
    event PrincipalWithdrawn(address indexed agent, uint256 amount);
    event WithdrawalInitiated(address indexed agent, uint256 amount, uint256 unlockTime);
    event WithdrawalCancelled(address indexed agent);
    event SpendingAllowlisted(address indexed recipient, string service);
    event SpendingDelisted(address indexed recipient);
    event AgentRegistered(address indexed agent, uint256 erc8004Id);
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);
}

contract AgentTreasuryV4 is Ownable, ReentrancyGuard, AgentTreasuryV4Events {

    // ============ State Variables ============

    IERC20 public immutable wstETH;
    ISwapRouter02 public immutable swapRouter;
    address public immutable WETH;
    address public immutable USDC;

    uint256 public constant WITHDRAWAL_LOCK = 7 days;
    uint256 public constant MIN_DEPOSIT = 0.001 ether;

    /// @notice stEthPerToken rate, updatable by owner to sync from L1
    uint256 public stEthPerToken;

    mapping(address => AgentTreasuryInfo) public treasuries;
    mapping(address => PendingWithdrawal) public pendingWithdrawals;
    mapping(address => bool) public spendingAllowlist;
    mapping(address => string) public serviceProviderNames;
    mapping(address => uint256) public agentERC8004Id;

    uint256 public totalPrincipal;

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
        address _usdc,
        uint256 _initialRate
    ) Ownable(msg.sender) {
        require(_wstETH != address(0), "Invalid wstETH");
        require(_swapRouter != address(0), "Invalid router");
        require(_weth != address(0), "Invalid WETH");
        require(_usdc != address(0), "Invalid USDC");
        require(_initialRate > 0, "Invalid rate");

        wstETH = IERC20(_wstETH);
        swapRouter = ISwapRouter02(_swapRouter);
        WETH = _weth;
        USDC = _usdc;
        stEthPerToken = _initialRate;
    }

    // ============ Rate Oracle ============

    /// @notice Update stEthPerToken rate (synced from L1 by owner or keeper)
    function updateRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Invalid rate");
        uint256 oldRate = stEthPerToken;
        stEthPerToken = newRate;
        emit RateUpdated(oldRate, newRate, block.timestamp);
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

        uint256 currentRate = stEthPerToken;
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

    /// @notice Swap yield to ETH via Uniswap V3 (SwapRouter02)
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

        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(wstETH),
            tokenOut: WETH,
            fee: 100, // 0.01% fee tier (correlated pair on Base)
            recipient: msg.sender,
            amountIn: yieldAmount,
            amountOutMinimum: minEthOut,
            sqrtPriceLimitX96: 0
        });

        ethAmount = swapRouter.exactInputSingle(params);
        emit YieldSwappedToETH(msg.sender, yieldAmount, ethAmount);
    }

    /// @notice Swap yield to USDC via wstETH -> WETH -> USDC multi-hop
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

        ISwapRouter02.ExactInputParams memory params = ISwapRouter02.ExactInputParams({
            path: abi.encodePacked(
                address(wstETH),
                uint24(100),   // 0.01% wstETH-WETH
                WETH,
                uint24(500),   // 0.05% WETH-USDC
                USDC
            ),
            recipient: msg.sender,
            amountIn: yieldAmount,
            amountOutMinimum: minUsdcOut
        });

        usdcAmount = swapRouter.exactInput(params);
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
        return stEthPerToken;
    }

    function getAccruedYield(address agent) public view returns (uint256) {
        AgentTreasuryInfo storage treasury = treasuries[agent];
        if (!treasury.exists || treasury.principalShares == 0) return 0;

        uint256 currentRate = stEthPerToken;
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
        uint256 totalYieldClaimed_,
        uint256 totalYieldSpent_,
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
            stEthPerToken,
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
        uint256 currentRate = stEthPerToken;
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
        uint256 currentRate = stEthPerToken;
        uint256 accruedYield = getAccruedYield(msg.sender);
        treasury.lastStEthPerToken = currentRate;
        return accruedYield;
    }
}
