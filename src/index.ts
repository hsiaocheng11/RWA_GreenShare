// FILE: src/index.ts
import dotenv from 'dotenv';
import { createSignedMeterData, importPrivateKeyFromPEM } from './crypto';
import { ROFLClient } from './client';

// Load environment variables
dotenv.config();

interface Config {
  roflEndpoint: string;
  meterPrivateKeyPEM: string;
  meterId: string;
  intervalMs: number;
  kwhRange: { min: number; max: number };
}

class SmartMeterSimulator {
  private client: ROFLClient;
  private config: Config;
  private privateKeyHex: string;
  private intervalId: NodeJS.Timeout | null = null;
  private isRunning = false;

  constructor() {
    this.config = this.loadConfig();
    this.client = new ROFLClient({
      endpoint: this.config.roflEndpoint,
      timeout: 15000,
      retryAttempts: 3,
      retryDelay: 2000
    });
    
    // Import and validate private key
    this.privateKeyHex = importPrivateKeyFromPEM(this.config.meterPrivateKeyPEM);
    
    console.log('🔧 Smart Meter Simulator initialized:', {
      meterId: this.config.meterId,
      endpoint: this.config.roflEndpoint,
      intervalMs: this.config.intervalMs
    });
  }

  /**
   * Load and validate configuration from environment
   */
  private loadConfig(): Config {
    const roflEndpoint = process.env.ROFL_ENDPOINT;
    const meterPrivateKeyPEM = process.env.METER_PRIVATE_KEY_PEM;
    const meterId = process.env.METER_ID;

    if (!roflEndpoint) {
      throw new Error('ROFL_ENDPOINT environment variable is required');
    }
    if (!meterPrivateKeyPEM) {
      throw new Error('METER_PRIVATE_KEY_PEM environment variable is required');
    }
    if (!meterId) {
      throw new Error('METER_ID environment variable is required');
    }

    return {
      roflEndpoint,
      meterPrivateKeyPEM,
      meterId,
      intervalMs: parseInt(process.env.INTERVAL_MS || '15000'), // Default 15 seconds
      kwhRange: {
        min: parseFloat(process.env.KWH_MIN || '0.1'),
        max: parseFloat(process.env.KWH_MAX || '2.5')
      }
    };
  }

  /**
   * Generate realistic kWh delta value
   */
  private generateKwhDelta(): number {
    const { min, max } = this.config.kwhRange;
    const delta = Math.random() * (max - min) + min;
    return Math.round(delta * 1000) / 1000; // Round to 3 decimal places
  }

  /**
   * Send a single meter reading
   */
  private async sendMeterReading(): Promise<void> {
    try {
      const kwhDelta = this.generateKwhDelta();
      
      console.log(`\n⚡ Generating meter reading:`, {
        meter_id: this.config.meterId,
        kwh_delta: kwhDelta,
        timestamp: new Date().toISOString()
      });

      const signedData = createSignedMeterData(
        this.config.meterId,
        kwhDelta,
        this.privateKeyHex
      );

      const response = await this.client.ingestMeterData(signedData);
      
      console.log('✅ Meter reading sent successfully:', {
        receipt_id: response.receipt_id,
        server_timestamp: response.timestamp
      });

    } catch (error) {
      console.error('❌ Failed to send meter reading:', (error as Error).message);
      
      // Don't stop the simulator on individual failures
      console.log('🔄 Will retry on next interval...');
    }
  }

  /**
   * Start the meter simulation
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      console.warn('⚠️ Simulator is already running');
      return;
    }

    try {
      // Perform initial health check
      console.log('🏥 Checking ROFL enclave health...');
      const isHealthy = await this.client.healthCheck();
      
      if (!isHealthy) {
        console.warn('⚠️ Health check failed, but starting anyway...');
      } else {
        console.log('✅ ROFL enclave is healthy');
      }

      this.isRunning = true;
      
      console.log(`🚀 Starting Smart Meter Simulator...`);
      console.log(`📊 Sending readings every ${this.config.intervalMs}ms`);
      console.log(`🎯 Target endpoint: ${this.config.roflEndpoint}/ingest`);
      console.log('Press Ctrl+C to stop\n');

      // Send initial reading immediately
      await this.sendMeterReading();

      // Set up interval for subsequent readings
      this.intervalId = setInterval(async () => {
        await this.sendMeterReading();
      }, this.config.intervalMs);

    } catch (error) {
      console.error('❌ Failed to start simulator:', (error as Error).message);
      this.isRunning = false;
      throw error;
    }
  }

  /**
   * Stop the meter simulation
   */
  async stop(): Promise<void> {
    if (!this.isRunning) {
      return;
    }

    console.log('\n🛑 Stopping Smart Meter Simulator...');
    
    this.isRunning = false;
    
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }

    await this.client.close();
    console.log('✅ Simulator stopped successfully');
  }
}

// Handle graceful shutdown
async function gracefulShutdown(simulator: SmartMeterSimulator): Promise<void> {
  console.log('\n📡 Received shutdown signal...');
  await simulator.stop();
  process.exit(0);
}

// Main execution
async function main(): Promise<void> {
  try {
    const simulator = new SmartMeterSimulator();
    
    // Set up signal handlers for graceful shutdown
    process.on('SIGINT', () => gracefulShutdown(simulator));
    process.on('SIGTERM', () => gracefulShutdown(simulator));
    process.on('uncaughtException', async (error) => {
      console.error('💥 Uncaught exception:', error);
      await simulator.stop();
      process.exit(1);
    });

    await simulator.start();
    
  } catch (error) {
    console.error('💥 Fatal error:', (error as Error).message);
    process.exit(1);
  }
}

// Start the simulator if this file is run directly
if (require.main === module) {
  main().catch((error) => {
    console.error('💥 Startup error:', error);
    process.exit(1);
  });
}

export { SmartMeterSimulator };