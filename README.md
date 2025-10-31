# FILE: README.md

# GreenShare - Decentralized Solar Energy Community 🌱⚡

GreenShare is a comprehensive blockchain-based platform that enables decentralized solar energy trading through IoT smart meters, TEE verification, and cross-chain infrastructure.

## 🏗️ Architecture Overview

```
IoT Smart Meters → Oasis ROFL (TEE) → Sui (sKWH + NFT) → Zircuit (eKWH + Trading) → imToken (UX)
                           ↓                    ↓                      ↓
                    Walrus/Seal         Kiosk Custody         Gud Trading Engine
                           ↓                    ↓                      ↓
                   Content Proof         Certificate NFTs      Cross-chain Bridge
                           ↓                    ↓                      ↓
                     Celo SDK             zkLogin Auth           One-click Payment
```

## 🔧 Tech Stack

- **IoT & TEE**: Rust/ROFL enclave on Oasis for data aggregation and verification
- **Sui Blockchain**: Move smart contracts for sKWH tokens and certificate NFTs
- **Zircuit L2**: Solidity contracts for eKWH tokens and Gud Trading Engine integration
- **Celo**: Self Onchain SDK for minimal disclosure identity proofs
- **Walrus**: Decentralized storage for proof sealing and content verification
- **imToken**: Mobile wallet integration for seamless UX
- **Frontend**: Next.js/TypeScript with multi-chain support

## 🚀 Quick Start

### Prerequisites

```bash
# Install dependencies
node >= 18.0.0
pnpm >= 8.0.0
rust >= 1.75.0
sui CLI >= 1.15.0
foundry >= 0.2.0
docker >= 20.0.0
docker-compose >= 2.0.0
```

### One-Click Development Setup

```bash
# 1. Clone and setup
git clone https://github.com/greenshare/greenshare.git
cd greenshare

# 2. One-click devnet startup
chmod +x scripts/*.sh
pnpm devnet:up

# 3. Access services
# Frontend:      http://localhost:3000
# ROFL API:      http://localhost:8080
# Mock Walrus:   http://localhost:8081
```

### Alternative Setup Methods

#### Docker Compose (Recommended for Production-like Testing)
```bash
# Start all services with Docker
pnpm docker:up

# Check service status
pnpm docker:logs

# Stop all services
pnpm docker:down
```

#### Manual Setup
```bash
# 1. Copy environment variables
cp .env.example .env

# 2. Configure your networks
# Edit .env with your private keys and RPC URLs

# 3. Install dependencies
pnpm install

# 4. Start services individually
cargo run --bin rofl-enclave &
pnpm mock:walrus &
pnpm dev &
```

## 🛠️ Development Workflow

### Development Commands

```bash
# Development Environment
pnpm devnet:up              # Start all services
pnpm devnet:down            # Stop all services  
pnpm devnet:restart         # Restart all services
pnpm devnet:logs            # View all logs
pnpm devnet:status          # Check service status

# Docker Environment  
pnpm docker:up              # Start with Docker Compose
pnpm docker:down            # Stop Docker services
pnpm docker:logs            # View Docker logs
pnpm docker:clean           # Clean Docker resources

# Testing
pnpm test                   # Run all tests
pnpm test:components        # Test React components
pnpm test:integration       # Integration tests
pnpm test:storage           # Storage system tests
pnpm lint                   # Run linter
pnpm type-check             # TypeScript check
```

### Multi-Chain Deployment

```bash
# Deploy to all networks
pnpm deploy:all

# Deploy to specific networks
pnpm deploy:sui             # Sui testnet only
pnpm deploy:zircuit         # Zircuit testnet only  
pnpm deploy:celo            # Celo Alfajores only

# Dry run (test without deploying)
pnpm deploy:dry-run

# Manual deployment steps
./scripts/deploy-all.sh --all --dry-run
./scripts/deploy-all.sh --sui --zircuit
```

### Build & Test Individual Components

#### 1. ROFL TEE Enclave
```bash
cargo build --release       # Build Rust enclave
cargo test                  # Run Rust tests
cargo run --bin rofl-enclave # Start enclave
```

#### 2. Sui Move Contracts
```bash
sui move build              # Build Move packages
sui move test               # Run Move tests
sui client publish --gas-budget 100000000 # Deploy
```

#### 3. Solidity Contracts
```bash
forge build                 # Build contracts
forge test                  # Run tests
forge script scripts/deploy.ts --broadcast # Deploy
```

#### 4. Frontend DApp
```bash
pnpm dev                    # Development server
pnpm build                  # Production build
pnpm test                   # Unit tests
```

## 📱 imToken Wallet Integration

### Deep Link Testing

GreenShare integrates with imToken wallet for seamless mobile payments and cross-chain transfers. Here's how to test the imToken integration:

#### 1. Mobile Testing (Recommended)

**On Physical Device:**
```bash
# 1. Install imToken on your mobile device
# iOS: https://apps.apple.com/app/imtoken2/id1384798940
# Android: https://play.google.com/store/apps/details?id=im.token.app

# 2. Open GreenShare in mobile browser
https://app.greenshare.energy/pay

# 3. Test payment deep links
# The app will automatically detect imToken and show payment options
```

**Deep Link Examples:**
```bash
# Connect wallet
imtoken://dapp?dappUrl=https://app.greenshare.energy&dappName=GreenShare

# One-click payment for 10 sKWH
imtoken://send?address=0x742d35cc6cf004b4d6e8b0b1c5b2e7a5&amount=0.005&chainId=48899

# Cross-chain bridge sKWH → eKWH
imtoken://crosschain?fromChain=101&toChain=48899&token=sKWH&amount=100&recipient=0x742d35cc6cf004b4d6e8b0b1c5b2e7a5
```

#### 2. Desktop Testing (Simulation)

**Using Browser Developer Tools:**
```bash
# 1. Open Chrome DevTools
# 2. Toggle Device Toolbar (Ctrl+Shift+M)
# 3. Select mobile device (iPhone 12 Pro recommended)
# 4. Navigate to payment page
npm run dev
# Go to: http://localhost:3000/pay

# 5. Test deep link generation
# Links will be generated but won't open imToken on desktop
```

**Manual Deep Link Testing:**
```javascript
// Test in browser console
const testLink = 'imtoken://send?address=0x742d35cc6cf004b4d6e8b0b1c5b2e7a5&amount=0.005';
window.open(testLink, '_self');
// This will show "Protocol not supported" on desktop but works on mobile
```

#### 3. QR Code Testing

```bash
# Generate QR codes for payment
# Visit: http://localhost:3000/pay
# Click "Generate QR Code" button
# Scan with imToken mobile app
```

#### 4. Integration Testing

**Standalone Test Page:**
```bash
# Open the dedicated test page
http://localhost:3000/demo/imtoken-test.html

# This page provides:
# - Device detection
# - Deep link generation
# - QR code testing
# - Real-time result logging
```

**Test Payment Wizard:**
```typescript
// Mobile-first payment flow
// 1. Go to /pay page on mobile device
// 2. Select payment type in wizard
// 3. Choose amount
// 4. Confirm and pay via imToken

// Desktop testing
import { ImTokenPaymentWizard } from '@/components/ImTokenDeepLink';
```

**Test Cross-Chain Bridge:**
```typescript
// Mobile bridge flow
// 1. Go to /bridge page on mobile
// 2. Configure bridge parameters
// 3. Use mobile flow for seamless UX

// Desktop bridge interface
// 1. Select networks (Sui → Zircuit)
// 2. Choose tokens (sKWH → eKWH)
// 3. Enter amount
// 4. Click "Bridge via imToken"
```

**Comprehensive Testing Checklist:**
```bash
✅ Device Detection
   - Mobile vs Desktop identification
   - imToken app detection
   - Platform detection (iOS/Android)

✅ Deep Link Generation
   - Connection links (imtoken://dapp?...)
   - Payment links (imtoken://send?...)
   - Cross-chain links (imtoken://crosschain?...)

✅ Mobile UX Flow
   - Payment wizard (3-step process)
   - Bridge interface (mobile-optimized)
   - QR code fallback option

✅ Error Handling
   - No imToken installed
   - Desktop fallback behavior
   - Payment failure scenarios

✅ Real Device Testing
   - iOS Safari + imToken
   - Android Chrome + imToken
   - Deep link callback handling
```

### Troubleshooting imToken Integration

**Common Issues:**

1. **Deep Links Not Working on Desktop**
   ```bash
   # Expected behavior - deep links only work on mobile
   # Use mobile device or mobile simulator for testing
   ```

2. **imToken Not Detected**
   ```bash
   # Install imToken mobile app first
   # Ensure you're testing on mobile device
   # Check browser console for detection logs
   ```

3. **Payment Fails**
   ```bash
   # Ensure wallet has sufficient balance
   # Check network configuration (Zircuit testnet)
   # Verify contract addresses in .env
   ```

**Debug Mode:**
```typescript
// Enable debug mode in imToken provider
// Check browser console for detailed logs
console.log('imToken detection:', {
  isAvailable: true,
  isMobile: true,
  platform: 'ios',
  userAgent: navigator.userAgent
});
```

### Production Deployment

**Configure imToken Integration:**
```bash
# Set production URLs in .env
NEXT_PUBLIC_IMTOKEN_SCHEME=imtoken://
NEXT_PUBLIC_IMTOKEN_CALLBACK_URL=https://app.greenshare.energy/callback
NEXT_PUBLIC_APP_NAME=GreenShare

# Deploy with mobile-optimized URLs
# Ensure HTTPS for production deep links
```

## 📋 Usage Examples

### 1. Smart Meter Data Ingestion

```rust
// ROFL enclave receives meter data
let meter_data = SignedMeterData {
    record: MeterRecord {
        meter_id: "meter_001".to_string(),
        timestamp: 1700000000,
        kwh_delta: 1.234,
        nonce: "unique_nonce".to_string(),
    },
    sig: "ecdsa_signature".to_string(),
};

// POST /api/v1/ingest
```

### 2. Mint sKWH Tokens on Sui

```move
// Mint sKWH tokens from verified certificate
let skwh_coin = sKWH::mint_skwh(
    &admin_cap,
    &mut registry,
    certificate_id,
    kwh_amount,
    proof_data,
    walrus_blob_url,
    &clock,
    ctx
);
```

### 3. Bridge to Zircuit

```typescript
// Bridge sKWH to eKWH on Zircuit
const bridgeRequest = await bridgeContract.bridge(
  amount,
  recipient,
  suiTxDigest
);
```

### 4. Trade on Gud Engine

```solidity
// Execute trade through Gud adapter
IGudTradingEngine.Order memory order = IGudTradingEngine.Order({
    trader: msg.sender,
    tokenIn: address(eKWHToken),
    tokenOut: usdcAddress,
    amountIn: 100e18,
    minAmountOut: 95e6,
    deadline: block.timestamp + 3600,
    signature: signature
});

OrderResult memory result = gudAdapter.placeOrder(
    order.tokenIn,
    order.tokenOut,
    order.amountIn,
    order.minAmountOut,
    order.deadline
);
```

### 5. One-Click Payment with imToken

```tsx
// React component for imToken integration
<ImTokenPayButton
  payment={{
    recipient: "0x742d35cc6cf004b4d6e8b0b1c5b2e7a5",
    amount: "0.01",
    token: eKWHContractAddress,
    chainId: 48899
  }}
  onSuccess={(txHash) => console.log("Payment successful:", txHash)}
>
  Buy 100 eKWH
</ImTokenPayButton>
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

Our CI/CD pipeline automatically runs on every push and pull request:

```yaml
✅ Lint & Type Check      # ESLint, Prettier, TypeScript
✅ Rust Tests             # Cargo test, Clippy, Format check  
✅ Sui Move Tests         # Move test, Build verification
✅ Solidity Tests         # Forge test, Gas reports
✅ Frontend Tests         # Jest, Component tests
✅ Integration Tests      # End-to-end testing
✅ Security Audit         # npm audit, cargo audit, Slither
✅ Docker Build           # Multi-stage builds
🚀 Auto Deploy           # Staging deployment on main branch
```

### Running CI Locally

```bash
# Run all CI checks locally
./scripts/ci-local.sh

# Individual CI steps
pnpm lint                   # Linting
pnpm type-check            # Type checking  
cargo test                 # Rust tests
sui move test              # Move tests
forge test                 # Solidity tests
pnpm test                  # Frontend tests
pnpm test:integration      # Integration tests
```

### Deployment Pipeline

```bash
# Automatic deployment on main branch
git push origin main

# Manual deployment
pnpm deploy:all --dry-run   # Test deployment
pnpm deploy:all             # Deploy to testnets

# Environment-specific deployments
pnpm deploy:staging         # Deploy to staging
pnpm deploy:production      # Deploy to production
```

## 🧪 Testing

### Comprehensive Test Suite

```bash
# Run all tests
pnpm test:all

# Unit Tests
cargo test                  # Rust unit tests
sui move test              # Move unit tests  
forge test                 # Solidity unit tests
pnpm test                  # TypeScript unit tests

# Integration Tests  
pnpm test:integration      # API integration tests
pnpm test:storage          # Storage system tests
pnpm test:e2e              # End-to-end tests

# Performance Tests
cargo bench                # Rust benchmarks
pnpm test:performance      # Frontend performance
```

### Test Coverage

```bash
# Generate coverage reports
cargo tarpaulin            # Rust coverage
pnpm test:coverage         # TypeScript coverage
forge coverage             # Solidity coverage

# View reports
open coverage/lcov-report/index.html
```

### Integration Tests

```bash
# Full integration test
cargo test integration_test

# Test smart meter simulation
npm run test:meter

# Test cross-chain flow
npm run test:bridge
```

### Load Testing

```bash
# Simulate multiple meters
METER_COUNT=100 npm run simulate

# Load test ROFL endpoint
artillery run loadtest.yml
```

## 🔒 Security Features

### 1. TEE Verification
- **ROFL Enclave**: Trusted execution environment for data aggregation
- **Signature Validation**: ECDSA verification of meter data
- **Replay Protection**: Nonce-based duplicate prevention
- **Time Windows**: Configurable aggregation periods

### 2. Smart Contract Security
- **Access Control**: Role-based permissions
- **Reentrancy Guards**: Protection against reentrancy attacks
- **Overflow Protection**: SafeMath/built-in overflow checks
- **Emergency Pause**: Circuit breaker functionality

### 3. Cross-Chain Security
- **Merkle Proofs**: Cryptographic verification of cross-chain transfers
- **Time Locks**: Delayed execution for security
- **Multi-Signature**: Required approvals for admin functions
- **Rate Limiting**: Protection against spam attacks

## 📊 Monitoring & Analytics

### Health Checks

```bash
# ROFL enclave health
curl http://localhost:8080/health

# Contract deployment verification
forge verify-contract <address> <contract> --chain-id 48899

# Frontend monitoring
curl https://app.greenshare.energy/api/health
```

### Metrics & Logs

```bash
# View enclave logs
tail -f /var/log/rofl-enclave.log

# Monitor blockchain events
sui client events --package <package-id>

# Frontend analytics
pnpm run analyze
```

## 🌐 Network Configuration

### Testnet Addresses

```yaml
Sui Testnet:
  RPC: https://fullnode.testnet.sui.io:443
  Package: 0x<SUI_PACKAGE_ID>
  Registry: 0x<SUI_SKWH_REGISTRY>

Zircuit Testnet:
  RPC: https://zircuit-testnet.drpc.org
  Chain ID: 48899
  eKWH: 0x<ZIRCUIT_EKWH_CONTRACT>
  Bridge: 0x<ZIRCUIT_BRIDGE_CONTRACT>

Celo Alfajores:
  RPC: https://alfajores-forno.celo-testnet.org
  Chain ID: 44787
  KYC Registry: 0x<CELO_KYC_REGISTRY>
```

### Mainnet Deployment

```bash
# Deploy to production networks
SUI_NETWORK=mainnet sui client publish
ZIRCUIT_RPC_URL=https://zircuit.drpc.org forge script script/Deploy.s.sol --broadcast
```

## 🤝 Contributing

### Development Workflow

1. **Fork & Clone**
```bash
git clone https://github.com/your-username/greenshare.git
cd greenshare
```

2. **Create Feature Branch**
```bash
git checkout -b feature/new-feature
```

3. **Development**
```bash
pnpm install
pnpm dev
```

4. **Testing**
```bash
pnpm test
cargo test
forge test
sui move test
```

5. **Submit PR**
```bash
git push origin feature/new-feature
# Create pull request on GitHub
```

### Code Standards

- **Rust**: `cargo fmt && cargo clippy`
- **TypeScript**: `pnpm lint:fix`
- **Solidity**: `forge fmt`
- **Move**: `sui move build` (built-in formatting)

## 📚 Documentation

### API Reference

- **ROFL API**: `/docs/api/rofl.md`
- **Sui Contracts**: `/docs/api/sui.md`
- **Zircuit Contracts**: `/docs/api/zircuit.md`
- **Frontend SDK**: `/docs/api/frontend.md`

### Tutorials

- **Setup Guide**: `/docs/tutorials/setup.md`
- **Smart Meter Integration**: `/docs/tutorials/meter.md`
- **Cross-Chain Bridging**: `/docs/tutorials/bridge.md`
- **Trading Integration**: `/docs/tutorials/trading.md`

## 🐛 Troubleshooting

### Common Issues

1. **ROFL Enclave Not Starting**
```bash
# Check port availability
netstat -tlnp | grep 8080

# Verify environment variables
source .env && echo $ROFL_ENDPOINT
```

2. **Sui Transaction Failures**
```bash
# Check gas balance
sui client gas

# Verify object ownership
sui client object <object-id>
```

3. **Cross-Chain Bridge Issues**
```bash
# Check bridge contract state
cast call $BRIDGE_CONTRACT "getBridgeStatus(bytes32)" $REQUEST_ID

# Verify signatures
cast call $BRIDGE_CONTRACT "verifySignature(bytes32,bytes)" $HASH $SIGNATURE
```

4. **Frontend Connection Issues**
```bash
# Clear browser cache and reconnect wallets
# Check network configuration in wallet
# Verify RPC endpoints are accessible
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Website**: [https://greenshare.energy](https://greenshare.energy)
- **Documentation**: [https://docs.greenshare.energy](https://docs.greenshare.energy)
- **Discord**: [https://discord.gg/greenshare](https://discord.gg/greenshare)
- **Twitter**: [@GreenShareEnergy](https://twitter.com/GreenShareEnergy)

## 🏆 Acknowledgments

- **Oasis Protocol** for ROFL TEE infrastructure
- **Sui Foundation** for Move smart contract platform
- **Zircuit** for L2 scaling solution
- **Celo** for identity verification tools
- **Walrus** for decentralized storage
- **imToken** for mobile wallet integration
- **Gud Trading Engine** for DEX infrastructure

---

**GreenShare** - Powering the future of renewable energy 🌱⚡# RWA_GreenShare
