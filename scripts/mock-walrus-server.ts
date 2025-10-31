// FILE: scripts/mock-walrus-server.ts
import express from 'express';
import cors from 'cors';
import { createHash } from 'crypto';
import fs from 'fs/promises';
import path from 'path';

interface MockStorage {
  [blobId: string]: {
    data: string;
    timestamp: number;
    size: number;
    cost: number;
    txDigest: string;
  };
}

class MockWalrusServer {
  private app: express.Application;
  private storage: MockStorage = {};
  private port: number;
  private storageDir: string;

  constructor(port: number = 8080) {
    this.app = express();
    this.port = port;
    this.storageDir = path.join(__dirname, '../mock-storage');
    this.setupMiddleware();
    this.setupRoutes();
    this.initializeStorage();
  }

  private setupMiddleware() {
    this.app.use(cors());
    this.app.use(express.json({ limit: '50mb' }));
    this.app.use(express.raw({ limit: '50mb' }));
    
    // Logging middleware
    this.app.use((req, res, next) => {
      console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
      next();
    });
  }

  private async initializeStorage() {
    try {
      await fs.mkdir(this.storageDir, { recursive: true });
      console.log(`📁 Mock storage directory: ${this.storageDir}`);
    } catch (error) {
      console.error('Failed to create storage directory:', error);
    }
  }

  private setupRoutes() {
    // Health check
    this.app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        storage_items: Object.keys(this.storage).length
      });
    });

    // Mock Walrus publisher endpoint
    this.app.put('/v1/store', async (req, res) => {
      try {
        const { data, epochs = 5, deletable = false } = req.body;
        
        if (!data) {
          return res.status(400).json({ error: 'Missing data field' });
        }

        // Decode base64 data
        let jsonData: string;
        try {
          jsonData = Buffer.from(data, 'base64').toString('utf-8');
        } catch (error) {
          return res.status(400).json({ error: 'Invalid base64 data' });
        }

        // Generate blob ID based on content hash
        const contentHash = createHash('sha256').update(jsonData).digest('hex');
        const blobId = `mock_${contentHash.slice(0, 32)}`;
        
        // Calculate mock cost (based on data size and epochs)
        const sizeKB = Buffer.byteLength(jsonData, 'utf8') / 1024;
        const cost = Math.ceil(sizeKB * epochs * 10); // 10 units per KB per epoch

        // Generate mock transaction digest
        const txDigest = '0x' + createHash('sha256')
          .update(blobId + Date.now().toString())
          .digest('hex');

        // Store in memory
        this.storage[blobId] = {
          data: data,
          timestamp: Date.now(),
          size: Buffer.byteLength(jsonData, 'utf8'),
          cost,
          txDigest
        };

        // Also save to disk for persistence
        const filePath = path.join(this.storageDir, `${blobId}.json`);
        await fs.writeFile(filePath, JSON.stringify({
          blobId,
          data: jsonData,
          metadata: {
            timestamp: Date.now(),
            size: Buffer.byteLength(jsonData, 'utf8'),
            cost,
            epochs,
            deletable,
            txDigest
          }
        }, null, 2));

        console.log(`📤 Stored blob: ${blobId} (${sizeKB.toFixed(2)} KB)`);

        // Simulate network delay
        await new Promise(resolve => setTimeout(resolve, 500 + Math.random() * 1000));

        res.json({
          blobId,
          cost,
          event: {
            txDigest,
            eventSeq: Date.now()
          }
        });

      } catch (error) {
        console.error('Store error:', error);
        res.status(500).json({ error: 'Internal server error' });
      }
    });

    // Mock Walrus gateway endpoint
    this.app.get('/v1/:blobId', async (req, res) => {
      try {
        const { blobId } = req.params;
        
        // Check memory storage first
        let storedData = this.storage[blobId];
        
        // If not in memory, try to load from disk
        if (!storedData) {
          try {
            const filePath = path.join(this.storageDir, `${blobId}.json`);
            const fileContent = await fs.readFile(filePath, 'utf-8');
            const fileData = JSON.parse(fileContent);
            
            // Reconstruct storage format
            storedData = {
              data: Buffer.from(fileData.data).toString('base64'),
              timestamp: fileData.metadata.timestamp,
              size: fileData.metadata.size,
              cost: fileData.metadata.cost,
              txDigest: fileData.metadata.txDigest
            };
            
            // Update memory cache
            this.storage[blobId] = storedData;
          } catch (error) {
            return res.status(404).json({ error: 'Blob not found' });
          }
        }

        console.log(`📥 Retrieved blob: ${blobId}`);

        // Simulate network delay
        await new Promise(resolve => setTimeout(resolve, 200 + Math.random() * 500));

        // Return the base64 data (Walrus format)
        res.send(storedData.data);

      } catch (error) {
        console.error('Retrieve error:', error);
        res.status(500).json({ error: 'Internal server error' });
      }
    });

    // List all stored blobs (debug endpoint)
    this.app.get('/debug/blobs', async (req, res) => {
      const blobs = Object.entries(this.storage).map(([blobId, data]) => ({
        blobId,
        size: data.size,
        timestamp: new Date(data.timestamp).toISOString(),
        cost: data.cost,
        txDigest: data.txDigest
      }));

      res.json({
        total: blobs.length,
        blobs: blobs.sort((a, b) => b.timestamp.localeCompare(a.timestamp))
      });
    });

    // Clear storage (debug endpoint)
    this.app.delete('/debug/clear', async (req, res) => {
      this.storage = {};
      
      try {
        const files = await fs.readdir(this.storageDir);
        for (const file of files) {
          if (file.endsWith('.json')) {
            await fs.unlink(path.join(this.storageDir, file));
          }
        }
      } catch (error) {
        console.error('Clear storage error:', error);
      }

      console.log('🗑️ Storage cleared');
      res.json({ message: 'Storage cleared' });
    });

    // Get blob metadata (debug endpoint)
    this.app.get('/debug/blob/:blobId', (req, res) => {
      const { blobId } = req.params;
      const storedData = this.storage[blobId];
      
      if (!storedData) {
        return res.status(404).json({ error: 'Blob not found' });
      }

      // Decode and parse data for inspection
      try {
        const jsonData = Buffer.from(storedData.data, 'base64').toString('utf-8');
        const parsedData = JSON.parse(jsonData);
        
        res.json({
          blobId,
          metadata: {
            size: storedData.size,
            timestamp: new Date(storedData.timestamp).toISOString(),
            cost: storedData.cost,
            txDigest: storedData.txDigest
          },
          content: parsedData
        });
      } catch (error) {
        res.json({
          blobId,
          metadata: {
            size: storedData.size,
            timestamp: new Date(storedData.timestamp).toISOString(),
            cost: storedData.cost,
            txDigest: storedData.txDigest
          },
          content: 'Unable to parse content as JSON',
          rawData: storedData.data.slice(0, 200) + '...'
        });
      }
    });

    // Mock endpoints for both publisher and gateway
    this.app.use('/mock/v1/store', this.app._router.stack.find(r => r.route?.path === '/v1/store')?.route?.stack[0]?.handle);
    this.app.use('/mock/v1/:blobId', this.app._router.stack.find(r => r.route?.path === '/v1/:blobId')?.route?.stack[0]?.handle);
  }

  public start(): Promise<void> {
    return new Promise((resolve) => {
      this.app.listen(this.port, () => {
        console.log(`🚀 Mock Walrus server running on port ${this.port}`);
        console.log(`📋 Endpoints:`);
        console.log(`   Publisher: http://localhost:${this.port}/v1/store`);
        console.log(`   Gateway: http://localhost:${this.port}/v1/<blob-id>`);
        console.log(`   Mock: http://localhost:${this.port}/mock/v1/...`);
        console.log(`   Health: http://localhost:${this.port}/health`);
        console.log(`   Debug: http://localhost:${this.port}/debug/blobs`);
        resolve();
      });
    });
  }

  public getStorageStats() {
    const blobs = Object.values(this.storage);
    return {
      totalBlobs: blobs.length,
      totalSize: blobs.reduce((sum, blob) => sum + blob.size, 0),
      totalCost: blobs.reduce((sum, blob) => sum + blob.cost, 0),
      oldestTimestamp: blobs.length > 0 ? Math.min(...blobs.map(b => b.timestamp)) : null,
      newestTimestamp: blobs.length > 0 ? Math.max(...blobs.map(b => b.timestamp)) : null
    };
  }
}

// CLI interface
async function main() {
  const port = parseInt(process.env.MOCK_WALRUS_PORT || '8080');
  const server = new MockWalrusServer(port);
  
  await server.start();

  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down mock Walrus server...');
    const stats = server.getStorageStats();
    console.log(`📊 Final stats:`, stats);
    process.exit(0);
  });

  // Keep the server running
  process.on('uncaughtException', (error) => {
    console.error('Uncaught exception:', error);
  });

  process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled rejection at:', promise, 'reason:', reason);
  });
}

// Export for use as library
export { MockWalrusServer };

// Run server if called directly
if (require.main === module) {
  main().catch(console.error);
}