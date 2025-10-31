// FILE: lib/config/chains.ts
import { Chain } from 'wagmi';
import { SuiNetworkConfig } from '@mysten/sui.js/client';

// Custom Zircuit chain configuration
export const zircuitTestnet: Chain = {
  id: 48899,
  name: 'Zircuit Testnet',
  network: 'zircuit-testnet',
  nativeCurrency: {
    decimals: 18,
    name: 'Ethereum',
    symbol: 'ETH',
  },
  rpcUrls: {
    public: { http: ['https://zircuit1-testnet.p2pify.com/'] },
    default: { http: ['https://zircuit1-testnet.p2pify.com/'] },
  },
  blockExplorers: {
    default: { name: 'Zircuit Explorer', url: 'https://explorer.testnet.zircuit.com' },
  },
  testnet: true,
};

export const zircuitMainnet: Chain = {
  id: 48900,
  name: 'Zircuit',
  network: 'zircuit',
  nativeCurrency: {
    decimals: 18,
    name: 'Ethereum',
    symbol: 'ETH',
  },
  rpcUrls: {
    public: { http: ['https://zircuit1-mainnet.p2pify.com/'] },
    default: { http: ['https://zircuit1-mainnet.p2pify.com/'] },
  },
  blockExplorers: {
    default: { name: 'Zircuit Explorer', url: 'https://explorer.zircuit.com' },
  },
  testnet: false,
};

// Celo chain configurations (already supported by wagmi)
export const celoAlfajores: Chain = {
  id: 44787,
  name: 'Celo Alfajores',
  network: 'celo-alfajores',
  nativeCurrency: {
    decimals: 18,
    name: 'Celo',
    symbol: 'CELO',
  },
  rpcUrls: {
    public: { http: ['https://alfajores-forno.celo-testnet.org'] },
    default: { http: ['https://alfajores-forno.celo-testnet.org'] },
  },
  blockExplorers: {
    default: { name: 'Celo Explorer', url: 'https://explorer.celo.org/alfajores' },
  },
  testnet: true,
};

export const celoMainnet: Chain = {
  id: 42220,
  name: 'Celo',
  network: 'celo',
  nativeCurrency: {
    decimals: 18,
    name: 'Celo',
    symbol: 'CELO',
  },
  rpcUrls: {
    public: { http: ['https://forno.celo.org'] },
    default: { http: ['https://forno.celo.org'] },
  },
  blockExplorers: {
    default: { name: 'Celo Explorer', url: 'https://explorer.celo.org' },
  },
  testnet: false,
};

// Sui network configurations
export const suiTestnet: SuiNetworkConfig = {
  name: 'testnet',
  url: process.env.NEXT_PUBLIC_SUI_RPC_URL || 'https://fullnode.testnet.sui.io:443',
};

export const suiMainnet: SuiNetworkConfig = {
  name: 'mainnet', 
  url: 'https://fullnode.mainnet.sui.io:443',
};

// Network configuration type
export interface NetworkConfig {
  id: string;
  name: string;
  chainId?: number;
  rpcUrl: string;
  explorerUrl: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  testnet: boolean;
}

// Supported networks configuration
export const SUPPORTED_NETWORKS: Record<string, NetworkConfig> = {
  sui_testnet: {
    id: 'sui_testnet',
    name: 'Sui Testnet',
    rpcUrl: process.env.NEXT_PUBLIC_SUI_RPC_URL || 'https://fullnode.testnet.sui.io:443',
    explorerUrl: 'https://suiexplorer.com/?network=testnet',
    nativeCurrency: {
      name: 'Sui',
      symbol: 'SUI',
      decimals: 9,
    },
    testnet: true,
  },
  sui_mainnet: {
    id: 'sui_mainnet',
    name: 'Sui Mainnet',
    rpcUrl: 'https://fullnode.mainnet.sui.io:443',
    explorerUrl: 'https://suiexplorer.com',
    nativeCurrency: {
      name: 'Sui',
      symbol: 'SUI',
      decimals: 9,
    },
    testnet: false,
  },
  zircuit_testnet: {
    id: 'zircuit_testnet',
    name: 'Zircuit Testnet',
    chainId: 48899,
    rpcUrl: process.env.NEXT_PUBLIC_ZIRCUIT_RPC_URL || 'https://zircuit1-testnet.p2pify.com/',
    explorerUrl: process.env.NEXT_PUBLIC_ZIRCUIT_EXPLORER_URL || 'https://explorer.testnet.zircuit.com',
    nativeCurrency: {
      name: 'Ethereum',
      symbol: 'ETH',
      decimals: 18,
    },
    testnet: true,
  },
  zircuit_mainnet: {
    id: 'zircuit_mainnet',
    name: 'Zircuit Mainnet',
    chainId: 48900,
    rpcUrl: 'https://zircuit1-mainnet.p2pify.com/',
    explorerUrl: 'https://explorer.zircuit.com',
    nativeCurrency: {
      name: 'Ethereum',
      symbol: 'ETH',
      decimals: 18,
    },
    testnet: false,
  },
  celo_alfajores: {
    id: 'celo_alfajores',
    name: 'Celo Alfajores',
    chainId: 44787,
    rpcUrl: process.env.NEXT_PUBLIC_CELO_RPC_URL || 'https://alfajores-forno.celo-testnet.org',
    explorerUrl: process.env.NEXT_PUBLIC_CELO_EXPLORER_URL || 'https://explorer.celo.org/alfajores',
    nativeCurrency: {
      name: 'Celo',
      symbol: 'CELO',
      decimals: 18,
    },
    testnet: true,
  },
  celo_mainnet: {
    id: 'celo_mainnet',
    name: 'Celo Mainnet',
    chainId: 42220,
    rpcUrl: 'https://forno.celo.org',
    explorerUrl: 'https://explorer.celo.org',
    nativeCurrency: {
      name: 'Celo',
      symbol: 'CELO',
      decimals: 18,
    },
    testnet: false,
  },
};

// Default network based on environment
export const DEFAULT_NETWORK = process.env.NODE_ENV === 'production' 
  ? 'mainnet' 
  : 'testnet';

// Get network configuration by ID
export function getNetworkConfig(networkId: string): NetworkConfig | undefined {
  return SUPPORTED_NETWORKS[networkId];
}

// Check if network is testnet
export function isTestnet(networkId: string): boolean {
  const config = getNetworkConfig(networkId);
  return config?.testnet ?? true;
}

// Get EVM chains for wagmi
export function getEvmChains(): Chain[] {
  const chains: Chain[] = [];
  
  if (process.env.NODE_ENV !== 'production') {
    chains.push(zircuitTestnet, celoAlfajores);
  }
  
  chains.push(zircuitMainnet, celoMainnet);
  
  return chains;
}

// Get current Sui network config
export function getCurrentSuiNetwork(): SuiNetworkConfig {
  return process.env.NODE_ENV === 'production' ? suiMainnet : suiTestnet;
}