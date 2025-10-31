// FILE: tests/crypto.test.ts
import { describe, it, expect, beforeEach } from 'vitest';
import {
  generateKeyPair,
  importPrivateKeyFromPEM,
  generateNonce,
  createMessageHash,
  signMeterRecord,
  verifySignature,
  createSignedMeterData,
  type MeterRecord
} from '../src/crypto';

describe('Crypto Module', () => {
  let testPrivateKey: string;
  let testPublicKey: string;
  let testRecord: MeterRecord;

  beforeEach(() => {
    const keyPair = generateKeyPair();
    testPrivateKey = keyPair.privateKey;
    testPublicKey = keyPair.publicKey;
    
    testRecord = {
      meter_id: 'test_meter_001',
      timestamp: 1640995200000, // Fixed timestamp for deterministic tests
      kwh_delta: 1.234,
      nonce: 'test_nonce_123456'
    };
  });

  describe('Key Generation', () => {
    it('should generate valid ECDSA key pairs', () => {
      const keyPair = generateKeyPair();
      
      expect(keyPair.privateKey).toMatch(/^[0-9a-f]{64}$/i);
      expect(keyPair.publicKey).toMatch(/^[0-9a-f]{130}$/i);
    });

    it('should generate different keys on each call', () => {
      const keyPair1 = generateKeyPair();
      const keyPair2 = generateKeyPair();
      
      expect(keyPair1.privateKey).not.toBe(keyPair2.privateKey);
      expect(keyPair1.publicKey).not.toBe(keyPair2.publicKey);
    });
  });

  describe('PEM Import', () => {
    it('should import private key from PEM format', () => {
      const pemKey = `-----BEGIN PRIVATE KEY-----
${Buffer.from(testPrivateKey, 'hex').toString('base64')}
-----END PRIVATE KEY-----`;
      
      const imported = importPrivateKeyFromPEM(pemKey);
      expect(imported).toBe(testPrivateKey);
    });

    it('should handle PEM with whitespace and newlines', () => {
      const pemKey = `  -----BEGIN PRIVATE KEY-----  
${Buffer.from(testPrivateKey, 'hex').toString('base64')}
  -----END PRIVATE KEY-----  `;
      
      const imported = importPrivateKeyFromPEM(pemKey);
      expect(imported).toBe(testPrivateKey);
    });

    it('should throw error for invalid PEM format', () => {
      const invalidPem = '-----BEGIN PRIVATE KEY-----\ninvalid_base64\n-----END PRIVATE KEY-----';
      
      expect(() => importPrivateKeyFromPEM(invalidPem)).toThrow();
    });
  });

  describe('Nonce Generation', () => {
    it('should generate 32-character hex nonces', () => {
      const nonce = generateNonce();
      
      expect(nonce).toMatch(/^[0-9a-f]{32}$/i);
      expect(nonce).toHaveLength(32);
    });

    it('should generate unique nonces', () => {
      const nonce1 = generateNonce();
      const nonce2 = generateNonce();
      
      expect(nonce1).not.toBe(nonce2);
    });
  });

  describe('Message Hashing', () => {
    it('should create deterministic hash for same record', () => {
      const hash1 = createMessageHash(testRecord);
      const hash2 = createMessageHash(testRecord);
      
      expect(hash1).toBe(hash2);
      expect(hash1).toMatch(/^[0-9a-f]{64}$/i);
    });

    it('should create different hashes for different records', () => {
      const record2 = { ...testRecord, kwh_delta: 5.678 };
      
      const hash1 = createMessageHash(testRecord);
      const hash2 = createMessageHash(record2);
      
      expect(hash1).not.toBe(hash2);
    });

    it('should be sensitive to all record fields', () => {
      const originalHash = createMessageHash(testRecord);
      
      // Test each field
      const fields: (keyof MeterRecord)[] = ['meter_id', 'timestamp', 'kwh_delta', 'nonce'];
      
      fields.forEach(field => {
        const modifiedRecord = { ...testRecord };
        if (field === 'timestamp') {
          modifiedRecord[field] = testRecord[field] + 1;
        } else if (field === 'kwh_delta') {
          modifiedRecord[field] = testRecord[field] + 0.001;
        } else {
          modifiedRecord[field] = testRecord[field] + '_modified';
        }
        
        const modifiedHash = createMessageHash(modifiedRecord);
        expect(modifiedHash).not.toBe(originalHash);
      });
    });
  });

  describe('Digital Signatures', () => {
    it('should create valid signatures', () => {
      const signature = signMeterRecord(testRecord, testPrivateKey);
      
      expect(signature).toMatch(/^0x[0-9a-f]{130}$/i);
      expect(signature).toHaveLength(132); // 0x + 64 + 64 + 2
    });

    it('should create different signatures for different records', () => {
      const record2 = { ...testRecord, kwh_delta: 5.678 };
      
      const sig1 = signMeterRecord(testRecord, testPrivateKey);
      const sig2 = signMeterRecord(record2, testPrivateKey);
      
      expect(sig1).not.toBe(sig2);
    });

    it('should verify valid signatures', () => {
      const signature = signMeterRecord(testRecord, testPrivateKey);
      const isValid = verifySignature(testRecord, signature, testPublicKey);
      
      expect(isValid).toBe(true);
    });

    it('should reject invalid signatures', () => {
      const signature = signMeterRecord(testRecord, testPrivateKey);
      const tamperedRecord = { ...testRecord, kwh_delta: 999.999 };
      const isValid = verifySignature(tamperedRecord, signature, testPublicKey);
      
      expect(isValid).toBe(false);
    });

    it('should reject signatures from wrong key', () => {
      const wrongKeyPair = generateKeyPair();
      const signature = signMeterRecord(testRecord, wrongKeyPair.privateKey);
      const isValid = verifySignature(testRecord, signature, testPublicKey);
      
      expect(isValid).toBe(false);
    });

    it('should handle malformed signatures gracefully', () => {
      const malformedSig = '0xinvalidsignature';
      const isValid = verifySignature(testRecord, malformedSig, testPublicKey);
      
      expect(isValid).toBe(false);
    });
  });

  describe('Signed Meter Data Creation', () => {
    it('should create complete signed meter data package', () => {
      const signedData = createSignedMeterData('test_meter', 2.5, testPrivateKey);
      
      expect(signedData.record).toMatchObject({
        meter_id: 'test_meter',
        kwh_delta: 2.5
      });
      expect(signedData.record.timestamp).toBeTypeOf('number');
      expect(signedData.record.nonce).toMatch(/^[0-9a-f]{32}$/i);
      expect(signedData.sig).toMatch(/^0x[0-9a-f]{130}$/i);
    });

    it('should create verifiable signed data', () => {
      const signedData = createSignedMeterData('test_meter', 1.5, testPrivateKey);
      const isValid = verifySignature(signedData.record, signedData.sig, testPublicKey);
      
      expect(isValid).toBe(true);
    });

    it('should generate unique timestamps and nonces', () => {
      const data1 = createSignedMeterData('test_meter', 1.0, testPrivateKey);
      
      // Small delay to ensure different timestamp
      await new Promise(resolve => setTimeout(resolve, 10));
      
      const data2 = createSignedMeterData('test_meter', 1.0, testPrivateKey);
      
      expect(data1.record.timestamp).not.toBe(data2.record.timestamp);
      expect(data1.record.nonce).not.toBe(data2.record.nonce);
      expect(data1.sig).not.toBe(data2.sig);
    });
  });

  describe('Error Handling', () => {
    it('should throw error for invalid private key in signing', () => {
      const invalidKey = 'invalid_key';
      
      expect(() => signMeterRecord(testRecord, invalidKey)).toThrow();
    });

    it('should handle empty record gracefully', () => {
      const emptyRecord = {
        meter_id: '',
        timestamp: 0,
        kwh_delta: 0,
        nonce: ''
      };
      
      expect(() => signMeterRecord(emptyRecord, testPrivateKey)).not.toThrow();
      expect(() => createMessageHash(emptyRecord)).not.toThrow();
    });
  });
});