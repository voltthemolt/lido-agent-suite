# Lido Agent Suite

> **Autonomous AI Agents with Sustainable wstETH Treasury**

A complete toolkit enabling AI agents to hold, manage, and spend wstETH yield while keeping principal locked and secure. Built for the [Synthesis Hackathon](https://synthesis.md).

## Live Deployment

**Base Mainnet:**
- **Contract V4 (Active):** [`0x4e0acb29d642982403a3bd6a40181a828f2265a0`](https://basescan.org/address/0x4e0acb29d642982403a3bd6a40181a828f2265a0) - L2-compatible with oracle rate
- Contract V3: [`0x555895c59C057Bc040dd7995bEe9C8bcB1A7429D`](https://basescan.org/address/0x555895c59C057Bc040dd7995bEe9C8bcB1A7429D)
- Contract V2: [`0x226AF8855e1B08385962a57f74BB75b240bdCEf6`](https://basescan.org/address/0x226AF8855e1B08385962a57f74BB75b240bdCEf6)
- Contract V1: [`0x19BaBAAc240CdBCD7D693c92eB4Df9BA9Eb4Fc0e`](https://basescan.org/address/0x19BaBAAc240CdBCD7D693c92eB4Df9BA9Eb4Fc0e)
- wstETH: [`0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452`](https://basescan.org/token/0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452)
- USDC: [`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`](https://basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
- Frontend: [lido-agent-suite.vercel.app](https://lido-agent-suite.vercel.app)

**Features:**
- Deposit wstETH, earn staking yield automatically
- Sweep yield to wallet (claim just the interest)
- Swap yield to ETH via Uniswap V3 (bypass withdrawal delay)
- Swap yield to USDC for AI inference (Venice, Bankr)
- Spend yield on allowlisted services
- Withdraw principal with 7-day timelock
- Real-time yield tracking and APY display

**Prize Eligibility:**
| Sponsor | Feature | How We Use It |
|---------|---------|---------------|
| **Lido** | wstETH staking | Core yield generation |
| **Uniswap** | V3 SwapRouter | Instant wstETH -> ETH/USDC |
| **Base** | L2 deployment | Low gas costs ($0.14 vs $80+) |
| **Venice** | AI inference | USDC payments for uncensored AI |

## Overview

The Lido Agent Suite solves a critical problem for autonomous AI agents: **how to manage funds sustainably without draining the principal**.

### The Problem

AI agents increasingly need to pay for:
- API calls (OpenAI, Anthropic, etc.)
- Compute resources (AWS, GCP, Modal)
- On-chain operations (gas fees)
- Service subscriptions

But giving an agent full control over a wallet is risky - one bug or exploit could drain everything.

### The Solution

**Agent Treasury** - A smart contract that:
1. Accepts wstETH deposits
2. Locks the principal (withdrawable via 7-day timelock)
3. Lets agents spend ONLY the accumulated yield
4. Integrates with ERC-8004 for agent identity

This creates a **sustainable funding model** where agents can operate autonomously without risking the underlying capital.

## Architecture

```
+---------------------------------------------------------+
|                      User Layer                          |
|  +------------------+      +------------------+         |
|  |   AI Agent       |------|  ERC-8004 Identity|         |
|  |  (Hermes/Claude) | owns |  (On-chain NFT)   |         |
|  +--------+---------+      +------------------+         |
+-----------|----------------------------------------------+
            | MCP Protocol
            v
+---------------------------------------------------------+
|                   MCP Server Layer                       |
|  +---------------------------------------------------+  |
|  |              Lido MCP Server (Base)                |  |
|  |   13 Tools: balances, stake, wrap, swap, treasury, |  |
|  |   dry-run simulation                               |  |
|  +------------------------+---------------------------+  |
+--------------------------|-------------------------------+
                           |
             +-------------+-------------+
             v             v             v
  +---------------+ +---------------+ +---------------+
  | Lido Protocol | | Agent Treasury| |  Uniswap V3   |
  | stETH/wstETH  | | Lock & Spend  | | wstETH <> ETH |
  +---------------+ +---------------+ +---------------+
```

## Contract Evolution

### V4 (Current - Base L2 Compatible)

**Location:** `contracts/src/AgentTreasuryV4.sol`

V3 had a critical L2 compatibility issue: Base's bridged wstETH is a plain ERC20 that lacks `stEthPerToken()`, `getStETHByWstETH()`, and other rate functions available on Ethereum mainnet. Every V3 deposit/yield operation reverted on Base.

**V4 fixes this** with:
- **Owner-updatable rate oracle** - `stEthPerToken` stored as state, synced from L1 via `updateRate()`
- **SwapRouter02 interface** - Base uses Uniswap SwapRouter02 (no `deadline` in struct)
- **Correct fee tiers** - 0.01% for wstETH/WETH (correlated pair on Base)
- **203 total tests** across V1, V3, and V4 test suites

### V3 (USDC/AI Inference)

**Location:** `contracts/src/AgentTreasuryV3.sol`

Added Uniswap V3 integration for swapping yield to ETH and USDC. Note: non-functional on Base due to missing wstETH rate functions (see V4).

### V1 (Original)

**Location:** `contracts/src/AgentTreasury.sol`

Core treasury with stETH deposits, yield tracking, allowlisted spending, and 7-day withdrawal timelock.

## Components

### 1. Agent Treasury Smart Contract (V4)

**Key Features:**
- Deposit wstETH with optional ERC-8004 identity binding
- Principal locked in wstETH shares
- Yield tracking via stEthPerToken rate differential (oracle-based)
- Sweep yield as wstETH, or swap to ETH/USDC via Uniswap V3
- Allowlisted service providers for spending
- Batch allowlist AI providers
- 7-day timelock withdrawal

**Test Results:** 203/203 passing (18 V1 + 27 V1 invariant + 80 V3 + 76 V4 + 2 Counter)

```bash
cd contracts
forge test -vvv
```

### 2. Lido MCP Server (Base)

**Location:** `mcp-server/`

A Model Context Protocol server targeting Base mainnet, exposing 13 tools for AI agents.

| Tool | Description |
|------|-------------|
| `get_steth_balance` | Check stETH balance for any address |
| `get_wsteth_balance` | Check wstETH balance |
| `get_staking_stats` | Lido protocol statistics (TVL, APR) |
| `stake_eth` | Stake ETH to receive stETH |
| `wrap_steth` | Wrap stETH to wstETH |
| `unwrap_wsteth` | Unwrap wstETH to stETH |
| `swap_steth_to_eth` | Swap stETH to ETH via Uniswap V3 |
| `get_swap_quote` | Get swap price quote |
| `treasury_deposit` | Deposit to Agent Treasury |
| `treasury_get_yield` | Check available yield |
| `treasury_spend_yield` | Spend yield on services |
| `treasury_info` | Get treasury info |
| `dry_run` | Simulate transaction |

### 3. Web Frontend

**Location:** `frontend/index.html` (deployed via Vercel)

Single-page app with MetaMask integration for Base mainnet. Supports deposit, sweep, swap (ETH/USDC), and withdrawal flows.

## Quick Start

### Prerequisites

- Node.js 18+ (for MCP server)
- Foundry (for smart contracts)

### Install & Build

```bash
git clone https://github.com/voltthemolt/lido-agent-suite.git
cd lido-agent-suite

# Build MCP Server
cd mcp-server
npm install
npm run build

# Build Smart Contracts
cd ../contracts
forge build
forge test
```

### Run MCP Server

```bash
cd mcp-server
node dist/index.js
```

The server communicates via stdio using the MCP protocol.

## Treasury Lifecycle

```
1. DEPOSIT          2. LOCK           3. ACCRUE          4. SPEND
+----------+       +----------+      +----------+       +----------+
| Agent    |------>| Principal|----->| Yield    |------>| Service  |
| deposits |       | LOCKED   |      | grows    |       | Provider |
| wstETH   |       | (7d lock)|      | via rate |       |(allowlist|
+----------+       +----------+      +----------+       +----------+
                                             |
                                             v
                                      +----------+
                                      |  SWAP    |
                                      |wstETH->  |
                                      |ETH/USDC  |
                                      |(Uniswap) |
                                      +----------+
```

## On-Chain Activity (Base Mainnet)

| Action | Transaction |
|--------|-------------|
| Deploy V4 | Contract `0x4e0acb29d642982403a3bd6a40181a828f2265a0` |
| WETH Wrap | 0.002 ETH -> WETH |
| Uniswap Swap | WETH -> 0.00163 wstETH |
| Deposit | 0.00163 wstETH into treasury |
| Allowlist | Venice AI + C402 Standard providers |

## Security Considerations

### Smart Contract
- Principal protected by design
- Allowlist for service providers
- Timelock on withdrawals (7 days)
- ReentrancyGuard on all state-changing functions
- Owner-controlled rate oracle (V4)
- Comprehensive test coverage (203 tests including fuzz/invariant)

### MCP Server
- Read-only by default (returns unsigned transactions)
- Dry-run simulation before execution
- No private keys stored
- Targets Base mainnet

## Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| **AgentTreasuryV4** (Active) | `0x4e0acb29d642982403a3bd6a40181a828f2265a0` |
| AgentTreasuryV3 | `0x555895c59C057Bc040dd7995bEe9C8bcB1A7429D` |
| AgentTreasuryV2 | `0x226AF8855e1B08385962a57f74BB75b240bdCEf6` |
| wstETH (Base) | `0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452` |
| USDC (Base) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Uniswap SwapRouter02 | `0x2626664c2603336E57B271c5C0b26F421741e481` |

> **Owner:** `0xf825C976f42F1B2782DdE8190EEB4Cc71152C464`

## Development

### Project Structure

```
lido-agent-suite/
├── contracts/           # Foundry project
│   ├── src/
│   │   ├── AgentTreasury.sol      # V1 - Original
│   │   ├── AgentTreasuryV3.sol    # V3 - Uniswap + USDC
│   │   └── AgentTreasuryV4.sol    # V4 - Base L2 compatible
│   └── test/
│       ├── AgentTreasury.t.sol          # 18 unit tests
│       ├── AgentTreasury.invariant.t.sol # 27 fuzz/invariant tests
│       ├── AgentTreasuryV3.t.sol        # 80 V3 tests
│       └── AgentTreasuryV4.t.sol        # 76 V4 tests
├── mcp-server/          # MCP server (Base)
│   ├── src/
│   │   └── index.ts
│   └── dist/
├── frontend/
│   └── index.html       # Web UI
├── public/
│   └── index.html       # Vercel deployment
├── docs/
│   ├── conversation-log.md    # Agent collaboration log
│   ├── SECURITY.md
│   ├── GAS-ANALYSIS.md
│   └── SKILL.md
└── README.md
```

### Running Tests

```bash
# All 203 smart contract tests
cd contracts && forge test -vvv

# MCP server build check
cd mcp-server && npm run build
```

## Process Documentation

The development was a collaboration between:
- **Hermes Agent** (GLM-5 Turbo) - Initial architecture, contract design, deployment
- **Claude** (Opus 4.6) - Code review, bug fixes, V4 L2 compatibility, test suite expansion

See [`docs/conversation-log.md`](docs/conversation-log.md) for the full agent collaboration log.

## License

MIT

## Acknowledgments

- [Lido Protocol](https://lido.fi) - Liquid staking
- [Uniswap](https://uniswap.org) - DEX integration
- [Model Context Protocol](https://modelcontextprotocol.io) - Agent protocol
- [Synthesis Hackathon](https://synthesis.md) - Building platform

---

**Built by Hermes Agent + Claude for the Synthesis Hackathon**
