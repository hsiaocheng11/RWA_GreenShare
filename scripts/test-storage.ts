// FILE: scripts/test-storage.ts
import fs from 'fs/promises';
import path from 'path';
import { WalrusStorageClient, type ProofMetadata } from './upload';
import { MockWalrusServer } from './mock-walrus-server';

interface TestResult {
  testName: string;
  success: boolean;
  duration: number;
  details: any;
  error?: string;
}

class StorageTestSuite {
  private client: WalrusStorageClient;
  private mockServer?: MockWalrusServer;
  private results: TestResult[] = [];

  constructor(useMockServer: boolean = true) {
    const config = {
      publisherUrl: useMockServer 
        ? 'http://localhost:8080/mock'
        : process.env.WALRUS_PUBLISHER_URL || 'https://publisher-devnet.walrus.space',
      gatewayUrl: useMockServer
        ? 'http://localhost:8080/mock'
        : process.env.WALRUS_GATEWAY_URL || 'https://aggregator-devnet.walrus.space',
      epochs: parseInt(process.env.WALRUS_EPOCHS || '5'),
      privateKey: process.env.WALRUS_PRIVATE_KEY
    };

    this.client = new WalrusStorageClient(config);

    if (useMockServer) {
      this.mockServer = new MockWalrusServer(8080);
    }
  }

  private async runTest(testName: string, testFn: () => Promise<any>): Promise<TestResult> {
    const startTime = Date.now();
    console.log(`🧪 Running test: ${testName}`);

    try {
      const details = await testFn();
      const duration = Date.now() - startTime;
      
      const result: TestResult = {
        testName,
        success: true,
        duration,
        details
      };

      console.log(`✅ ${testName} passed (${duration}ms)`);
      this.results.push(result);
      return result;

    } catch (error) {
      const duration = Date.now() - startTime;
      const result: TestResult = {
        testName,
        success: false,
        duration,
        details: null,
        error: error instanceof Error ? error.message : String(error)
      };

      console.error(`❌ ${testName} failed (${duration}ms): ${result.error}`);
      this.results.push(result);
      return result;
    }
  }

  private generateTestProof(): ProofMetadata {
    const now = new Date();
    const windowStart = new Date(now.getTime() - 300000); // 5 minutes ago

    return {
      version: '1.0.0',
      proofId: `test_proof_${Date.now()}`,
      aggregateKwh: Math.round((Math.random() * 1000 + 100) * 100) / 100,
      merkleRoot: '0x' + Array.from({ length: 64 }, () => 
        Math.floor(Math.random() * 16).toString(16)
      ).join(''),
      recordCount: Math.floor(Math.random() * 100) + 10,
      windowStart: windowStart.toISOString(),
      windowEnd: now.toISOString(),
      generatedAt: now.toISOString(),
      meterIds: Array.from({ length: Math.floor(Math.random() * 10) + 3 }, (_, i) => 
        `meter_${String(i + 1).padStart(3, '0')}`
      )
    };
  }

  async runAllTests(): Promise<void> {
    console.log('🚀 Starting GreenShare Storage Test Suite');
    console.log('=' .repeat(50));

    // Start mock server if needed
    if (this.mockServer) {
      console.log('🔧 Starting mock Walrus server...');
      await this.mockServer.start();
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait for server to be ready
    }

    // Test 1: Basic upload and retrieval
    await this.runTest('Basic Upload and Retrieval', async () => {
      const testProof = this.generateTestProof();
      
      // Upload
      const uploadResult = await this.client.uploadProof(testProof);
      if (!uploadResult.success) {
        throw new Error(`Upload failed: ${uploadResult.error}`);
      }

      // Retrieve
      const retrieved = await this.client.retrieve(uploadResult.walrusCid!);
      
      return {
        uploadResult,
        retrieved,
        proofId: testProof.proofId,
        walrusCid: uploadResult.walrusCid,
        sealHash: uploadResult.sealHash
      };
    });

    // Test 2: Seal signature verification
    await this.runTest('Seal Signature Verification', async () => {
      const testProof = this.generateTestProof();
      
      const uploadResult = await this.client.uploadProof(testProof);
      if (!uploadResult.success) {
        throw new Error(`Upload failed: ${uploadResult.error}`);
      }

      const verified = await this.client.verifySeal(uploadResult.metadata!);
      if (!verified) {
        throw new Error('Seal verification failed');
      }

      return {
        proofId: testProof.proofId,
        sealHash: uploadResult.sealHash,
        signature: uploadResult.signature,
        verified
      };
    });

    // Test 3: File upload from filesystem
    await this.runTest('File Upload from Filesystem', async () => {
      const testProof = this.generateTestProof();
      const testDir = path.join(__dirname, '../tmp');
      const testFile = path.join(testDir, 'test_proof.json');

      // Create test directory and file
      await fs.mkdir(testDir, { recursive: true });
      await fs.writeFile(testFile, JSON.stringify(testProof, null, 2));

      try {
        const uploadResult = await this.client.uploadFile(testFile);
        if (!uploadResult.success) {
          throw new Error(`File upload failed: ${uploadResult.error}`);
        }

        return {
          filePath: testFile,
          uploadResult,
          proofId: testProof.proofId
        };
      } finally {
        // Cleanup
        try {
          await fs.unlink(testFile);
          await fs.rmdir(testDir);
        } catch (error) {
          console.warn('Cleanup warning:', error);
        }
      }
    });

    // Test 4: Large file handling
    await this.runTest('Large File Handling', async () => {
      const largeProof = this.generateTestProof();
      
      // Add large meter data to simulate bigger files
      const largeMeterData = Array.from({ length: 1000 }, (_, i) => ({
        meterId: `large_meter_${i}`,
        readings: Array.from({ length: 100 }, (_, j) => ({
          timestamp: Date.now() - (j * 60000),
          kwh: Math.random() * 10,
          signature: '0x' + Array.from({ length: 128 }, () => 
            Math.floor(Math.random() * 16).toString(16)
          ).join('')
        }))
      }));

      const largeProofWithData = {
        ...largeProof,
        detailedMeterData: largeMeterData
      };

      const uploadResult = await this.client.uploadProof(largeProofWithData);
      if (!uploadResult.success) {
        throw new Error(`Large file upload failed: ${uploadResult.error}`);
      }

      // Calculate approximate size
      const dataSize = JSON.stringify(largeProofWithData).length;

      return {
        dataSize,
        uploadResult,
        retrievalTest: await this.client.retrieve(uploadResult.walrusCid!)
      };
    });

    // Test 5: Error handling
    await this.runTest('Error Handling', async () => {
      const errors: string[] = [];

      // Test invalid blob ID retrieval
      try {
        await this.client.retrieve('invalid_blob_id');
        errors.push('Should have failed for invalid blob ID');
      } catch (error) {
        // Expected error
      }

      // Test invalid proof data
      try {
        const invalidProof = {} as ProofMetadata;
        await this.client.uploadProof(invalidProof);
        errors.push('Should have failed for invalid proof data');
      } catch (error) {
        // Expected error
      }

      if (errors.length > 0) {
        throw new Error(`Error handling test failed: ${errors.join(', ')}`);
      }

      return { message: 'Error handling working correctly' };
    });

    // Test 6: Batch operations
    await this.runTest('Batch Operations', async () => {
      const batchSize = 5;
      const proofs = Array.from({ length: batchSize }, () => this.generateTestProof());
      
      const uploadPromises = proofs.map(proof => this.client.uploadProof(proof));
      const uploadResults = await Promise.all(uploadPromises);

      const successCount = uploadResults.filter(r => r.success).length;
      const totalSize = uploadResults.reduce((sum, r) => 
        sum + JSON.stringify(r.metadata || {}).length, 0
      );

      if (successCount !== batchSize) {
        throw new Error(`Only ${successCount}/${batchSize} uploads succeeded`);
      }

      return {
        batchSize,
        successCount,
        totalSize,
        averageSize: Math.round(totalSize / batchSize),
        walrusCids: uploadResults.map(r => r.walrusCid)
      };
    });

    // Print final results
    console.log('\n' + '='.repeat(50));
    console.log('📊 Test Results Summary');
    console.log('='.repeat(50));

    const passedTests = this.results.filter(r => r.success);
    const failedTests = this.results.filter(r => !r.success);
    const totalDuration = this.results.reduce((sum, r) => sum + r.duration, 0);

    console.log(`✅ Passed: ${passedTests.length}/${this.results.length}`);
    console.log(`❌ Failed: ${failedTests.length}/${this.results.length}`);
    console.log(`⏱️  Total Duration: ${totalDuration}ms`);
    console.log(`⚡ Average Duration: ${Math.round(totalDuration / this.results.length)}ms`);

    if (failedTests.length > 0) {
      console.log('\n❌ Failed Tests:');
      failedTests.forEach(test => {
        console.log(`   ${test.testName}: ${test.error}`);
      });
    }

    // Get mock server stats if available
    if (this.mockServer) {
      const stats = this.mockServer.getStorageStats();
      console.log('\n📊 Mock Storage Stats:');
      console.log(`   Total Blobs: ${stats.totalBlobs}`);
      console.log(`   Total Size: ${(stats.totalSize / 1024).toFixed(2)} KB`);
      console.log(`   Total Cost: ${stats.totalCost} units`);
    }

    console.log('\n🎉 Test suite completed!');

    if (failedTests.length > 0) {
      process.exit(1);
    }
  }

  async runSingleTest(testName: string): Promise<void> {
    if (this.mockServer) {
      await this.mockServer.start();
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

    switch (testName.toLowerCase()) {
      case 'upload':
        await this.runTest('Single Upload Test', async () => {
          const testProof = this.generateTestProof();
          return await this.client.uploadProof(testProof);
        });
        break;

      case 'retrieve':
        const blobId = process.argv[4];
        if (!blobId) {
          console.error('❌ Blob ID required for retrieve test');
          process.exit(1);
        }
        await this.runTest('Single Retrieve Test', async () => {
          return await this.client.retrieve(blobId);
        });
        break;

      default:
        console.error(`❌ Unknown test: ${testName}`);
        console.log('Available tests: upload, retrieve');
        process.exit(1);
    }

    console.log(`\n✅ ${testName} test completed`);
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'all';
  const useMockServer = !args.includes('--real');

  const testSuite = new StorageTestSuite(useMockServer);

  switch (command) {
    case 'all':
      await testSuite.runAllTests();
      break;

    case 'single':
      const testName = args[1];
      if (!testName) {
        console.error('❌ Test name required');
        console.log('Usage: npm run test:storage single <test-name>');
        process.exit(1);
      }
      await testSuite.runSingleTest(testName);
      break;

    default:
      console.log(`
GreenShare Storage Test Suite

Usage:
  npm run test:storage [command] [options]

Commands:
  all                    Run all tests (default)
  single <test-name>     Run a single test

Options:
  --real                 Use real Walrus endpoints instead of mock

Examples:
  npm run test:storage                    # Run all tests with mock server
  npm run test:storage --real             # Run all tests with real Walrus
  npm run test:storage single upload      # Run only upload test
  npm run test:storage single retrieve <blob-id>  # Test retrieval of specific blob
      `);
      break;
  }
}

// Export for use as library
export { StorageTestSuite };

// Run CLI if called directly
if (require.main === module) {
  main().catch((error) => {
    console.error('❌ Test suite failed:', error);
    process.exit(1);
  });
}