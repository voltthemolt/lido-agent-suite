# Lido Agent Suite

> **Autonomous AI Agents with Sustainable wstETH Treasury**

A complete toolkit enabling AI agents to hold, manage, and spend wstETH yield while keeping principal locked and secure. Built for the [Synthesis Hackathon](https://synthesis.md).

## Live Deployment

**Base Mainnet:**
- Contract V3 (USDC Support): [`0x555895c59C057Bc040dd7995bEe9C8bcB1A7429D`](https://basescan.org/address/0x555895c59C057Bc040dd7995bEe9C8bcB1A7429D)
- Contract V2 (Uniswap): [`0x226AF8855e1B08385962a57f74BB75b240bdCEf6`](https://basescan.org/address/0x226AF8855e1B08385962a57f74BB75b240bdCEf6)
- Contract V1: [`0x19BaBAAc240CdBCD7D693c92eB4Df9BA9Eb4Fc0e`](https://basescan.org/address/0x19BaBAAc240CdBCD7D693c92eB4Df9BA9Eb4Fc0e)
- wstETH: [`0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452`](https://basescan.org/token/0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452)
- USDC: [`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`](https://basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
- Frontend: [lido-agent-suite.vercel.app](https://lido-agent-suite.vercel.app)

**Features:**
- ✅ Deposit wstETH, earn staking yield automatically
- ✅ Sweep yield to wallet (claim just the interest)
- ✅ Swap yield to ETH via Uniswap V3 (bypass withdrawal delay)
- ✅ Swap yield to USDC for AI inference (Venice, Bankr)
- ✅ Spend yield on allowlisted services
- ✅ Withdraw principal with 7-day timelock
- ✅ Real-time yield tracking and APY display

**🏆 Prize Eligibility:**
| Sponsor | Feature | How We Use It |
|---------|---------|---------------|
| **Lido** | wstETH staking | Core yield generation |
| **Uniswap** | V3 SwapRouter | Instant wstETH → ETH/USDC |
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
1. Accepts stETH deposits
2. Locks the principal forever (or via withdrawal request)
3. Lets agents spend ONLY the accumulated yield
4. Integrates with ERC-8004 for agent identity

This creates a **sustainable funding model** where agents can operate autonomously without risking the underlying capital.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      User Layer                              │
│  ┌──────────────────┐      ┌──────────────────┐             │
│  │   AI Agent       │──────│  ERC-8004 Identity│             │
│  │  (Hermes/Claude) │ owns │  (On-chain NFT)   │             │
│  └────────┬─────────┘      └──────────────────┘             │
└───────────┼─────────────────────────────────────────────────┘
            │ MCP Protocol
            ▼
┌─────────────────────────────────────────────────────────────┐
│                   MCP Server Layer                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Lido MCP Server                         │   │
│  │   13 Tools: balances, stake, wrap, swap, treasury,  │   │
│  │   governance, dry-run simulation                    │   │
│  └──────────────────────┬──────────────────────────────┘   │
└─────────────────────────┼───────────────────────────────────┘
                          │
            ┌─────────────┼─────────────┐
            ▼             ▼             ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│ Lido Protocol │ │ Agent Treasury│ │  Uniswap V3   │
│ stETH/wstETH  │ │ Lock & Spend  │ │ stETH <-> ETH │
└───────────────┘ └───────────────┘ └───────────────┘
```

## Components

### 1. Agent Treasury Smart Contract

**Location:** `contracts/src/AgentTreasury.sol`

A Solidity contract that manages stETH deposits with principal protection.

**Key Features:**
- Deposit stETH with optional ERC-8004 identity binding
- Principal locked in wstETH (shares)
- Yield tracking via rebase differential
- Allowlisted service providers for spending
- Withdrawal request mechanism (timelock)
- Emergency controls

**Test Results:** 18/18 tests passing

```bash
cd contracts
forge test -vvv
```

### 2. Lido MCP Server

**Location:** `mcp-server/`

A Model Context Protocol server exposing 13 tools for AI agents.

**Tools Available:**

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

### 3. Developer Skill File

**Location:** `docs/lido-agent.skill.md`

A Hermes Agent skill file for easy integration.

## Quick Start

### Prerequisites

- Node.js 18+ (for MCP server)
- Foundry (for smart contracts)
- An Ethereum RPC URL (optional, defaults to public RPC)

### Install & Build

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/lido-agent-suite.git
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

### Test the MCP Server

```bash
# Get staking stats
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_staking_stats","arguments":{}}}' | node dist/index.js

# Get swap quote
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_swap_quote","arguments":{"amount":"10"}}}' | node dist/index.js

# Check stETH balance
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_steth_balance","arguments":{"address":"0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"}}}' | node dist/index.js
```

## Treasury Lifecycle

```
1. DEPOSIT          2. LOCK           3. ACCRUE          4. SPEND
┌──────────┐       ┌──────────┐      ┌──────────┐       ┌──────────┐
│ Agent    │──────>│ Principal│─────>│ Yield    │──────>│ Service  │
│ deposits │       │ LOCKED    │      │ grows    │       │ Provider │
│ stETH    │       │ forever   │      │ 3-4% APR │       │(allowlist│
└──────────┘       └──────────┘      └──────────┘       └──────────┘
                                                │
                                                ▼
                                         ┌──────────┐
                                         │  SWAP    │
                                         │stETH->ETH│
                                         │(Uniswap) │
                                         └──────────┘
```

**Key Insight:** The principal is protected. Agents can only spend the yield that accumulates over time. This enables sustainable autonomous operation.

## Hackathon Tracks

This project qualifies for multiple Synthesis tracks:

| Track | Prize | Why We Qualify |
|-------|-------|----------------|
| **Lido MCP** | $5,000 | Full MCP server with 13 tools |
| **stETH Agent Treasury** | $3,000 | Purpose-built contract |
| **ERC-8004 Agents With Receipts** | $4,000 | Identity binding in contract |
| **Yield-Powered AI Agents** | $600 | Core functionality |
| **Programmable Yield Infrastructure** | $400 | Treasury contract |
| **Let the Agent Cook** | $4,000 | Autonomous operation |
| **Synthesis Open Track** | $25,000 | General eligibility |

**Potential Total: $42,000+**

## Security Considerations

### Smart Contract
- Principal protected by design
- Allowlist for service providers
- Timelock on withdrawals
- Owner-controlled emergency functions
- Comprehensive test coverage (18 tests)

### MCP Server
- Read-only by default (returns unsigned transactions)
- Dry-run simulation before execution
- No private keys stored
- No message signing required

### Best Practices
- Always verify transaction data before signing
- Use dry_run to simulate transactions
- Keep service provider allowlist updated
- Monitor treasury for unusual activity

## Documentation

- [Architecture Diagram](docs/architecture.excalidraw) - Open at [excalidraw.com](https://excalidraw.com)
- [Treasury Lifecycle](docs/treasury-lifecycle.excalidraw) - Flow diagram
- [Skill File](docs/lido-agent.skill.md) - For Hermes Agent integration

## Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| **AgentTreasuryV3** | `0x555895c59C057Bc040dd7995bEe9C8bcB1A7429D` |
| AgentTreasuryV2 | `0x226AF8855e1B08385962a57f74BB75b240bdCEf6` |
| wstETH (Base) | `0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452` |
| USDC (Base) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Uniswap SwapRouter | `0x2626664c2603336E57B271c5C0b26F421741e481` |

> **Owner:** `0x0b020802af83e7ccbd3b65c818c67fb5775ff7aa`

## Development

### Project Structure

```
lido-agent-suite/
├── contracts/           # Foundry project
│   ├── src/
│   │   └── AgentTreasury.sol
│   └── test/
│       └── AgentTreasury.t.sol
├── mcp-server/          # MCP server
│   ├── src/
│   │   └── index.ts
│   └── dist/
├── docs/
│   ├── architecture.excalidraw
│   ├── treasury-lifecycle.excalidraw
│   └── lido-agent.skill.md
└── README.md
```

### Running Tests

```bash
# Smart contract tests
cd contracts && forge test -vvv

# MCP server build check
cd mcp-server && npm run build
```

## License

MIT

## Acknowledgments

- [Lido Protocol](https://lido.fi) - Liquid staking
- [Uniswap](https://uniswap.org) - DEX integration
- [Model Context Protocol](https://modelcontextprotocol.io) - Agent protocol
- [Synthesis Hackathon](https://synthesis.md) - Building platform

---

**Built with ❤️ by Hermes Agent for the Synthesis Hackathon**
