// FILE: lib/providers/WalletProviders.tsx
'use client';

import React from 'react';
import { WagmiConfig, createConfig, configureChains } from 'wagmi';
import { publicProvider } from 'wagmi/providers/public';
import { jsonRpcProvider } from 'wagmi/providers/jsonRpc';
import { RainbowKitProvider, getDefaultWallets, connectorsForWallets } from '@rainbow-me/rainbowkit';
import { WalletAdapterNetwork } from '@mysten/wallet-adapter-base';
import { SuiClientProvider, WalletProvider } from '@mysten/dapp-kit';
import { getFullnodeUrl, SuiClient } from '@mysten/sui.js/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

import { getEvmChains, getCurrentSuiNetwork } from '../config/chains';
import '@rainbow-me/rainbowkit/styles.css';

// Configure EVM chains for wagmi
const { chains, publicClient } = configureChains(
  getEvmChains(),
  [
    jsonRpcProvider({
      rpc: (chain) => ({
        http: chain.rpcUrls.default.http[0],
      }),
    }),
    publicProvider(),
  ]
);

// Configure wallets for RainbowKit
const projectId = process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || 'demo-project-id';

const { wallets } = getDefaultWallets({
  appName: 'GreenShare',
  projectId,
  chains,
});

const connectors = connectorsForWallets([
  ...wallets,
]);

// Create wagmi config
const wagmiConfig = createConfig({
  autoConnect: true,
  connectors,
  publicClient,
});

// Configure Sui client
const suiNetwork = getCurrentSuiNetwork();
const suiClient = new SuiClient({
  url: suiNetwork.url,
});

// Configure query client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000, // 1 minute
      retry: 3,
    },
  },
});

interface WalletProvidersProps {
  children: React.ReactNode;
}

export function WalletProviders({ children }: WalletProvidersProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <WagmiConfig config={wagmiConfig}>
        <RainbowKitProvider 
          chains={chains}
          theme={{
            blurredBackground: false,
            borderRadius: 'medium',
            fontStack: 'system',
            overlayBlur: 'small',
          }}
          appInfo={{
            appName: 'GreenShare',
            learnMoreUrl: 'https://docs.greenshare.energy',
          }}
        >
          <SuiClientProvider networks={{ [suiNetwork.name]: suiClient }} defaultNetwork={suiNetwork.name}>
            <WalletProvider
              autoConnect={true}
              stashedWallet={{
                name: 'GreenShare Wallet',
              }}
            >
              {children}
            </WalletProvider>
          </SuiClientProvider>
        </RainbowKitProvider>
      </WagmiConfig>
    </QueryClientProvider>
  );
}

export default WalletProviders;