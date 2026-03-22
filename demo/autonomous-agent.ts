/**
 * Autonomous Agent Demo
 *
 * Demonstrates a full decision loop: discover -> plan -> execute -> verify.
 * Uses viem for on-chain reads on Base mainnet and external APIs
 * (Uniswap Trading API, Snapshot GraphQL) for off-chain data.
 *
 * This is a standalone script - no MCP protocol/SDK dependency.
 */

import { createPublicClient, http, formatEther, parseEther } from 'viem';
import { base } from 'viem/chains';
import { writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// ============ Configuration ============

const AGENT_ADDRESS = '0xf825C976f42F1B2782DdE8190EEB4Cc71152C464' as const;

const CONTRACTS = {
  wstETH: '0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452' as `0x${string}`,
  agentTreasury: '0x4e0acb29d642982403a3bd6a40181a828f2265a0' as `0x${string}`,
};

const UNISWAP_API_KEY = 'CQlhRign_d5zFkm__YqTMzFnjf-bgS15opC3Ntx_0Ik';
const UNISWAP_API_BASE = 'https://trade-api.gateway.uniswap.org/v1';
const SNAPSHOT_GRAPHQL_URL = 'https://hub.snapshot.org/graphql';
const LIDO_SNAPSHOT_SPACE = 'lido-snapshot.eth';

// x402 service discovery endpoint (configurable)
const X402_SERVICE_URL = process.env.X402_SERVICE_URL || 'http://localhost:4020';

// Yield sweep threshold in wstETH (raw units)
const YIELD_THRESHOLD = parseEther('0.000001');

// Base chain tokens
const WETH_BASE = '0x4200000000000000000000000000000000000006';
const WSTETH_BASE = CONTRACTS.wstETH;
const USDC_BASE = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';

// ============ ABIs ============

const TREASURY_ABI = [
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
  {
    name: 'getAvailableYield',
    inputs: [{ name: 'agent', type: 'address' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'getCurrentStEthPerToken',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    name: 'getYieldStats',
    inputs: [{ name: 'agent', type: 'address' }],
    outputs: [
      { name: 'principalWstETH', type: 'uint256' },
      { name: 'currentStETHValue', type: 'uint256' },
      { name: 'yieldEarnedStETH', type: 'uint256' },
      { name: 'aprBps', type: 'uint256' },
    ],
    stateMutability: 'view',
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
    name: 'stEthPerToken',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ============ Helpers ============

function banner(title: string) {
  const line = '='.repeat(60);
  console.log(`\n${line}`);
  console.log(`  ${title}`);
  console.log(line);
}

function step(n: number, msg: string) {
  console.log(`  [Step ${n}] ${msg}`);
}

function detail(label: string, value: string) {
  console.log(`           ${label}: ${value}`);
}

function timestamp(): string {
  return new Date().toISOString();
}

// ============ API Helpers ============

async function uniswapQuote(params: {
  tokenIn: string;
  tokenOut: string;
  amount: string;
  type: 'EXACT_INPUT' | 'EXACT_OUTPUT';
}): Promise<any> {
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
      tokenInChainId: base.id,
      tokenOutChainId: base.id,
      amount: params.amount,
      type: params.type,
      swapper: '0x0000000000000000000000000000000000000001',
      autoSlippage: 'DEFAULT',
      routingPreference: 'BEST_PRICE',
    }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Uniswap API ${resp.status}: ${text}`);
  }
  return resp.json();
}

async function snapshotQuery(query: string): Promise<any> {
  const resp = await fetch(SNAPSHOT_GRAPHQL_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Snapshot API ${resp.status}: ${text}`);
  }
  const json = (await resp.json()) as { data?: any; errors?: any[] };
  if (json.errors) {
    throw new Error(`Snapshot GraphQL error: ${JSON.stringify(json.errors)}`);
  }
  return json.data;
}

/**
 * Extract the output amount from a Uniswap quote response.
 * The API structure can vary; we try several known paths.
 */
function extractQuoteOutput(quote: any): string | null {
  if (!quote) return null;
  // v1/quote typical structure: { quote: { output: { amount: "..." } } }
  // or { quote: "..." } or { output: "..." } or nested
  const candidates = [
    quote?.quote?.output?.amount,
    quote?.quote?.output,
    quote?.quote?.quoteDecimals && quote?.quote?.quote,
    quote?.quote?.amount,
    quote?.output?.amount,
    quote?.output,
    quote?.amount,
    quote?.quoteGasAdjusted,
  ];
  for (const c of candidates) {
    if (typeof c === 'string' && /^\d+$/.test(c)) return c;
    if (typeof c === 'number') return String(c);
    if (typeof c === 'bigint') return c.toString();
  }
  return null;
}

// ============ Report Accumulator ============

interface AgentReport {
  agentAddress: string;
  timestamp: string;
  cycles: {
    discover: any;
    plan: any;
    x402Discovery: any;
    verify: any;
  };
  summary: string;
}

const report: AgentReport = {
  agentAddress: AGENT_ADDRESS,
  timestamp: '',
  cycles: {
    discover: null,
    plan: null,
    x402Discovery: null,
    verify: null,
  },
  summary: '',
};

// ============ Main Agent Logic ============

async function main() {
  console.log('\n  Autonomous Agent Demo');
  console.log('  Lido Agent Suite - Decision Loop\n');
  console.log(`  Agent: ${AGENT_ADDRESS}`);
  console.log(`  Chain: Base (chain ID ${base.id})`);
  console.log(`  Time:  ${timestamp()}`);
  report.timestamp = timestamp();

  // ---- Create viem client ----
  const client = createPublicClient({
    chain: base,
    transport: http(process.env.BASE_RPC_URL || 'https://mainnet.base.org'),
  });

  // ================================================================
  // CYCLE 1: DISCOVER & ASSESS
  // ================================================================
  banner('CYCLE 1: DISCOVER & ASSESS');

  step(1, 'Connecting to Base RPC...');
  const blockNumber = await client.getBlockNumber();
  detail('Block number', blockNumber.toString());

  step(2, 'Reading treasury info for agent...');
  let treasuryInfo: any;
  let treasuryExists = false;
  try {
    treasuryInfo = await client.readContract({
      address: CONTRACTS.agentTreasury,
      abi: TREASURY_ABI,
      functionName: 'getTreasuryInfo',
      args: [AGENT_ADDRESS],
    });
    treasuryExists = treasuryInfo[7]; // exists field
    detail('Principal', `${formatEther(treasuryInfo[0])} wstETH`);
    detail('Available yield', `${formatEther(treasuryInfo[1])} wstETH`);
    detail('Total yield claimed', `${formatEther(treasuryInfo[2])} wstETH`);
    detail('Total yield spent', `${formatEther(treasuryInfo[3])} wstETH`);
    detail('Deposit time', new Date(Number(treasuryInfo[4]) * 1000).toISOString());
    detail('Current rate', treasuryInfo[5].toString());
    detail('Deposit rate', treasuryInfo[6].toString());
    detail('Exists', treasuryExists.toString());
  } catch (e: any) {
    detail('Treasury', `Read failed: ${e.message?.slice(0, 120)}`);
    // Set defaults for report
    treasuryInfo = [0n, 0n, 0n, 0n, 0n, 0n, 0n, false];
  }

  step(3, 'Checking available yield...');
  let availableYield = 0n;
  try {
    const yieldResult = await client.readContract({
      address: CONTRACTS.agentTreasury,
      abi: TREASURY_ABI,
      functionName: 'getAvailableYield',
      args: [AGENT_ADDRESS],
    });
    availableYield = yieldResult as bigint;
    detail('Available yield (direct)', `${formatEther(availableYield)} wstETH`);
  } catch (e: any) {
    detail('Yield check', `Failed: ${e.message?.slice(0, 120)}`);
  }

  step(4, 'Getting Uniswap quote for wstETH -> ETH...');
  let swapQuote: any = null;
  let swapOutputRaw: string | null = null;
  const quoteAmountWei = availableYield > 0n
    ? availableYield.toString()
    : parseEther('0.001').toString(); // use a reference amount if no yield
  try {
    swapQuote = await uniswapQuote({
      tokenIn: WSTETH_BASE,
      tokenOut: WETH_BASE,
      amount: quoteAmountWei,
      type: 'EXACT_INPUT',
    });
    // Extract output amount from Uniswap response (structure varies by API version)
    swapOutputRaw = extractQuoteOutput(swapQuote);
    if (!swapOutputRaw) {
      detail('Quote response (debug)', JSON.stringify(swapQuote).slice(0, 300));
    }
    const quoteIn = formatEther(BigInt(quoteAmountWei));
    const quoteOut = swapOutputRaw ? formatEther(BigInt(swapOutputRaw)) : 'N/A';
    detail('Quote input', `${quoteIn} wstETH`);
    detail('Quote output', `${quoteOut} WETH`);
    detail('Gas estimate', swapQuote?.quote?.gasUseEstimate ?? swapQuote?.gasUseEstimate ?? 'N/A');
  } catch (e: any) {
    detail('Uniswap quote', `Failed: ${e.message?.slice(0, 200)}`);
  }

  step(5, 'Querying Lido governance health from Snapshot...');
  let snapshotData: any = null;
  try {
    snapshotData = await snapshotQuery(`{
      space(id: "${LIDO_SNAPSHOT_SPACE}") {
        id
        name
        members
        proposalsCount
        followersCount
      }
      proposals(
        first: 3
        where: { space_in: ["${LIDO_SNAPSHOT_SPACE}"] }
        orderBy: "created"
        orderDirection: desc
      ) {
        id
        title
        state
        created
        scores_total
      }
    }`);
    if (snapshotData?.space) {
      detail('Space', snapshotData.space.name);
      detail('Total proposals', snapshotData.space.proposalsCount?.toString() ?? 'N/A');
      detail('Followers', snapshotData.space.followersCount?.toString() ?? 'N/A');
    }
    if (snapshotData?.proposals?.length) {
      for (const p of snapshotData.proposals) {
        detail('Recent proposal', `[${p.state}] ${p.title}`);
      }
    }
  } catch (e: any) {
    detail('Snapshot', `Failed: ${e.message?.slice(0, 200)}`);
  }

  step(6, 'Discovery complete.');
  const principalStr = formatEther(treasuryInfo[0]);
  const yieldStr = formatEther(availableYield);
  const rateStr = swapOutputRaw
    ? `1 wstETH ~ ${(Number(formatEther(BigInt(swapOutputRaw))) / Number(formatEther(BigInt(quoteAmountWei)))).toFixed(6)} WETH`
    : 'N/A';
  detail('Summary', `Principal: ${principalStr} wstETH, Yield: ${yieldStr} wstETH, Swap rate: ${rateStr}`);

  report.cycles.discover = {
    blockNumber: blockNumber.toString(),
    treasuryExists,
    principal: principalStr,
    availableYield: yieldStr,
    swapQuoteInput: formatEther(BigInt(quoteAmountWei)),
    swapQuoteOutput: swapOutputRaw ? formatEther(BigInt(swapOutputRaw)) : null,
    snapshotSpace: snapshotData?.space?.name ?? null,
    recentProposals: snapshotData?.proposals?.map((p: any) => p.title) ?? [],
  };

  // ================================================================
  // CYCLE 2: PLAN
  // ================================================================
  banner('CYCLE 2: PLAN');

  step(7, 'Evaluating yield against threshold...');
  const thresholdStr = formatEther(YIELD_THRESHOLD);
  detail('Threshold', `${thresholdStr} wstETH`);
  detail('Available', `${yieldStr} wstETH`);
  const yieldAboveThreshold = availableYield > YIELD_THRESHOLD;
  detail('Above threshold', yieldAboveThreshold.toString());

  step(8, 'Checking Uniswap for best swap route...');
  let usdcQuote: any = null;
  let usdcOutputRaw: string | null = null;
  try {
    usdcQuote = await uniswapQuote({
      tokenIn: WSTETH_BASE,
      tokenOut: USDC_BASE,
      amount: quoteAmountWei,
      type: 'EXACT_INPUT',
    });
    usdcOutputRaw = extractQuoteOutput(usdcQuote);
    const usdcOut = usdcOutputRaw
      ? (Number(usdcOutputRaw) / 1e6).toFixed(2)
      : 'N/A';
    detail('wstETH -> USDC output', `${usdcOut} USDC`);
  } catch (e: any) {
    detail('USDC quote', `Failed: ${e.message?.slice(0, 200)}`);
  }

  step(9, 'Deciding action...');
  let decision: string;
  let reasoning: string;

  if (!treasuryExists) {
    decision = 'HOLD';
    reasoning = 'No treasury deposit found for this agent. Nothing to sweep.';
  } else if (!yieldAboveThreshold) {
    decision = 'HOLD';
    reasoning = `Yield (${yieldStr} wstETH) is below the threshold (${thresholdStr} wstETH). Accumulating more yield before action.`;
  } else {
    // Compare WETH and USDC outputs to decide best swap
    const ethValue = swapOutputRaw ? Number(formatEther(BigInt(swapOutputRaw))) : 0;
    const usdcValue = usdcOutputRaw ? Number(usdcOutputRaw) / 1e6 : 0;

    if (ethValue === 0 && usdcValue === 0) {
      decision = 'SWEEP_YIELD';
      reasoning = 'Yield is above threshold but swap quotes unavailable. Recommend sweeping yield for later use.';
    } else if (usdcValue > ethValue * 3000) {
      // Very rough: if USDC value seems better accounting for ETH price ~$3000
      decision = 'SWAP_TO_USDC';
      reasoning = `USDC route appears favorable. Would receive ${usdcValue.toFixed(2)} USDC vs ${ethValue.toFixed(6)} ETH.`;
    } else {
      decision = 'SWAP_TO_ETH';
      reasoning = `ETH route is standard. Would receive ${ethValue.toFixed(6)} ETH from ${yieldStr} wstETH yield.`;
    }
  }

  step(10, `Decision: ${decision}`);
  detail('Reasoning', reasoning);

  report.cycles.plan = {
    yieldAboveThreshold,
    threshold: thresholdStr,
    ethSwapEstimate: swapOutputRaw ? formatEther(BigInt(swapOutputRaw)) : null,
    usdcSwapEstimate: usdcOutputRaw ? (Number(usdcOutputRaw) / 1e6).toFixed(2) : null,
    decision,
    reasoning,
  };

  // ================================================================
  // CYCLE 3: x402 SERVICE DISCOVERY
  // ================================================================
  banner('CYCLE 3: x402 SERVICE DISCOVERY');

  step(11, `Attempting to discover x402 service at ${X402_SERVICE_URL}...`);
  let x402Available = false;
  let x402Terms: any = null;

  try {
    const x402Resp = await fetch(`${X402_SERVICE_URL}/weather?city=Zurich`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });

    if (x402Resp.status === 402) {
      x402Available = true;
      detail('Status', '402 Payment Required (x402 service detected!)');

      step(12, 'Parsing 402 payment terms...');
      const paymentHeader = x402Resp.headers.get('x-payment') ||
                             x402Resp.headers.get('www-authenticate');
      let body: any = null;
      try {
        body = await x402Resp.json();
      } catch {
        body = await x402Resp.text().catch(() => null);
      }

      x402Terms = {
        paymentHeader,
        body: typeof body === 'object' ? body : { raw: body },
      };
      detail('Payment header', paymentHeader ?? '(none)');
      detail('Body', JSON.stringify(x402Terms.body)?.slice(0, 200) ?? '(none)');

      step(13, 'Evaluating affordability...');
      // Try to extract cost from the payment terms
      const costMatch = JSON.stringify(x402Terms.body).match(/"maxAmountRequired"\s*:\s*"?(\d+)"?/);
      if (costMatch) {
        const serviceCost = BigInt(costMatch[1]);
        const canAfford = availableYield >= serviceCost;
        detail('Service cost', `${formatEther(serviceCost)} wstETH`);
        detail('Available yield', `${yieldStr} wstETH`);
        detail('Can afford', canAfford.toString());
      } else {
        detail('Cost parsing', 'Could not extract cost from payment terms');
        detail('Available yield', `${yieldStr} wstETH`);
      }
    } else if (x402Resp.ok) {
      detail('Status', `${x402Resp.status} OK (service responded without payment requirement)`);
      const responseBody = await x402Resp.text().catch(() => '');
      detail('Response', responseBody.slice(0, 200));
    } else {
      detail('Status', `${x402Resp.status} (unexpected response)`);
    }
  } catch (e: any) {
    detail('x402 discovery', `Service not available: ${e.message?.slice(0, 120)}`);
    detail('Note', 'This is expected if the x402 demo server is not running');
  }

  step(14, 'x402 discovery summary.');
  const x402Summary = x402Available
    ? 'x402 service found - payment-gated API detected'
    : 'x402 service not available (demo server likely not running)';
  detail('Result', x402Summary);

  report.cycles.x402Discovery = {
    serviceUrl: X402_SERVICE_URL,
    available: x402Available,
    terms: x402Terms,
    summary: x402Summary,
  };

  // ================================================================
  // CYCLE 4: VERIFY & REPORT
  // ================================================================
  banner('CYCLE 4: VERIFY & REPORT');

  step(15, 'Re-reading treasury state...');
  let verifyTreasuryInfo: any;
  let verifyYield = 0n;
  try {
    verifyTreasuryInfo = await client.readContract({
      address: CONTRACTS.agentTreasury,
      abi: TREASURY_ABI,
      functionName: 'getTreasuryInfo',
      args: [AGENT_ADDRESS],
    });
    verifyYield = verifyTreasuryInfo[1] as bigint;
    detail('Principal', `${formatEther(verifyTreasuryInfo[0])} wstETH`);
    detail('Available yield', `${formatEther(verifyYield)} wstETH`);
  } catch (e: any) {
    detail('Verify treasury', `Read failed: ${e.message?.slice(0, 120)}`);
    verifyTreasuryInfo = treasuryInfo;
    verifyYield = availableYield;
  }

  step(16, 'Comparing with initial state...');
  const yieldDelta = verifyYield - availableYield;
  detail('Initial yield', `${formatEther(availableYield)} wstETH`);
  detail('Current yield', `${formatEther(verifyYield)} wstETH`);
  detail('Delta', `${formatEther(yieldDelta)} wstETH`);
  detail('Note', yieldDelta >= 0n
    ? 'Yield accrued during agent run (or unchanged)'
    : 'Yield decreased (possibly spent between reads)');

  step(17, 'Generating JSON report...');
  report.cycles.verify = {
    principalBefore: principalStr,
    principalAfter: formatEther(verifyTreasuryInfo[0]),
    yieldBefore: yieldStr,
    yieldAfter: formatEther(verifyYield),
    yieldDelta: formatEther(yieldDelta),
    blockAtVerify: (await client.getBlockNumber()).toString(),
  };

  report.summary = [
    `Agent ${AGENT_ADDRESS} on Base (block ${report.cycles.verify.blockAtVerify}).`,
    `Treasury: ${treasuryExists ? 'active' : 'not found'}.`,
    `Principal: ${principalStr} wstETH.`,
    `Yield: ${yieldStr} wstETH (threshold: ${thresholdStr}).`,
    `Decision: ${decision} - ${reasoning}`,
    `x402: ${x402Summary}.`,
  ].join(' ');

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const reportPath = join(__dirname, '..', 'agent-report.json');
  await writeFile(reportPath, JSON.stringify(report, null, 2));

  step(18, `Report written to ${reportPath}`);

  banner('AGENT RUN COMPLETE');
  console.log(`\n  Summary: ${report.summary}\n`);
}

// ============ Entry Point ============

main().catch((err) => {
  console.error('\n  FATAL ERROR:', err);
  process.exit(1);
});
