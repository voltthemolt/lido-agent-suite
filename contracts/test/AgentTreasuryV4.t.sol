// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentTreasuryV4, ISwapRouter02} from "../src/AgentTreasuryV4.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============ Mock Contracts ============

/**
 * @notice Mock wstETH as a plain ERC20 (no rate functions — V4 doesn't call them)
 */
contract MockWstETHV4 is IERC20 {
    string public name = "Wrapped liquid staked Ether 2.0";
    string public symbol = "wstETH";
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
 * @notice Mock USDC with 6 decimals
 */
contract MockUSDCV4 is IERC20 {
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
contract MockWETHV4 is IERC20 {
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
 * @notice Mock Uniswap V3 SwapRouter02 (Base version — no deadline in structs)
 * @dev Implements ISwapRouter02 from AgentTreasuryV4. Simulates swaps with fixed rates.
 */
contract MockSwapRouter02 is ISwapRouter02 {
    MockWstETHV4 public wstETH;
    MockWETHV4 public weth;
    MockUSDCV4 public usdc;

    /// @notice Fixed simulated exchange rate: 1 wstETH = 2 ETH (WETH)
    uint256 public wstethToWethRate = 2 ether;
    /// @notice Fixed simulated exchange rate: 1 wstETH = 4000 USDC (4000e6)
    uint256 public wstethToUsdcRate = 4000e6;

    constructor(address _wstETH, address _weth, address _usdc) {
        wstETH = MockWstETHV4(_wstETH);
        weth = MockWETHV4(_weth);
        usdc = MockUSDCV4(_usdc);
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
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

    function exactInput(ExactInputParams calldata params)
        external
        payable
        override
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
}

// ============ Test Contract ============

/**
 * @title AgentTreasuryV4 Test Suite
 * @notice Tests for V4 treasury: owner-updatable rate oracle, SwapRouter02 (no deadline), 100 fee tier
 */
contract AgentTreasuryV4Test is Test {

    AgentTreasuryV4 public treasury;

    // Mock tokens
    MockWstETHV4 public wstETH;
    MockWETHV4 public weth;
    MockUSDCV4 public usdc;
    MockSwapRouter02 public router;

    // Test addresses
    address public owner;
    address public agent1;
    address public agent2;
    address public agent3;
    address public serviceProvider;
    address public serviceProvider2;

    uint256 public constant INITIAL_RATE = 1.15 ether;

    // ============ Events (mirrored from AgentTreasuryV4Events for expectEmit) ============
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

    function setUp() public {
        owner = makeAddr("owner");
        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        agent3 = makeAddr("agent3");
        serviceProvider = makeAddr("serviceProvider");
        serviceProvider2 = makeAddr("serviceProvider2");

        // Deploy mock tokens
        wstETH = new MockWstETHV4();
        weth = new MockWETHV4();
        usdc = new MockUSDCV4();

        // Deploy mock swap router
        router = new MockSwapRouter02(address(wstETH), address(weth), address(usdc));

        // Deploy treasury with initial rate
        vm.prank(owner);
        treasury = new AgentTreasuryV4(
            address(wstETH),
            address(router),
            address(weth),
            address(usdc),
            INITIAL_RATE
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

    /// @notice Helper to simulate yield by updating the rate and minting tokens to cover yield
    function _simulateYield(uint256 newRate) internal {
        vm.prank(owner);
        treasury.updateRate(newRate);
        // Mint enough wstETH to the treasury to cover yield claims
        wstETH.mint(address(treasury), 50 ether);
    }

    // ============ Constructor Tests ============

    function test_ConstructorSetsImmutables() public view {
        assertEq(address(treasury.wstETH()), address(wstETH));
        assertEq(address(treasury.swapRouter()), address(router));
        assertEq(treasury.WETH(), address(weth));
        assertEq(treasury.USDC(), address(usdc));
    }

    function test_ConstructorSetsInitialRate() public view {
        assertEq(treasury.stEthPerToken(), INITIAL_RATE, "Initial rate should be set");
        assertEq(treasury.getCurrentStEthPerToken(), INITIAL_RATE, "getCurrentStEthPerToken should match");
    }

    function test_ConstructorSetsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    function test_ConstructorRevertsZeroWstETH() public {
        vm.expectRevert("Invalid wstETH");
        new AgentTreasuryV4(address(0), address(router), address(weth), address(usdc), INITIAL_RATE);
    }

    function test_ConstructorRevertsZeroRouter() public {
        vm.expectRevert("Invalid router");
        new AgentTreasuryV4(address(wstETH), address(0), address(weth), address(usdc), INITIAL_RATE);
    }

    function test_ConstructorRevertsZeroWETH() public {
        vm.expectRevert("Invalid WETH");
        new AgentTreasuryV4(address(wstETH), address(router), address(0), address(usdc), INITIAL_RATE);
    }

    function test_ConstructorRevertsZeroUSDC() public {
        vm.expectRevert("Invalid USDC");
        new AgentTreasuryV4(address(wstETH), address(router), address(weth), address(0), INITIAL_RATE);
    }

    function test_ConstructorRevertsZeroRate() public {
        vm.expectRevert("Invalid rate");
        new AgentTreasuryV4(address(wstETH), address(router), address(weth), address(usdc), 0);
    }

    // ============ updateRate Tests ============

    function test_UpdateRate() public {
        uint256 newRate = 1.20 ether;

        vm.prank(owner);
        treasury.updateRate(newRate);

        assertEq(treasury.stEthPerToken(), newRate, "Rate should be updated");
    }

    function test_UpdateRateEmitsEvent() public {
        uint256 newRate = 1.20 ether;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit RateUpdated(INITIAL_RATE, newRate, block.timestamp);
        treasury.updateRate(newRate);
    }

    function test_UpdateRateOnlyOwner() public {
        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", agent1));
        treasury.updateRate(1.20 ether);
    }

    function test_UpdateRateRevertsZero() public {
        vm.prank(owner);
        vm.expectRevert("Invalid rate");
        treasury.updateRate(0);
    }

    function test_UpdateRateMultipleTimes() public {
        vm.startPrank(owner);

        treasury.updateRate(1.16 ether);
        assertEq(treasury.stEthPerToken(), 1.16 ether);

        treasury.updateRate(1.17 ether);
        assertEq(treasury.stEthPerToken(), 1.17 ether);

        treasury.updateRate(1.18 ether);
        assertEq(treasury.stEthPerToken(), 1.18 ether);

        vm.stopPrank();
    }

    function test_UpdateRateCanDecrease() public {
        vm.startPrank(owner);
        treasury.updateRate(1.10 ether);
        assertEq(treasury.stEthPerToken(), 1.10 ether, "Rate can be set lower than initial");
        vm.stopPrank();
    }

    // ============ Rate Update Affects Yield Tests ============

    function test_RateUpdateAffectsYieldCalculation() public {
        _depositFor(agent1, 10 ether, 0);

        // Update rate from 1.15 to 1.2075 (5% increase)
        uint256 newRate = 1.2075 ether;
        vm.prank(owner);
        treasury.updateRate(newRate);

        uint256 accrued = treasury.getAccruedYield(agent1);
        // Expected: (10 ether * (1.2075 - 1.15)) / 1.15 = (10 * 0.0575) / 1.15 = 0.5 ether
        uint256 expected = (10 ether * (newRate - INITIAL_RATE)) / INITIAL_RATE;
        assertEq(accrued, expected, "Accrued yield should match formula");
        assertEq(accrued, 0.5 ether, "Accrued yield should be 0.5 ether");
    }

    function test_RateDecreaseAfterDepositYieldsZero() public {
        _depositFor(agent1, 10 ether, 0);

        // Decrease rate
        vm.prank(owner);
        treasury.updateRate(1.10 ether);

        uint256 accrued = treasury.getAccruedYield(agent1);
        assertEq(accrued, 0, "No yield when rate decreases");
    }

    function test_RateDecreaseAfterIncreaseResetsYield() public {
        _depositFor(agent1, 10 ether, 0);

        // Rate goes up
        vm.prank(owner);
        treasury.updateRate(1.20 ether);

        uint256 yieldAfterIncrease = treasury.getAccruedYield(agent1);
        assertGt(yieldAfterIncrease, 0, "Should have yield after increase");

        // Rate goes back down below deposit rate
        vm.prank(owner);
        treasury.updateRate(1.10 ether);

        uint256 yieldAfterDecrease = treasury.getAccruedYield(agent1);
        assertEq(yieldAfterDecrease, 0, "Yield should be 0 after rate drop below deposit rate");
    }

    function test_MultipleRateUpdatesBetweenOperations() public {
        _depositFor(agent1, 10 ether, 0);

        // Multiple rate updates
        vm.startPrank(owner);
        treasury.updateRate(1.16 ether);
        treasury.updateRate(1.17 ether);
        treasury.updateRate(1.20 ether);
        vm.stopPrank();

        // Only the final rate matters for yield calculation
        uint256 accrued = treasury.getAccruedYield(agent1);
        uint256 expected = (10 ether * (1.20 ether - INITIAL_RATE)) / INITIAL_RATE;
        assertEq(accrued, expected, "Yield should reflect final rate only");
    }

    function test_RateUpdateBetweenDeposits() public {
        // First deposit at initial rate 1.15
        _depositFor(agent1, 10 ether, 0);

        // Rate increases
        uint256 midRate = 1.20 ether;
        vm.prank(owner);
        treasury.updateRate(midRate);

        // Yield before second deposit
        uint256 yieldBefore = treasury.getAccruedYield(agent1);
        uint256 expectedYield = (10 ether * (midRate - INITIAL_RATE)) / INITIAL_RATE;
        assertEq(yieldBefore, expectedYield, "Yield should accrue before second deposit");

        // Second deposit checkpoints yield (lastStEthPerToken updated to midRate)
        _depositFor(agent1, 5 ether, 0);

        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 15 ether, "Principal includes both deposits");

        // Accrued yield resets after checkpoint since rate hasn't changed
        uint256 yieldAfter = treasury.getAccruedYield(agent1);
        assertEq(yieldAfter, 0, "Yield resets after checkpoint at same rate");

        // Rate increases again
        uint256 finalRate = 1.25 ether;
        vm.prank(owner);
        treasury.updateRate(finalRate);

        // Yield is now based on 15 ether principal from midRate
        uint256 newYield = treasury.getAccruedYield(agent1);
        uint256 expectedNew = (15 ether * (finalRate - midRate)) / midRate;
        assertEq(newYield, expectedNew, "Yield should accrue on full principal from checkpointed rate");
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        vm.startPrank(agent1);
        wstETH.approve(address(treasury), 10 ether);

        vm.expectEmit(true, false, false, true);
        emit Deposited(agent1, 10 ether, INITIAL_RATE);

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
        assertEq(currentRate, INITIAL_RATE);
        assertEq(depositRate, INITIAL_RATE);
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

        // Increase rate to simulate yield accrual
        uint256 newRate = 1.20 ether;
        vm.prank(owner);
        treasury.updateRate(newRate);

        // Yield before second deposit
        uint256 yieldBefore = treasury.getAccruedYield(agent1);
        uint256 expectedYield = (10 ether * (newRate - INITIAL_RATE)) / INITIAL_RATE;
        assertEq(yieldBefore, expectedYield, "Yield should accrue before second deposit");

        // Second deposit should checkpoint yield (updating lastStEthPerToken)
        _depositFor(agent1, 5 ether, 0);

        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 15 ether, "Principal includes both deposits");
    }

    // ============ Yield Calculation Tests ============

    function test_YieldAccruesOnRateIncrease() public {
        _depositFor(agent1, 10 ether, 0);

        // Increase rate by ~5%
        uint256 newRate = 1.2075 ether; // 1.15 * 1.05
        vm.prank(owner);
        treasury.updateRate(newRate);

        uint256 accrued = treasury.getAccruedYield(agent1);
        uint256 expected = (10 ether * (newRate - INITIAL_RATE)) / INITIAL_RATE;
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

        vm.prank(owner);
        treasury.updateRate(1.10 ether);

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
        assertEq(treasury.getAvailableYield(agent1), 0, "Available yield should be 0 after full claim");
        assertEq(claimed, accrued, "Claimed should equal accrued");
    }

    // ============ sweepYield Tests ============

    function test_SweepYield() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - INITIAL_RATE)) / INITIAL_RATE;
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

    function test_SweepYieldAfterRateIncrease() public {
        _depositFor(agent1, 10 ether, 0);

        // First rate increase
        _simulateYield(1.20 ether);

        vm.prank(agent1);
        uint256 claimed1 = treasury.sweepYield();
        assertGt(claimed1, 0, "Should claim yield from first rate increase");

        // Second rate increase
        _simulateYield(1.25 ether);

        vm.prank(agent1);
        uint256 claimed2 = treasury.sweepYield();
        assertGt(claimed2, 0, "Should claim yield from second rate increase");

        // Total claimed
        (,, uint256 totalClaimed,,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalClaimed, claimed1 + claimed2, "Total claimed should be sum of both sweeps");
    }

    // ============ swapYieldToETH Tests ============

    function test_SwapYieldToETH() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - INITIAL_RATE)) / INITIAL_RATE;
        // Mock router converts at 2 ETH per wstETH
        uint256 expectedEth = (expectedYield * 2 ether) / 1 ether;

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit YieldSwappedToETH(agent1, expectedYield, expectedEth);
        uint256 ethOut = treasury.swapYieldToETH(0);

        assertEq(ethOut, expectedEth, "Should receive expected WETH");
        assertEq(weth.balanceOf(agent1), expectedEth, "Agent should have WETH");

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

    function test_SwapYieldToETHUsing100FeeTier() public {
        // This test verifies the contract compiles and works with the 100 fee tier
        // The V4 contract hard-codes fee: 100 (0.01% for correlated pairs on Base)
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        vm.prank(agent1);
        uint256 ethOut = treasury.swapYieldToETH(0);
        assertGt(ethOut, 0, "Swap with 100 fee tier should work");
    }

    // ============ swapYieldToUSDC Tests ============

    function test_SwapYieldToUSDC() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 newRate = 1.2075 ether;
        _simulateYield(newRate);

        uint256 expectedYield = (10 ether * (newRate - INITIAL_RATE)) / INITIAL_RATE;
        // Mock router converts at 4000 USDC per wstETH
        uint256 expectedUsdc = (expectedYield * 4000e6) / 1 ether;

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit YieldSwappedToUSDC(agent1, expectedYield, expectedUsdc);
        uint256 usdcOut = treasury.swapYieldToUSDC(0);

        assertEq(usdcOut, expectedUsdc, "Should receive expected USDC");
        assertEq(usdc.balanceOf(agent1), expectedUsdc, "Agent should have USDC");

        // Check totalYieldClaimed updated
        (,, uint256 totalYieldClaimed,,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalYieldClaimed, expectedYield);
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

    // ============ spendYield Tests ============

    function test_SpendYield() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        uint256 availableYield = treasury.getAccruedYield(agent1);
        uint256 spendAmount = availableYield / 2;

        uint256 providerBefore = wstETH.balanceOf(serviceProvider);

        vm.prank(agent1);
        vm.expectEmit(true, true, false, true);
        emit YieldSpent(agent1, serviceProvider, spendAmount, "AI inference");
        treasury.spendYield(serviceProvider, spendAmount, "AI inference");

        assertEq(wstETH.balanceOf(serviceProvider), providerBefore + spendAmount, "Provider should receive wstETH");

        (,,, uint256 totalYieldSpent,,,,) = treasury.getTreasuryInfo(agent1);
        assertEq(totalYieldSpent, spendAmount);
    }

    function test_SpendYieldRevertsNotAllowlisted() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        address notAllowlisted = makeAddr("notAllowlisted");

        vm.prank(agent1);
        vm.expectRevert("Recipient not allowlisted");
        treasury.spendYield(notAllowlisted, 0.1 ether, "test");
    }

    function test_SpendYieldRevertsInsufficientYield() public {
        _depositFor(agent1, 10 ether, 0);
        _simulateYield(1.2075 ether);

        uint256 availableYield = treasury.getAccruedYield(agent1);

        vm.prank(agent1);
        vm.expectRevert("Insufficient yield");
        treasury.spendYield(serviceProvider, availableYield + 1, "too much");
    }

    function test_SpendYieldRevertsNoTreasury() public {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("No treasury found");
        treasury.spendYield(serviceProvider, 0.1 ether, "test");
    }

    // ============ Withdrawal Flow Tests ============

    function test_InitiateWithdrawal() public {
        _depositFor(agent1, 10 ether, 0);

        uint256 unlockTime = block.timestamp + 7 days;

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit WithdrawalInitiated(agent1, 5 ether, unlockTime);
        treasury.initiateWithdrawal(5 ether);

        (uint256 amount, uint256 unlock, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 5 ether);
        assertEq(unlock, unlockTime);
        assertFalse(ready, "Should not be ready yet");
    }

    function test_InitiateWithdrawalRevertsInsufficientPrincipal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("Insufficient principal");
        treasury.initiateWithdrawal(11 ether);
    }

    function test_InitiateWithdrawalRevertsWhenAlreadyPending() public {
        _depositFor(agent1, 10 ether, 0);

        vm.startPrank(agent1);
        treasury.initiateWithdrawal(5 ether);

        vm.expectRevert("Withdrawal pending");
        treasury.initiateWithdrawal(3 ether);
        vm.stopPrank();
    }

    function test_CompleteWithdrawal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        // Warp past lock period
        vm.warp(block.timestamp + 7 days);

        uint256 balanceBefore = wstETH.balanceOf(agent1);

        vm.prank(agent1);
        vm.expectEmit(true, false, false, true);
        emit PrincipalWithdrawn(agent1, 5 ether);
        treasury.completeWithdrawal();

        assertEq(wstETH.balanceOf(agent1), balanceBefore + 5 ether, "Agent should receive wstETH");

        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 5 ether, "Principal should be reduced");
        assertEq(treasury.totalPrincipal(), 5 ether);

        // Pending withdrawal should be cleared
        (uint256 amt,, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amt, 0);
        assertFalse(ready);
    }

    function test_CompleteWithdrawalRevertsBeforeLock() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        // Warp to just before lock expiry
        vm.warp(block.timestamp + 7 days - 1);

        vm.prank(agent1);
        vm.expectRevert("Locked");
        treasury.completeWithdrawal();
    }

    function test_CompleteWithdrawalRevertsNoPending() public {
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

        // Pending should be cleared
        (uint256 amt,, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amt, 0);
        assertFalse(ready);

        // Principal should be unchanged
        (uint256 principal,,,,,,, ) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 10 ether);

        vm.stopPrank();
    }

    function test_CancelWithdrawalRevertsNoPending() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        vm.expectRevert("No pending");
        treasury.cancelWithdrawal();
    }

    // ============ allowlistAIProviders Tests ============

    function test_AllowlistAIProviders() public {
        address[] memory providers = new address[](2);
        providers[0] = serviceProvider;
        providers[1] = serviceProvider2;
        string[] memory names = new string[](2);
        names[0] = "Venice AI";
        names[1] = "OpenRouter";

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SpendingAllowlisted(serviceProvider, "Venice AI");
        vm.expectEmit(true, false, false, true);
        emit SpendingAllowlisted(serviceProvider2, "OpenRouter");
        treasury.allowlistAIProviders(providers, names);

        assertTrue(treasury.spendingAllowlist(serviceProvider));
        assertTrue(treasury.spendingAllowlist(serviceProvider2));
        assertEq(treasury.serviceProviderNames(serviceProvider), "Venice AI");
        assertEq(treasury.serviceProviderNames(serviceProvider2), "OpenRouter");
    }

    function test_AllowlistAIProvidersRevertsLengthMismatch() public {
        address[] memory providers = new address[](2);
        providers[0] = serviceProvider;
        providers[1] = serviceProvider2;
        string[] memory names = new string[](1);
        names[0] = "Venice AI";

        vm.prank(owner);
        vm.expectRevert("Length mismatch");
        treasury.allowlistAIProviders(providers, names);
    }

    function test_AllowlistAIProvidersOnlyOwner() public {
        address[] memory providers = new address[](1);
        providers[0] = serviceProvider;
        string[] memory names = new string[](1);
        names[0] = "Venice AI";

        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", agent1));
        treasury.allowlistAIProviders(providers, names);
    }

    function test_DelistSpending() public {
        assertTrue(treasury.spendingAllowlist(serviceProvider), "Should start allowlisted");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit SpendingDelisted(serviceProvider);
        treasury.delistSpending(serviceProvider);

        assertFalse(treasury.spendingAllowlist(serviceProvider), "Should be delisted");
    }

    // ============ getYieldStats Tests ============

    function test_GetYieldStats() public {
        _depositFor(agent1, 10 ether, 0);

        // Warp time forward and increase rate
        vm.warp(block.timestamp + 365 days);
        uint256 newRate = 1.2075 ether;
        vm.prank(owner);
        treasury.updateRate(newRate);

        (
            uint256 principalWstETH,
            uint256 currentStETHValue,
            uint256 yieldEarnedStETH,
            uint256 aprBps
        ) = treasury.getYieldStats(agent1);

        assertEq(principalWstETH, 10 ether, "Principal should be 10 wstETH");
        assertEq(currentStETHValue, (10 ether * newRate) / 1e18, "Current stETH value should reflect new rate");

        uint256 principalStETH = (10 ether * INITIAL_RATE) / 1e18;
        uint256 expectedYieldStETH = currentStETHValue - principalStETH;
        assertEq(yieldEarnedStETH, expectedYieldStETH, "Yield in stETH terms");

        // APR: yieldEarned / principal * 10000 (bps) * 365 days / elapsed
        // elapsed == 365 days, so APR = yieldEarned * 10000 / principal
        uint256 expectedApr = (expectedYieldStETH * 10000) / principalStETH;
        assertEq(aprBps, expectedApr, "APR should match expected");
    }

    function test_GetYieldStatsWithRateChanges() public {
        _depositFor(agent1, 10 ether, 0);

        vm.warp(block.timestamp + 180 days);

        // Rate goes up
        vm.prank(owner);
        treasury.updateRate(1.18 ether);

        (
            uint256 principalWstETH,
            uint256 currentStETHValue,
            uint256 yieldEarnedStETH,
            uint256 aprBps
        ) = treasury.getYieldStats(agent1);

        assertEq(principalWstETH, 10 ether);
        assertGt(currentStETHValue, 0);
        assertGt(yieldEarnedStETH, 0, "Should have yield at higher rate");
        assertGt(aprBps, 0, "APR should be positive");
    }

    function test_GetYieldStatsNonExistentAgent() public {
        address nobody = makeAddr("nobody");
        (uint256 p, uint256 v, uint256 y, uint256 a) = treasury.getYieldStats(nobody);
        assertEq(p, 0);
        assertEq(v, 0);
        assertEq(y, 0);
        assertEq(a, 0);
    }

    function test_GetYieldStatsWhenRateDecrease() public {
        _depositFor(agent1, 10 ether, 0);
        vm.warp(block.timestamp + 30 days);

        // Rate goes down
        vm.prank(owner);
        treasury.updateRate(1.10 ether);

        (,, uint256 yieldEarnedStETH,) = treasury.getYieldStats(agent1);
        assertEq(yieldEarnedStETH, 0, "Yield should be 0 when rate drops");
    }

    // ============ getTreasuryInfo Tests ============

    function test_GetTreasuryInfo() public {
        _depositFor(agent1, 10 ether, 42);

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

        assertEq(principal, 10 ether);
        assertEq(availableYield, 0);
        assertEq(totalYieldClaimed, 0);
        assertEq(totalYieldSpent, 0);
        assertGt(depositTime, 0);
        assertEq(currentRate, INITIAL_RATE);
        assertEq(depositRate, INITIAL_RATE);
        assertTrue(exists);
    }

    function test_GetTreasuryInfoReflectsRateUpdate() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(owner);
        treasury.updateRate(1.20 ether);

        (
            ,
            uint256 availableYield,
            ,
            ,
            ,
            uint256 currentRate,
            uint256 depositRate,
        ) = treasury.getTreasuryInfo(agent1);

        assertEq(currentRate, 1.20 ether, "Current rate should reflect update");
        assertEq(depositRate, INITIAL_RATE, "Deposit rate should not change");
        assertGt(availableYield, 0, "Should have yield after rate increase");
    }

    // ============ getWithdrawalInfo Tests ============

    function test_GetWithdrawalInfoNoPending() public {
        _depositFor(agent1, 10 ether, 0);

        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 0);
        assertEq(unlockTime, 0);
        assertFalse(ready);
    }

    function test_GetWithdrawalInfoPending() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 5 ether);
        assertEq(unlockTime, block.timestamp + 7 days);
        assertFalse(ready, "Not ready yet");
    }

    function test_GetWithdrawalInfoReady() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        vm.warp(block.timestamp + 7 days);

        (uint256 amount, uint256 unlockTime, bool ready) = treasury.getWithdrawalInfo(agent1);
        assertEq(amount, 5 ether);
        assertGt(unlockTime, 0);
        assertTrue(ready, "Should be ready after lock period");
    }

    // ============ Multiple Agents with Independent Yield after Rate Updates ============

    function test_MultipleAgentsIndependentYield() public {
        // Agent1 deposits first
        _depositFor(agent1, 10 ether, 0);

        // Rate increases
        vm.prank(owner);
        treasury.updateRate(1.20 ether);

        // Agent2 deposits after rate increase
        _depositFor(agent2, 10 ether, 0);

        // Rate increases again
        vm.prank(owner);
        treasury.updateRate(1.25 ether);

        // Agent1 yield should be based on rate change from 1.15 -> 1.25
        uint256 agent1Yield = treasury.getAccruedYield(agent1);
        uint256 expectedAgent1 = (10 ether * (1.25 ether - INITIAL_RATE)) / INITIAL_RATE;
        assertEq(agent1Yield, expectedAgent1, "Agent1 yield from initial rate");

        // Agent2 yield should be based on rate change from 1.20 -> 1.25
        uint256 agent2Yield = treasury.getAccruedYield(agent2);
        uint256 agent2DepositRate = 1.20 ether;
        uint256 agent2CurrentRate = 1.25 ether;
        uint256 expectedAgent2 = (10 ether * (agent2CurrentRate - agent2DepositRate)) / agent2DepositRate;
        assertEq(agent2Yield, expectedAgent2, "Agent2 yield from later deposit rate");

        // Agent1 should have more yield since they deposited earlier
        assertGt(agent1Yield, agent2Yield, "Earlier depositor should have more yield");
    }

    function test_MultipleAgentsIndependentAfterRateUpdates() public {
        _depositFor(agent1, 20 ether, 0);
        _depositFor(agent2, 10 ether, 0);

        // Rate goes up
        vm.prank(owner);
        treasury.updateRate(1.20 ether);

        // Agent1 sweeps yield
        wstETH.mint(address(treasury), 50 ether);
        vm.prank(agent1);
        uint256 agent1Claimed = treasury.sweepYield();
        assertGt(agent1Claimed, 0);

        // Agent2 hasn't swept yet - their yield should still be there
        uint256 agent2Yield = treasury.getAccruedYield(agent2);
        assertGt(agent2Yield, 0, "Agent2 yield should be unaffected by agent1 sweep");

        // Rate goes up again
        vm.prank(owner);
        treasury.updateRate(1.25 ether);

        // Agent2 now sweeps
        vm.prank(agent2);
        uint256 agent2Claimed = treasury.sweepYield();
        assertGt(agent2Claimed, 0);

        // Agent1 should also have new yield from 1.20 -> 1.25
        uint256 agent1NewYield = treasury.getAccruedYield(agent1);
        uint256 a1CheckpointRate = 1.20 ether;
        uint256 a1FinalRate = 1.25 ether;
        uint256 expectedAgent1New = (20 ether * (a1FinalRate - a1CheckpointRate)) / a1CheckpointRate;
        assertEq(agent1NewYield, expectedAgent1New, "Agent1 new yield from checkpointed rate");
    }

    // ============ Full Lifecycle Test ============

    function test_FullLifecycleDepositRateUpdateSweepSwapToUSDC() public {
        // 1. Deposit
        _depositFor(agent1, 10 ether, 1001);
        assertEq(treasury.agentERC8004Id(agent1), 1001);

        // 2. First rate update (yield accrues)
        vm.prank(owner);
        treasury.updateRate(1.20 ether);
        wstETH.mint(address(treasury), 50 ether);

        uint256 yieldAfterFirst = treasury.getAccruedYield(agent1);
        assertGt(yieldAfterFirst, 0, "Should have yield after first rate update");

        // 3. Sweep yield
        vm.prank(agent1);
        uint256 swept = treasury.sweepYield();
        assertEq(swept, yieldAfterFirst, "Swept amount should equal accrued");

        // 4. Second rate update
        vm.prank(owner);
        treasury.updateRate(1.30 ether);

        uint256 yieldAfterSecond = treasury.getAccruedYield(agent1);
        assertGt(yieldAfterSecond, 0, "Should have yield after second rate update");

        // 5. Swap yield to USDC
        vm.prank(agent1);
        uint256 usdcOut = treasury.swapYieldToUSDC(0);
        assertGt(usdcOut, 0, "Should receive USDC");
        assertGt(usdc.balanceOf(agent1), 0, "Agent should hold USDC");

        // 6. Verify totals
        (
            uint256 principal,
            ,
            uint256 totalYieldClaimed,
            ,
            ,
            uint256 currentRate,
            uint256 depositRate,
        ) = treasury.getTreasuryInfo(agent1);

        assertEq(principal, 10 ether, "Principal should be unchanged");
        assertEq(totalYieldClaimed, swept + yieldAfterSecond, "Total claimed should be sum of both operations");
        assertEq(currentRate, 1.30 ether, "Current rate should reflect last update");
        assertEq(depositRate, INITIAL_RATE, "Deposit rate should remain initial");
    }

    function test_FullLifecycleWithWithdrawal() public {
        // Deposit
        _depositFor(agent1, 10 ether, 0);

        // Accumulate yield
        _simulateYield(1.25 ether);

        // Spend some yield
        vm.prank(agent1);
        treasury.spendYield(serviceProvider, 0.1 ether, "AI compute");

        // Initiate withdrawal
        vm.prank(agent1);
        treasury.initiateWithdrawal(5 ether);

        // Warp and complete
        vm.warp(block.timestamp + 7 days);

        vm.prank(agent1);
        treasury.completeWithdrawal();

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 5 ether, "Half withdrawn");
        assertTrue(exists, "Treasury still exists");
        assertEq(treasury.totalPrincipal(), 5 ether);
    }

    // ============ Edge Cases ============

    function test_DepositAfterRateUpdateUsesNewRate() public {
        // Update rate before any deposits
        vm.prank(owner);
        treasury.updateRate(1.20 ether);

        _depositFor(agent1, 10 ether, 0);

        (,,,,, uint256 currentRate, uint256 depositRate,) = treasury.getTreasuryInfo(agent1);
        assertEq(depositRate, 1.20 ether, "Deposit rate should be updated rate");
        assertEq(currentRate, 1.20 ether, "Current rate should match");
    }

    function test_StEthPerTokenIsPublicStateVariable() public view {
        // V4 stores stEthPerToken as a public state variable (not an external call)
        uint256 rate = treasury.stEthPerToken();
        assertEq(rate, INITIAL_RATE, "stEthPerToken should be a readable state variable");

        // getCurrentStEthPerToken() should return the same thing
        assertEq(treasury.getCurrentStEthPerToken(), rate);
    }

    function test_WithdrawalFullPrincipal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(10 ether);

        vm.warp(block.timestamp + 7 days);

        vm.prank(agent1);
        treasury.completeWithdrawal();

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 0, "Principal should be zero");
        assertTrue(exists, "Treasury still exists even with 0 principal");
        assertEq(treasury.totalPrincipal(), 0);
    }

    function test_ReDepositAfterFullWithdrawal() public {
        _depositFor(agent1, 10 ether, 0);

        vm.prank(agent1);
        treasury.initiateWithdrawal(10 ether);
        vm.warp(block.timestamp + 7 days);
        vm.prank(agent1);
        treasury.completeWithdrawal();

        // Deposit again
        _depositFor(agent1, 5 ether, 0);

        (uint256 principal,,,,,,, bool exists) = treasury.getTreasuryInfo(agent1);
        assertEq(principal, 5 ether, "Principal should reflect new deposit");
        assertTrue(exists);
    }

    function test_ConstantValues() public view {
        assertEq(treasury.WITHDRAWAL_LOCK(), 7 days);
        assertEq(treasury.MIN_DEPOSIT(), 0.001 ether);
    }
}
