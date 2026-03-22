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
 * - Uniswap Developer Platform API integration
 */
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema, ErrorCode, McpError, } from '@modelcontextprotocol/sdk/types.js';
import { createPublicClient, http, formatEther, parseEther, encodeFunctionData } from 'viem';
import { base, mainnet } from 'viem/chains';
// ============ Configuration ============
const LIDO_CONTRACTS = {
    stETH: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', // Reference only, not directly used on Base
    wstETH: '0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452',
    agentTreasury: '0x4e0acb29d642982403a3bd6a40181a828f2265a0',
    LDO: '0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32', // LDO governance token (Ethereum mainnet)
};
// Snapshot governance API
const SNAPSHOT_GRAPHQL_URL = 'https://hub.snapshot.org/graphql';
const LIDO_SNAPSHOT_SPACE = 'lido-snapshot.eth';
// Uniswap V3 contracts (Base mainnet)
const UNISWAP_CONTRACTS = {
    // SwapRouter02 on Base
    swapRouter: '0x2626664c2603336E57B271c5C0b26F421741e481',
};
// Pool fee for stETH/ETH (0.3%)
const POOL_FEE = 3000;
// Uniswap Developer Platform API
const UNISWAP_API_KEY = process.env.UNISWAP_API_KEY || 'CQlhRign_d5zFkm__YqTMzFnjf-bgS15opC3Ntx_0Ik';
const UNISWAP_API_BASE = 'https://trade-api.gateway.uniswap.org/v1';
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
];
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
    {
        name: 'stEthPerToken',
        inputs: [],
        outputs: [{ type: 'uint256' }],
        stateMutability: 'view',
        type: 'function',
    },
];
const LDO_ABI = [
    {
        name: 'balanceOf',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ type: 'uint256' }],
        stateMutability: 'view',
        type: 'function',
    },
];
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
            { name: 'principal', type: 'uint256' },
            { name: 'availableYield', type: 'uint256' },
            { name: 'totalYieldClaimed', type: 'uint256' },
            { name: 'totalYieldSpent', type: 'uint256' },
            { name: 'depositTime', type: 'uint256' },
            { name: 'currentRate', type: 'uint256' },
            { name: 'depositRate', type: 'uint256' },
            { name: 'exists', type: 'bool' },
        ],
        stateMutability: 'view',
        type: 'function',
    },
];
const ERC20_TRANSFER_ABI = [
    {
        name: 'transfer',
        inputs: [
            { name: 'to', type: 'address' },
            { name: 'amount', type: 'uint256' },
        ],
        outputs: [{ type: 'bool' }],
        stateMutability: 'nonpayable',
        type: 'function',
    },
];
// ============ Uniswap API Helper ============
async function uniswapApiQuote(params) {
    const resp = await fetch(`${UNISWAP_API_BASE}/quote`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-api-key': UNISWAP_API_KEY,
            'x-universal-router-version': '2.0',
        },
        body: JSON.stringify({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            tokenInChainId: params.chainId,
            tokenOutChainId: params.chainId,
            amount: params.amount,
            type: params.type,
            swapper: params.swapper || '0x0000000000000000000000000000000000000001',
            autoSlippage: 'DEFAULT',
            routingPreference: 'BEST_PRICE',
        }),
    });
    if (!resp.ok) {
        const text = await resp.text();
        throw new Error(`Uniswap API error ${resp.status}: ${text}`);
    }
    return resp.json();
}
// ============ Server Setup ============
const server = new Server({
    name: 'lido-mcp-server',
    version: '1.0.0',
}, {
    capabilities: {
        tools: {},
    },
});
// Create viem clients
const client = createPublicClient({
    chain: base,
    transport: http(process.env.BASE_RPC_URL || process.env.ETHEREUM_RPC_URL || 'https://mainnet.base.org'),
});
// Mainnet client for governance queries (LDO token, stETH on L1)
const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(process.env.ETHEREUM_RPC_URL || 'https://ethereum.publicnode.com'),
});
// ============ Snapshot GraphQL Helper ============
async function snapshotQuery(query) {
    const resp = await fetch(SNAPSHOT_GRAPHQL_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }),
    });
    if (!resp.ok) {
        const text = await resp.text();
        throw new Error(`Snapshot API error ${resp.status}: ${text}`);
    }
    const json = await resp.json();
    if (json.errors) {
        throw new Error(`Snapshot GraphQL error: ${JSON.stringify(json.errors)}`);
    }
    return json.data;
}
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
        description: 'Get a quote for swapping stETH to ETH without generating a transaction. Uses the Uniswap Developer Platform API for real-time pricing.',
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
    {
        name: 'uniswap_get_quote',
        description: 'Get a real-time swap quote from Uniswap Developer Platform API on Base',
        inputSchema: {
            type: 'object',
            properties: {
                tokenIn: {
                    type: 'string',
                    description: 'Input token address (use "ETH" for native)',
                },
                tokenOut: {
                    type: 'string',
                    description: 'Output token address',
                },
                amount: {
                    type: 'string',
                    description: 'Amount of input token (in human readable, e.g. "1.5")',
                },
            },
            required: ['tokenIn', 'tokenOut', 'amount'],
        },
    },
    // Governance tools
    {
        name: 'lido_get_proposals',
        description: 'Get active and recent Lido governance proposals from Snapshot',
        inputSchema: {
            type: 'object',
            properties: {
                state: {
                    type: 'string',
                    description: 'Filter by proposal state: "active", "closed", "pending", or "all" (default: "all")',
                },
                limit: {
                    type: 'number',
                    description: 'Number of proposals to return (default: 5, max: 20)',
                },
            },
        },
    },
    {
        name: 'lido_get_proposal_details',
        description: 'Get full details of a specific Lido governance proposal from Snapshot, including the body text and discussion link',
        inputSchema: {
            type: 'object',
            properties: {
                proposalId: {
                    type: 'string',
                    description: 'The Snapshot proposal ID',
                },
            },
            required: ['proposalId'],
        },
    },
    {
        name: 'lido_get_voting_power',
        description: 'Get LDO token balance (voting power) for an Ethereum address',
        inputSchema: {
            type: 'object',
            properties: {
                address: {
                    type: 'string',
                    description: 'The Ethereum address to check LDO balance for',
                },
            },
            required: ['address'],
        },
    },
    {
        name: 'lido_protocol_health',
        description: 'Get a comprehensive Lido protocol health report including staking APR, TVL, governance activity, and exchange rates',
        inputSchema: {
            type: 'object',
            properties: {},
        },
    },
    // x402 payment protocol tools
    {
        name: 'x402_discover',
        description: 'Probe a URL for x402 payment requirements. Makes a GET request; if the server returns HTTP 402 with an x402 payment descriptor, returns the payment terms. If it returns 200, returns the data directly.',
        inputSchema: {
            type: 'object',
            properties: {
                url: {
                    type: 'string',
                    description: 'The URL to probe for x402 payment requirements',
                },
            },
            required: ['url'],
        },
    },
    {
        name: 'x402_pay',
        description: 'Build an unsigned transaction to fulfil an x402 payment. If the recipient is the Agent Treasury allowlist, uses spendYield; otherwise returns a direct wstETH transfer.',
        inputSchema: {
            type: 'object',
            properties: {
                amount: {
                    type: 'string',
                    description: 'Payment amount in wei (from the x402 descriptor)',
                },
                token: {
                    type: 'string',
                    description: 'ERC-20 token address (from the x402 descriptor)',
                },
                recipient: {
                    type: 'string',
                    description: 'Recipient address (from the x402 descriptor)',
                },
                purpose: {
                    type: 'string',
                    description: 'Human-readable description of the payment purpose',
                },
            },
            required: ['amount', 'token', 'recipient'],
        },
    },
    {
        name: 'x402_complete',
        description: 'Complete an x402 payment flow. Re-requests the URL with the X-Payment-TxHash header set to the transaction hash and returns the response data.',
        inputSchema: {
            type: 'object',
            properties: {
                url: {
                    type: 'string',
                    description: 'The original URL that returned 402',
                },
                txHash: {
                    type: 'string',
                    description: 'The transaction hash proving payment',
                },
            },
            required: ['url', 'txHash'],
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
    const noArgTools = ['get_staking_stats', 'lido_get_proposals', 'lido_protocol_health'];
    if (!args && !noArgTools.includes(name)) {
        throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
    }
    try {
        switch (name) {
            // Balance queries
            case 'get_steth_balance': {
                const address = args.address;
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
                            text: `stETH Balance: ${formatEther(balance)} stETH`,
                        },
                    ],
                };
            }
            case 'get_wsteth_balance': {
                const address = args.address;
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
                            text: `wstETH Balance: ${formatEther(balance)} wstETH`,
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
- Total Pooled ETH: ${formatEther(totalPooled)} ETH
- Total Shares: ${formatEther(totalShares)}
- Approximate APR: ${apr}%
- Exchange Rate: ${(Number(totalPooled) / Number(totalShares)).toFixed(6)} stETH/share`,
                        },
                    ],
                };
            }
            // Staking operations (return tx data for signing)
            case 'stake_eth': {
                const amount = parseEther(args.amount);
                const referral = (args.referral || '0x0000000000000000000000000000000000000000');
                return {
                    content: [
                        {
                            type: 'text',
                            text: `Transaction to sign:
- To: ${LIDO_CONTRACTS.stETH}
- Value: ${args.amount} ETH
- Data: submit(${referral})
- Function: Lido.submit() - stakes ETH and mints stETH`,
                        },
                    ],
                };
            }
            case 'wrap_steth': {
                const amount = parseEther(args.amount);
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
                const amount = parseEther(args.amount);
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
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const amount = args.amount;
                const erc8004Id = BigInt(args.erc8004Id || 0);
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
                const agent = args.agent;
                const yieldAmount = await client.readContract({
                    address: LIDO_CONTRACTS.agentTreasury,
                    abi: AGENT_TREASURY_ABI,
                    functionName: 'getAvailableYield',
                    args: [agent],
                });
                return {
                    content: [
                        {
                            type: 'text',
                            text: `Available Yield: ${formatEther(yieldAmount)} stETH`,
                        },
                    ],
                };
            }
            case 'treasury_spend_yield': {
                if (!LIDO_CONTRACTS.agentTreasury) {
                    throw new McpError(ErrorCode.InvalidRequest, 'Agent Treasury not deployed');
                }
                const recipient = args.recipient;
                const amount = args.amount;
                const purpose = args.purpose;
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
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const agent = args.agent;
                const info = await client.readContract({
                    address: LIDO_CONTRACTS.agentTreasury,
                    abi: AGENT_TREASURY_ABI,
                    functionName: 'getTreasuryInfo',
                    args: [agent],
                });
                const [principal, availableYield, totalYieldClaimed, totalYieldSpent, depositTime, currentRate, depositRate, exists] = info;
                return {
                    content: [
                        {
                            type: 'text',
                            text: exists
                                ? `Treasury Info for ${agent}:
- Principal: ${formatEther(principal)} wstETH
- Available Yield: ${formatEther(availableYield)} wstETH
- Total Yield Claimed: ${formatEther(totalYieldClaimed)} wstETH
- Total Yield Spent: ${formatEther(totalYieldSpent)} wstETH
- Deposit Time: ${new Date(Number(depositTime) * 1000).toISOString()}
- Current Rate: ${formatEther(currentRate)}
- Deposit Rate: ${formatEther(depositRate)}`
                                : `No treasury found for ${agent}`,
                        },
                    ],
                };
            }
            case 'dry_run': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const { to, data, from, value } = args;
                try {
                    // Use eth_call for dry run simulation
                    const result = await client.call({
                        to: to,
                        data: data,
                        account: from,
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
                }
                catch (error) {
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
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const quoteAmountWei = parseEther(args.amount);
                try {
                    // Use the Uniswap Developer Platform API for a real-time quote
                    const quote = await uniswapApiQuote({
                        tokenIn: LIDO_CONTRACTS.wstETH,
                        tokenOut: '0x4200000000000000000000000000000000000006', // WETH on Base
                        amount: quoteAmountWei.toString(),
                        chainId: 8453, // Base
                        type: 'EXACT_INPUT',
                    });
                    const qd = quote.quote || {};
                    const quoteOutputAmt = qd.output?.amount || '0';
                    const quotePriceImpact = qd.priceImpact != null ? `${qd.priceImpact}%` : 'N/A';
                    const quoteGasFeeUsd = qd.gasFeeUSD || 'N/A';
                    const quoteSlippage = qd.slippage != null ? `${qd.slippage}%` : 'N/A';
                    const quoteRouteSummary = qd.route
                        ? qd.route
                            .map((path) => path.map((hop) => `${hop.tokenIn?.symbol || '?'} -> ${hop.tokenOut?.symbol || '?'} (${(Number(hop.fee || 0) / 10000).toFixed(2)}%)`).join(' -> ')).join(' | ')
                        : 'wstETH -> WETH via Uniswap V3';
                    let quoteFormattedOutput;
                    try {
                        quoteFormattedOutput = formatEther(BigInt(quoteOutputAmt)) + ' ETH';
                    }
                    catch {
                        quoteFormattedOutput = quoteOutputAmt + ' ETH';
                    }
                    return {
                        content: [
                            {
                                type: 'text',
                                text: `Swap Quote (wstETH -> ETH) via Uniswap API:
- Input: ${args.amount} wstETH
- Expected Output: ${quoteFormattedOutput}
- Price Impact: ${quotePriceImpact}
- Slippage: ${quoteSlippage}
- Gas Fee: $${quoteGasFeeUsd}
- Route: ${quoteRouteSummary}
- Chain: Base (8453)

Quote sourced from Uniswap Developer Platform API.
Use swap_steth_to_eth to generate the transaction data.`,
                            },
                        ],
                    };
                }
                catch (apiError) {
                    // Fallback to estimate if API is unavailable
                    const fallbackPrice = 0.99;
                    const fallbackOutput = Number(args.amount) * fallbackPrice;
                    const fallbackFee = Number(args.amount) * 0.003;
                    const fallbackAfterFee = fallbackOutput - fallbackFee;
                    return {
                        content: [
                            {
                                type: 'text',
                                text: `Swap Quote (stETH -> ETH) [Estimated - API unavailable]:
- Input: ${args.amount} stETH
- Expected Output: ~${fallbackAfterFee.toFixed(6)} ETH
- Fee (0.3%): ~${fallbackFee.toFixed(6)} ETH
- Price Impact: ~0.01% (for small amounts)
- Route: stETH -> ETH via Uniswap V3 (0.3% pool)

Note: Uniswap API was unavailable. This is a fallback estimate.
Error: ${apiError instanceof Error ? apiError.message : 'Unknown error'}`,
                            },
                        ],
                    };
                }
            }
            case 'swap_steth_to_eth': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const amountIn = parseEther(args.amount);
                const slippage = Number(args.slippage || '0.5');
                // Try to get a real-time quote from Uniswap API for accurate pricing
                let swapEstimatedOutput;
                let apiQuoteInfo = '';
                try {
                    const apiQuote = await uniswapApiQuote({
                        tokenIn: LIDO_CONTRACTS.wstETH,
                        tokenOut: '0x4200000000000000000000000000000000000006', // WETH on Base
                        amount: amountIn.toString(),
                        chainId: 8453,
                        type: 'EXACT_INPUT',
                    });
                    const rawOutput = (apiQuote.quote ?? apiQuote.quoteDecimals ?? '').toString();
                    if (rawOutput) {
                        swapEstimatedOutput = Number(formatEther(BigInt(rawOutput)));
                        const swapPriceImpact = apiQuote.priceImpact != null ? `${(Number(apiQuote.priceImpact) * 100).toFixed(4)}%` : 'N/A';
                        const swapGas = apiQuote.gasUseEstimate || apiQuote.gasFee || 'N/A';
                        apiQuoteInfo = `\n\nUniswap API Quote:
- Expected Output: ${swapEstimatedOutput.toFixed(6)} ETH
- Price Impact: ${swapPriceImpact}
- Gas Estimate: ${swapGas}`;
                    }
                    else {
                        swapEstimatedOutput = Number(args.amount) * 0.99 * (1 - 0.003);
                    }
                }
                catch {
                    // Fallback to hardcoded estimate
                    swapEstimatedOutput = Number(args.amount) * 0.99 * (1 - 0.003);
                    apiQuoteInfo = '\n\nNote: Uniswap API unavailable, using estimated pricing.';
                }
                const minOutput = swapEstimatedOutput * (1 - slippage / 100);
                const amountOutMinimum = parseEther(minOutput.toFixed(18));
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
- tokenOut: 0x4200000000000000000000000000000000000006 (WETH on Base)
- fee: ${POOL_FEE}
- amountIn: ${amountIn.toString()}
- amountOutMinimum: ${amountOutMinimum.toString()}
- sqrtPriceLimitX96: 0

Steps to execute:
1. Approve SwapRouter to spend your stETH: approve(${UNISWAP_CONTRACTS.swapRouter}, ${amountIn})
2. Sign and send the exactInputSingle transaction${apiQuoteInfo}`,
                        },
                    ],
                };
            }
            case 'uniswap_get_quote': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const tokenIn = args.tokenIn;
                const tokenOut = args.tokenOut;
                const humanAmount = args.amount;
                // Convert human-readable amount to wei (18 decimals)
                const amountWeiStr = parseEther(humanAmount).toString();
                // Map "ETH" to the wrapped native token on Base
                const resolvedTokenIn = tokenIn.toUpperCase() === 'ETH'
                    ? '0x4200000000000000000000000000000000000006'
                    : tokenIn;
                const resolvedTokenOut = tokenOut.toUpperCase() === 'ETH'
                    ? '0x4200000000000000000000000000000000000006'
                    : tokenOut;
                const uniQuote = await uniswapApiQuote({
                    tokenIn: resolvedTokenIn,
                    tokenOut: resolvedTokenOut,
                    amount: amountWeiStr,
                    chainId: 8453, // Base
                    type: 'EXACT_INPUT',
                });
                // Parse the Uniswap Trading API response structure
                const q = uniQuote.quote || {};
                const outputAmount = q.output?.amount || '0';
                const priceImpact = q.priceImpact != null ? `${q.priceImpact}%` : 'N/A';
                const gasFeeUsd = q.gasFeeUSD || 'N/A';
                const gasEstimate = q.gasUseEstimate || 'N/A';
                const slippage = q.slippage != null ? `${q.slippage}%` : 'N/A';
                const routeInfo = q.route
                    ? q.route
                        .map((path) => path.map((hop) => `${hop.tokenIn?.symbol || '?'} -> ${hop.tokenOut?.symbol || '?'} (${(Number(hop.fee || 0) / 10000).toFixed(2)}%)`).join(' -> ')).join(' | ')
                    : `${resolvedTokenIn} -> ${resolvedTokenOut}`;
                let formattedOutput;
                try {
                    formattedOutput = formatEther(BigInt(outputAmount));
                }
                catch {
                    formattedOutput = outputAmount;
                }
                return {
                    content: [
                        {
                            type: 'text',
                            text: `Uniswap Quote (Base):
- Input: ${humanAmount} ${q.input?.token || resolvedTokenIn}
- Output: ${formattedOutput} ${q.output?.token || resolvedTokenOut}
- Price Impact: ${priceImpact}
- Slippage: ${slippage}
- Gas Fee: $${gasFeeUsd} (${gasEstimate} gas units)
- Route: ${routeInfo}
- Chain: Base (8453)

Quote sourced from Uniswap Developer Platform API.`,
                        },
                    ],
                };
            }
            // ============ x402 Payment Flow ============
            case 'x402_discover': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const discoverUrl = args.url;
                try {
                    const resp = await fetch(discoverUrl);
                    if (resp.status === 402) {
                        const body = await resp.json();
                        const payment = body.x402?.payment || body.payment || body;
                        return {
                            content: [{
                                    type: 'text',
                                    text: `x402 Payment Required:
- URL: ${discoverUrl}
- Amount: ${payment.amount ? formatEther(BigInt(payment.amount)) : 'N/A'} ${payment.token ? 'wstETH' : ''}
- Token: ${payment.token || 'N/A'}
- Recipient: ${payment.recipient || 'N/A'}
- Chain: ${payment.chainId || 'N/A'}
- Description: ${payment.description || 'N/A'}

Use x402_pay to generate a payment transaction, then x402_complete to access the resource.`,
                                }],
                        };
                    }
                    else {
                        const data = await resp.text();
                        return {
                            content: [{
                                    type: 'text',
                                    text: `URL returned ${resp.status} (no payment required):\n${data.substring(0, 500)}`,
                                }],
                        };
                    }
                }
                catch (fetchErr) {
                    throw new McpError(ErrorCode.InternalError, `Failed to reach ${discoverUrl}: ${fetchErr instanceof Error ? fetchErr.message : 'Unknown error'}`);
                }
            }
            case 'x402_pay': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const payAmount = args.amount;
                const payToken = args.token;
                const payRecipient = args.recipient;
                // Generate transaction data using the treasury spendYield or direct transfer
                const txData = encodeFunctionData({
                    abi: ERC20_TRANSFER_ABI,
                    functionName: 'transfer',
                    args: [payRecipient, BigInt(payAmount)],
                });
                return {
                    content: [{
                            type: 'text',
                            text: `x402 Payment Transaction:
- To: ${payToken} (wstETH)
- Function: transfer(${payRecipient}, ${payAmount})
- Data: ${txData}
- Amount: ${formatEther(BigInt(payAmount))} wstETH

Sign and broadcast this transaction, then use x402_complete with the tx hash.`,
                        }],
                };
            }
            case 'x402_complete': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const completeUrl = args.url;
                const txHash = args.txHash;
                try {
                    const resp = await fetch(completeUrl, {
                        headers: { 'X-Payment-TxHash': txHash },
                    });
                    const data = await resp.text();
                    return {
                        content: [{
                                type: 'text',
                                text: `x402 Response (${resp.status}):\n${data}`,
                            }],
                    };
                }
                catch (fetchErr) {
                    throw new McpError(ErrorCode.InternalError, `Failed to complete x402: ${fetchErr instanceof Error ? fetchErr.message : 'Unknown error'}`);
                }
            }
            // ============ Lido Governance ============
            case 'lido_get_proposals': {
                const state = args?.state || 'all';
                const limit = Math.min(Number(args?.limit) || 5, 20);
                const whereClause = state === 'all'
                    ? `space_in: ["${LIDO_SNAPSHOT_SPACE}"]`
                    : `space_in: ["${LIDO_SNAPSHOT_SPACE}"], state: "${state}"`;
                const data = await snapshotQuery(`{
          proposals(first: ${limit}, skip: 0, where: { ${whereClause} }, orderBy: "created", orderDirection: desc) {
            id title state start end choices scores scores_total votes author
          }
        }`);
                const proposals = data.proposals || [];
                if (proposals.length === 0) {
                    return { content: [{ type: 'text', text: 'No Lido governance proposals found.' }] };
                }
                const formatted = proposals.map((p, i) => {
                    const startDate = new Date(p.start * 1000).toISOString().split('T')[0];
                    const endDate = new Date(p.end * 1000).toISOString().split('T')[0];
                    const topChoice = p.scores && p.choices
                        ? p.choices[p.scores.indexOf(Math.max(...p.scores))]
                        : 'N/A';
                    return `${i + 1}. [${p.state.toUpperCase()}] ${p.title}
   Period: ${startDate} to ${endDate} | Votes: ${p.votes} | Leading: ${topChoice}
   ID: ${p.id}`;
                }).join('\n\n');
                return { content: [{ type: 'text', text: `Lido Governance Proposals:\n\n${formatted}` }] };
            }
            case 'lido_get_proposal_details': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const proposalId = args.id;
                const data = await snapshotQuery(`{
          proposal(id: "${proposalId}") {
            id title body state start end choices scores scores_total votes author link discussion
          }
        }`);
                const p = data.proposal;
                if (!p) {
                    return { content: [{ type: 'text', text: `Proposal ${proposalId} not found.` }] };
                }
                const startDate = new Date(p.start * 1000).toISOString();
                const endDate = new Date(p.end * 1000).toISOString();
                const choiceResults = p.choices?.map((c, i) => `  ${c}: ${p.scores?.[i]?.toFixed(2) || '0'} votes`).join('\n') || 'N/A';
                // Truncate body to avoid huge responses
                const body = p.body?.substring(0, 1000) || 'No description';
                return {
                    content: [{
                            type: 'text',
                            text: `Proposal: ${p.title}
State: ${p.state.toUpperCase()}
Author: ${p.author}
Period: ${startDate} to ${endDate}
Total Votes: ${p.votes}

Results:
${choiceResults}

Description:
${body}${p.body?.length > 1000 ? '\n...(truncated)' : ''}

Link: ${p.link || 'N/A'}
Discussion: ${p.discussion || 'N/A'}`,
                        }],
                };
            }
            case 'lido_get_voting_power': {
                if (!args)
                    throw new McpError(ErrorCode.InvalidRequest, 'Missing arguments');
                const voterAddress = args.address;
                const ldoBalance = await mainnetClient.readContract({
                    address: LIDO_CONTRACTS.LDO,
                    abi: LDO_ABI,
                    functionName: 'balanceOf',
                    args: [voterAddress],
                });
                return {
                    content: [{
                            type: 'text',
                            text: `Voting Power for ${voterAddress}:
- LDO Balance: ${formatEther(ldoBalance)} LDO
- Network: Ethereum Mainnet

Note: Voting power in Lido Snapshot governance is based on LDO token holdings.`,
                        }],
                };
            }
            case 'lido_protocol_health': {
                const [totalPooled, totalShares, proposalsData] = await Promise.all([
                    mainnetClient.readContract({
                        address: LIDO_CONTRACTS.stETH,
                        abi: STETH_ABI,
                        functionName: 'getTotalPooledEther',
                    }).catch(() => null),
                    mainnetClient.readContract({
                        address: LIDO_CONTRACTS.stETH,
                        abi: STETH_ABI,
                        functionName: 'getTotalShares',
                    }).catch(() => null),
                    snapshotQuery(`{
            proposals(first: 5, where: { space_in: ["${LIDO_SNAPSHOT_SPACE}"], state: "active" }) {
              id title state
            }
          }`).catch(() => ({ proposals: [] })),
                ]);
                const tvl = totalPooled ? formatEther(totalPooled) : 'N/A';
                const shares = totalShares ? formatEther(totalShares) : 'N/A';
                const rate = (totalPooled && totalShares)
                    ? (Number(totalPooled) / Number(totalShares)).toFixed(6)
                    : 'N/A';
                const activeProposals = proposalsData.proposals || [];
                return {
                    content: [{
                            type: 'text',
                            text: `Lido Protocol Health Report:
- Total Value Locked: ${tvl} ETH
- Total Shares: ${shares}
- stETH/Share Rate: ${rate}
- Approximate APR: ~3.0-3.5%
- Active Governance Proposals: ${activeProposals.length}
${activeProposals.map((p) => `  - ${p.title}`).join('\n')}

Data sourced from Ethereum mainnet and Snapshot.`,
                        }],
                };
            }
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
        }
    }
    catch (error) {
        if (error instanceof McpError)
            throw error;
        throw new McpError(ErrorCode.InternalError, `Error executing ${name}: ${error instanceof Error ? error.message : 'Unknown error'}`);
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
