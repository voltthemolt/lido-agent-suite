#!/usr/bin/env node

/**
 * x402 Demo Server
 *
 * A standalone HTTP server demonstrating the x402 payment protocol.
 * Endpoints return dummy data but require x402 payment proof (a tx hash header).
 *
 * Usage:
 *   node dist/x402-server.js [port]
 */

import { createServer, IncomingMessage, ServerResponse } from 'node:http';

// ============ Payment Descriptor ============

interface X402PaymentDescriptor {
  version: string;
  payment: {
    amount: string;
    token: string;
    recipient: string;
    chainId: number;
    description: string;
  };
}

const PAYMENT_DESCRIPTORS: Record<string, X402PaymentDescriptor> = {
  '/api/ai-weather': {
    version: '1',
    payment: {
      amount: '10000000000000',
      token: '0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452',
      recipient: '0x000000000000000000000000000000000000dEaD',
      chainId: 8453,
      description: 'AI Weather API access - 1 call',
    },
  },
  '/api/ai-news': {
    version: '1',
    payment: {
      amount: '10000000000000',
      token: '0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452',
      recipient: '0x000000000000000000000000000000000000dEaD',
      chainId: 8453,
      description: 'AI News API access - 1 call',
    },
  },
};

// ============ Dummy Data ============

const WEATHER_DATA = {
  location: 'New York, NY',
  temperature: 72,
  unit: 'F',
  conditions: 'Partly cloudy',
  humidity: 55,
  wind: { speed: 8, direction: 'NW' },
  forecast: [
    { day: 'Today', high: 74, low: 62, conditions: 'Partly cloudy' },
    { day: 'Tomorrow', high: 78, low: 65, conditions: 'Sunny' },
    { day: 'Wednesday', high: 71, low: 58, conditions: 'Rain likely' },
  ],
  source: 'x402-demo',
  timestamp: new Date().toISOString(),
};

const NEWS_DATA = {
  articles: [
    {
      title: 'DeFi Protocol Reaches $10B TVL Milestone',
      summary: 'A leading DeFi protocol has crossed the $10 billion total value locked threshold.',
      category: 'DeFi',
      published: '2026-03-22T10:00:00Z',
    },
    {
      title: 'Layer 2 Adoption Surges in Q1',
      summary: 'Layer 2 rollup solutions see record transaction volumes as adoption accelerates.',
      category: 'Infrastructure',
      published: '2026-03-22T09:30:00Z',
    },
    {
      title: 'AI Agents Now Managing On-Chain Treasuries',
      summary: 'Autonomous AI agents are increasingly being used to manage protocol treasuries and yield strategies.',
      category: 'AI',
      published: '2026-03-22T08:45:00Z',
    },
  ],
  source: 'x402-demo',
  timestamp: new Date().toISOString(),
};

// ============ Request Handler ============

function sendJson(res: ServerResponse, statusCode: number, data: unknown, headers?: Record<string, string>): void {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    ...headers,
  });
  res.end(body);
}

function handleRequest(req: IncomingMessage, res: ServerResponse): void {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const pathname = url.pathname;

  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'X-Payment-TxHash, Content-Type',
    });
    res.end();
    return;
  }

  // Health check
  if (pathname === '/' || pathname === '/health') {
    sendJson(res, 200, { status: 'ok', endpoints: ['/api/ai-weather', '/api/ai-news'] });
    return;
  }

  // Check if this is a paid endpoint
  const descriptor = PAYMENT_DESCRIPTORS[pathname];
  if (!descriptor) {
    sendJson(res, 404, { error: 'Not found' });
    return;
  }

  // Only GET is supported
  if (req.method !== 'GET') {
    sendJson(res, 405, { error: 'Method not allowed' });
    return;
  }

  // Check for payment proof
  const txHash = req.headers['x-payment-txhash'] as string | undefined;

  if (!txHash) {
    // No payment proof -- return 402 with payment descriptor
    sendJson(res, 402, { x402: descriptor });
    return;
  }

  // Payment proof provided -- return data with receipt header
  const receiptId = `rcpt_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  const responseHeaders: Record<string, string> = {
    'X-Payment-Receipt': receiptId,
    'X-Payment-TxHash': txHash,
  };

  if (pathname === '/api/ai-weather') {
    sendJson(res, 200, WEATHER_DATA, responseHeaders);
  } else if (pathname === '/api/ai-news') {
    sendJson(res, 200, NEWS_DATA, responseHeaders);
  }
}

// ============ Start Server ============

const PORT = parseInt(process.env.X402_PORT || process.argv[2] || '4020', 10);

const httpServer = createServer(handleRequest);

httpServer.listen(PORT, () => {
  console.log(`x402 demo server listening on http://localhost:${PORT}`);
  console.log('Endpoints:');
  console.log(`  GET http://localhost:${PORT}/api/ai-weather  (requires x402 payment)`);
  console.log(`  GET http://localhost:${PORT}/api/ai-news     (requires x402 payment)`);
});
