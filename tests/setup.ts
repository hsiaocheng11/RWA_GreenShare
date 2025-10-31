// FILE: tests/setup.ts
import { config } from 'dotenv';
import path from 'path';

// Load test environment variables
config({ path: path.resolve(__dirname, '../.env.test') });

// Mock environment variables for testing
process.env.ROFL_ENDPOINT = 'http://localhost:8080';
process.env.ROFL_HOST = '0.0.0.0';
process.env.ROFL_PORT = '8080';
process.env.WALRUS_GATEWAY_URL = 'https://aggregator-devnet.walrus.space';
process.env.SUI_NETWORK = 'testnet';
process.env.ZIRCUIT_RPC_URL = 'https://zircuit-testnet.drpc.org';
process.env.CELO_RPC_URL = 'https://alfajores-forno.celo-testnet.org';

// Global test timeout
jest.setTimeout(30000);

// Mock crypto for Node.js testing
global.crypto = require('crypto').webcrypto;