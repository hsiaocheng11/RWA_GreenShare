// FILE: lib/config/contracts.ts
import { Address } from 'viem';

// Contract interface definitions
export interface ContractConfig {
  address: Address;
  abi: any[];
  deploymentBlock?: number;
}

export interface SuiContractConfig {
  packageId: string;
  objectId?: string;
}

// Zircuit contract addresses and ABIs
export const ZIRCUIT_CONTRACTS = {
  testnet: {
    eKWH: {
      address: (process.env.NEXT_PUBLIC_ZIRCUIT_EKWH_ADDRESS || '0x') as Address,
      abi: [
        'function balanceOf(address) view returns (uint256)',
        'function transfer(address to, uint256 amount) returns (bool)',
        'function approve(address spender, uint256 amount) returns (bool)',
        'function allowance(address owner, address spender) view returns (uint256)',
        'function bridgeIn(address to, uint256 amount, bytes32 operationId, string suiTxHash)',
        'function bridgeOut(uint256 amount, bytes32 operationId, string suiAddress)',
        'function getBridgeStats() view returns (uint256 bridgedIn, uint256 bridgedOut, uint256 netSupply)',
        'function totalSupply() view returns (uint256)',
        'function decimals() view returns (uint8)',
        'event Transfer(address indexed from, address indexed to, uint256 value)',
        'event BridgedIn(address indexed recipient, uint256 amount, bytes32 indexed operationId, string suiTxHash, uint256 timestamp)',
        'event BridgedOut(address indexed sender, uint256 amount, bytes32 indexed operationId, string suiAddress, uint256 timestamp)'
      ],
    },
    bridge: {
      address: (process.env.NEXT_PUBLIC_ZIRCUIT_BRIDGE_ADDRESS || '0x') as Address,
      abi: [
        'function processBridgeIn(tuple(bytes32 merkleRoot, uint256 blockHeight, uint256 timestamp, bytes signature, string proofHash) proof, tuple(address recipient, uint256 amount, bytes32 operationId, string suiTxHash) operation)',
        'function initiateBridgeOut(uint256 amount, string suiAddress)',
        'function getBridgeStats() view returns (tuple(uint256 totalOperations, uint256 totalVolume, uint256 successfulOperations, uint256 failedOperations))',
        'function calculateFee(uint256 amount) view returns (uint256)',
        'function isOperationProcessed(bytes32 operationId) view returns (bool)',
        'function minBridgeAmount() view returns (uint256)',
        'function maxBridgeAmount() view returns (uint256)',
        'event BridgeOperationCompleted(bytes32 indexed operationId, address indexed recipient, uint256 amount, uint256 actualAmount, uint256 timestamp)',
        'event BridgeOperationFailed(bytes32 indexed operationId, address indexed recipient, string reason, uint256 timestamp)'
      ],
    },
    gudAdapter: {
      address: (process.env.NEXT_PUBLIC_ZIRCUIT_GUD_ADAPTER_ADDRESS || '0x') as Address,
      abi: [
        'function createEKWHPool(address tokenPair, uint24 feeTier) returns (address pool)',
        'function addEKWHLiquidity(address tokenPair, uint256 ekwhAmount, uint256 pairAmount, uint256 minEKWH, uint256 minPair, uint256 deadline) returns (uint128 liquidity)',
        'function swapToEKWH(address tokenIn, uint256 amountIn, uint256 amountOutMin, uint256 deadline) returns (uint256 amountOut)',
        'function swapFromEKWH(address tokenOut, uint256 amountIn, uint256 amountOutMin, uint256 deadline) returns (uint256 amountOut)',
        'function getQuoteToEKWH(address tokenIn, uint256 amountIn) view returns (uint256 amountOut)',
        'function getQuoteFromEKWH(address tokenOut, uint256 amountIn) view returns (uint256 amountOut)',
        'function ekwhPoolExists(address tokenPair, uint24 feeTier) view returns (bool exists)',
        'function getUserStats(address user) view returns (tuple(uint256 totalTrades, uint256 totalVolume, uint256 totalLiquidityProvided, uint256 totalLiquidityRemoved))',
        'event EKWHTrade(address indexed trader, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 timestamp)',
        'event EKWHLiquidityAdded(address indexed provider, address indexed tokenPair, uint256 ekwhAmount, uint256 pairAmount, uint128 liquidity, uint256 timestamp)'
      ],
    },
  },
  mainnet: {
    // TODO: Add mainnet addresses
    eKWH: {
      address: '0x' as Address,
      abi: [], // Same ABI as testnet
    },
    bridge: {
      address: '0x' as Address,
      abi: [], // Same ABI as testnet
    },
    gudAdapter: {
      address: '0x' as Address,
      abi: [], // Same ABI as testnet
    },
  },
};

// Celo contract addresses and ABIs
export const CELO_CONTRACTS = {
  alfajores: {
    verifier: {
      address: (process.env.NEXT_PUBLIC_CELO_VERIFIER_ADDRESS || '0x') as Address,
      abi: [
        'function verifyProof(tuple(string proofType, bytes proofData, uint256[] publicSignals, bytes32 nullifierHash, bytes32 merkleRoot) proof) returns (tuple(bool isValid, bytes32 proofHash, uint256 timestamp))',
        'function getSupportedProofTypes() view returns (string[])',
        'function getKYCRequirements() view returns (tuple(bool requireAgeProof, bool requireSanctionsProof, bool requireCountryProof, string[] allowedCountries, uint256 minAge))',
        'function getVerificationResult(address user, string proofType) view returns (tuple(bool isValid, bytes32 proofHash, uint256 timestamp))',
        'function isUserKYCCompleted(address user) view returns (bool completed)',
        'event ProofVerified(address indexed user, bytes32 indexed proofHash, string proofType, bytes32 nullifierHash, uint256 timestamp)',
        'event ProofRejected(address indexed user, string proofType, string reason, uint256 timestamp)'
      ],
    },
    kycRegistry: {
      address: (process.env.NEXT_PUBLIC_CELO_KYC_REGISTRY_ADDRESS || '0x') as Address,
      abi: [
        'function processKYCVerification(address user, string[] proofTypes)',
        'function getUserKYCInfo(address user) view returns (tuple(uint8 kycLevel, bool isWhitelisted, uint256 bridgeLimit, uint256 tradingLimit, uint256 lastVerification, uint256 verificationExpiry, string[] completedProofs, bool isActive))',
        'function isWhitelisted(address user) view returns (bool)',
        'function getKYCLevel(address user) view returns (uint8)',
        'function getBridgeLimit(address user) view returns (uint256)',
        'function getTradingLimit(address user) view returns (uint256)',
        'function isCrossChainWhitelisted(address user, string chain) view returns (bool)',
        'function getKYCStats() view returns (tuple(uint256 totalUsers, uint256 whitelistedUsers, uint256 basicKYCUsers, uint256 enhancedKYCUsers, uint256 premiumKYCUsers))',
        'event KYCStatusUpdated(address indexed user, uint8 oldLevel, uint8 newLevel, bool whitelisted, uint256 timestamp)',
        'event CrossChainWhitelistUpdated(address indexed user, string chain, bool whitelisted, uint256 timestamp)'
      ],
    },
  },
  mainnet: {
    // TODO: Add mainnet addresses
    verifier: {
      address: '0x' as Address,
      abi: [], // Same ABI as alfajores
    },
    kycRegistry: {
      address: '0x' as Address,
      abi: [], // Same ABI as alfajores
    },
  },
};

// Sui contract configurations
export const SUI_CONTRACTS = {
  testnet: {
    sKWH: {
      packageId: process.env.NEXT_PUBLIC_SUI_SKWH_PACKAGE_ID || '0x',
      treasuryCapId: '0x',
      quotaLedgerId: '0x',
      adminCapId: '0x',
    },
    certificate: {
      packageId: process.env.NEXT_PUBLIC_SUI_CERTIFICATE_PACKAGE_ID || '0x',
      publisherCapId: '0x',
      registryId: '0x',
      transferPolicyId: '0x',
    },
    walrusSeal: {
      packageId: process.env.NEXT_PUBLIC_SUI_WALRUS_PACKAGE_ID || '0x',
      blobRegistryId: '0x',
      adminCapId: '0x',
    },
  },
  mainnet: {
    // Production mainnet package IDs - deploy packages to mainnet first
    mainnet: {
      packageId: process.env.SUI_MAINNET_PACKAGE_ID || '<SUI_MAINNET_PACKAGE_ID>',
      sKWH: process.env.SUI_MAINNET_SKWH_REGISTRY || '<SUI_MAINNET_SKWH_REGISTRY>',
      Certificate: process.env.SUI_MAINNET_CERTIFICATE_KIOSK || '<SUI_MAINNET_CERTIFICATE_KIOSK>',
      WalrusSeal: process.env.SUI_MAINNET_WALRUS_SEAL || '<SUI_MAINNET_WALRUS_SEAL>',
    },
    sKWH: {
      packageId: '0x',
      treasuryCapId: '0x',
      quotaLedgerId: '0x',
      adminCapId: '0x',
    },
    certificate: {
      packageId: '0x',
      publisherCapId: '0x',
      registryId: '0x',
      transferPolicyId: '0x',
    },
    walrusSeal: {
      packageId: '0x',
      blobRegistryId: '0x',
      adminCapId: '0x',
    },
  },
};

// Helper functions to get contract configs based on environment
export function getZircuitContracts() {
  return process.env.NODE_ENV === 'production' 
    ? ZIRCUIT_CONTRACTS.mainnet 
    : ZIRCUIT_CONTRACTS.testnet;
}

export function getCeloContracts() {
  return process.env.NODE_ENV === 'production' 
    ? CELO_CONTRACTS.mainnet 
    : CELO_CONTRACTS.alfajores;
}

export function getSuiContracts() {
  return process.env.NODE_ENV === 'production' 
    ? SUI_CONTRACTS.mainnet 
    : SUI_CONTRACTS.testnet;
}

// Contract addresses for easy access
export const CONTRACT_ADDRESSES = {
  zircuit: getZircuitContracts(),
  celo: getCeloContracts(),
  sui: getSuiContracts(),
};

// Token configurations
export interface TokenConfig {
  symbol: string;
  name: string;
  decimals: number;
  address?: Address;
  packageId?: string;
  icon?: string;
}

export const TOKENS: Record<string, TokenConfig> = {
  sKWH: {
    symbol: 'sKWH',
    name: 'Sustainable Kilowatt-Hour',
    decimals: 6,
    packageId: getSuiContracts().sKWH.packageId,
    icon: '/icons/skwh.svg',
  },
  eKWH: {
    symbol: 'eKWH',
    name: 'Ethereum Kilowatt-Hour',
    decimals: 6,
    address: getZircuitContracts().eKWH.address,
    icon: '/icons/ekwh.svg',
  },
  SUI: {
    symbol: 'SUI',
    name: 'Sui',
    decimals: 9,
    icon: '/icons/sui.svg',
  },
  ETH: {
    symbol: 'ETH',
    name: 'Ethereum',
    decimals: 18,
    icon: '/icons/eth.svg',
  },
  CELO: {
    symbol: 'CELO',
    name: 'Celo',
    decimals: 18,
    icon: '/icons/celo.svg',
  },
};

// Service endpoints
export const SERVICE_ENDPOINTS = {
  walrus: {
    publisher: process.env.NEXT_PUBLIC_WALRUS_PUBLISHER_URL || 'https://publisher.walrus-testnet.walrus.space',
    aggregator: process.env.NEXT_PUBLIC_WALRUS_AGGREGATOR_URL || 'https://aggregator.walrus-testnet.walrus.space',
    gateway: process.env.NEXT_PUBLIC_WALRUS_GATEWAY_URL || 'https://walrus.site',
  },
  rofl: {
    endpoint: process.env.NEXT_PUBLIC_ROFL_ENDPOINT || 'http://localhost:8080',
    apiVersion: 'v1',
  },
  analytics: {
    endpoint: process.env.NEXT_PUBLIC_ANALYTICS_API_URL || 'https://analytics.greenshare.example.com',
  },
};

export default CONTRACT_ADDRESSES;