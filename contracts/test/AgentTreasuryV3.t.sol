// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentTreasuryV3} from "../src/AgentTreasuryV3.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============ Mock Contracts ============

/**
 * @notice Mock wstETH with controllable stEthPerToken rate for yield simulation
 */
contract MockWstETHV3 is IERC20 {
    string public name = "Wrapped liquid staked Ether 2.0";
    string public symbol = "wstETH";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    /// @notice Controllable rate for simulating yield
    uint256 private _stEthPerToken;

    constructor() {
        _stEthPerToken = 1.15 ether; // Start at a realistic rate
    }

    function setStEthPerToken(uint256 rate) external {
        _stEthPerToken = rate;
    }

    function stEthPerToken() external view returns (uint256) {
        return _stEthPerToken;
    }

    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return (_wstETHAmount * _stEthPerToken) / 1e18;
    }

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return (_stETHAmount * 1e18) / _stEthPerToken;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
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
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @notice Mock USDC with 6 decimals
 */
contract MockUSDC is IERC20 {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
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
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @notice Mock WETH (standard ERC20, 18 decimals)
 */
contract MockWETH is IERC20 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
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
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
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
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @notice Mock Uniswap V3 SwapRouter
 * @dev Simulates swaps by pulling tokenIn from sender and minting/transferring tokenOut to recipient.
 *      Uses a fixed exchange rate for deterministic testing.
 */
contract MockSwapRouter {
    MockWstETHV3 public wstETH;
    MockWETH public weth;
    MockUSDC public usdc;

    /// @notice Fixed simulated exchange rate: 1 wstETH = 2 ETH (WETH)
    uint256 public wstethToWethRate = 2 ether;
    /// @notice Fixed simulated exchange rate: 1 wstETH = 4000 USDC (4000e6)
    uint256 public wstethToUsdcRate = 4000e6;

    constructor(address _wstETH, address _weth, address _usdc) {
        wstETH = MockWstETHV3(_wstETH);
        weth = MockWETH(_weth);
        usdc = MockUSDC(_usdc);
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        // Pull tokenIn from the caller (treasury)
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Determine output amount based on tokenOut
        if (params.tokenOut == address(weth)) {
            amountOut = (params.amountIn * wstethToWethRate) / 1 ether;
            weth.mint(params.recipient, amountOut);
        } else if (params.tokenOut == address(usdc)) {
            amountOut = (params.amountIn * wstethToUsdcRate) / 1 ether;
            usdc.mint(params.recipient, amountOut);
        } else {
            revert("Unsupported tokenOut");
        }

        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function exactInput(ISwapRouter.ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        // Decode first token from path (first 20 bytes)
        address tokenIn;
        bytes memory path = params.path;
        require(path.length >= 20, "Invalid path");
        assembly {
            tokenIn := mload(add(path, 20))
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // For multi-hop wstETH -> WETH -> USDC, output is USDC
        amountOut = (params.amountIn * wstethToUsdcRate) / 1 ether;
        usdc.mint(params.recipient, amountOut);

        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    /// @notice Stub for IUniswapV3SwapCallback (not used in mock)
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external {}
}

// ============ Test Contract ============

/**
 * @title AgentTreasuryV3 Test Suite
 * @notice Comprehensive tests for the wstETH Agent Treasury V3 with Uniswap V3 integration
 */
contract AgentTreasuryV3Test is Test {

    AgentTreasuryV3 public treasury;

    // Mock tokens
    MockWstETHV3 public wstETH;
    MockWETH public weth;
    MockUSDC public usdc;
    MockSwapRouter public router;

    // Test addresses
    address public owner;
    address public agent1;
    address public agent2;
    address public agent3;
    address public serviceProvider;
    address public serviceProvider2;

    // ============ Events (copied from AgentTreasuryV3Events for expectEmit) ============
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

    function setUp() public {
        owner = makeAddr("owner");
        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        agent3 = makeAddr("agent3");
        serviceProvider = makeAddr("serviceProvider");
        serviceProvider2 = makeAddr("serviceProvider2");

        // Deploy mock tokens
        wstETH = new MockWstETHV3();
        weth = new MockWETH();
        usdc = new MockUSDC();

        // Deploy mock swap router
        router = new MockSwapRouter(address(wstETH), address(weth), address(usdc));

        // Deploy treasury
        vm.prank(owner);
        treasury = new AgentTreasuryV3(
            address(wstETH),
            address(router),
            address(weth),
            address(usdc)
        );

        // Mint wstETH to agents
        wstETH.mint(agent1, 100 ether);
        wstETH.mint(agent2, 100 ether);
        wstETH.mint(agent3, 50 ether);

        // Allowlist service provider
        vm.prank(owner);
        treasury.allowlistSpending(serviceProvider, "Test Service");
    }

    // ============ Helper Functions ============

    /// @notice Helper to deposit wstETH for an agent
    function _depositFor(address agent, uint256 amount, uint256 erc8004Id) internal {
        vm.startPrank(agent);
        wstETH.approve(address(treasury), amount);
        treasury.deposit(amount, erc8004Id);
        vm.stopPrank();
    }

    /// @notice Helper to simulate yield by increasing the stEthPerToken rate
    function _simulateYield(uint256 newRate) internal {
        wstETH.setStEthPerToken(newRate);
        // Mint enough wstETH to the treasury to cover yield claims
        // The treasury needs actual tokens to transfer out as yield
        wstETH.mint(address(treasury), 50 ether);
    }

    // ============ Constructor Tests ============

    function test_ConstructorSetsImmutables() public view {
        assertEq(address(treasury.wstETH()), address(wstETH));
        assertEq(address(treasury.swapRouter()), address(router));
        assertEq(treasury.WETH(), address(weth));
        assertEq(treasury.USDC(), address(usdc));
    }

    function test_ConstructorRevertsZeroWstETH() public {
        vm.expectRevert("Invalid wstETH");
        new AgentTreasuryV3(address(0), address(router), address(weth), address(usdc));
    }

    function test_ConstructorRevertsZeroRouter() public {
        vm.expectRevert("Invalid router");
        new AgentTreasuryV3(address(wstETH), address(0), address(weth), address(usdc));
    }

    function test_ConstructorRevertsZeroWETH() public {
        vm.expectRevert("Invalid WETH");
        new AgentTreasuryV3(address(wstETH), address(router), address(0), address(usdc));
    }

    function test_ConstructorRevertsZeroUSDC() public {
        vm.expectRevert("Invalid USDC");
        new AgentTreasuryV3(address(wstETH), address(router), address(weth), address(0));
    }

    function test_ConstructorSetsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        vm.startPrank(agent1);
        wstETH.approve(address(treasury), 10 ether);

        vm.expectEmit(true, false, false, true);
        emit Deposited(agent1, 10 ether, wstETH.stEthPerToken());

        treasury.deposit(10 ether, 0);

        (
            uint256 principal,
            uint256 availableYield,
            uint256 totalYieldClaimed,
            uint256 totalYieldSpent,
            uint256 depositTime,
            uint256 currentRate,
            uint256 depositRate,
            bool exists
        ) = treasury.getTreasuryInfo(agent1);

        assertEq(principal, 10 ether, "Principal should equal deposit");
        assertEq(availableYield, 0, "No yield yet");
        assertEq(totalYieldClaimed, 0);
        assertEq(totalYieldSpent, 0);
        assertEq(depositTime, block.timestamp);
        assertEq(currentRate, wstETH.stEthPerToken());
        assertEq(depositRate, wstETH.stEthPerToken());
        assertTrue(exists, "Treasury should exist");

        assertEq(treasury.totalPrincipal(), 10 ether);
        assertEq(wstETH.balanceOf(address(treasury)), 10 ether);

        vm.stopPrank();
    }

    function test_DepositBelowMinimum() public {
        vm.startPrank(agent1);
        wstETH.approve(address(treasury), 0.0005 ether);

        vm.expectRevert("Below minimum");
        treasury.deposit(0.0005 ether, 0);

        vm.stopPrank();
    }

    function test_DepositExactMinimum() public {
        vm.startPrank(agent1);
        wstETH.approve(address(treasury), 0.001 ether);
        treasury.deposit(0.001 ether, 0);

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 0.001 ether);
        assertTrue(exists);

        vm.stopPrank();
    }

    function test_DepositWithERC8004() public {
        uint256 erc8004Id = 42;

        vm.startPrank(agent1);
        wstETH.approve(address(treasury), 10 ether);

        vm.expectEmit(true, false, false, true);
        emit AgentRegistered(agent1, erc8004Id);

        treasury.deposit(10 ether, erc8004Id);

        assertEq(treasury.agentERC8004Id(agent1), erc8004Id, "ERC-8004 ID should be set");

        vm.stopPrank();
    }

    function test_DepositWithERC8004IdZeroDoesNotRegister() public {
        _depositFor(agent1, 10 ether, 0);
        assertEq(treasury.agentERC8004Id(agent1), 0, "ERC-8004 ID should not be set for zero");
    }

    function test_MultipleDeposits() public {
        vm.startPrank(agent1);
        wstETH.approve(address(treasury), 30 ether);

        treasury.deposit(10 ether, 0);
        treasury.deposit(10 ether, 0);
        treasury.deposit(10 ether, 0);

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);

        assertEq(principal, 30 ether, "Principal should be cumulative");
        assertTrue(exists);
        assertEq(treasury.totalPrincipal(), 30 ether);

        vm.stopPrank();
    }

    function test_MultipleDepositsCheckpointYield() public {
        // First deposit at initial rate
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken(); // 1.15 ether

        // Increase rate to simulate yield accrual
        uint256 newRate = 1.20 ether;
        wstETH.setStEthPerToken(newRate);

        // Yield before second deposit
        uint256 yieldBefore = treasury.getAccruedYield(agent1);
        // Expected: (10 ether * (1.20 - 1.15) ether) / 1.15 ether
        uint256 expectedYield = (10 ether * (newRate - initialRate)) / initialRate;
        assertEq(yieldBefore, expectedYield, "Yield should accrue before second deposit");

        // Second deposit should checkpoint yield (updating lastStEthPerToken)
        _depositFor(agent1, 5 ether, 0);

        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 15 ether, "Principal includes both deposits");
    }

    // ============ Yield Calculation Tests ============

    function test_YieldAccruesOnRateIncrease() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken(); // 1.15 ether

        // Increase rate by ~5%
        uint256 newRate = 1.2075 ether; // 1.15 * 1.05
        wstETH.setStEthPerToken(newRate);

        uint256 accrued = treasury.getAccruedYield(agent1);
        // Expected: (10 ether * (1.2075 - 1.15)) / 1.15 = (10 * 0.0575) / 1.15 = 0.5 ether
        uint256 expected = (10 ether * (newRate - initialRate)) / initialRate;
        assertEq(accrued, expected, "Accrued yield should match formula");
        assertEq(accrued, 0.5 ether, "Accrued yield should be 0.5 ether");
    }

    function test_YieldZeroWhenRateUnchanged() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 accrued = treasury.getAccruedYield(agent1);
        assertEq(accrued, 0, "No yield when rate unchanged");
    }

    function test_YieldZeroWhenRateDecreases() public {
        _depositFor(agent1, 10 ether, 0);

        // Decrease rate (shouldn't happen normally but contract handles it)
        wstETH.setStEthPerToken(1.10 ether);

        uint256 accrued = treasury.getAccruedYield(agent1);
        assertEq(accrued, 0, "No yield when rate decreases");
    }

    function test_YieldForNonExistentAgent() public {
        address nobody = makeAddr("nobody");
        assertEq(treasury.getAccruedYield(nobody), 0);
        assertEq(treasury.getAvailableYield(nobody), 0);
    }

    function test_AvailableYieldDeductsClaimedAndSpent() public {
        _depositFor(agent1, 10 ether, 0);

        // Simulate yield
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 accrued = treasury.getAccruedYield(agent1);
        assertGt(accrued, 0, "Should have accrued yield");

        // Sweep some yield (claims it)
        vm.prank(agent1);
        uint256 claimed = treasury.sweepYield();

        // After claiming all available yield, available should be 0
        // (rate was checkpointed, so new accrued = 0)
        assertEq(treasury.getAvailableYield(agent1), 0, "Available yield should be 0 after full claim");
        assertEq(claimed, accrued, "Claimed should equal accrued");
    }

    // ============ sweepYield Tests ============

    function test_SweepYield() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken();
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - initialRate)) / initialRate;
        uint256 balanceBefore = wstETH.balanceOf(agent1);

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit YieldClaimed(agent1, expectedYield);
        uint256 claimed = treasury.sweepYield();

        assertEq(claimed, expectedYield, "Should claim expected yield");
        assertEq(wstETH.balanceOf(agent1), balanceBefore + expectedYield, "Agent should receive wstETH yield");

        // Check totalYieldClaimed updated
        (,, uint256 totalYieldClaimed,,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalYieldClaimed, expectedYield);
    }

    function test_SweepYieldRevertsWhenNoYield() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No yield");
        treasury.sweepYield();
    }

    function test_SweepYieldRevertsWhenNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.sweepYield();
    }

    // ============ swapYieldToETH Tests ============

    function test_SwapYieldToETH() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken();
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - initialRate)) / initialRate;
        // Mock router converts at 2 ETH per wstETH
        uint256 expectedEth = (expectedYield * 2 ether) / 1 ether;

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit YieldSwappedToETH(agent1, expectedYield, expectedEth);
        uint256 ethOut = treasury.swapYieldToETH(0);

        assertEq(ethOut, expectedEth, "Should receive expected ETH");
        assertEq(weth.balanceOf(agent1), expectedEth, "Agent should receive WETH");

        // Check totalYieldClaimed updated
        (,, uint256 totalYieldClaimed,,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalYieldClaimed, expectedYield);
    }

    function test_SwapYieldToETHRevertsNoYield() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No yield");
        treasury.swapYieldToETH(0);
    }

    function test_SwapYieldToETHRevertsNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.swapYieldToETH(0);
    }

    function test_SwapYieldToETHApprovesRouter() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        vm.prank(agent1);
        treasury.swapYieldToETH(0);

        // After the swap, the router should have pulled the tokens
        // The allowance may be zero or reduced depending on router behavior
        // Main verification: the swap succeeded (no revert)
    }

    // ============ swapYieldToUSDC Tests (multi-hop) ============

    function test_SwapYieldToUSDC() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken();
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - initialRate)) / initialRate;
        // Mock router converts at 4000 USDC per wstETH
        uint256 expectedUsdc = (expectedYield * 4000e6) / 1 ether;

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit YieldSwappedToUSDC(agent1, expectedYield, expectedUsdc);
        uint256 usdcOut = treasury.swapYieldToUSDC(0);

        assertEq(usdcOut, expectedUsdc, "Should receive expected USDC");
        assertEq(usdc.balanceOf(agent1), expectedUsdc, "Agent should receive USDC");
    }

    function test_SwapYieldToUSDCRevertsNoYield() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No yield");
        treasury.swapYieldToUSDC(0);
    }

    function test_SwapYieldToUSDCRevertsNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.swapYieldToUSDC(0);
    }

    // ============ swapYieldToUSDCSingle Tests ============

    function test_SwapYieldToUSDCSingle() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken();
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - initialRate)) / initialRate;
        uint256 expectedUsdc = (expectedYield * 4000e6) / 1 ether;

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit YieldSwappedToUSDC(agent1, expectedYield, expectedUsdc);
        uint256 usdcOut = treasury.swapYieldToUSDCSingle(0, 3000);

        assertEq(usdcOut, expectedUsdc, "Should receive expected USDC via single hop");
        assertEq(usdc.balanceOf(agent1), expectedUsdc);
    }

    function test_SwapYieldToUSDCSingleDifferentFeeTier() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        // Use 500 bps fee tier (0.05%) - should still work with mock
        vm.prank(agent1);
        uint256 usdcOut = treasury.swapYieldToUSDCSingle(0, 500);
        assertGt(usdcOut, 0, "Should receive USDC with 500 fee tier");
    }

    function test_SwapYieldToUSDCSingleRevertsNoYield() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No yield");
        treasury.swapYieldToUSDCSingle(0, 3000);
    }

    // ============ spendYield Tests ============

    function test_SpendYield() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken();
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - initialRate)) / initialRate;
        // Spend half the yield
        uint256 spendAmount = expectedYield / 2;

        uint256 providerBalanceBefore = wstETH.balanceOf(serviceProvider);

        vm.prank(agent1);
        vm.expectEmit(true, true, false, true);
        emit YieldSpent(agent1, serviceProvider, spendAmount, "API calls");
        treasury.spendYield(serviceProvider, spendAmount, "API calls");

        assertEq(
            wstETH.balanceOf(serviceProvider),
            providerBalanceBefore + spendAmount,
            "Service provider should receive wstETH"
        );

        (,,, uint256 totalYieldSpent,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalYieldSpent, spendAmount, "Should track yield spent");
    }

    function test_SpendYieldNotAllowlisted() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        address notAllowlisted = makeAddr("notAllowlisted");

        vm.prank(agent1);
        vm.expectRevert("Recipient not allowlisted");
        treasury.spendYield(notAllowlisted, 0.1 ether, "Should fail");
    }

    function test_SpendYieldInsufficientYield() public {
        _depositFor(agent1, 10 ether, 0);

        // No rate increase, no yield
        vm.prank(agent1);
        vm.expectRevert("Insufficient yield");
        treasury.spendYield(serviceProvider, 1 ether, "Should fail");
    }

    function test_SpendYieldInsufficientForAmount() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        uint256 available = treasury.getAccruedYield(agent1);

        vm.prank(agent1);
        vm.expectRevert("Insufficient yield");
        treasury.spendYield(serviceProvider, available + 1, "Too much");
    }

    function test_SpendYieldRevertsNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.spendYield(serviceProvider, 1 ether, "Should fail");
    }

    // ============ Withdrawal Flow Tests ============

    function test_InitiateWithdrawal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit WithdrawalInitiated(agent1, 5 ether, block.timestamp + 7 days);
        treasury.initiateWithdrawal(5 ether);

        (uint256 amount, uint256 unlockTime, bool exists) = treasury.pendingWithdrawals(agent1);
        assertEq(amount, 5 ether, "Withdrawal amount should be set");
        assertEq(unlockTime, block.timestamp + 7 days, "Unlock time should be 7 days");
        assertTrue(exists, "Withdrawal should exist");
    }

    function test_InitiateWithdrawalInsufficientPrincipal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("Insufficient principal");
        treasury.initiateWithdrawal(11 ether);
    }

    function test_InitiateWithdrawalAlreadyPending() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(3 ether);

        vm.expectRevert("Withdrawal pending");
        treasury.initiateWithdrawal(3 ether);

        vm.stopPrank();
    }

    function test_InitiateWithdrawalNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.initiateWithdrawal(1 ether);
    }

    function test_CompleteWithdrawalAfterTimelock() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(5 ether);

        // Fast forward past the timelock
        skip(7 days + 1);

        uint256 balanceBefore = wstETH.balanceOf(agent1);

        vm.expectEmit(true, false, false, true);
        emit PrincipalWithdrawn(agent1, 5 ether);
        treasury.completeWithdrawal();

        uint256 balanceAfter = wstETH.balanceOf(agent1);
        assertEq(balanceAfter, balanceBefore + 5 ether, "Should receive withdrawn wstETH");

        // Check principal reduced
        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 5 ether, "Principal should be reduced");
        assertTrue(exists, "Treasury should still exist");

        // Check totalPrincipal reduced
        assertEq(treasury.totalPrincipal(), 5 ether);

        // Pending withdrawal should be cleared
        (, , bool pendingExists) = treasury.pendingWithdrawals(agent1);
        assertFalse(pendingExists, "Pending withdrawal should be cleared");

        vm.stopPrank();
    }

    function test_CompleteWithdrawalBeforeTimelock() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(5 ether);

        // Don't skip time
        vm.expectRevert("Locked");
        treasury.completeWithdrawal();

        vm.stopPrank();
    }

    function test_CompleteWithdrawalExactlyAtTimelock() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(5 ether);

        // Fast forward exactly to unlock time
        skip(7 days);

        // Should succeed at exactly the unlock time
        treasury.completeWithdrawal();

        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 5 ether);

        vm.stopPrank();
    }

    function test_CompleteWithdrawalNoPending() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No pending");
        treasury.completeWithdrawal();
    }

    function test_CancelWithdrawal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(5 ether);

        vm.expectEmit(true, false, false, false);
        emit WithdrawalCancelled(agent1);
        treasury.cancelWithdrawal();

        (, , bool exists) = treasury.pendingWithdrawals(agent1);
        assertFalse(exists, "Withdrawal should be cancelled");

        // Principal should be unchanged
        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 10 ether, "Principal should remain unchanged after cancel");

        vm.stopPrank();
    }

    function test_CancelWithdrawalNoPending() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No pending");
        treasury.cancelWithdrawal();
    }

    function test_CancelWithdrawalNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.cancelWithdrawal();
    }

    function test_CancelAndReinitiateWithdrawal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);

        // Initiate, cancel, then re-initiate with different amount
        treasury.initiateWithdrawal(3 ether);
        treasury.cancelWithdrawal();
        treasury.initiateWithdrawal(7 ether);

        (uint256 amount,, bool exists) = treasury.pendingWithdrawals(agent1);
        assertEq(amount, 7 ether);
        assertTrue(exists);

        vm.stopPrank();
    }

    function test_WithdrawFullPrincipal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(10 ether);
        skip(7 days);
        treasury.completeWithdrawal();

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 0, "Principal should be zero");
        assertTrue(exists, "Treasury should still exist (exists flag not cleared)");
        assertEq(treasury.totalPrincipal(), 0);

        vm.stopPrank();
    }

    // ============ allowlistAIProviders Tests ============

    function test_AllowlistAIProvidersBatch() public {
        address[] memory providers = new address[](3);
        providers[0] = makeAddr("venice");
        providers[1] = makeAddr("openai");
        providers[2] = makeAddr("anthropic");

        string[] memory names = new string[](3);
        names[0] = "Venice AI";
        names[1] = "OpenAI";
        names[2] = "Anthropic";

        vm.prank(owner);
        treasury.allowlistAIProviders(providers, names);

        for (uint256 i = 0; i < providers.length; i++) {
            assertTrue(treasury.spendingAllowlist(providers[i]), "Provider should be allowlisted");
            assertEq(treasury.serviceProviderNames(providers[i]), names[i], "Name should match");
        }
    }

    function test_AllowlistAIProvidersEmitsEvents() public {
        address[] memory providers = new address[](2);
        providers[0] = makeAddr("provider1");
        providers[1] = makeAddr("provider2");

        string[] memory names = new string[](2);
        names[0] = "Provider 1";
        names[1] = "Provider 2";

        vm.prank(owner);
        // Expect the second event (last one emitted)
        vm.expectEmit(true, false, false, true);
        emit SpendingAllowlisted(providers[1], names[1]);
        treasury.allowlistAIProviders(providers, names);
    }

    function test_AllowlistAIProvidersLengthMismatch() public {
        address[] memory providers = new address[](2);
        providers[0] = makeAddr("p1");
        providers[1] = makeAddr("p2");

        string[] memory names = new string[](1);
        names[0] = "Only one";

        vm.prank(owner);
        vm.expectRevert("Length mismatch");
        treasury.allowlistAIProviders(providers, names);
    }

    function test_AllowlistAIProvidersEmptyArrays() public {
        address[] memory providers = new address[](0);
        string[] memory names = new string[](0);

        vm.prank(owner);
        treasury.allowlistAIProviders(providers, names);
        // Should succeed with no-op
    }

    function test_AllowlistAIProvidersNonOwnerReverts() public {
        address[] memory providers = new address[](1);
        providers[0] = makeAddr("p1");

        string[] memory names = new string[](1);
        names[0] = "P1";

        vm.prank(agent1);
        vm.expectRevert();
        treasury.allowlistAIProviders(providers, names);
    }

    // ============ Admin Tests ============

    function test_AllowlistSpending() public {
        address newService = makeAddr("newService");

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SpendingAllowlisted(newService, "New Service");
        treasury.allowlistSpending(newService, "New Service");

        assertTrue(treasury.spendingAllowlist(newService), "Should be allowlisted");
        assertEq(treasury.serviceProviderNames(newService), "New Service");
    }

    function test_DelistSpending() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit SpendingDelisted(serviceProvider);
        treasury.delistSpending(serviceProvider);

        assertFalse(treasury.spendingAllowlist(serviceProvider), "Should be delisted");
    }

    function test_DelistAndReallowlist() public {
        vm.startPrank(owner);
        treasury.delistSpending(serviceProvider);
        assertFalse(treasury.spendingAllowlist(serviceProvider));

        treasury.allowlistSpending(serviceProvider, "Re-listed Service");
        assertTrue(treasury.spendingAllowlist(serviceProvider));
        assertEq(treasury.serviceProviderNames(serviceProvider), "Re-listed Service");
        vm.stopPrank();
    }

    function test_NonOwnerCannotAllowlist() public {
        vm.prank(agent1);
        vm.expectRevert();
        treasury.allowlistSpending(makeAddr("test"), "Test");
    }

    function test_NonOwnerCannotDelist() public {
        vm.prank(agent1);
        vm.expectRevert();
        treasury.delistSpending(serviceProvider);
    }

    // ============ getYieldStats Tests ============

    function test_GetYieldStatsNonExistent() public {
        address nobody = makeAddr("nobody");
        (
            uint256 principalWstETH,
            uint256 currentStETHValue,
            uint256 yieldEarnedStETH,
            uint256 aprBps
        ) = treasury.getYieldStats(nobody);

        assertEq(principalWstETH, 0);
        assertEq(currentStETHValue, 0);
        assertEq(yieldEarnedStETH, 0);
        assertEq(aprBps, 0);
    }

    function test_GetYieldStatsAfterDeposit() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 rate = wstETH.stEthPerToken(); // 1.15 ether

        (
            uint256 principalWstETH,
            uint256 currentStETHValue,
            uint256 yieldEarnedStETH,
            uint256 aprBps
        ) = treasury.getYieldStats(agent1);

        assertEq(principalWstETH, 10 ether);
        assertEq(currentStETHValue, (10 ether * rate) / 1e18);
        assertEq(yieldEarnedStETH, 0, "No yield at deposit rate");
        assertEq(aprBps, 0, "APR zero with no yield");
    }

    function test_GetYieldStatsWithYield() public {
        _depositFor(agent1, 10 ether, 0);

        // Advance time by 365 days
        skip(365 days);

        // Increase rate by 5%
        uint256 depositRate = wstETH.stEthPerToken(); // 1.15 ether
        uint256 newRate = 1.2075 ether; // 1.15 * 1.05
        wstETH.setStEthPerToken(newRate);

        (
            uint256 principalWstETH,
            uint256 currentStETHValue,
            uint256 yieldEarnedStETH,
            uint256 aprBps
        ) = treasury.getYieldStats(agent1);

        assertEq(principalWstETH, 10 ether);

        uint256 expectedCurrentValue = (10 ether * newRate) / 1e18;
        assertEq(currentStETHValue, expectedCurrentValue);

        uint256 principalStETH = (10 ether * depositRate) / 1e18;
        uint256 expectedYield = expectedCurrentValue - principalStETH;
        assertEq(yieldEarnedStETH, expectedYield);

        // APR over 365 days with 5% yield should be ~500 bps
        // aprBps = (yieldEarnedStETH * 365 days * 10000) / (principalStETH * elapsed)
        // With elapsed = 365 days, this simplifies to: (yieldEarnedStETH * 10000) / principalStETH
        uint256 expectedApr = (expectedYield * 10000) / principalStETH;
        assertEq(aprBps, expectedApr, "APR should reflect yield over time");
    }

    // ============ getWithdrawalInfo Tests ============

    function test_GetWithdrawalInfoNoPending() public {
        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 0);
        assertEq(unlockTime, 0);
        assertFalse(ready);
    }

    function test_GetWithdrawalInfoPendingNotReady() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 5 ether);
        assertEq(unlockTime, block.timestamp + 7 days);
        assertFalse(ready, "Should not be ready before timelock");
    }

    function test_GetWithdrawalInfoReady() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        skip(7 days);

        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 5 ether);
        assertTrue(ready, "Should be ready after timelock");
        assertEq(unlockTime, block.timestamp); // we skipped exactly 7 days
    }

    function test_GetWithdrawalInfoAfterCancel() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(5 ether);
        treasury.cancelWithdrawal();
        vm.stopPrank();

        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 0);
        assertEq(unlockTime, 0);
        assertFalse(ready);
    }

    // ============ Multiple Agents / Independent Yield ============

    function test_MultipleAgentsIndependentDeposits() public {
        _depositFor(agent1, 10 ether, 0);
        _depositFor(agent2, 20 ether, 0);

        assertEq(treasury.totalPrincipal(), 30 ether);

        (uint256 principal1,,,,,,, bool exists1) = treasury.getTreasuryInfo(agent1);
        (uint256 principal2,,,,,,, bool exists2) = treasury.getTreasuryInfo(agent2);

        assertEq(principal1, 10 ether);
        assertEq(principal2, 20 ether);
        assertTrue(exists1);
        assertTrue(exists2);
    }

    function test_MultipleAgentsIndependentYield() public {
        _depositFor(agent1, 10 ether, 0);
        _depositFor(agent2, 20 ether, 0);

        // Increase rate
        uint256 initialRate = wstETH.stEthPerToken();
        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 rateIncrease = newRate - initialRate;

        uint256 yield1 = treasury.getAccruedYield(agent1);
        uint256 yield2 = treasury.getAccruedYield(agent2);

        uint256 expected1 = (10 ether * rateIncrease) / initialRate;
        uint256 expected2 = (20 ether * rateIncrease) / initialRate;

        assertEq(yield1, expected1, "Agent1 yield should match");
        assertEq(yield2, expected2, "Agent2 yield should match");
        assertEq(yield2, yield1 * 2, "Agent2 yield should be double agent1's");
    }

    function test_MultipleAgentsIndependentClaims() public {
        _depositFor(agent1, 10 ether, 0);
        _depositFor(agent2, 20 ether, 0);

        _simulateYield(1.2075 ether);

        // Agent1 claims yield
        vm.prank(agent1);
        uint256 claimed1 = treasury.sweepYield();
        assertGt(claimed1, 0);

        // Agent2's yield should be unaffected
        // After agent1's claim, the rate was checkpointed for agent1 but not agent2
        // However, getAccruedYield for agent2 still uses agent2's lastStEthPerToken
        uint256 yield2 = treasury.getAccruedYield(agent2);
        assertGt(yield2, 0, "Agent2 yield should still be available");

        vm.prank(agent2);
        uint256 claimed2 = treasury.sweepYield();
        assertEq(claimed2, yield2, "Agent2 should claim their full yield");
    }

    function test_MultipleAgentsDifferentDepositTimes() public {
        // Agent1 deposits first
        _depositFor(agent1, 10 ether, 0);

        // Rate increases
        uint256 midRate = 1.2075 ether;
        wstETH.setStEthPerToken(midRate);

        // Agent2 deposits at higher rate
        _depositFor(agent2, 10 ether, 0);

        // Rate increases again
        uint256 finalRate = 1.265 ether; // ~5% above midRate
        wstETH.setStEthPerToken(finalRate);
        wstETH.mint(address(treasury), 50 ether);

        uint256 yield1 = treasury.getAccruedYield(agent1);
        uint256 yield2 = treasury.getAccruedYield(agent2);

        // Agent1 deposited at 1.15, current is 1.265
        // Agent1 yield: (10 * (1.265 - 1.15)) / 1.15 = (10 * 0.115) / 1.15 = 1.0 ether
        uint256 expected1 = (10 ether * (finalRate - 1.15 ether)) / 1.15 ether;

        // Agent2 deposited at 1.2075, current is 1.265
        // Agent2 yield: (10 * (1.265 - 1.2075)) / 1.2075
        uint256 expected2 = (10 ether * (finalRate - midRate)) / midRate;

        assertEq(yield1, expected1, "Agent1 yield should include full appreciation");
        assertEq(yield2, expected2, "Agent2 yield should only include post-deposit appreciation");
        assertGt(yield1, yield2, "Agent1 should have more yield (deposited earlier)");
    }

    // ============ Edge Cases ============

    function test_GetCurrentStEthPerToken() public view {
        assertEq(treasury.getCurrentStEthPerToken(), wstETH.stEthPerToken());
    }

    function test_WithdrawalLockConstant() public view {
        assertEq(treasury.WITHDRAWAL_LOCK(), 7 days);
    }

    function test_MinDepositConstant() public view {
        assertEq(treasury.MIN_DEPOSIT(), 0.001 ether);
    }

    function test_SpendAfterPartialYieldClaim() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        // Sweep yield first (claims all available)
        vm.prank(agent1);
        treasury.sweepYield();

        // Now increase rate again for more yield
        uint256 newerRate = 1.265 ether;
        wstETH.setStEthPerToken(newerRate);
        wstETH.mint(address(treasury), 50 ether);

        // Spend some of the new yield
        uint256 newYield = treasury.getAccruedYield(agent1);
        assertGt(newYield, 0, "Should have new yield after rate increase");

        vm.prank(agent1);
        treasury.spendYield(serviceProvider, newYield / 2, "Inference");

        (,,, uint256 totalSpent,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalSpent, newYield / 2);
    }

    function test_DepositAfterFullWithdrawal() public {
        // Deposit and fully withdraw
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(10 ether);
        skip(7 days);
        treasury.completeWithdrawal();
        vm.stopPrank();

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 0);
        assertTrue(exists);

        // Re-deposit
        _depositFor(agent1, 5 ether, 0);

        (principal,,,,,,, exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 5 ether, "Should be able to add to existing treasury");
        assertTrue(exists);
    }

    function test_TreasuryInfoReturnsCorrectRate() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 depositRate = wstETH.stEthPerToken();

        wstETH.setStEthPerToken(1.3 ether);

        (,,,,, uint256 currentRate, uint256 storedDepositRate,) = treasury.getTreasuryInfo(agent1);
        assertEq(currentRate, 1.3 ether, "Current rate should reflect new rate");
        assertEq(storedDepositRate, depositRate, "Deposit rate should be original");
    }

    function test_LargeDeposit() public {
        uint256 largeAmount = 10_000 ether;
        wstETH.mint(agent1, largeAmount);

        _depositFor(agent1, largeAmount, 0);

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, largeAmount);
        assertTrue(exists);
    }

    function test_YieldPrecisionWithSmallDeposit() public {
        // Deposit exactly the minimum
        _depositFor(agent1, 0.001 ether, 0);

        uint256 initialRate = wstETH.stEthPerToken();
        // 10% rate increase
        uint256 newRate = initialRate * 110 / 100;
        wstETH.setStEthPerToken(newRate);

        uint256 yield = treasury.getAccruedYield(agent1);
        uint256 expected = (0.001 ether * (newRate - initialRate)) / initialRate;
        assertEq(yield, expected, "Yield should be precise even for small deposits");
        assertGt(yield, 0, "Should have non-zero yield");
    }

    function test_SwapYieldToETHThenSwapYieldToUSDCSequentially() public {
        _depositFor(agent1, 10 ether, 0);

        // First yield period
        uint256 rate1 = 1.2075 ether;
        _simulateYield(rate1);

        vm.prank(agent1);
        uint256 ethOut = treasury.swapYieldToETH(0);
        assertGt(ethOut, 0);

        // Second yield period
        uint256 rate2 = 1.265 ether;
        wstETH.setStEthPerToken(rate2);
        wstETH.mint(address(treasury), 50 ether);

        vm.prank(agent1);
        uint256 usdcOut = treasury.swapYieldToUSDC(0);
        assertGt(usdcOut, 0);

        // Both yields should be tracked
        (,, uint256 totalClaimed,,,,,) = treasury.getTreasuryInfo(agent1);
        assertGt(totalClaimed, 0, "Total claimed should reflect both swaps");
    }

    function test_ThreeAgentsFullLifecycle() public {
        // All three agents deposit
        _depositFor(agent1, 10 ether, 42);
        _depositFor(agent2, 20 ether, 99);
        _depositFor(agent3, 5 ether, 0);

        assertEq(treasury.totalPrincipal(), 35 ether);
        assertEq(treasury.agentERC8004Id(agent1), 42);
        assertEq(treasury.agentERC8004Id(agent2), 99);
        assertEq(treasury.agentERC8004Id(agent3), 0);

        // Yield accrues
        _simulateYield(1.2075 ether);

        // Agent1 sweeps yield
        vm.prank(agent1);
        uint256 yield1 = treasury.sweepYield();
        assertGt(yield1, 0);

        // Agent2 swaps yield to USDC
        vm.prank(agent2);
        uint256 usdcOut = treasury.swapYieldToUSDC(0);
        assertGt(usdcOut, 0);

        // Agent3 spends yield
        uint256 yield3 = treasury.getAccruedYield(agent3);
        if (yield3 > 0) {
            vm.prank(agent3);
            treasury.spendYield(serviceProvider, yield3, "AI inference");
        }

        // Agent1 initiates withdrawal
        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        skip(7 days);

        vm.prank(agent1);
        treasury.completeWithdrawal();

        (uint256 p1,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(p1, 5 ether, "Agent1 should have half principal remaining");
        assertEq(treasury.totalPrincipal(), 30 ether, "Total principal should reflect withdrawal");
    }
}
