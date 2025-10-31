// FILE: demo/seed-smartmeter.ts
import axios from 'axios';
import crypto from 'crypto';
import { createReadStream } from 'fs';
import { writeFileSync } from 'fs';

interface MeterReading {
  meter_id: string;
  timestamp: number;
  kwh_delta: number;
  nonce: string;
}

interface SignedMeterData {
  record: MeterReading;
  sig: string;
}

class SmartMeterSimulator {
  private meterIds: string[];
  private baseConsumption: { [meterId: string]: number };
  private roflEndpoint: string;
  private privateKey: string;
  private readings: SignedMeterData[] = [];

  constructor(config: {
    meterCount?: number;
    roflEndpoint?: string;
    privateKey?: string;
  } = {}) {
    this.meterIds = Array.from({ length: config.meterCount || 10 }, (_, i) => 
      `METER_${String(i + 1).padStart(3, '0')}`
    );
    
    this.baseConsumption = {};
    this.meterIds.forEach(id => {
      // Random base consumption between 0.5 and 3.0 kWh per hour
      this.baseConsumption[id] = 0.5 + Math.random() * 2.5;
    });

    this.roflEndpoint = config.roflEndpoint || process.env.ROFL_ENDPOINT || 'http://localhost:8080';
    this.privateKey = config.privateKey || process.env.METER_PRIVATE_KEY || this.generateMockPrivateKey();
  }

  private generateMockPrivateKey(): string {
    return crypto.randomBytes(32).toString('hex');
  }

  private generateRealisticConsumption(meterId: string, hour: number, minute: number): number {
    const baseHourly = this.baseConsumption[meterId];
    
    // Time-based patterns
    const timeOfDay = hour + minute / 60;
    
    // Peak consumption during evening hours (17-22)
    let timeMultiplier = 1.0;
    if (timeOfDay >= 17 && timeOfDay <= 22) {
      timeMultiplier = 1.5 + Math.sin((timeOfDay - 17) * Math.PI / 5) * 0.5;
    } else if (timeOfDay >= 6 && timeOfDay <= 9) {
      // Morning peak
      timeMultiplier = 1.3;
    } else if (timeOfDay >= 0 && timeOfDay <= 6) {
      // Night time - lower consumption
      timeMultiplier = 0.6;
    }

    // Weather simulation (random weather impact)
    const weatherMultiplier = 0.8 + Math.random() * 0.4; // 0.8 to 1.2

    // Random variation (±20%)
    const randomVariation = 0.8 + Math.random() * 0.4;

    // Calculate kWh for this 15-minute interval
    const intervalHours = 15 / 60; // 15 minutes = 0.25 hours
    const consumption = baseHourly * timeMultiplier * weatherMultiplier * randomVariation * intervalHours;

    // Round to 3 decimal places
    return Math.round(consumption * 1000) / 1000;
  }

  private signReading(reading: MeterReading): string {
    // Create message to sign
    const message = `${reading.meter_id}:${reading.timestamp}:${reading.kwh_delta}:${reading.nonce}`;
    
    // Mock ECDSA signature (in production, use actual cryptographic signing)
    const hash = crypto.createHash('sha256').update(message).digest();
    const signature = crypto.createHmac('sha256', this.privateKey).update(hash).digest('hex');
    
    return `0x${signature}`;
  }

  private async sendToROFL(signedData: SignedMeterData): Promise<boolean> {
    try {
      const response = await axios.post(`${this.roflEndpoint}/api/v1/ingest`, signedData, {
        headers: {
          'Content-Type': 'application/json'
        },
        timeout: 5000
      });

      return response.status === 200;
    } catch (error) {
      console.error(`Failed to send data to ROFL: ${error}`);
      return false;
    }
  }

  async generateHistoricalData(durationHours: number = 2): Promise<SignedMeterData[]> {
    console.log(`🔌 Generating ${durationHours} hours of smart meter data...`);
    console.log(`📊 Simulating ${this.meterIds.length} smart meters`);
    console.log(`⚡ ROFL Endpoint: ${this.roflEndpoint}`);
    
    const readings: SignedMeterData[] = [];
    const startTime = Date.now() - (durationHours * 60 * 60 * 1000); // Start from N hours ago
    const intervalMs = 15 * 60 * 1000; // 15-minute intervals
    const totalIntervals = (durationHours * 60) / 15; // Number of 15-minute intervals
    
    console.log(`🕐 Generating ${totalIntervals} intervals per meter (15-minute intervals)`);
    console.log(`📈 Expected total readings: ${totalIntervals * this.meterIds.length}`);

    for (let interval = 0; interval < totalIntervals; interval++) {
      const timestamp = startTime + (interval * intervalMs);
      const date = new Date(timestamp);
      const hour = date.getHours();
      const minute = date.getMinutes();

      console.log(`⏰ Processing interval ${interval + 1}/${totalIntervals} - ${date.toLocaleTimeString()}`);

      for (const meterId of this.meterIds) {
        const kwhDelta = this.generateRealisticConsumption(meterId, hour, minute);
        const nonce = `${meterId}_${timestamp}_${crypto.randomBytes(4).toString('hex')}`;

        const reading: MeterReading = {
          meter_id: meterId,
          timestamp: Math.floor(timestamp / 1000), // Convert to seconds
          kwh_delta: kwhDelta,
          nonce
        };

        const signature = this.signReading(reading);
        const signedData: SignedMeterData = {
          record: reading,
          sig: signature
        };

        readings.push(signedData);
      }
    }

    this.readings = readings;
    console.log(`✅ Generated ${readings.length} signed meter readings`);
    
    // Save to file for inspection
    const outputFile = 'demo/generated-meter-data.json';
    writeFileSync(outputFile, JSON.stringify(readings, null, 2));
    console.log(`💾 Saved readings to ${outputFile}`);

    return readings;
  }

  async sendDataToROFL(readings?: SignedMeterData[]): Promise<void> {
    const dataToSend = readings || this.readings;
    
    if (dataToSend.length === 0) {
      console.error('❌ No data to send. Generate data first.');
      return;
    }

    console.log(`📤 Sending ${dataToSend.length} readings to ROFL...`);
    
    let successCount = 0;
    let failureCount = 0;
    const batchSize = 10;
    
    // Send in batches to avoid overwhelming the ROFL endpoint
    for (let i = 0; i < dataToSend.length; i += batchSize) {
      const batch = dataToSend.slice(i, i + batchSize);
      console.log(`📦 Sending batch ${Math.floor(i / batchSize) + 1}/${Math.ceil(dataToSend.length / batchSize)}`);

      const batchPromises = batch.map(async (reading) => {
        const success = await this.sendToROFL(reading);
        if (success) {
          successCount++;
        } else {
          failureCount++;
        }
        return success;
      });

      await Promise.all(batchPromises);
      
      // Small delay between batches
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    console.log(`📊 Send Summary:`);
    console.log(`   ✅ Successful: ${successCount}`);
    console.log(`   ❌ Failed: ${failureCount}`);
    console.log(`   📈 Success Rate: ${((successCount / dataToSend.length) * 100).toFixed(1)}%`);
  }

  async simulateRealTime(durationMinutes: number = 30): Promise<void> {
    console.log(`🔄 Starting real-time simulation for ${durationMinutes} minutes...`);
    
    const intervalMs = 15 * 60 * 1000; // 15-minute intervals
    const endTime = Date.now() + (durationMinutes * 60 * 1000);
    
    while (Date.now() < endTime) {
      const timestamp = Date.now();
      const date = new Date(timestamp);
      const hour = date.getHours();
      const minute = date.getMinutes();

      console.log(`⚡ Real-time reading at ${date.toLocaleTimeString()}`);

      const readings: SignedMeterData[] = [];
      
      for (const meterId of this.meterIds) {
        const kwhDelta = this.generateRealisticConsumption(meterId, hour, minute);
        const nonce = `${meterId}_${timestamp}_${crypto.randomBytes(4).toString('hex')}`;

        const reading: MeterReading = {
          meter_id: meterId,
          timestamp: Math.floor(timestamp / 1000),
          kwh_delta: kwhDelta,
          nonce
        };

        const signature = this.signReading(reading);
        const signedData: SignedMeterData = {
          record: reading,
          sig: signature
        };

        readings.push(signedData);
      }

      // Send batch to ROFL
      await this.sendDataToROFL(readings);
      
      // Wait for next interval
      await new Promise(resolve => setTimeout(resolve, intervalMs));
    }

    console.log(`✅ Real-time simulation completed`);
  }

  getStatistics(): any {
    if (this.readings.length === 0) {
      return null;
    }

    const totalKwh = this.readings.reduce((sum, reading) => sum + reading.record.kwh_delta, 0);
    const avgKwh = totalKwh / this.readings.length;
    const maxKwh = Math.max(...this.readings.map(r => r.record.kwh_delta));
    const minKwh = Math.min(...this.readings.map(r => r.record.kwh_delta));

    const meterStats: { [meterId: string]: any } = {};
    this.meterIds.forEach(meterId => {
      const meterReadings = this.readings.filter(r => r.record.meter_id === meterId);
      const meterTotal = meterReadings.reduce((sum, r) => sum + r.record.kwh_delta, 0);
      
      meterStats[meterId] = {
        readings: meterReadings.length,
        totalKwh: Math.round(meterTotal * 1000) / 1000,
        avgKwh: Math.round((meterTotal / meterReadings.length) * 1000) / 1000
      };
    });

    return {
      summary: {
        totalReadings: this.readings.length,
        totalKwh: Math.round(totalKwh * 1000) / 1000,
        avgKwhPerReading: Math.round(avgKwh * 1000) / 1000,
        maxKwh: Math.round(maxKwh * 1000) / 1000,
        minKwh: Math.round(minKwh * 1000) / 1000,
        totalMeters: this.meterIds.length
      },
      byMeter: meterStats
    };
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'generate';
  
  const simulator = new SmartMeterSimulator({
    meterCount: parseInt(args[1]) || 10,
    roflEndpoint: process.env.ROFL_ENDPOINT || 'http://localhost:8080'
  });

  try {
    switch (command) {
      case 'generate':
        const hours = parseFloat(args[2]) || 2;
        console.log(`🚀 Generating ${hours} hours of historical data...`);
        
        const readings = await simulator.generateHistoricalData(hours);
        await simulator.sendDataToROFL(readings);
        
        const stats = simulator.getStatistics();
        console.log('\n📊 Generation Statistics:');
        console.log(JSON.stringify(stats, null, 2));
        break;

      case 'realtime':
        const minutes = parseInt(args[2]) || 30;
        console.log(`🔄 Starting real-time simulation for ${minutes} minutes...`);
        await simulator.simulateRealTime(minutes);
        break;

      case 'stats':
        const stats2 = simulator.getStatistics();
        if (stats2) {
          console.log('📊 Current Statistics:');
          console.log(JSON.stringify(stats2, null, 2));
        } else {
          console.log('📊 No data available. Generate data first.');
        }
        break;

      default:
        console.log(`
GreenShare Smart Meter Simulator

Usage:
  npm run demo:seed [command] [options]

Commands:
  generate [meters] [hours]    Generate historical data (default: 10 meters, 2 hours)
  realtime [meters] [minutes]  Simulate real-time data (default: 10 meters, 30 minutes)
  stats                        Show statistics of generated data

Examples:
  npm run demo:seed generate 5 1     # 5 meters, 1 hour of data
  npm run demo:seed realtime 10 60   # 10 meters, 60 minutes real-time
  npm run demo:seed stats             # Show statistics

Environment Variables:
  ROFL_ENDPOINT                ROFL enclave endpoint (default: http://localhost:8080)
  METER_PRIVATE_KEY           Private key for signing (optional, auto-generated)
        `);
        break;
    }
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

// Export for use as library
export { SmartMeterSimulator, type MeterReading, type SignedMeterData };

// Run CLI if called directly
if (require.main === module) {
  main().catch(console.error);
}