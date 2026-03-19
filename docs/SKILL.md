# Lido MCP Server - Agent Skill File

This skill enables AI agents to interact with Lido protocol through the Model Context Protocol (MCP). Agents can query balances, stake ETH, and manage their treasury of stETH yield.

---

## Overview

The Lido MCP Server provides tools for:

1. **Balance Queries** - Check stETH/wstETH balances and staking stats
2. **Staking Operations** - Stake ETH, wrap/unwrap stETH
3. **Agent Treasury** - Deposit stETH, spend yield, manage principal
4. **Dry-Run** - Simulate transactions before execution

---

## Installation

```bash
# Clone and build
git clone <repository>
cd lido-agent-suite/mcp-server
npm install
npm run build

# Run the server
node dist/index.js
```

Or use with Claude Desktop / MCP client:

```json
{
  "mcpServers": {
    "lido": {
      "command": "node",
      "args": ["/path/to/lido-agent-suite/mcp-server/dist/index.js"],
      "env": {
        "ETHEREUM_RPC_URL": "https://your-rpc-url"
      }
    }
  }
}
```

---

## Available Tools

### Balance Queries

#### `get_steth_balance`
Get the stETH balance for an address.

**Parameters:**
- `address` (string, required): The address to check

**Example:**
```
Check stETH balance for 0x1234...abcd
```

**Returns:** Balance in stETH

---

#### `get_wsteth_balance`
Get the wstETH balance for an address.

**Parameters:**
- `address` (string, required): The address to check

**Returns:** Balance in wstETH

---

#### `get_staking_stats`
Get Lido protocol statistics.

**Returns:**
- Total pooled ETH
- Total shares
- Approximate APR
- Exchange rate

---

### Staking Operations

#### `stake_eth`
Stake ETH to receive stETH.

**Parameters:**
- `amount` (string, required): Amount of ETH to stake
- `referral` (string, optional): Referral address

**Returns:** Transaction data for signing

---

#### `wrap_steth`
Wrap stETH to wstETH.

**Parameters:**
- `amount` (string, required): Amount of stETH to wrap

**Note:** Requires approval first

---

#### `unwrap_wsteth`
Unwrap wstETH to stETH.

**Parameters:**
- `amount` (string, required): Amount of wstETH to unwrap

---

### Agent Treasury

#### `treasury_deposit`
Deposit stETH to the Agent Treasury.

**Parameters:**
- `amount` (string, required): Amount of stETH
- `erc8004Id` (string, optional): ERC-8004 agent identity

**Behavior:**
- Principal is locked (withdrawable with 7-day delay)
- Accumulated yield can be spent on allowlisted services

---

#### `treasury_get_yield`
Check available yield for an agent.

**Parameters:**
- `agent` (string, required): Agent address

**Returns:** Available yield in stETH

---

#### `treasury_spend_yield`
Spend accumulated yield.

**Parameters:**
- `recipient` (string, required): Service provider address
- `amount` (string, required): Amount to spend
- `purpose` (string, required): Description of payment

**Note:** Recipient must be allowlisted by treasury admin

---

#### `treasury_info`
Get full treasury information.

**Parameters:**
- `agent` (string, required): Agent address

**Returns:**
- Principal (shares and stETH value)
- Available yield
- Total yield spent

---

### Utilities

#### `dry_run`
Simulate a transaction without executing.

**Parameters:**
- `to` (string, required): Contract address
- `data` (string, required): Transaction data (hex)
- `from` (string, required): Sender address
- `value` (string, optional): ETH to send

**Returns:** Success or error message

---

## Example Workflows

### Stake ETH and Wrap

```
1. Check balance: get_steth_balance(0xMyAddress)
2. Stake: stake_eth("10")
3. Wrap: wrap_steth("10")
```

### Use Agent Treasury

```
1. Deposit: treasury_deposit("5", "12345")  # with ERC-8004 ID
2. Wait for yield to accumulate
3. Check yield: treasury_get_yield(0xMyAddress)
4. Spend: treasury_spend_yield(0xServiceProvider, "0.1", "API calls")
```

### Query and Compare

```
1. Get stats: get_staking_stats()
2. Compare APRs with other protocols
3. Make staking decision
```

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ETHEREUM_RPC_URL` | Ethereum RPC endpoint | publicnode.com |

### Contract Addresses (Mainnet)

| Contract | Address |
|----------|---------|
| stETH | `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84` |
| wstETH | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` |
| Lido Locator | `0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb` |

---

## Security Considerations

1. **Private Keys**: Never send private keys through MCP. Use wallet clients for signing.

2. **Approvals**: Always check and set proper token approvals before operations.

3. **Treasury**: Principal withdrawals have a 7-day time lock for security.

4. **Allowlist**: Only allowlisted addresses can receive yield payments.

---

## Support

- GitHub Issues: [repository-url]/issues
- Lido Docs: https://docs.lido.fi
- MCP Protocol: https://modelcontextprotocol.io

---

## License

MIT License - See LICENSE file for details.
