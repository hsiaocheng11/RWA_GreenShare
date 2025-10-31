# FILE: demo/README.md

# GreenShare Demo - 3-Minute Energy Tokenization Journey 🌱⚡

Experience the complete GreenShare energy tokenization flow from IoT meter data to DEX trading in just 3 minutes!

## 🎯 Demo Overview

This demo showcases the end-to-end process of converting solar energy production into tradeable tokens:

```
Smart Meter Data → ROFL Aggregation → Sui sKWH → Zircuit eKWH → Gud Trading
      (2 min)           (30 sec)        (1 min)      (1 min)       (30 sec)
```

## ⚡ Quick Start (3 Minutes)

### Prerequisites Check

```bash
# Ensure services are running
pnpm devnet:status

# If not running, start them
pnpm devnet:up
```

### 🚀 Complete Demo Flow

```bash
# Step 1: Generate 2 hours of smart meter data (30 seconds)
npm run demo:seed generate 5 2

# Step 2: Create aggregated proof (30 seconds)
./demo/make-proof.sh

# Step 3: Mint sKWH tokens on Sui (1 minute)
npm run demo:mint

# Step 4: Bridge to Zircuit eKWH (1 minute)
npm run demo:bridge

# Step 5: Trade on Gud Engine (30 seconds)
npm run demo:trade

# 🎉 Complete! Check your results
ls demo/*-result.json
```

## 📋 Step-by-Step Guide

### Step 1: Smart Meter Data Generation 🔌

Generate realistic IoT smart meter data for the demo:

```bash
# Generate 2 hours of data from 5 smart meters
npm run demo:seed generate 5 2

# What this does:
# ✅ Creates 480 realistic meter readings (5 meters × 8 intervals/hour × 2 hours)
# ✅ Simulates time-of-day consumption patterns
# ✅ Adds weather and random variations
# ✅ Signs each reading with ECDSA signatures
# ✅ Sends data to ROFL enclave for aggregation

# Expected output:
# 🔌 Generating 2 hours of smart meter data...
# 📊 Simulating 5 smart meters
# ⚡ ROFL Endpoint: http://localhost:8080
# 📤 Sending 480 readings to ROFL...
# ✅ Generation completed: 125.4 kWh total
```

**Customization Options:**
```bash
# Different configurations
npm run demo:seed generate 10 1    # 10 meters, 1 hour
npm run demo:seed generate 3 4     # 3 meters, 4 hours
npm run demo:seed realtime 5 30    # Real-time simulation for 30 minutes
```

### Step 2: Proof Generation 🔮

Trigger ROFL aggregation and generate cryptographic proof:

```bash
# Generate proof from accumulated meter data
./demo/make-proof.sh

# What this does:
# ✅ Checks ROFL enclave health
# ✅ Triggers data aggregation
# ✅ Generates Merkle tree proof
# ✅ Seals proof to Walrus storage
# ✅ Downloads proof.json file

# Expected output:
# 🔮 GreenShare Proof Generation
# ✅ ROFL enclave is healthy
# 📊 Pending Records: 480
# 🔒 Generated content hash: 0xabc123...
# ✅ Proof generation completed!
# 📁 Latest Proof: demo/proofs/latest_proof.json
```

**Advanced Options:**
```bash
./demo/make-proof.sh --force          # Force aggregation
./demo/make-proof.sh --upload-walrus  # Upload to Walrus
./demo/make-proof.sh --max-wait 120   # Wait up to 2 minutes
```

### Step 3: Sui sKWH Minting 🌱

Mint sKWH tokens on Sui blockchain from the verified proof:

```bash
# Mint sKWH tokens from the latest proof
npm run demo:mint

# What this does:
# ✅ Reads proof.json file
# ✅ Connects to Sui testnet
# ✅ Creates Certificate NFT
# ✅ Mints sKWH tokens (1:1 with kWh)
# ✅ Places Certificate in Kiosk

# Expected output:
# 🌱 Starting mint process for proof: proof_1234
# 💎 Minting 125.4 sKWH tokens...
# 📤 Submitting transaction...
# ✅ Mint successful!
# 📋 Transaction: 0xdef456...
# 🪙 Certificate NFT: 0x789abc...
# 💰 sKWH Coin: 0x012def...
```

**Other Commands:**
```bash
npm run demo:mint balance                    # Check sKWH balance
npm run demo:mint verify 0x1234...          # Verify transaction
npm run demo:mint mint custom_proof.json    # Mint from specific proof
```

### Step 4: Cross-Chain Bridge 🌉

Bridge sKWH tokens to Zircuit as eKWH:

```bash
# Bridge 50 sKWH to Zircuit eKWH
npm run demo:bridge bridge 50

# What this does:
# ✅ Burns sKWH tokens on Sui
# ✅ Creates cross-chain bridge request
# ✅ Generates cryptographic proof
# ✅ Mints eKWH tokens on Zircuit
# ✅ Updates metadata with cross-chain info

# Expected output:
# 🌉 Starting cross-chain bridge: 50 sKWH → eKWH
# 🔥 Step 1: Burning sKWH on Sui...
# 🌱 Step 2: Minting eKWH on Zircuit...
# ✅ Bridge completed successfully!
# 📋 Sui Tx: 0xabc123...
# 📋 Zircuit Tx: 0xdef456...
```

**Bridge Options:**
```bash
npm run demo:bridge bridge 25 0x742d35cc...  # Bridge to specific address
npm run demo:bridge balance                   # Check cross-chain balances
```

### Step 5: DEX Trading 📈

Trade eKWH tokens on Gud Trading Engine:

```bash
# Trade 25 eKWH for USDC
npm run demo:trade trade 25

# What this does:
# ✅ Connects to Gud Trading Engine
# ✅ Gets market price for eKWH/USDC
# ✅ Calculates slippage tolerance
# ✅ Executes trade order
# ✅ Shows profit/loss analysis

# Expected output:
# 📈 Starting eKWH trade...
# 📊 Market Data: Price: $0.5040, Volume: $45,230
# 💱 Expected Output: 12.6 USDC
# ✅ Trade executed successfully!
# 📋 Order ID: 0x789abc...
# 💰 P&L: +0.12 USDC (+0.95%)
```

**Trading Options:**
```bash
npm run demo:trade trade 10 1.5        # Trade with 1.5% slippage
npm run demo:trade market              # Show market data
npm run demo:trade history             # Show trade history
npm run demo:trade balance             # Check trading balances
```

## 📊 Demo Results

After completing the demo, check your results:

```bash
# View all demo results
ls demo/*-result.json

# Individual result files
cat demo/mint-result.json      # Sui minting results
cat demo/bridge-result.json    # Cross-chain bridge results  
cat demo/trade-result.json     # Trading results

# Generated proof file
cat demo/proofs/latest_proof.json
```

### Sample Results

**Mint Result:**
```json
{
  "success": true,
  "transactionDigest": "0xabc123...",
  "certificateId": "0xdef456...",
  "skwhCoinId": "0x789abc...",
  "gasUsed": "0.025 SUI"
}
```

**Bridge Result:**
```json
{
  "success": true,
  "suiTxDigest": "0x123abc...",
  "zircuitTxHash": "0x456def...",
  "amountBridged": "50",
  "recipient": "0x742d35cc..."
}
```

**Trade Result:**
```json
{
  "success": true,
  "transactionHash": "0x789ghi...",
  "amountIn": "25",
  "amountOut": "12.6",
  "tokenIn": "eKWH",
  "tokenOut": "USDC"
}
```

## 🛠️ Demo Configuration

### Environment Variables

The demo uses these key environment variables:

```bash
# ROFL Configuration
ROFL_ENDPOINT=http://localhost:8080

# Sui Configuration  
SUI_NETWORK=testnet
SUI_PRIVATE_KEY=0x...
SUI_PACKAGE_ID=0x...
SUI_SKWH_REGISTRY=0x...

# Zircuit Configuration
ZIRCUIT_RPC_URL=https://zircuit-testnet.drpc.org
ZIRCUIT_PRIVATE_KEY=0x...
ZIRCUIT_EKWH_CONTRACT=0x...
ZIRCUIT_BRIDGE_CONTRACT=0x...

# Trading Configuration
TRADING_MOCK_MODE=true
```

### Mock vs Real Mode

The demo supports both mock and real blockchain interactions:

**Mock Mode (Default):**
- ✅ Fast execution
- ✅ No real gas costs
- ✅ Simulated market data
- ✅ Perfect for demos

**Real Mode:**
- ✅ Actual blockchain transactions
- ✅ Real gas costs
- ✅ Live market data
- ✅ Production testing

Switch modes by setting:
```bash
export TRADING_MOCK_MODE=false  # Enable real mode
export TRADING_MOCK_MODE=true   # Enable mock mode
```

## 🧪 Demo Variations

### Quick Demo (1 Minute)

For a faster demo experience:

```bash
# Use pre-generated data
cp demo/samples/sample_proof.json demo/proofs/latest_proof.json

# Run just the blockchain steps
npm run demo:mint && npm run demo:bridge && npm run demo:trade
```

### Extended Demo (10 Minutes)

For a comprehensive experience:

```bash
# Generate 6 hours of data from 20 meters
npm run demo:seed generate 20 6

# Multiple proof cycles
for i in {1..3}; do
  ./demo/make-proof.sh --force
  npm run demo:mint
  npm run demo:bridge bridge 30
  npm run demo:trade trade 15
  sleep 60  # Wait between cycles
done
```

### Real-Time Demo

For live data simulation:

```bash
# Start real-time meter simulation (runs continuously)
npm run demo:seed realtime 10 60 &

# Periodic proof generation (every 5 minutes)
watch -n 300 './demo/make-proof.sh --force && npm run demo:mint && npm run demo:bridge bridge 20'
```

## 📈 Demo Analytics

### Performance Metrics

Track demo performance:

```bash
# Time each step
time npm run demo:seed generate 5 2        # ~30 seconds
time ./demo/make-proof.sh                  # ~30 seconds  
time npm run demo:mint                     # ~60 seconds
time npm run demo:bridge                   # ~60 seconds
time npm run demo:trade                    # ~30 seconds
```

### Data Statistics

View generated data statistics:

```bash
# Meter data statistics
npm run demo:seed stats

# Proof statistics  
jq '.aggregate_kwh, .record_count, .meter_ids | length' demo/proofs/latest_proof.json

# Trading statistics
npm run demo:trade history
```

## 🔧 Troubleshooting

### Common Issues

**1. ROFL Enclave Not Responding**
```bash
# Check if ROFL is running
curl http://localhost:8080/health

# Restart if needed
pnpm devnet:restart
```

**2. Insufficient Balance**
```bash
# Check Sui balance
npm run demo:mint balance

# Get testnet SUI from faucet
open https://testnet.sui.io/faucet
```

**3. Bridge Timeout**
```bash
# Check both chain balances
npm run demo:bridge balance

# Retry with longer timeout
./demo/make-proof.sh --max-wait 180
```

**4. Trading Fails**
```bash
# Switch to mock mode
export TRADING_MOCK_MODE=true
npm run demo:trade
```

### Reset Demo

To reset and start fresh:

```bash
# Clear all demo data
rm -rf demo/proofs/* demo/*-result.json demo/generated-meter-data.json

# Restart services
pnpm devnet:restart

# Start fresh demo
npm run demo:seed generate 5 2
```

## 🎬 Demo Scenarios

### Scenario 1: Solar Farm Demo
```bash
# Large solar installation
npm run demo:seed generate 50 4    # 50 meters, 4 hours
./demo/make-proof.sh
npm run demo:mint
npm run demo:bridge bridge 200
npm run demo:trade trade 100
```

### Scenario 2: Residential Community  
```bash
# Small residential community
npm run demo:seed generate 8 6     # 8 homes, 6 hours
./demo/make-proof.sh
npm run demo:mint  
npm run demo:bridge bridge 75
npm run demo:trade trade 35
```

### Scenario 3: Real-Time Trading
```bash
# Continuous trading simulation
npm run demo:seed realtime 15 120 &
while true; do
  sleep 300  # Wait 5 minutes
  ./demo/make-proof.sh --force
  npm run demo:mint
  npm run demo:bridge bridge 25
  npm run demo:trade trade 12
done
```

## 🎯 Demo Success Criteria

A successful demo should show:

✅ **Data Generation:** 480+ meter readings generated  
✅ **Proof Creation:** Valid proof.json with Merkle root  
✅ **Token Minting:** sKWH tokens minted on Sui  
✅ **Cross-Chain Bridge:** eKWH tokens on Zircuit  
✅ **DEX Trading:** Successful trade execution  
✅ **End-to-End Flow:** Complete tokenization journey  

## 📚 Next Steps

After completing the demo:

1. **Explore the Code:** Dive into the source code to understand the implementation
2. **Try Variations:** Experiment with different parameters and scenarios  
3. **Real Deployment:** Deploy to actual testnets for real blockchain interactions
4. **Integration:** Integrate GreenShare into your own renewable energy projects
5. **Contribute:** Submit improvements and new features via GitHub

## 🤝 Support

Need help with the demo?

- 📚 **Documentation:** [Full docs](../README.md)
- 💬 **Discord:** [GreenShare Community](https://discord.gg/greenshare)
- 🐛 **Issues:** [GitHub Issues](https://github.com/greenshare/issues)
- 📧 **Email:** demo@greenshare.energy

---

**Ready to tokenize renewable energy? Let's start the demo! 🌱⚡**