// FILE: lib/hooks/useBalances.ts
import { useState, useEffect, useCallback } from 'react';
import { useAccount, useBalance } from 'wagmi';
import { SuiClient, getFullnodeUrl } from '@mysten/sui.js/client';
import CONTRACT_ADDRESSES from '../config/contracts';

export interface Balances {
  sKWH: number;
  eKWH: number;
  SUI: number;
  ETH: number;
  CELO: number;
}

export function useBalances() {
  const [balances, setBalances] = useState<Balances>({
    sKWH: 0,
    eKWH: 0,
    SUI: 0,
    ETH: 0,
    CELO: 0,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // EVM wallet connection
  const { address: evmAddress, isConnected: isEvmConnected } = useAccount();
  
  // Mock Sui account for now (replace with actual wallet integration)
  const suiAccount = { address: 'mock_sui_address' };

  // EVM balances
  const { data: ethBalance } = useBalance({
    address: evmAddress,
    enabled: isEvmConnected,
  });

  const { data: eKWHBalance } = useBalance({
    address: evmAddress,
    token: CONTRACT_ADDRESSES.zircuit.testnet.eKWH,
    enabled: isEvmConnected,
  });

  // Mock function to get sKWH balance (would use actual Sui contract call)
  const getSKWHBalance = useCallback(async () => {
    if (!suiAccount?.address) return 0;
    
    // Implement actual sKWH balance query using Sui SDK
    try {
      const client = new SuiClient({ url: getFullnodeUrl('testnet') });
      const objects = await client.getOwnedObjects({
        owner: suiAccount.address,
        filter: {
          StructType: `${process.env.NEXT_PUBLIC_SUI_PACKAGE_ID}::sKWH::sKWH`
        }
      });
      
      let totalBalance = 0;
      for (const obj of objects.data) {
        const details = await client.getObject({
          id: obj.data?.objectId!,
          options: { showContent: true }
        });
        if (details.data?.content && 'fields' in details.data.content) {
          totalBalance += Number((details.data.content.fields as any).balance || 0);
        }
      }
      return totalBalance / 1000000; // Convert from micro units
    } catch (error) {
      console.error('Failed to fetch sKWH balance:', error);
      return 0;
    }
    // For now, return mock data
    return Math.random() * 1000 + 500; // Mock balance between 500-1500
  }, [suiAccount?.address]);

  const refresh = useCallback(async () => {
    if (!isEvmConnected && !suiAccount) {
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const newBalances: Balances = {
        sKWH: 0,
        eKWH: 0,
        SUI: 0,
        ETH: 0,
        CELO: 0,
      };

      // Update EVM balances
      if (isEvmConnected) {
        if (ethBalance) {
          newBalances.ETH = parseFloat(ethBalance.formatted);
        }
        if (eKWHBalance) {
          newBalances.eKWH = parseFloat(eKWHBalance.formatted);
        }
      }

      // Update Sui balances
      if (suiAccount) {
        // Mock SUI balance for now
        newBalances.SUI = Math.random() * 100 + 50; // Mock 50-150 SUI
        
        // Get sKWH balance
        const sKWHBal = await getSKWHBalance();
        newBalances.sKWH = sKWHBal;
      }

      setBalances(newBalances);
    } catch (err) {
      console.error('Error fetching balances:', err);
      setError('Failed to fetch balances');
    } finally {
      setLoading(false);
    }
  }, [isEvmConnected, suiAccount, ethBalance, eKWHBalance, getSKWHBalance]);

  // Auto-refresh balances when wallet connections change
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Auto-refresh every 30 seconds
  useEffect(() => {
    const interval = setInterval(refresh, 30000);
    return () => clearInterval(interval);
  }, [refresh]);

  return {
    balances,
    loading,
    error,
    refresh,
  };
}