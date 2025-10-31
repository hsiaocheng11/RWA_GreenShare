// FILE: tests/contracts.test.ts
import { ethers } from 'ethers';
import CONTRACT_ADDRESSES from '../lib/config/contracts';

describe('Smart Contract Configuration Tests', () => {
  test('Contract addresses are properly configured', () => {
    expect(CONTRACT_ADDRESSES).toHaveProperty('zircuit');
    expect(CONTRACT_ADDRESSES).toHaveProperty('celo');
    expect(CONTRACT_ADDRESSES).toHaveProperty('sui');

    // Check Zircuit addresses
    expect(CONTRACT_ADDRESSES.zircuit.testnet).toHaveProperty('eKWH');
    expect(CONTRACT_ADDRESSES.zircuit.testnet).toHaveProperty('Bridge');
    expect(CONTRACT_ADDRESSES.zircuit.testnet).toHaveProperty('GudAdapter');

    // Check Celo addresses  
    expect(CONTRACT_ADDRESSES.celo.alfajores).toHaveProperty('KYCRegistry');

    // Check Sui package IDs
    expect(CONTRACT_ADDRESSES.sui.testnet).toHaveProperty('packageId');
    expect(CONTRACT_ADDRESSES.sui.testnet).toHaveProperty('sKWH');
    expect(CONTRACT_ADDRESSES.sui.testnet).toHaveProperty('Certificate');
  });

  test('Addresses have valid format', () => {
    // Test Ethereum address format (0x + 40 hex chars)
    const ethAddressRegex = /^0x[a-fA-F0-9]{40}$/;
    
    Object.values(CONTRACT_ADDRESSES.zircuit.testnet).forEach(address => {
      if (typeof address === 'string' && address !== '<PLACEHOLDER>') {
        expect(address).toMatch(ethAddressRegex);
      }
    });

    Object.values(CONTRACT_ADDRESSES.celo.alfajores).forEach(address => {
      if (typeof address === 'string' && address !== '<PLACEHOLDER>') {
        expect(address).toMatch(ethAddressRegex);
      }
    });

    // Test Sui object ID format (0x + 64 hex chars)
    const suiIdRegex = /^0x[a-fA-F0-9]{64}$/;
    
    Object.values(CONTRACT_ADDRESSES.sui.testnet).forEach(id => {
      if (typeof id === 'string' && id !== '<PLACEHOLDER>') {
        expect(id).toMatch(suiIdRegex);
      }
    });
  });

  test('Environment variables are accessible', () => {
    // These should be set in test environment
    expect(process.env.ROFL_ENDPOINT).toBeDefined();
    expect(process.env.WALRUS_GATEWAY_URL).toBeDefined();
    expect(process.env.SUI_NETWORK).toBeDefined();
  });
});