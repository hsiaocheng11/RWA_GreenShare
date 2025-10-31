// FILE: demo/trade-eKWH.ts
import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';

interface TradeOrder {
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  minAmountOut: string;
  deadline: number;
}

interface TradeResult {
  success: boolean;
  transactionHash?: string;
  orderId?: string;
  amountIn?: string;
  amountOut?: string;
  tokenIn?: string;
  tokenOut?: string;
  gasUsed?: string;
  error?: string;
}

interface MarketData {
  price: number;
  volume24h: number;
  change24h: number;
  liquidity: number;
}

class EKWHTrader {
  private provider: ethers.Provider;
  private wallet: ethers.Wallet;
  private gudAdapterAddress: string;
  private ekwhTokenAddress: string;
  private usdcTokenAddress: string;
  private mockMode: boolean;

  constructor(config: {
    rpcUrl?: string;
    privateKey?: string;
    gudAdapterAddress?: string;
    ekwhTokenAddress?: string;
    usdcTokenAddress?: string;
    mockMode?: boolean;
  } = {}) {
    // Initialize provider
    const rpcUrl = config.rpcUrl || process.env.ZIRCUIT_RPC_URL || 'https://zircuit-testnet.drpc.org';
    this.provider = new ethers.JsonRpcProvider(rpcUrl);

    // Initialize wallet
    if (config.privateKey || process.env.ZIRCUIT_PRIVATE_KEY) {
      const privateKey = config.privateKey || process.env.ZIRCUIT_PRIVATE_KEY!;
      this.wallet = new ethers.Wallet(privateKey, this.provider);
    } else {
      console.warn('⚠️  No private key provided, generating random wallet');
      this.wallet = ethers.Wallet.createRandom().connect(this.provider);
    }

    // Set contract addresses
    this.gudAdapterAddress = config.gudAdapterAddress || process.env.ZIRCUIT_GUD_ADAPTER_CONTRACT || '0x0';
    this.ekwhTokenAddress = config.ekwhTokenAddress || process.env.ZIRCUIT_EKWH_CONTRACT || '0x0';
    this.usdcTokenAddress = config.usdcTokenAddress || process.env.ZIRCUIT_USDC_CONTRACT || '0x0';
    this.mockMode = config.mockMode ?? true; // Default to mock mode

    console.log(`📈 eKWH Trading Configuration:`);
    console.log(`   Network: Zircuit ${this.mockMode ? '(Mock Mode)' : '(Live)'}`);
    console.log(`   Trader Address: ${this.wallet.address}`);
    console.log(`   Gud Adapter: ${this.gudAdapterAddress}`);
    console.log(`   eKWH Token: ${this.ekwhTokenAddress}`);
    console.log(`   USDC Token: ${this.usdcTokenAddress}`);
  }

  async checkBalances(): Promise<void> {
    try {
      // Check ETH balance
      const ethBalance = await this.provider.getBalance(this.wallet.address);
      const ethAmount = parseFloat(ethers.formatEther(ethBalance));

      console.log(`💰 Trading Account Balances:`);
      console.log(`   ETH: ${ethAmount.toFixed(6)} ETH`);

      // Check eKWH balance
      if (this.ekwhTokenAddress !== '0x0') {
        try {
          const ekwhBalance = await this.getTokenBalance(this.ekwhTokenAddress, 18);
          console.log(`   eKWH: ${ekwhBalance.toFixed(3)} eKWH`);
        } catch (error) {
          console.log(`   eKWH: Unable to fetch (${error})`);
        }
      }

      // Check USDC balance
      if (this.usdcTokenAddress !== '0x0') {
        try {
          const usdcBalance = await this.getTokenBalance(this.usdcTokenAddress, 6);
          console.log(`   USDC: ${usdcBalance.toFixed(2)} USDC`);
        } catch (error) {
          console.log(`   USDC: Unable to fetch (${error})`);
        }
      }

      if (ethAmount < 0.001) {
        console.warn('⚠️  Low ETH balance for gas fees');
      }
    } catch (error) {
      console.warn(`⚠️  Could not check balances: ${error}`);
    }
  }

  async getTokenBalance(tokenAddress: string, decimals: number): Promise<number> {
    try {
      const tokenABI = [
        "function balanceOf(address owner) view returns (uint256)"
      ];

      const tokenContract = new ethers.Contract(tokenAddress, tokenABI, this.provider);
      const balance = await tokenContract.balanceOf(this.wallet.address);
      
      return parseFloat(ethers.formatUnits(balance, decimals));
    } catch (error) {
      throw new Error(`Failed to get token balance: ${error}`);
    }
  }

  async getMarketData(tokenIn: string, tokenOut: string): Promise<MarketData> {
    try {
      if (this.mockMode) {
        // Return mock market data
        const basePrice = tokenIn.toLowerCase().includes('ekwh') ? 0.5 : 2.0; // eKWH = $0.50, assume inverse for USDC
        const randomVariation = 0.9 + Math.random() * 0.2; // ±10% variation
        
        return {
          price: basePrice * randomVariation,
          volume24h: 10000 + Math.random() * 50000,
          change24h: -10 + Math.random() * 20, // -10% to +10%
          liquidity: 500000 + Math.random() * 1000000
        };
      }

      // In real implementation, fetch from Gud Engine API
      const gudEngineABI = [
        "function getQuote(address tokenIn, address tokenOut, uint256 amountIn) view returns (uint256 amountOut)"
      ];

      const gudContract = new ethers.Contract(this.gudAdapterAddress, gudEngineABI, this.provider);
      const testAmount = ethers.parseEther("1"); // Test with 1 token
      const quote = await gudContract.getQuote(tokenIn, tokenOut, testAmount);
      
      const price = parseFloat(ethers.formatEther(quote));
      
      return {
        price,
        volume24h: 0, // Would need additional API calls
        change24h: 0,
        liquidity: 0
      };
    } catch (error) {
      console.warn(`⚠️  Could not fetch market data: ${error}`);
      // Return mock data as fallback
      return {
        price: 0.5,
        volume24h: 25000,
        change24h: 2.5,
        liquidity: 750000
      };
    }
  }

  async approveToken(tokenAddress: string, spenderAddress: string, amount: string): Promise<string> {
    try {
      console.log(`✅ Approving ${amount} tokens for trading...`);
      
      const tokenABI = [
        "function approve(address spender, uint256 amount) returns (bool)"
      ];

      const tokenContract = new ethers.Contract(tokenAddress, tokenABI, this.wallet);
      const amountWei = ethers.parseEther(amount);

      const tx = await tokenContract.approve(spenderAddress, amountWei, {
        gasLimit: 100000
      });

      console.log(`📋 Approval Transaction: ${tx.hash}`);
      await tx.wait();
      
      console.log(`✅ Token approval completed`);
      return tx.hash;
    } catch (error) {
      throw new Error(`Token approval failed: ${error}`);
    }
  }

  async executeTradeReal(order: TradeOrder): Promise<TradeResult> {
    try {
      console.log(`📈 Executing real trade via Gud Engine...`);
      
      // Gud Adapter ABI
      const gudAdapterABI = [
        {
          "inputs": [
            {"name": "tokenIn", "type": "address"},
            {"name": "tokenOut", "type": "address"},
            {"name": "amountIn", "type": "uint256"},
            {"name": "minAmountOut", "type": "uint256"},
            {"name": "deadline", "type": "uint256"}
          ],
          "name": "placeOrder",
          "outputs": [{"name": "orderId", "type": "bytes32"}],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ];

      const gudAdapter = new ethers.Contract(this.gudAdapterAddress, gudAdapterABI, this.wallet);

      // Approve tokens for trading
      await this.approveToken(order.tokenIn, this.gudAdapterAddress, order.amountIn);

      // Execute trade
      const tx = await gudAdapter.placeOrder(
        order.tokenIn,
        order.tokenOut,
        ethers.parseEther(order.amountIn),
        ethers.parseEther(order.minAmountOut),
        order.deadline,
        {
          gasLimit: 500000
        }
      );

      console.log(`📋 Trade Transaction: ${tx.hash}`);
      console.log(`⏳ Waiting for confirmation...`);

      const receipt = await tx.wait();

      if (receipt.status === 1) {
        // Extract order ID from logs
        const orderId = receipt.logs?.[0]?.topics?.[1] || 'unknown';
        
        console.log(`✅ Trade executed successfully!`);
        console.log(`   Order ID: ${orderId}`);
        console.log(`   Gas Used: ${receipt.gasUsed.toString()}`);

        return {
          success: true,
          transactionHash: tx.hash,
          orderId,
          amountIn: order.amountIn,
          tokenIn: order.tokenIn,
          tokenOut: order.tokenOut,
          gasUsed: receipt.gasUsed.toString()
        };
      } else {
        throw new Error('Transaction failed');
      }
    } catch (error) {
      throw new Error(`Real trade execution failed: ${error}`);
    }
  }

  async executeTradeMock(order: TradeOrder): Promise<TradeResult> {
    try {
      console.log(`🧪 Executing mock trade...`);
      
      // Simulate trade execution with a simple ETH transfer
      const tx = await this.wallet.sendTransaction({
        to: this.wallet.address, // Self-transfer for demo
        value: ethers.parseEther('0.001'), // Small amount
        gasLimit: 21000
      });

      console.log(`📋 Mock Trade Transaction: ${tx.hash}`);
      console.log(`⏳ Waiting for confirmation...`);

      const receipt = await tx.wait();

      // Generate mock order ID
      const orderId = ethers.keccak256(ethers.toUtf8Bytes(`mock_order_${Date.now()}`));
      
      // Calculate mock output amount (simulate 2% slippage)
      const marketData = await this.getMarketData(order.tokenIn, order.tokenOut);
      const amountOut = (parseFloat(order.amountIn) * marketData.price * 0.98).toFixed(6);

      console.log(`✅ Mock trade executed successfully!`);
      console.log(`   Order ID: ${orderId}`);
      console.log(`   Amount In: ${order.amountIn} tokens`);
      console.log(`   Amount Out: ${amountOut} tokens`);
      console.log(`   Price: ${marketData.price.toFixed(4)}`);
      console.log(`   Gas Used: ${receipt!.gasUsed.toString()}`);

      return {
        success: true,
        transactionHash: tx.hash,
        orderId,
        amountIn: order.amountIn,
        amountOut,
        tokenIn: order.tokenIn,
        tokenOut: order.tokenOut,
        gasUsed: receipt!.gasUsed.toString()
      };
    } catch (error) {
      throw new Error(`Mock trade execution failed: ${error}`);
    }
  }

  async trade(
    tokenIn: string,
    tokenOut: string,
    amountIn: number,
    slippageTolerance: number = 2.0
  ): Promise<TradeResult> {
    try {
      console.log(`📈 Starting eKWH trade...`);
      console.log(`   Sell: ${amountIn} ${tokenIn === this.ekwhTokenAddress ? 'eKWH' : 'tokens'}`);
      console.log(`   For: ${tokenOut === this.usdcTokenAddress ? 'USDC' : 'tokens'}`);
      console.log(`   Slippage: ${slippageTolerance}%`);

      // Check balances
      await this.checkBalances();

      // Get market data
      const marketData = await this.getMarketData(tokenIn, tokenOut);
      console.log(`\n📊 Market Data:`);
      console.log(`   Price: ${marketData.price.toFixed(4)}`);
      console.log(`   24h Volume: $${marketData.volume24h.toLocaleString()}`);
      console.log(`   24h Change: ${marketData.change24h.toFixed(2)}%`);
      console.log(`   Liquidity: $${marketData.liquidity.toLocaleString()}`);

      // Calculate expected output
      const expectedOutput = amountIn * marketData.price;
      const minAmountOut = expectedOutput * (1 - slippageTolerance / 100);

      console.log(`\n💱 Trade Calculation:`);
      console.log(`   Expected Output: ${expectedOutput.toFixed(6)} tokens`);
      console.log(`   Minimum Output: ${minAmountOut.toFixed(6)} tokens`);

      // Prepare order
      const order: TradeOrder = {
        tokenIn,
        tokenOut,
        amountIn: amountIn.toString(),
        minAmountOut: minAmountOut.toString(),
        deadline: Math.floor(Date.now() / 1000) + 1800 // 30 minutes from now
      };

      // Execute trade
      let result: TradeResult;
      if (this.mockMode || this.gudAdapterAddress === '0x0') {
        console.log(`\n🧪 Executing in mock mode...`);
        result = await this.executeTrademock(order);
      } else {
        console.log(`\n📈 Executing real trade...`);
        result = await this.executeTradeReal(order);
      }

      if (result.success) {
        console.log(`\n🎉 Trade completed successfully!`);
        
        // Calculate profit/loss if we have output amount
        if (result.amountOut) {
          const actualOutput = parseFloat(result.amountOut);
          const profit = actualOutput - expectedOutput;
          const profitPercent = (profit / expectedOutput) * 100;
          
          console.log(`   Actual Output: ${actualOutput.toFixed(6)} tokens`);
          console.log(`   P&L: ${profit >= 0 ? '+' : ''}${profit.toFixed(6)} tokens (${profitPercent.toFixed(2)}%)`);
        }
      }

      return result;
    } catch (error) {
      console.error(`❌ Trade failed: ${error}`);
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }

  async getTradeHistory(): Promise<any[]> {
    try {
      // In mock mode, return sample data
      if (this.mockMode) {
        return [
          {
            id: '1',
            timestamp: Date.now() - 3600000,
            type: 'sell',
            tokenIn: 'eKWH',
            tokenOut: 'USDC',
            amountIn: '50.0',
            amountOut: '25.2',
            price: '0.504',
            status: 'completed'
          },
          {
            id: '2',
            timestamp: Date.now() - 7200000,
            type: 'buy',
            tokenIn: 'USDC',
            tokenOut: 'eKWH',
            amountIn: '100.0',
            amountOut: '198.5',
            price: '0.503',
            status: 'completed'
          }
        ];
      }

      // For real implementation, query blockchain events
      return [];
    } catch (error) {
      console.warn(`⚠️  Could not fetch trade history: ${error}`);
      return [];
    }
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'trade';
  
  const trader = new EKWHTrader({
    rpcUrl: process.env.ZIRCUIT_RPC_URL,
    privateKey: process.env.ZIRCUIT_PRIVATE_KEY,
    gudAdapterAddress: process.env.ZIRCUIT_GUD_ADAPTER_CONTRACT,
    ekwhTokenAddress: process.env.ZIRCUIT_EKWH_CONTRACT,
    usdcTokenAddress: process.env.ZIRCUIT_USDC_CONTRACT,
    mockMode: process.env.TRADING_MOCK_MODE !== 'false'
  });

  try {
    switch (command) {
      case 'trade':
        const amount = parseFloat(args[1]) || 10; // Default 10 eKWH
        const slippage = parseFloat(args[2]) || 2.0; // Default 2% slippage
        
        console.log(`🚀 Trading ${amount} eKWH for USDC...`);
        
        const result = await trader.trade(
          trader['ekwhTokenAddress'], // tokenIn (eKWH)
          trader['usdcTokenAddress'], // tokenOut (USDC)
          amount,
          slippage
        );
        
        if (result.success) {
          // Save result
          const resultFile = 'demo/trade-result.json';
          await fs.writeFile(resultFile, JSON.stringify(result, null, 2));
          console.log(`💾 Result saved to: ${resultFile}`);
        } else {
          console.error(`❌ Trade failed: ${result.error}`);
          process.exit(1);
        }
        break;

      case 'balance':
        console.log(`💰 Checking trading balances...`);
        await trader.checkBalances();
        break;

      case 'market':
        console.log(`📊 Fetching market data...`);
        const marketData = await trader.getMarketData(
          trader['ekwhTokenAddress'],
          trader['usdcTokenAddress']
        );
        console.log(`   eKWH/USDC Price: $${marketData.price.toFixed(4)}`);
        console.log(`   24h Volume: $${marketData.volume24h.toLocaleString()}`);
        console.log(`   24h Change: ${marketData.change24h.toFixed(2)}%`);
        console.log(`   Liquidity: $${marketData.liquidity.toLocaleString()}`);
        break;

      case 'history':
        console.log(`📈 Fetching trade history...`);
        const history = await trader.getTradeHistory();
        if (history.length > 0) {
          console.log(`\n📋 Recent Trades:`);
          history.forEach((trade, index) => {
            const date = new Date(trade.timestamp).toLocaleString();
            console.log(`   ${index + 1}. ${trade.type.toUpperCase()} ${trade.amountIn} ${trade.tokenIn} → ${trade.amountOut} ${trade.tokenOut}`);
            console.log(`      Price: $${trade.price} | ${date} | ${trade.status}`);
          });
        } else {
          console.log(`   No trade history found`);
        }
        break;

      default:
        console.log(`
GreenShare eKWH Trader

Usage:
  npm run demo:trade [command] [options]

Commands:
  trade [amount] [slippage]    Trade eKWH for USDC (default: 10 eKWH, 2% slippage)
  balance                      Check trading account balances
  market                       Show market data for eKWH/USDC
  history                      Show trade history

Examples:
  npm run demo:trade                         # Trade 10 eKWH with 2% slippage
  npm run demo:trade trade 25 1.5           # Trade 25 eKWH with 1.5% slippage
  npm run demo:trade balance                 # Check balances
  npm run demo:trade market                  # Show market data
  npm run demo:trade history                 # Show trade history

Environment Variables:
  ZIRCUIT_RPC_URL              Zircuit RPC endpoint
  ZIRCUIT_PRIVATE_KEY          Trading account private key
  ZIRCUIT_GUD_ADAPTER_CONTRACT Gud adapter contract address
  ZIRCUIT_EKWH_CONTRACT        eKWH token contract address
  ZIRCUIT_USDC_CONTRACT        USDC token contract address
  TRADING_MOCK_MODE            Enable mock trading (true/false)
        `);
        break;
    }
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

// Export for use as library
export { EKWHTrader, type TradeResult, type MarketData };

// Run CLI if called directly
if (require.main === module) {
  main().catch(console.error);
}