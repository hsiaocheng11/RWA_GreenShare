// FILE: src/crypto.ts
import { ec as EC } from 'elliptic';
import crypto from 'crypto';

// Initialize secp256k1 curve
const ec = new EC('secp256k1');

export interface MeterRecord {
  meter_id: string;
  timestamp: number;
  kwh_delta: number;
  nonce: string;
}

export interface SignedMeterData {
  record: MeterRecord;
  sig: string;
}

/**
 * Generate a new ECDSA key pair for meter
 */
export function generateKeyPair(): { privateKey: string; publicKey: string } {
  const keyPair = ec.genKeyPair();
  const privateKey = keyPair.getPrivate('hex');
  const publicKey = keyPair.getPublic('hex');
  
  return { privateKey, publicKey };
}

/**
 * Import private key from PEM format
 */
export function importPrivateKeyFromPEM(pemString: string): string {
  // Remove PEM headers and whitespace
  const base64 = pemString
    .replace(/-----BEGIN.*?-----/g, '')
    .replace(/-----END.*?-----/g, '')
    .replace(/\s/g, '');
  
  // For secp256k1, we expect the private key to be 32 bytes
  const buffer = Buffer.from(base64, 'base64');
  
  // Extract the 32-byte private key (may need to skip DER encoding overhead)
  let privateKeyHex: string;
  if (buffer.length === 32) {
    privateKeyHex = buffer.toString('hex');
  } else if (buffer.length > 32) {
    // Try to extract the last 32 bytes (common DER format)
    privateKeyHex = buffer.slice(-32).toString('hex');
  } else {
    throw new Error('Invalid private key format');
  }
  
  // Validate the key
  try {
    ec.keyFromPrivate(privateKeyHex);
    return privateKeyHex;
  } catch (error) {
    throw new Error(`Invalid secp256k1 private key: ${error}`);
  }
}

/**
 * Generate cryptographically secure nonce
 */
export function generateNonce(): string {
  return crypto.randomBytes(16).toString('hex');
}

/**
 * Create deterministic message hash for signing
 */
export function createMessageHash(record: MeterRecord): string {
  const message = JSON.stringify({
    meter_id: record.meter_id,
    timestamp: record.timestamp,
    kwh_delta: record.kwh_delta,
    nonce: record.nonce
  });
  
  return crypto.createHash('sha256').update(message, 'utf8').digest('hex');
}

/**
 * Sign meter record with ECDSA
 */
export function signMeterRecord(record: MeterRecord, privateKeyHex: string): string {
  try {
    const keyPair = ec.keyFromPrivate(privateKeyHex);
    const messageHash = createMessageHash(record);
    
    const signature = keyPair.sign(messageHash);
    const r = signature.r.toString('hex').padStart(64, '0');
    const s = signature.s.toString('hex').padStart(64, '0');
    const v = (signature.recoveryParam || 0).toString(16).padStart(2, '0');
    
    return `0x${r}${s}${v}`;
  } catch (error) {
    throw new Error(`Failed to sign meter record: ${error}`);
  }
}

/**
 * Verify signature (for testing purposes)
 */
export function verifySignature(record: MeterRecord, signature: string, publicKeyHex: string): boolean {
  try {
    const keyPair = ec.keyFromPublic(publicKeyHex, 'hex');
    const messageHash = createMessageHash(record);
    
    // Parse signature
    const sig = signature.replace('0x', '');
    const r = sig.slice(0, 64);
    const s = sig.slice(64, 128);
    
    return keyPair.verify(messageHash, { r, s });
  } catch (error) {
    console.error('Signature verification failed:', error);
    return false;
  }
}

/**
 * Create a complete signed meter data package
 */
export function createSignedMeterData(
  meterId: string,
  kwhDelta: number,
  privateKeyHex: string
): SignedMeterData {
  const record: MeterRecord = {
    meter_id: meterId,
    timestamp: Date.now(),
    kwh_delta: kwhDelta,
    nonce: generateNonce()
  };
  
  const signature = signMeterRecord(record, privateKeyHex);
  
  return {
    record,
    sig: signature
  };
}