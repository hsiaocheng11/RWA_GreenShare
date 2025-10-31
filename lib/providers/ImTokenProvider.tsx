// FILE: lib/providers/ImTokenProvider.tsx
import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import { toast } from 'react-hot-toast';

interface ImTokenConfig {
  scheme: string;
  callbackUrl: string;
  appName: string;
}

interface TransactionRequest {
  to: string;
  value?: string;
  data?: string;
  chainId?: number;
  gasLimit?: string;
  gasPrice?: string;
}

interface CrossChainRequest {
  fromChain: number;
  toChain: number;
  token: string;
  amount: string;
  recipient: string;
}

interface ImTokenContextType {
  isImTokenAvailable: boolean;
  isConnected: boolean;
  address?: string;
  sendTransaction: (request: TransactionRequest) => Promise<string>;
  crossChainTransfer: (request: CrossChainRequest) => Promise<string>;
  connect: () => Promise<void>;
  disconnect: () => void;
  openImToken: (path?: string) => void;
}

const ImTokenContext = createContext<ImTokenContextType | undefined>(undefined);

const DEFAULT_CONFIG: ImTokenConfig = {
  scheme: process.env.NEXT_PUBLIC_IMTOKEN_SCHEME || 'imtoken://',
  callbackUrl: process.env.NEXT_PUBLIC_IMTOKEN_CALLBACK_URL || 'https://app.greenshare.energy/callback',
  appName: process.env.NEXT_PUBLIC_APP_NAME || 'GreenShare'
};

export function ImTokenProvider({ children }: { children: React.ReactNode }) {
  const [isConnected, setIsConnected] = useState(false);
  const [address, setAddress] = useState<string>();
  const [isImTokenAvailable, setIsImTokenAvailable] = useState(false);

  // Check if imToken is available
  useEffect(() => {
    const checkImToken = () => {
      // Check if we're in a mobile environment and imToken might be available
      const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
      const hasImTokenUA = navigator.userAgent.includes('imToken');
      
      setIsImTokenAvailable(isMobile || hasImTokenUA);
    };

    checkImToken();
  }, []);

  // Listen for callback messages
  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      if (event.data?.type === 'IMTOKEN_RESPONSE') {
        handleImTokenResponse(event.data);
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  const handleImTokenResponse = useCallback((data: any) => {
    switch (data.method) {
      case 'connect':
        if (data.success && data.address) {
          setIsConnected(true);
          setAddress(data.address);
          toast.success('Connected to imToken wallet');
        } else {
          toast.error('Failed to connect to imToken');
        }
        break;
      
      case 'sendTransaction':
        if (data.success) {
          toast.success(`Transaction sent: ${data.txHash}`);
        } else {
          toast.error(`Transaction failed: ${data.error}`);
        }
        break;
      
      case 'crossChain':
        if (data.success) {
          toast.success(`Cross-chain transfer initiated: ${data.txHash}`);
        } else {
          toast.error(`Cross-chain transfer failed: ${data.error}`);
        }
        break;
    }
  }, []);

  const openImToken = useCallback((path: string = '') => {
    const url = `${DEFAULT_CONFIG.scheme}${path}`;
    
    if (isImTokenAvailable) {
      window.open(url, '_self');
    } else {
      // Fallback: open imToken download page
      window.open('https://token.im/', '_blank');
      toast.info('Please install imToken to continue');
    }
  }, [isImTokenAvailable]);

  const connect = useCallback(async () => {
    if (!isImTokenAvailable) {
      toast.error('imToken is not available');
      return;
    }

    const connectParams = {
      method: 'connect',
      params: {
        dappName: DEFAULT_CONFIG.appName,
        dappUrl: DEFAULT_CONFIG.callbackUrl,
        chainIds: [1, 56, 137, 42220, 48899], // ETH, BSC, Polygon, Celo, Zircuit
      }
    };

    const connectUrl = `${DEFAULT_CONFIG.scheme}dapp/connect?${encodeURIComponent(JSON.stringify(connectParams))}`;
    openImToken(`dapp/connect?${encodeURIComponent(JSON.stringify(connectParams))}`);
  }, [isImTokenAvailable, openImToken]);

  const disconnect = useCallback(() => {
    setIsConnected(false);
    setAddress(undefined);
    toast.success('Disconnected from imToken');
  }, []);

  const sendTransaction = useCallback(async (request: TransactionRequest): Promise<string> => {
    if (!isConnected) {
      throw new Error('Wallet not connected');
    }

    return new Promise((resolve, reject) => {
      const txParams = {
        method: 'sendTransaction',
        params: {
          from: address,
          to: request.to,
          value: request.value || '0x0',
          data: request.data || '0x',
          chainId: request.chainId || 1,
          gasLimit: request.gasLimit,
          gasPrice: request.gasPrice,
        },
        callbackUrl: DEFAULT_CONFIG.callbackUrl,
      };

      // Listen for response
      const handleTxResponse = (event: MessageEvent) => {
        if (event.data?.type === 'IMTOKEN_RESPONSE' && event.data.method === 'sendTransaction') {
          window.removeEventListener('message', handleTxResponse);
          
          if (event.data.success) {
            resolve(event.data.txHash);
          } else {
            reject(new Error(event.data.error || 'Transaction failed'));
          }
        }
      };

      window.addEventListener('message', handleTxResponse);

      // Open imToken with transaction
      const txUrl = `dapp/transaction?${encodeURIComponent(JSON.stringify(txParams))}`;
      openImToken(txUrl);

      // Cleanup after timeout
      setTimeout(() => {
        window.removeEventListener('message', handleTxResponse);
        reject(new Error('Transaction timeout'));
      }, 60000);
    });
  }, [isConnected, address, openImToken]);

  const crossChainTransfer = useCallback(async (request: CrossChainRequest): Promise<string> => {
    if (!isConnected) {
      throw new Error('Wallet not connected');
    }

    return new Promise((resolve, reject) => {
      const crossChainParams = {
        method: 'crossChain',
        params: {
          fromChain: request.fromChain,
          toChain: request.toChain,
          token: request.token,
          amount: request.amount,
          recipient: request.recipient,
          sender: address,
        },
        callbackUrl: DEFAULT_CONFIG.callbackUrl,
      };

      // Listen for response
      const handleCrossChainResponse = (event: MessageEvent) => {
        if (event.data?.type === 'IMTOKEN_RESPONSE' && event.data.method === 'crossChain') {
          window.removeEventListener('message', handleCrossChainResponse);
          
          if (event.data.success) {
            resolve(event.data.txHash);
          } else {
            reject(new Error(event.data.error || 'Cross-chain transfer failed'));
          }
        }
      };

      window.addEventListener('message', handleCrossChainResponse);

      // Open imToken with cross-chain transfer
      const crossChainUrl = `dapp/crosschain?${encodeURIComponent(JSON.stringify(crossChainParams))}`;
      openImToken(crossChainUrl);

      // Cleanup after timeout
      setTimeout(() => {
        window.removeEventListener('message', handleCrossChainResponse);
        reject(new Error('Cross-chain transfer timeout'));
      }, 120000);
    });
  }, [isConnected, address, openImToken]);

  const value: ImTokenContextType = {
    isImTokenAvailable,
    isConnected,
    address,
    sendTransaction,
    crossChainTransfer,
    connect,
    disconnect,
    openImToken,
  };

  return (
    <ImTokenContext.Provider value={value}>
      {children}
    </ImTokenContext.Provider>
  );
}

export function useImToken() {
  const context = useContext(ImTokenContext);
  if (context === undefined) {
    throw new Error('useImToken must be used within an ImTokenProvider');
  }
  return context;
}

// Helper hook for one-click payment
export function useImTokenPayment() {
  const { sendTransaction, crossChainTransfer, isConnected } = useImToken();

  const payWithImToken = useCallback(async (
    recipient: string,
    amount: string,
    token?: string,
    chainId?: number
  ) => {
    if (!isConnected) {
      throw new Error('Please connect imToken wallet first');
    }

    const txRequest: TransactionRequest = {
      to: recipient,
      value: token ? '0x0' : amount,
      chainId: chainId || 1,
    };

    // If it's an ERC20 token, encode transfer data
    if (token) {
      // Encode ERC20 transfer function call
      // transfer(address to, uint256 amount) = 0xa9059cbb
      const transferSelector = '0xa9059cbb';
      const addressParam = recipient.slice(2).padStart(64, '0');
      const amountHex = BigInt(amount).toString(16).padStart(64, '0');
      const transferData = `${transferSelector}${addressParam}${amountHex}`;
      txRequest.to = token;
      txRequest.data = transferData;
    }

    return sendTransaction(txRequest);
  }, [sendTransaction, isConnected]);

  const crossChainPay = useCallback(async (
    fromChain: number,
    toChain: number,
    token: string,
    amount: string,
    recipient: string
  ) => {
    if (!isConnected) {
      throw new Error('Please connect imToken wallet first');
    }

    return crossChainTransfer({
      fromChain,
      toChain,
      token,
      amount,
      recipient,
    });
  }, [crossChainTransfer, isConnected]);

  return {
    payWithImToken,
    crossChainPay,
  };
}