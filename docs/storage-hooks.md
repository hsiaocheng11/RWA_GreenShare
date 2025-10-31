# FILE: docs/storage-hooks.md

# Walrus/Seal Storage Hooks Documentation

## Overview

GreenShare integrates with Walrus decentralized storage for immutable proof storage and Seal for content verification. This document provides comprehensive guidance on using the storage hooks system.

## Architecture

```
IoT Meter Data → ROFL Aggregation → Walrus Storage → Seal Verification → Sui NFT
                                  ↓                    ↓                  ↓
                            proof.json          content_hash         metadata.walrus_cid
                                  ↓                    ↓                  ↓
                             Base64 Upload       ECDSA Signature    seal_hash + signature
```

## Core Components

### 1. WalrusStorageClient

The main client for interacting with Walrus storage and generating Seal signatures.

```typescript
import { WalrusStorageClient } from '../scripts/upload';

const client = new WalrusStorageClient({
  publisherUrl: 'https://publisher-devnet.walrus.space',
  gatewayUrl: 'https://aggregator-devnet.walrus.space',
  epochs: 5,
  privateKey: process.env.WALRUS_PRIVATE_KEY
});
```

### 2. Proof Metadata Structure

```typescript
interface ProofMetadata {
  version: string;              // Schema version (e.g., "1.0.0")
  proofId: string;              // Unique proof identifier
  aggregateKwh: number;         // Total energy in kWh
  merkleRoot: string;           // Merkle root of meter readings
  recordCount: number;          // Number of aggregated records
  windowStart: string;          // ISO timestamp of window start
  windowEnd: string;            // ISO timestamp of window end
  generatedAt: string;          // ISO timestamp of proof generation
  meterIds: string[];           // Array of meter identifiers
  walrusCid?: string;           // Walrus content identifier
  sealHash?: string;            // Content hash for verification
  sealSignature?: SealSignature; // Digital signature
}
```

### 3. Seal Signature

```typescript
interface SealSignature {
  hash: string;                 // SHA-256 hash of content
  signature: string;            // ECDSA signature
  signer: string;               // Ethereum address of signer
  timestamp: number;            // Unix timestamp
}
```

## Usage Guide

### 1. Environment Setup

Configure your environment variables:

```bash
# .env
WALRUS_PUBLISHER_URL=https://publisher-devnet.walrus.space
WALRUS_GATEWAY_URL=https://aggregator-devnet.walrus.space
WALRUS_EPOCHS=5
WALRUS_PRIVATE_KEY=0x1234567890abcdef...

# For testing with mock endpoints
WALRUS_PUBLISHER_URL=http://localhost:8080/mock
WALRUS_GATEWAY_URL=http://localhost:8080/mock
```

### 2. Upload Proof to Walrus

#### From ROFL Enclave (Automated)

```rust
// In ROFL enclave (src/handlers.rs)
use crate::seal::WalrusClient;

async fn seal_proof_to_walrus(proof: &ProofData) -> Result<String, Error> {
    let walrus_client = WalrusClient::new(
        env::var("WALRUS_PUBLISHER_URL")?,
        env::var("WALRUS_GATEWAY_URL")?,
        5
    );
    
    let seal_response = walrus_client.seal_proof(proof).await?;
    
    if seal_response.success {
        Ok(seal_response.blob_id.unwrap())
    } else {
        Err(Error::new(ErrorKind::Other, seal_response.error.unwrap()))
    }
}
```

#### From TypeScript (Manual)

```typescript
// Upload proof file
const result = await client.uploadFile('./proofs/proof_123.json');

if (result.success) {
  console.log('Walrus CID:', result.walrusCid);
  console.log('Seal Hash:', result.sealHash);
  console.log('Signature:', result.signature);
}
```

#### CLI Usage

```bash
# Upload a proof file
npm run upload ./proofs/proof_123.json

# Test upload with generated data
npm run upload:test

# Retrieve stored data
npm run retrieve mock_1234567890abcdef

# Verify seal signature
npm run verify ./proofs/sealed_proof.json
```

### 3. Generating Seal Signatures

The seal signature process creates a cryptographic proof of content integrity:

```typescript
// Automatic seal generation during upload
const uploadResult = await client.uploadProof(proofMetadata);

// Manual seal generation
const sealResult = await client.generateSeal(proofMetadata, walrusCid);
console.log('Content Hash:', sealResult.hash);
console.log('Signature:', sealResult.signature);
```

The seal hash is generated from:
```typescript
const contentString = JSON.stringify({
  proofId: metadata.proofId,
  merkleRoot: metadata.merkleRoot,
  aggregateKwh: metadata.aggregateKwh,
  recordCount: metadata.recordCount,
  walrusCid: walrusCid
});

const sealHash = sha256(contentString);
```

### 4. Sui NFT Integration

#### Update Certificate Metadata

```move
// In Sui Move contract (sources/certificate.move)
public fun update_certificate_storage(
    certificate: &mut Certificate,
    walrus_cid: String,
    seal_hash: String,
    seal_signature: String,
    ctx: &mut TxContext
) {
    certificate.walrus_cid = walrus_cid;
    certificate.seal_hash = seal_hash;
    certificate.seal_signature = seal_signature;
    certificate.storage_timestamp = tx_context::epoch(ctx);
}
```

#### TypeScript Integration

```typescript
import { TransactionBlock } from '@mysten/sui.js/transactions';

async function updateCertificateStorage(
  certificateId: string,
  uploadResult: UploadResult
) {
  const tx = new TransactionBlock();
  
  tx.moveCall({
    target: `${PACKAGE_ID}::certificate::update_certificate_storage`,
    arguments: [
      tx.object(certificateId),
      tx.pure(uploadResult.walrusCid),
      tx.pure(uploadResult.sealHash),
      tx.pure(uploadResult.signature?.signature)
    ]
  });
  
  return await suiClient.signAndExecuteTransactionBlock({
    signer: keypair,
    transactionBlock: tx
  });
}
```

## API Reference

### WalrusStorageClient Methods

#### `uploadProof(proofData: ProofMetadata): Promise<UploadResult>`

Uploads proof data to Walrus and generates seal signature.

**Parameters:**
- `proofData`: Proof metadata object

**Returns:**
- `UploadResult` with Walrus CID, seal hash, and signature

**Example:**
```typescript
const result = await client.uploadProof({
  version: '1.0.0',
  proofId: 'proof_123',
  aggregateKwh: 125.5,
  merkleRoot: '0xabc123...',
  recordCount: 50,
  windowStart: '2024-01-01T00:00:00Z',
  windowEnd: '2024-01-01T01:00:00Z',
  generatedAt: '2024-01-01T01:05:00Z',
  meterIds: ['meter_001', 'meter_002']
});
```

#### `uploadFile(filePath: string): Promise<UploadResult>`

Uploads a proof JSON file from the filesystem.

**Parameters:**
- `filePath`: Path to the proof JSON file

**Returns:**
- `UploadResult` with upload status and metadata

#### `retrieve(blobId: string): Promise<any>`

Retrieves data from Walrus storage by blob ID.

**Parameters:**
- `blobId`: Walrus blob identifier

**Returns:**
- Retrieved data object

#### `verifySeal(metadata: ProofMetadata): Promise<boolean>`

Verifies the seal signature and content hash.

**Parameters:**
- `metadata`: Proof metadata with seal signature

**Returns:**
- Boolean indicating verification success

## Testing & Development

### Mock Server Setup

For local development, use the mock endpoints:

```typescript
// Mock Walrus endpoints
const mockClient = new WalrusStorageClient({
  publisherUrl: 'http://localhost:8080/mock',
  gatewayUrl: 'http://localhost:8080/mock',
  epochs: 5
});
```

### Test Data Generation

```bash
# Generate and test with sample data
npm run upload:test

# This will:
# 1. Generate random proof data
# 2. Upload to Walrus (or mock)
# 3. Generate seal signature
# 4. Test retrieval
# 5. Verify signature
```

### Integration Testing

```typescript
// Complete integration test
describe('Walrus Storage Integration', () => {
  it('should upload, seal, and verify proof', async () => {
    const testProof = generateTestProof();
    
    // Upload
    const uploadResult = await client.uploadProof(testProof);
    expect(uploadResult.success).toBe(true);
    
    // Retrieve
    const retrieved = await client.retrieve(uploadResult.walrusCid!);
    expect(retrieved.proofId).toBe(testProof.proofId);
    
    // Verify
    const verified = await client.verifySeal(uploadResult.metadata!);
    expect(verified).toBe(true);
  });
});
```

## Production Deployment

### 1. Walrus Network Configuration

```bash
# Production Walrus endpoints
WALRUS_PUBLISHER_URL=https://publisher.walrus.space
WALRUS_GATEWAY_URL=https://aggregator.walrus.space
WALRUS_EPOCHS=100  # Longer storage period for production

# Signing configuration
WALRUS_PRIVATE_KEY=0x...  # Production signing key
WALRUS_SIGNER_ADDRESS=0x...  # Expected signer address
```

### 2. Security Considerations

- **Private Key Management**: Store signing keys securely (AWS KMS, Azure Key Vault)
- **Access Control**: Restrict upload endpoints to authorized services
- **Rate Limiting**: Implement rate limiting for upload operations
- **Content Validation**: Validate proof data before upload
- **Backup Strategy**: Maintain backup copies of critical proofs

### 3. Monitoring & Alerting

```typescript
// Add monitoring to upload operations
const uploadWithMonitoring = async (proof: ProofMetadata) => {
  const startTime = Date.now();
  
  try {
    const result = await client.uploadProof(proof);
    
    // Log success metrics
    console.log({
      event: 'walrus_upload_success',
      proofId: proof.proofId,
      duration: Date.now() - startTime,
      walrusCid: result.walrusCid,
      sealHash: result.sealHash
    });
    
    return result;
  } catch (error) {
    // Log error metrics
    console.error({
      event: 'walrus_upload_error',
      proofId: proof.proofId,
      duration: Date.now() - startTime,
      error: error.message
    });
    
    throw error;
  }
};
```

## Error Handling

### Common Error Scenarios

1. **Network Connectivity Issues**
   ```typescript
   if (error.code === 'ECONNREFUSED') {
     // Retry with exponential backoff
     await retry(uploadOperation, { maxAttempts: 3 });
   }
   ```

2. **Invalid Proof Data**
   ```typescript
   if (!validateProofMetadata(proof)) {
     throw new Error('Invalid proof metadata structure');
   }
   ```

3. **Signature Verification Failure**
   ```typescript
   const isValid = await client.verifySeal(metadata);
   if (!isValid) {
     throw new Error('Seal signature verification failed');
   }
   ```

4. **Storage Quota Exceeded**
   ```typescript
   if (error.message.includes('quota exceeded')) {
     // Implement cleanup of old proofs
     await cleanupOldProofs();
   }
   ```

### Recovery Procedures

1. **Failed Upload Recovery**
   ```bash
   # Retry failed uploads
   npm run upload:retry ./failed_uploads.json
   ```

2. **Seal Regeneration**
   ```bash
   # Regenerate seal for existing Walrus content
   npm run seal:regenerate <walrus-cid>
   ```

3. **Batch Operations**
   ```bash
   # Process multiple proof files
   npm run upload:batch ./proofs/*.json
   ```

## Best Practices

1. **Proof File Organization**
   ```
   proofs/
   ├── 2024/01/01/
   │   ├── proof_001.json
   │   ├── proof_002.json
   │   └── sealed_proof_001.json
   └── archive/
       └── 2023/
   ```

2. **Metadata Standards**
   - Always include version field for schema evolution
   - Use ISO 8601 timestamps
   - Include all required fields before upload
   - Validate data integrity before sealing

3. **Security Best Practices**
   - Rotate signing keys regularly
   - Implement multi-signature for critical operations
   - Audit storage access logs
   - Use HTTPS for all API communications

4. **Performance Optimization**
   - Batch small proofs together
   - Implement caching for frequently accessed data
   - Use CDN for public content retrieval
   - Monitor storage costs and usage

## Troubleshooting

### Debug Mode

```bash
# Enable debug logging
DEBUG=walrus:* npm run upload ./proof.json

# Verbose output
WALRUS_DEBUG=true npm run upload:test
```

### Common Issues

1. **"Blob not found" errors**: Check blob ID and gateway URL
2. **Signature verification fails**: Verify private key and content hash
3. **Upload timeout**: Increase timeout values or check network
4. **Invalid JSON**: Validate proof file structure

### Support

For additional support:
- Check Walrus documentation: https://docs.walrus.space
- GreenShare Discord: https://discord.gg/greenshare
- GitHub Issues: https://github.com/greenshare/issues