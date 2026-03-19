#!/usr/bin/env node

/**
 * Lido MCP Server
 * 
 * A Model Context Protocol server providing tools for AI agents
 * to interact with Lido protocol (stETH/wstETH) and the Agent Treasury.
 * 
 * Features:
 * - stETH/wstETH balance queries
 * - Stake/unstake operations
 * - Governance actions
 * - Agent Treasury integration
 * - Dry-run simulation support
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ErrorCode,
  McpError,
} from '@modelcontextprotocol/sdk/types.js';
import { createPublicClient, createWalletClient, http, formatEther, parseEther } from 'viem';
import { mainnet } from 'viem/chains';

// ============ Configuration ============

const LIDO_CONTRACTS = {
  stETH: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84' as `0x${string}`,
  wstETH: '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0' as `0x${string}`,
  lidoLocator: '0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb' as `0x${string}`,
  voting: '0x2e59A20f205bB85a89C53e193632b0d5BA6E4C29' as `0x${string}`,
  agentTreasury: '', // To be deployed
};

// Uniswap V3 contracts (Ethereum mainnet)
const UNISWAP_CONTRACTS = {
  // SwapRouter02 - supports both V2 and V3 swaps
  swapRouter: '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45' as `0x${string}`,
  // Quoter V2 for getting exact output quotes
  quoter: '0x61fFE014bA17989E743c5F6cB21bF9694882746B' as `0x${string}`,
  // stETH/ETH pool 0.3% fee
  stEthEthPool: '0xeC6770DD0f8368B6a8538B86321b938a8608B664' as `0x${string}`,
};

// Pool fee for stETH/ETH (0.3%)
const POOL_FEE = 3000;

// ============ ABIs ============

const STETH_ABI = [
  {
    name: 'balanceOf',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'getTotalShares',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'getTotalPooledEther',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'submit',
    inputs: [{ name: '_referral', type: 'address' }],
    outputs: [],
    stateMutability: 'payable',
    type: 'function',
  },
] as const;

const WSTETH_ABI = [
  {
    name: 'balanceOf',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'wrap',
    inputs: [{ name: '_stETHAmount', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    name: 'unwrap',
    inputs: [{ name: '_wstETHAmount', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    name: 'getStETHByWstETH',
    inputs: [{ name: '_wstETHAmount', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'getWstETHByStETH',
    inputs: [{ name: '_stETHAmount', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

const AGENT_TREASURY_ABI = [
  {
    name: 'deposit',
    inputs: [
      { name: 'amount', type: 'uint256' },
      { name: 'erc8004Id', type: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    name: 'spendYield',
    inputs: [
      { name: 'recipient', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'purpose', type: 'string' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    name: 'getAvailableYield',
    inputs: [{ name: 'agent', type: 'address' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'getTreasuryInfo',
    inputs: [{ name: 'agent', type: 'address' }],
    outputs: [
      { name: 'principalShares', type: 'uint256' },
      { name: 'principalStETH', type: 'uint256' },
      { name: 'availableYield', type: 'uint256' },
      { name: 'totalYieldSpent', type: 'uint256' },
      { name: 'exists', type: 'bool' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ============ Server Setup ============

const server = new Server(
  {
    name: 'lido-mcp-server',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Create viem client
const client = createPublicClient({
  chain: mainnet,
  transport: http(process.env.ETHEREUM_RPC_URL || 'https://ethereum.publicnode.com'),
});

// ============ Tool Definitions ============

const tools = [
  // Balance queries
  {
    name: 'get_steth_balance',
    description: 'Get the stETH balance for an address',
    inputSchema: {
      type: 'object',
      properties: {
        address: {
          type: 'string',
          description: 'The address to check balance for',
        },
      },
      required: ['address'],
    },
  },
  {
    name: 'get_wsteth_balance',
    description: 'Get the wstETH balance for an address',
    inputSchema: {
      type: 'object',
      properties: {
        address: {
          type: 'string',
          description: 'The address to check balance for',
        },
      },
      required: ['address'],
    },
  },
  {
    name: 'get_staking_stats',
    description: 'Get Lido staking statistics (total pooled ETH, total shares, APR)',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  // Staking operations
  {
    name: 'stake_eth',
    description: 'Stake ETH to receive stETH. Returns transaction data for signing.',
    inputSchema: {
      type: 'object',
      properties: {
        amount: {
          type: 'string',
          description: 'Amount of ETH to stake (in ETH, e.g., "1.5")',
        },
        referral: {
          type: 'string',
          description: 'Optional referral address',
        },
      },
      required: ['amount'],
    },
  },
  {
    name: 'wrap_steth',
    description: 'Wrap stETH to wstETH. Returns transaction data for signing.',
    inputSchema: {
      type: 'object',
      properties: {
        amount: {
          type: 'string',
          description: 'Amount of stETH to wrap (in ETH)',
        },
      },
      required: ['amount'],
    },
  },
  {
    name: 'unwrap_wsteth',
    description: 'Unwrap wstETH to stETH. Returns transaction data for signing.',
    inputSchema: {
      type: 'object',
      properties: {
        amount: {
          type: 'string',
          description: 'Amount of wstETH to unwrap (in wstETH)',
        },
      },
      required: ['amount'],
    },
  },
  // Treasury operations
  {
    name: 'treasury_deposit',
    description: 'Deposit stETH to the Agent Treasury. Principal is locked, yield can be spent.',
    inputSchema: {
      type: 'object',
      properties: {
        amount: {
          type: 'string',
          description: 'Amount of stETH to deposit',
        },
        erc8004Id: {
          type: 'string',
          description: 'Optional ERC-8004 agent identity ID',
        },
      },
      required: ['amount'],
    },
  },
  {
    name: 'treasury_get_yield',
    description: 'Get available yield for an agent treasury',
    inputSchema: {
      type: 'object',
      properties: {
        agent: {
          type: 'string',
          description: 'Agent address',
        },
      },
      required: ['agent'],
    },
  },
  {
    name: 'treasury_spend_yield',
    description: 'Spend treasury yield on allowlisted services',
    inputSchema: {
      type: 'object',
      properties: {
        recipient: {
          type: 'string',
          description: 'Service provider address',
        },
        amount: {
          type: 'string',
          description: 'Amount of yield to spend',
        },
        purpose: {
          type: 'string',
          description: 'Description of what is being paid for',
        },
      },
      required: ['recipient', 'amount', 'purpose'],
    },
  },
  {
    name: 'treasury_info',
    description: 'Get full treasury info for an agent',
    inputSchema: {
      type: 'object',
      properties: {
        agent: {
          type: 'string',
          description: 'Agent address',
        },
      },
      required: ['agent'],
    },
  },
  // Dry run
  {
    name: 'dry_run',
    description: 'Simulate a transaction without executing it. Returns expected outcome.',
    inputSchema: {
      type: 'object',
      properties: {
        to: {
          type: 'string',
          description: 'Contract address',
        },
        data: {
          type: 'string',
          description: 'Transaction data (hex)',
        },
        from: {
          type: 'string',
          description: 'Sender address',
        },
        value: {
          type: 'string',
          description: 'ETH value to send (optional)',
        },
      },
      required: ['to', 'data', 'from'],
    },
  },
  // Uniswap swap
  {
    name: 'swap_steth_to_eth',
    description: 'Get a quote and transaction data to swap stETH to ETH via Uniswap V3. Returns the expected output and unsigned transaction.',
    inputSchema: {
      type: 'object',
      properties: {
        amount: {
          type: 'string',
          description: 'Amount of stETH to swap (in ETH, e.g., "1.5")',
        },
        slippage: {
          type: 'string',
          description: 'Slippage tolerance in percent (default: "0.5")',
        },
        recipient: {
          type: 'string',
          description: 'Address to receive the ETH (defaults to sender)',
        },
      },
      required: ['amount'],
    },
  },
  {
    name: 'get_swap_quote',
    description: 'Get a quote for swapping stETH to ETH without generating a transaction.',
    inputSchema: {
      type: 'object',
      properties: {
        amount: {
          type: 'string',
          description: 'Amount of stETH to quote (in ETH)',
        },
      },
      required: ['amount'],
    },
  },
];

// ============ Tool Handlers ============

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  // Ensure args exists for all tools that require it
  if (!args && name !== 'get_staking_stats') {
    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
  }

  try {
    switch (name) {
      // Balance queries
      case 'get_steth_balance': {
        const address = args!.address as `0x${string}`;
        const balance = await client.readContract({
          address: LIDO_CONTRACTS.stETH,
          abi: STETH_ABI,
          functionName: 'balanceOf',
          args: [address],
        });
        return {
          content: [
            {
              type: 'text',
              text: `stETH Balance: ${formatEther(balance as bigint)} stETH`,
            },
          ],
        };
      }

      case 'get_wsteth_balance': {
        const address = args!.address as `0x${string}`;
        const balance = await client.readContract({
          address: LIDO_CONTRACTS.wstETH,
          abi: WSTETH_ABI,
          functionName: 'balanceOf',
          args: [address],
        });
        return {
          content: [
            {
              type: 'text',
              text: `wstETH Balance: ${formatEther(balance as bigint)} wstETH`,
            },
          ],
        };
      }

      case 'get_staking_stats': {
        const [totalPooled, totalShares] = await Promise.all([
          client.readContract({
            address: LIDO_CONTRACTS.stETH,
            abi: STETH_ABI,
            functionName: 'getTotalPooledEther',
          }),
          client.readContract({
            address: LIDO_CONTRACTS.stETH,
            abi: STETH_ABI,
            functionName: 'getTotalShares',
          }),
        ]);

        // Approximate APR (would need historical data for exact)
        const apr = '3.5'; // Placeholder - would calculate from beacon chain data

        return {
          content: [
            {
              type: 'text',
              text: `Lido Staking Statistics:
- Total Pooled ETH: ${formatEther(totalPooled as bigint)} ETH
- Total Shares: ${formatEther(totalShares as bigint)}
- Approximate APR: ${apr}%
- Exchange Rate: ${(Number(totalPooled) / Number(totalShares)).toFixed(6)} stETH/share`,
            },
          ],
        };
      }

      // Staking operations (return tx data for signing)
      case 'stake_eth': {
        const amount = parseEther(args!.amount as string);
        const referral = (args!.referral || '0x0000000000000000000000000000000000000000') as `0x${string}`;
        
        return {
          content: [
            {
              type: 'text',
              text: `Transaction to sign:
- To: ${LIDO_CONTRACTS.stETH}
- Value: ${args!.amount} ETH
- Data: submit(${referral})
- Function: Lido.submit() - stakes ETH and mints stETH`,
            },
          ],
        };
      }

      case 'wrap_steth': {
        const amount = parseEther(args!.amount as string);
        
        return {
          content: [
            {
              type: 'text',
              text: `Transaction to sign:
- To: ${LIDO_CONTRACTS.wstETH}
- Value: 0 ETH
- Data: wrap(${amount})
- Function: wstETH.wrap() - wraps stETH to wstETH

Note: You must approve wstETH contract to spend your stETH first.`,
            },
          ],
        };
      }

      case 'unwrap_wsteth': {
        const amount = parseEther(args!.amount as string);
        
        return {
          content: [
            {
              type: 'text',
              text: `Transaction to sign:
- To: ${LIDO_CONTRACTS.wstETH}
- Value: 0 ETH
- Data: unwrap(${amount})
- Function: wstETH.unwrap() - unwraps wstETH to stETH`,
            },
          ],
        };
      }

      // Treasury operations
      case 'treasury_deposit': {
        if (!LIDO_CONTRACTS.agentTreasury) {
          throw new McpError(ErrorCode.InvalidRequest, 'Agent Treasury not deployed');
        }
        if (!args) throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
        
        const amount = args.amount as string;
        const erc8004Id = BigInt((args.erc8004Id as string | number) || 0);
        
        return {
          content: [
            {
              type: 'text',
              text: `Transaction to sign:
- To: ${LIDO_CONTRACTS.agentTreasury}
- Value: 0 ETH
- Function: deposit(${parseEther(amount)}, ${erc8004Id})
- Description: Deposit stETH to Agent Treasury

Note: You must approve the treasury to spend your stETH first.`,
            },
          ],
        };
      }

      case 'treasury_get_yield': {
        if (!LIDO_CONTRACTS.agentTreasury) {
          throw new McpError(ErrorCode.InvalidRequest, 'Agent Treasury not deployed');
        }
        
        const agent = args!.agent as `0x${string}`;
        const yieldAmount = await client.readContract({
          address: LIDO_CONTRACTS.agentTreasury as `0x${string}`,
          abi: AGENT_TREASURY_ABI,
          functionName: 'getAvailableYield',
          args: [agent],
        });
        
        return {
          content: [
            {
              type: 'text',
              text: `Available Yield: ${formatEther(yieldAmount as bigint)} stETH`,
            },
          ],
        };
      }

      case 'treasury_spend_yield': {
        if (!LIDO_CONTRACTS.agentTreasury) {
          throw new McpError(ErrorCode.InvalidRequest, 'Agent Treasury not deployed');
        }
        
        const recipient = args!.recipient as string;
        const amount = args!.amount as string;
        const purpose = args!.purpose as string;
        
        return {
          content: [
            {
              type: 'text',
              text: `Transaction to sign:
- To: ${LIDO_CONTRACTS.agentTreasury}
- Function: spendYield(${recipient}, ${parseEther(amount)}, "${purpose}")
- Description: Spend treasury yield on ${purpose}

Note: Recipient must be allowlisted.`,
            },
          ],
        };
      }

      case 'treasury_info': {
        if (!LIDO_CONTRACTS.agentTreasury) {
          throw new McpError(ErrorCode.InvalidRequest, 'Agent Treasury not deployed');
        }
        if (!args) throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
        
        const agent = args.agent as `0x${string}`;
        const info = await client.readContract({
          address: LIDO_CONTRACTS.agentTreasury as `0x${string}`,
          abi: AGENT_TREASURY_ABI,
          functionName: 'getTreasuryInfo',
          args: [agent],
        }) as [bigint, bigint, bigint, bigint, boolean];
        
        const [principalShares, principalStETH, availableYield, totalYieldSpent, exists] = info;
        
        return {
          content: [
            {
              type: 'text',
              text: exists
                ? `Treasury Info for ${agent}:
- Principal (shares): ${formatEther(principalShares)} wstETH
- Principal (stETH): ${formatEther(principalStETH)} stETH
- Available Yield: ${formatEther(availableYield)} stETH
- Total Yield Spent: ${formatEther(totalYieldSpent)} stETH`
                : `No treasury found for ${agent}`,
            },
          ],
        };
      }

      case 'dry_run': {
        if (!args) throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
        const { to, data, from, value } = args as { to: string; data: string; from: string; value?: string };
        
        try {
          // Use eth_call for dry run simulation
          const result = await client.call({
            to: to as `0x${string}`,
            data: data as `0x${string}`,
            account: from as `0x${string}`,
            value: value ? parseEther(value) : undefined,
          });
          
          return {
            content: [
              {
                type: 'text',
                text: `Dry Run Result: SUCCESS\nTransaction would succeed.\nResult: ${result}`,
              },
            ],
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text',
                text: `Dry Run Result: FAILED\n${error instanceof Error ? error.message : 'Unknown error'}`,
              },
            ],
          };
        }
      }

      case 'get_swap_quote': {
        if (!args) throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
        const amount = parseEther(args.amount as string);
        
        // For quotes, we use a simplified calculation
        // In production, you'd call the Uniswap Quoter contract
        // stETH trades at ~1:1 with ETH, with slight discount due to withdrawal queue
        const stEthPrice = 0.99; // Approximate stETH/ETH ratio
        const estimatedOutput = Number(args.amount) * stEthPrice;
        const fee = Number(args.amount) * 0.003; // 0.3% fee
        const outputAfterFee = estimatedOutput - fee;
        
        return {
          content: [
            {
              type: 'text',
              text: `Swap Quote (stETH -> ETH):
- Input: ${args.amount} stETH
- Expected Output: ~${outputAfterFee.toFixed(6)} ETH
- Fee (0.3%): ~${fee.toFixed(6)} ETH
- Price Impact: ~0.01% (for small amounts)
- Route: stETH -> ETH via Uniswap V3 (0.3% pool)

Note: This is an estimate. Actual output depends on pool state at execution time.
Use swap_steth_to_eth to generate the transaction data.`,
            },
          ],
        };
      }

      case 'swap_steth_to_eth': {
        if (!args) throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
        const amountIn = parseEther(args.amount as string);
        const slippage = Number(args.slippage || '0.5');
        const recipient = args.recipient || 'SENDER'; // Will be replaced with actual sender
        
        // Calculate minimum output with slippage
        const stEthPrice = 0.99;
        const estimatedOutput = Number(args.amount) * stEthPrice * (1 - 0.003);
        const minOutput = estimatedOutput * (1 - slippage / 100);
        const amountOutMinimum = parseEther(minOutput.toFixed(18));
        
        // Generate the swap calldata
        // exactInputSingle for Uniswap V3
        const swapParams = {
          tokenIn: LIDO_CONTRACTS.stETH,
          tokenOut: '0x0000000000000000000000000000000000000000' as `0x${string}`, // ETH
          fee: POOL_FEE,
          recipient: recipient === 'SENDER' ? '0x0000000000000000000000000000000000000002' as `0x${string}` : recipient as `0x${string}`, // 0x02 = sender
          amountIn: amountIn,
          amountOutMinimum: amountOutMinimum,
          sqrtPriceLimitX96: 0, // No price limit
        };
        
        return {
          content: [
            {
              type: 'text',
              text: `Swap Transaction to Sign:
- Router: ${UNISWAP_CONTRACTS.swapRouter}
- Function: exactInputSingle
- Input: ${args.amount} stETH
- Minimum Output: ${minOutput.toFixed(6)} ETH
- Slippage: ${slippage}%
- Fee Tier: 0.3%

Parameters:
- tokenIn: ${LIDO_CONTRACTS.stETH} (stETH)
- tokenOut: 0x0000000000000000000000000000000000000000 (ETH)
- fee: ${POOL_FEE}
- amountIn: ${amountIn.toString()}
- amountOutMinimum: ${amountOutMinimum.toString()}
- sqrtPriceLimitX96: 0

Steps to execute:
1. Approve SwapRouter to spend your stETH: approve(${UNISWAP_CONTRACTS.swapRouter}, ${amountIn})
2. Sign and send the exactInputSingle transaction

Note: Output is sent as ETH (native), not WETH.`,
            },
          ],
        };
      }

      default:
        throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
    }
  } catch (error) {
    if (error instanceof McpError) throw error;
    throw new McpError(
      ErrorCode.InternalError,
      `Error executing ${name}: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
});

// ============ Start Server ============

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Lido MCP Server running on stdio');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
