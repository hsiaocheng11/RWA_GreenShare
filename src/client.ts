// FILE: src/client.ts
import axios, { AxiosInstance, AxiosError } from 'axios';
import { SignedMeterData } from './crypto';

export interface ROFLClientConfig {
  endpoint: string;
  timeout?: number;
  retryAttempts?: number;
  retryDelay?: number;
}

export interface ROFLResponse {
  success: boolean;
  message?: string;
  timestamp?: number;
  receipt_id?: string;
}

export class ROFLClient {
  private client: AxiosInstance;
  private config: Required<ROFLClientConfig>;

  constructor(config: ROFLClientConfig) {
    this.config = {
      timeout: 10000,
      retryAttempts: 3,
      retryDelay: 1000,
      ...config
    };

    this.client = axios.create({
      baseURL: this.config.endpoint,
      timeout: this.config.timeout,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'SmartMeter-Simulator/1.0.0'
      }
    });

    // Add request/response interceptors for logging
    this.client.interceptors.request.use(
      (config) => {
        console.log(`📤 Sending to ${config.url}:`, {
          method: config.method?.toUpperCase(),
          timestamp: new Date().toISOString()
        });
        return config;
      },
      (error) => {
        console.error('❌ Request error:', error.message);
        return Promise.reject(error);
      }
    );

    this.client.interceptors.response.use(
      (response) => {
        console.log(`📥 Response from ${response.config.url}:`, {
          status: response.status,
          statusText: response.statusText,
          timestamp: new Date().toISOString()
        });
        return response;
      },
      (error) => {
        if (error.response) {
          console.error(`❌ Response error ${error.response.status}:`, error.response.data);
        } else if (error.request) {
          console.error('❌ No response received:', error.message);
        } else {
          console.error('❌ Request setup error:', error.message);
        }
        return Promise.reject(error);
      }
    );
  }

  /**
   * Send signed meter data to ROFL enclave with retry logic
   */
  async ingestMeterData(data: SignedMeterData): Promise<ROFLResponse> {
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= this.config.retryAttempts; attempt++) {
      try {
        console.log(`🔄 Attempt ${attempt}/${this.config.retryAttempts} - Ingesting meter data...`);
        
        const response = await this.client.post<ROFLResponse>('/ingest', data);
        
        console.log('✅ Successfully ingested meter data:', {
          meter_id: data.record.meter_id,
          kwh_delta: data.record.kwh_delta,
          timestamp: data.record.timestamp,
          receipt_id: response.data.receipt_id
        });

        return response.data;

      } catch (error) {
        lastError = error as Error;
        
        if (error instanceof AxiosError) {
          const status = error.response?.status;
          const isRetryable = !status || status >= 500 || status === 429;
          
          if (!isRetryable || attempt === this.config.retryAttempts) {
            console.error(`❌ Non-retryable error or max attempts reached:`, {
              status,
              message: error.message,
              attempt
            });
            break;
          }
        }

        if (attempt < this.config.retryAttempts) {
          const delay = this.config.retryDelay * Math.pow(2, attempt - 1); // Exponential backoff
          console.warn(`⚠️ Retrying in ${delay}ms... (attempt ${attempt + 1}/${this.config.retryAttempts})`);
          await this.sleep(delay);
        }
      }
    }

    throw new Error(`Failed to ingest meter data after ${this.config.retryAttempts} attempts: ${lastError?.message}`);
  }

  /**
   * Health check endpoint
   */
  async healthCheck(): Promise<boolean> {
    try {
      const response = await this.client.get('/health');
      return response.status === 200;
    } catch (error) {
      console.warn('⚠️ Health check failed:', (error as Error).message);
      return false;
    }
  }

  /**
   * Get enclave status/info
   */
  async getStatus(): Promise<any> {
    try {
      const response = await this.client.get('/status');
      return response.data;
    } catch (error) {
      console.error('❌ Failed to get enclave status:', (error as Error).message);
      throw error;
    }
  }

  /**
   * Utility sleep function
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Close client and cleanup
   */
  async close(): Promise<void> {
    // Axios doesn't require explicit cleanup, but we can add any necessary cleanup here
    console.log('🔌 ROFL client connection closed');
  }
}