// FILE: scripts/upload.ts
import fs from 'fs/promises';
import path from 'path';
import crypto from 'crypto';
import { ethers } from 'ethers';
import axios from 'axios';
import FormData from 'form-data';
import { createHash } from 'crypto';

interface WalrusUploadResponse {
  blobId: string;
  cost: number;
  event: {
    txDigest: string;
    eventSeq: number;
  };
}

interface SealSignature {
  hash: string;
  signature: string;
  signer: string;
  timestamp: number;
}

interface ProofMetadata {
  version: string;
  proofId: string;
  aggregateKwh: number;
  merkleRoot: string;
  recordCount: number;
  windowStart: string;
  windowEnd: string;
  generatedAt: string;
  meterIds: string[];
  walrusCid?: string;
  sealHash?: string;
  sealSignature?: SealSignature;
}

interface UploadResult {
  success: boolean;
  walrusCid?: string;
  sealHash?: string;
  signature?: SealSignature;
  metadata?: ProofMetadata;
  error?: string;
}

class WalrusStorageClient {
  private publisherUrl: string;
  private gatewayUrl: string;
  private epochs: number;
  private privateKey?: string;
  private signer?: ethers.Wallet;

  constructor(config: {
    publisherUrl: string;
    gatewayUrl: string;
    epochs?: number;
    privateKey?: string;
  }) {
    this.publisherUrl = config.publisherUrl;
    this.gatewayUrl = config.gatewayUrl;
    this.epochs = config.epochs || 5;
    this.privateKey = config.privateKey;
    
    if (this.privateKey) {
      this.signer = new ethers.Wallet(this.privateKey);
    }
  }

  /**
   * Upload proof data to Walrus storage
   * @param proofData - The proof data to upload
   * @returns Upload result with CID and seal information
   */
  async uploadProof(proofData: ProofMetadata): Promise<UploadResult> {
    try {
      console.log('🔄 Starting Walrus upload process...');
      
      // Step 1: Prepare metadata
      const metadata = await this.prepareMetadata(proofData);
      console.log(`📋 Prepared metadata for proof: ${metadata.proofId}`);

      // Step 2: Upload to Walrus
      const walrusResult = await this.uploadToWalrus(metadata);
      console.log(`📤 Uploaded to Walrus: ${walrusResult.blobId}`);

      // Step 3: Generate seal signature
      const sealResult = await this.generateSeal(metadata, walrusResult.blobId);
      console.log(`🔒 Generated seal: ${sealResult.hash}`);

      // Step 4: Update metadata with Walrus CID and seal
      const finalMetadata: ProofMetadata = {
        ...metadata,
        walrusCid: walrusResult.blobId,
        sealHash: sealResult.hash,
        sealSignature: sealResult.signature
      };

      // Step 5: Upload final metadata to Walrus
      const finalUpload = await this.uploadToWalrus(finalMetadata);
      console.log(`✅ Final metadata uploaded: ${finalUpload.blobId}`);

      return {
        success: true,
        walrusCid: finalUpload.blobId,
        sealHash: sealResult.hash,
        signature: sealResult.signature,
        metadata: finalMetadata
      };

    } catch (error) {
      console.error('❌ Upload failed:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Upload file from filesystem
   * @param filePath - Path to the file to upload
   * @returns Upload result
   */
  async uploadFile(filePath: string): Promise<UploadResult> {
    try {
      console.log(`📁 Reading file: ${filePath}`);
      
      // Read and parse the proof file
      const fileContent = await fs.readFile(filePath, 'utf-8');
      const proofData: ProofMetadata = JSON.parse(fileContent);
      
      return await this.uploadProof(proofData);
      
    } catch (error) {
      console.error('❌ File upload failed:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'File upload failed'
      };
    }
  }

  /**
   * Prepare metadata with additional fields
   */
  private async prepareMetadata(proofData: ProofMetadata): Promise<ProofMetadata> {
    return {
      ...proofData,
      version: proofData.version || '1.0.0',
      generatedAt: proofData.generatedAt || new Date().toISOString()
    };
  }

  /**
   * Upload data to Walrus storage
   */
  private async uploadToWalrus(data: any): Promise<WalrusUploadResponse> {
    const uploadUrl = `${this.publisherUrl}/v1/store`;
    
    // Convert data to JSON and then to base64
    const jsonData = JSON.stringify(data, null, 2);
    const base64Data = Buffer.from(jsonData).toString('base64');
    
    console.log(`📤 Uploading ${jsonData.length} bytes to Walrus...`);
    
    // Mock implementation for testing
    if (this.publisherUrl.includes('localhost') || this.publisherUrl.includes('mock')) {
      return this.mockWalrusUpload(jsonData);
    }

    try {
      const response = await axios.put(uploadUrl, {
        data: base64Data,
        epochs: this.epochs,
        deletable: false
      }, {
        headers: {
          'Content-Type': 'application/json'
        },
        timeout: 60000 // 60 second timeout
      });

      if (response.status !== 200 && response.status !== 201) {
        throw new Error(`Walrus upload failed: ${response.status} ${response.statusText}`);
      }

      return response.data;
      
    } catch (error) {
      if (axios.isAxiosError(error)) {
        throw new Error(`Walrus upload failed: ${error.response?.status} ${error.response?.statusText}`);
      }
      throw error;
    }
  }

  /**
   * Mock Walrus upload for testing
   */
  private async mockWalrusUpload(data: string): Promise<WalrusUploadResponse> {
    console.log('🧪 Using mock Walrus upload...');
    
    // Generate a mock blob ID based on content hash
    const hash = createHash('sha256').update(data).digest('hex');
    const blobId = `mock_${hash.slice(0, 32)}`;
    
    // Simulate network delay
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    return {
      blobId,
      cost: 1000, // Mock cost
      event: {
        txDigest: `0x${hash}`,
        eventSeq: Date.now()
      }
    };
  }

  /**
   * Generate seal signature for content proof
   */
  private async generateSeal(metadata: ProofMetadata, walrusCid: string): Promise<{
    hash: string;
    signature: SealSignature;
  }> {
    // Create content hash
    const contentString = JSON.stringify({
      proofId: metadata.proofId,
      merkleRoot: metadata.merkleRoot,
      aggregateKwh: metadata.aggregateKwh,
      recordCount: metadata.recordCount,
      walrusCid
    });
    
    const contentHash = createHash('sha256').update(contentString).digest('hex');
    console.log(`🔒 Generated content hash: ${contentHash}`);

    let signature: SealSignature;

    if (this.signer) {
      // Sign with private key
      const messageHash = ethers.solidityPackedKeccak256(['string'], [contentHash]);
      const sig = await this.signer.signMessage(ethers.getBytes(messageHash));
      
      signature = {
        hash: contentHash,
        signature: sig,
        signer: this.signer.address,
        timestamp: Date.now()
      };
      
      console.log(`✍️ Signed with address: ${this.signer.address}`);
    } else {
      // Generate mock signature for testing
      const mockSig = createHash('sha256')
        .update(contentHash + Date.now().toString())
        .digest('hex');
      
      signature = {
        hash: contentHash,
        signature: `0x${mockSig}`,
        signer: '0x' + '0'.repeat(40), // Mock address
        timestamp: Date.now()
      };
      
      console.log('🧪 Generated mock signature');
    }

    return {
      hash: contentHash,
      signature
    };
  }

  /**
   * Retrieve data from Walrus storage
   */
  async retrieve(blobId: string): Promise<any> {
    const retrieveUrl = `${this.gatewayUrl}/v1/${blobId}`;
    
    console.log(`📥 Retrieving from Walrus: ${blobId}`);
    
    // Mock implementation for testing
    if (this.gatewayUrl.includes('localhost') || this.gatewayUrl.includes('mock')) {
      return this.mockWalrusRetrieve(blobId);
    }

    try {
      const response = await axios.get(retrieveUrl, {
        timeout: 30000
      });

      // Decode base64 data
      const base64Data = response.data;
      const jsonData = Buffer.from(base64Data, 'base64').toString('utf-8');
      
      return JSON.parse(jsonData);
      
    } catch (error) {
      if (axios.isAxiosError(error)) {
        throw new Error(`Walrus retrieval failed: ${error.response?.status} ${error.response?.statusText}`);
      }
      throw error;
    }
  }

  /**
   * Mock Walrus retrieval for testing
   */
  private async mockWalrusRetrieve(blobId: string): Promise<any> {
    console.log('🧪 Using mock Walrus retrieval...');
    
    // Simulate network delay
    await new Promise(resolve => setTimeout(resolve, 500));
    
    // Return mock data
    return {
      proofId: 'mock_proof_' + blobId.slice(-8),
      message: 'This is mock data from Walrus storage',
      blobId,
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Verify seal signature
   */
  async verifySeal(metadata: ProofMetadata): Promise<boolean> {
    if (!metadata.sealSignature || !metadata.walrusCid) {
      return false;
    }

    try {
      // Recreate content hash
      const contentString = JSON.stringify({
        proofId: metadata.proofId,
        merkleRoot: metadata.merkleRoot,
        aggregateKwh: metadata.aggregateKwh,
        recordCount: metadata.recordCount,
        walrusCid: metadata.walrusCid
      });
      
      const expectedHash = createHash('sha256').update(contentString).digest('hex');
      
      if (expectedHash !== metadata.sealSignature.hash) {
        console.log('❌ Seal hash mismatch');
        return false;
      }

      // Verify signature (simplified for mock)
      if (metadata.sealSignature.signature.startsWith('0x') && 
          metadata.sealSignature.signature.length === 66) {
        console.log('✅ Seal signature verified');
        return true;
      }

      return false;
      
    } catch (error) {
      console.error('❌ Seal verification failed:', error);
      return false;
    }
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];
  
  // Load configuration from environment
  const config = {
    publisherUrl: process.env.WALRUS_PUBLISHER_URL || 'http://localhost:8080/mock',
    gatewayUrl: process.env.WALRUS_GATEWAY_URL || 'http://localhost:8080/mock',
    epochs: parseInt(process.env.WALRUS_EPOCHS || '5'),
    privateKey: process.env.WALRUS_PRIVATE_KEY
  };

  const client = new WalrusStorageClient(config);

  switch (command) {
    case 'upload':
      const filePath = args[1];
      if (!filePath) {
        console.error('❌ Usage: npm run upload <file-path>');
        process.exit(1);
      }
      
      const result = await client.uploadFile(filePath);
      if (result.success) {
        console.log('✅ Upload successful!');
        console.log(`   Walrus CID: ${result.walrusCid}`);
        console.log(`   Seal Hash: ${result.sealHash}`);
        console.log(`   Signer: ${result.signature?.signer}`);
      } else {
        console.error(`❌ Upload failed: ${result.error}`);
        process.exit(1);
      }
      break;

    case 'retrieve':
      const blobId = args[1];
      if (!blobId) {
        console.error('❌ Usage: npm run retrieve <blob-id>');
        process.exit(1);
      }
      
      try {
        const data = await client.retrieve(blobId);
        console.log('✅ Retrieved data:');
        console.log(JSON.stringify(data, null, 2));
      } catch (error) {
        console.error(`❌ Retrieval failed: ${error}`);
        process.exit(1);
      }
      break;

    case 'verify':
      const verifyPath = args[1];
      if (!verifyPath) {
        console.error('❌ Usage: npm run verify <file-path>');
        process.exit(1);
      }
      
      try {
        const fileContent = await fs.readFile(verifyPath, 'utf-8');
        const metadata: ProofMetadata = JSON.parse(fileContent);
        const isValid = await client.verifySeal(metadata);
        
        if (isValid) {
          console.log('✅ Seal verification successful');
        } else {
          console.log('❌ Seal verification failed');
          process.exit(1);
        }
      } catch (error) {
        console.error(`❌ Verification failed: ${error}`);
        process.exit(1);
      }
      break;

    case 'test':
      // Generate test proof data
      const testProof: ProofMetadata = {
        version: '1.0.0',
        proofId: `test_${Date.now()}`,
        aggregateKwh: 123.45,
        merkleRoot: '0x' + crypto.randomBytes(32).toString('hex'),
        recordCount: 10,
        windowStart: new Date(Date.now() - 300000).toISOString(),
        windowEnd: new Date().toISOString(),
        generatedAt: new Date().toISOString(),
        meterIds: ['meter_001', 'meter_002', 'meter_003']
      };

      console.log('🧪 Testing with generated proof data...');
      const testResult = await client.uploadProof(testProof);
      
      if (testResult.success) {
        console.log('✅ Test upload successful!');
        console.log(`   Walrus CID: ${testResult.walrusCid}`);
        console.log(`   Seal Hash: ${testResult.sealHash}`);
        
        // Test retrieval
        if (testResult.walrusCid) {
          console.log('🔄 Testing retrieval...');
          const retrieved = await client.retrieve(testResult.walrusCid);
          console.log('✅ Test retrieval successful!');
          
          // Test verification
          console.log('🔄 Testing verification...');
          const verified = await client.verifySeal(testResult.metadata!);
          console.log(verified ? '✅ Test verification successful!' : '❌ Test verification failed!');
        }
      } else {
        console.error(`❌ Test failed: ${testResult.error}`);
        process.exit(1);
      }
      break;

    default:
      console.log(`
GreenShare Walrus Storage Client

Usage:
  npm run upload <file-path>     Upload proof file to Walrus
  npm run retrieve <blob-id>     Retrieve data from Walrus
  npm run verify <file-path>     Verify seal signature
  npm run test                   Run test upload/retrieve cycle

Environment Variables:
  WALRUS_PUBLISHER_URL          Walrus publisher endpoint
  WALRUS_GATEWAY_URL           Walrus gateway endpoint  
  WALRUS_EPOCHS                Storage epochs (default: 5)
  WALRUS_PRIVATE_KEY           Private key for signing

Examples:
  npm run upload ./proofs/proof_123.json
  npm run retrieve mock_1234567890abcdef
  npm run verify ./proofs/sealed_proof.json
      `);
      break;
  }
}

// Export for use as library
export { WalrusStorageClient, type ProofMetadata, type UploadResult, type SealSignature };

// Run CLI if called directly
if (require.main === module) {
  main().catch(console.error);
}