# Lido Agent Suite - Demo Workflow

This demo shows an AI agent using the Lido MCP Server and Agent Treasury to autonomously manage stETH and spend yield.

---

## Prerequisites

1. Deployed AgentTreasury contract
2. Running Lido MCP Server
3. Agent wallet with ETH/stETH

---

## Step 1: Check Balances

**Agent calls MCP:**
```
get_steth_balance(0xAgentAddress)
get_wsteth_balance(0xAgentAddress)
get_staking_stats()
```

**Response:**
```
stETH Balance: 5.0 stETH
wstETH Balance: 0 wstETH

Lido Staking Statistics:
- Total Pooled ETH: 9,234,567 ETH
- Approximate APR: 3.5%
```

---

## Step 2: Deposit to Treasury

**Agent calls MCP:**
```
treasury_deposit("5", "12345")
```

**MCP generates transaction:**
```javascript
{
  to: "0xTreasuryAddress",
  data: "0x...", // deposit(5e18, 12345)
  value: "0"
}
```

**Agent signs and submits:**

**Result:**
- 5 stETH deposited
- Principal locked
- Yield starts accumulating

---

## Step 3: Wait for Yield

After some time (e.g., 1 month):

**Agent calls MCP:**
```
treasury_get_yield(0xAgentAddress)
```

**Response:**
```
Available Yield: 0.0145 stETH
```

---

## Step 4: Spend Yield on Services

**Agent identifies service to pay for:**
- API provider: 0xServiceProvider
- Allowlisted by treasury admin

**Agent calls MCP:**
```
treasury_spend_yield("0xServiceProvider", "0.01", "API calls for data analysis")
```

**MCP generates transaction:**
```javascript
{
  to: "0xTreasuryAddress",
  data: "0x...", // spendYield(sp, 0.01e18, "API calls...")
}
```

**Result:**
- 0.01 stETH transferred to service provider
- Principal remains intact
- Agent received services

---

## Step 5: Monitor Treasury

**Agent calls MCP:**
```
treasury_info(0xAgentAddress)
```

**Response:**
```
Treasury Info:
- Principal: 5.0 stETH
- Available Yield: 0.0045 stETH
- Total Yield Spent: 0.01 stETH
```

---

## Full Autonomous Cycle

```
┌─────────────────────────────────────────────────────────────┐
│                    AGENT AUTONOMY LOOP                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   1. DISCOVER                                                │
│      └─ Agent detects need for API service                   │
│                                                              │
│   2. PLAN                                                     │
│      └─ Check treasury yield: get_yield()                   │
│      └─ Compare with service cost                            │
│                                                              │
│   3. EXECUTE                                                  │
│      └─ Spend yield: spendYield(provider, amount)            │
│                                                              │
│   4. VERIFY                                                   │
│      └─ Check service received                                │
│      └─ Monitor treasury: treasury_info()                    │
│                                                              │
│   5. REPEAT                                                   │
│      └─ Continue earning yield on staked ETH                 │
│      └─ Spend on agent operations                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Code Example: Autonomous Agent

```typescript
import { Client } from '@modelcontextprotocol/sdk/client/index.js';

async function autonomousAgentCycle() {
  const mcpClient = new Client(...);
  
  // Check if we can afford service
  const yieldInfo = await mcpClient.callTool('treasury_get_yield', {
    agent: myAddress
  });
  
  const serviceCost = parseEther('0.01');
  if (yieldInfo.amount >= serviceCost) {
    // Spend yield on service
    await mcpClient.callTool('treasury_spend_yield', {
      recipient: serviceProvider,
      amount: '0.01',
      purpose: 'Monthly API subscription'
    });
    
    console.log('Service paid for with stETH yield!');
  } else {
    console.log('Insufficient yield, waiting...');
  }
}

// Run every day
setInterval(autonomousAgentCycle, 24 * 60 * 60 * 1000);
```

---

## On-Chain Verification

All interactions are recorded on Ethereum:

1. **Treasury deposit** → ERC-8004 identity linked
2. **Yield spend** → Event log with purpose
3. **Principal** → Time-locked, auditable

---

## Benefits for AI Agents

| Feature | Benefit |
|---------|---------|
| Yield spending | Self-sustaining operations |
| Principal protection | Funds always recoverable |
| ERC-8004 identity | Verifiable on-chain identity |
| MCP integration | Works with any MCP-compatible agent |
| Allowlist security | Controlled spending destinations |

---

## Try It Yourself

1. Deploy the treasury contract
2. Start the MCP server
3. Connect your agent
4. Begin autonomous operations
