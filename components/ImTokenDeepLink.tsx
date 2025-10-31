// FILE: components/ImTokenDeepLink.tsx
import React, { useState } from 'react';
import { useImToken, useImTokenPayment } from '../lib/providers/ImTokenProvider';
import { ArrowRightIcon, CreditCardIcon, ArrowsRightLeftIcon } from '@heroicons/react/24/outline';
import { toast } from 'react-hot-toast';
import { clsx } from 'clsx';

interface PaymentRequest {
  recipient: string;
  amount: string;
  token?: string;
  chainId?: number;
  description?: string;
}

interface CrossChainPaymentRequest {
  fromChain: number;
  toChain: number;
  token: string;
  amount: string;
  recipient: string;
  description?: string;
}

interface ImTokenDeepLinkProps {
  className?: string;
  variant?: 'primary' | 'secondary' | 'outline';
  size?: 'sm' | 'md' | 'lg';
}

export default function ImTokenDeepLink({ 
  className,
  variant = 'primary',
  size = 'md'
}: ImTokenDeepLinkProps) {
  const { isImTokenAvailable, isConnected, connect, address } = useImToken();
  const { payWithImToken, crossChainPay } = useImTokenPayment();
  const [isProcessing, setIsProcessing] = useState(false);

  const handleConnect = async () => {
    try {
      setIsProcessing(true);
      await connect();
    } catch (error) {
      console.error('Connection failed:', error);
      toast.error('Failed to connect to imToken');
    } finally {
      setIsProcessing(false);
    }
  };

  const baseClasses = clsx(
    'inline-flex items-center justify-center font-medium rounded-lg transition-colors',
    'focus:outline-none focus:ring-2 focus:ring-offset-2',
    {
      'px-3 py-2 text-sm': size === 'sm',
      'px-4 py-2 text-base': size === 'md',
      'px-6 py-3 text-lg': size === 'lg',
    },
    {
      'bg-brand-600 hover:bg-brand-700 text-white focus:ring-brand-500': variant === 'primary',
      'bg-gray-100 hover:bg-gray-200 text-gray-900 focus:ring-gray-500': variant === 'secondary',
      'border-2 border-brand-600 text-brand-600 hover:bg-brand-50 focus:ring-brand-500': variant === 'outline',
    },
    className
  );

  if (!isImTokenAvailable) {
    return (
      <a
        href="https://token.im/"
        target="_blank"
        rel="noopener noreferrer"
        className={baseClasses}
      >
        <CreditCardIcon className="w-5 h-5 mr-2" />
        Install imToken
        <ArrowRightIcon className="w-4 h-4 ml-2" />
      </a>
    );
  }

  if (!isConnected) {
    return (
      <button
        onClick={handleConnect}
        disabled={isProcessing}
        className={clsx(baseClasses, {
          'opacity-50 cursor-not-allowed': isProcessing
        })}
      >
        <CreditCardIcon className="w-5 h-5 mr-2" />
        {isProcessing ? 'Connecting...' : 'Connect imToken'}
      </button>
    );
  }

  return (
    <div className="flex items-center space-x-2">
      <span className="text-sm text-gray-600">
        Connected: {address?.slice(0, 6)}...{address?.slice(-4)}
      </span>
      <div className="w-2 h-2 bg-green-500 rounded-full" />
    </div>
  );
}

// One-click payment button component
export function ImTokenPayButton({
  payment,
  children,
  className,
  variant = 'primary',
  size = 'md',
  onSuccess,
  onError,
}: {
  payment: PaymentRequest;
  children: React.ReactNode;
  className?: string;
  variant?: 'primary' | 'secondary' | 'outline';
  size?: 'sm' | 'md' | 'lg';
  onSuccess?: (txHash: string) => void;
  onError?: (error: Error) => void;
}) {
  const { isConnected } = useImToken();
  const { payWithImToken } = useImTokenPayment();
  const [isProcessing, setIsProcessing] = useState(false);

  const handlePayment = async () => {
    if (!isConnected) {
      toast.error('Please connect imToken wallet first');
      return;
    }

    try {
      setIsProcessing(true);
      const txHash = await payWithImToken(
        payment.recipient,
        payment.amount,
        payment.token,
        payment.chainId
      );
      
      toast.success('Payment successful!');
      onSuccess?.(txHash);
    } catch (error) {
      const err = error as Error;
      console.error('Payment failed:', err);
      toast.error(err.message || 'Payment failed');
      onError?.(err);
    } finally {
      setIsProcessing(false);
    }
  };

  const baseClasses = clsx(
    'inline-flex items-center justify-center font-medium rounded-lg transition-colors',
    'focus:outline-none focus:ring-2 focus:ring-offset-2',
    {
      'px-3 py-2 text-sm': size === 'sm',
      'px-4 py-2 text-base': size === 'md',
      'px-6 py-3 text-lg': size === 'lg',
    },
    {
      'bg-brand-600 hover:bg-brand-700 text-white focus:ring-brand-500': variant === 'primary',
      'bg-gray-100 hover:bg-gray-200 text-gray-900 focus:ring-gray-500': variant === 'secondary',
      'border-2 border-brand-600 text-brand-600 hover:bg-brand-50 focus:ring-brand-500': variant === 'outline',
    },
    {
      'opacity-50 cursor-not-allowed': isProcessing || !isConnected
    },
    className
  );

  return (
    <button
      onClick={handlePayment}
      disabled={isProcessing || !isConnected}
      className={baseClasses}
    >
      <CreditCardIcon className="w-5 h-5 mr-2" />
      {isProcessing ? 'Processing...' : children}
    </button>
  );
}

// Cross-chain transfer button component
export function ImTokenCrossChainButton({
  transfer,
  children,
  className,
  variant = 'primary',
  size = 'md',
  onSuccess,
  onError,
}: {
  transfer: CrossChainPaymentRequest;
  children: React.ReactNode;
  className?: string;
  variant?: 'primary' | 'secondary' | 'outline';
  size?: 'sm' | 'md' | 'lg';
  onSuccess?: (txHash: string) => void;
  onError?: (error: Error) => void;
}) {
  const { isConnected } = useImToken();
  const { crossChainPay } = useImTokenPayment();
  const [isProcessing, setIsProcessing] = useState(false);

  const handleCrossChainTransfer = async () => {
    if (!isConnected) {
      toast.error('Please connect imToken wallet first');
      return;
    }

    try {
      setIsProcessing(true);
      const txHash = await crossChainPay(
        transfer.fromChain,
        transfer.toChain,
        transfer.token,
        transfer.amount,
        transfer.recipient
      );
      
      toast.success('Cross-chain transfer initiated!');
      onSuccess?.(txHash);
    } catch (error) {
      const err = error as Error;
      console.error('Cross-chain transfer failed:', err);
      toast.error(err.message || 'Transfer failed');
      onError?.(err);
    } finally {
      setIsProcessing(false);
    }
  };

  const baseClasses = clsx(
    'inline-flex items-center justify-center font-medium rounded-lg transition-colors',
    'focus:outline-none focus:ring-2 focus:ring-offset-2',
    {
      'px-3 py-2 text-sm': size === 'sm',
      'px-4 py-2 text-base': size === 'md',
      'px-6 py-3 text-lg': size === 'lg',
    },
    {
      'bg-brand-600 hover:bg-brand-700 text-white focus:ring-brand-500': variant === 'primary',
      'bg-gray-100 hover:bg-gray-200 text-gray-900 focus:ring-gray-500': variant === 'secondary',
      'border-2 border-brand-600 text-brand-600 hover:bg-brand-50 focus:ring-brand-500': variant === 'outline',
    },
    {
      'opacity-50 cursor-not-allowed': isProcessing || !isConnected
    },
    className
  );

  return (
    <button
      onClick={handleCrossChainTransfer}
      disabled={isProcessing || !isConnected}
      className={baseClasses}
    >
      <ArrowsRightLeftIcon className="w-5 h-5 mr-2" />
      {isProcessing ? 'Transferring...' : children}
    </button>
  );
}

// Quick action buttons for common GreenShare actions
export function GreenShareQuickActions() {
  const { isConnected } = useImToken();

  if (!isConnected) {
    return (
      <div className="text-center py-8">
        <ImTokenDeepLink />
        <p className="text-sm text-gray-500 mt-2">
          Connect imToken for one-click payments and cross-chain transfers
        </p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
      {/* Buy eKWH */}
      <ImTokenPayButton
        payment={{
          recipient: process.env.NEXT_PUBLIC_EKWH_CONTRACT || '0x0000000000000000000000000000000000000000',
          amount: '0.01', // 0.01 ETH
          chainId: 48899, // Zircuit
          description: 'Buy eKWH tokens'
        }}
        className="w-full"
      >
        Buy eKWH
      </ImTokenPayButton>

      {/* Cross-chain transfer sKWH to eKWH */}
      <ImTokenCrossChainButton
        transfer={{
          fromChain: 101, // Sui (using custom chain ID for Sui)
          toChain: 48899, // Zircuit
          token: 'sKWH',
          amount: '100',
          recipient: process.env.NEXT_PUBLIC_BRIDGE_CONTRACT || '0x0000000000000000000000000000000000000000',
          description: 'Bridge sKWH to eKWH'
        }}
        className="w-full"
      >
        Bridge to Zircuit
      </ImTokenCrossChainButton>
    </div>
  );
}

// Payment wizard component for guided payment flow
export function ImTokenPaymentWizard() {
  const [step, setStep] = useState(1);
  const [paymentData, setPaymentData] = useState({
    type: '',
    amount: '',
    recipient: '',
    token: 'ETH',
    chainId: 48899
  });

  const paymentTypes = [
    {
      id: 'buy-skwh',
      title: 'Buy sKWH Tokens',
      description: 'Purchase solar energy tokens',
      icon: <BoltIcon className="w-8 h-8 text-green-500" />,
      recommended: true
    },
    {
      id: 'pay-bill',
      title: 'Pay Energy Bill',
      description: 'Pay your energy consumption bill',
      icon: <CreditCardIcon className="w-8 h-8 text-blue-500" />
    },
    {
      id: 'custom',
      title: 'Custom Payment',
      description: 'Send tokens to any address',
      icon: <ArrowRightIcon className="w-8 h-8 text-gray-500" />
    }
  ];

  const amounts = [
    { value: '0.005', label: '10 sKWH', usd: 10 },
    { value: '0.025', label: '50 sKWH', usd: 50 },
    { value: '0.05', label: '100 sKWH', usd: 100 },
    { value: 'custom', label: 'Custom Amount', usd: 0 }
  ];

  return (
    <div className="max-w-md mx-auto bg-white rounded-2xl border border-gray-200 p-6">
      <div className="text-center mb-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-2">Payment Wizard</h3>
        <div className="flex justify-center space-x-2">
          {[1, 2, 3].map((stepNum) => (
            <div
              key={stepNum}
              className={clsx(
                "w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium",
                step >= stepNum
                  ? "bg-brand-600 text-white"
                  : "bg-gray-200 text-gray-600"
              )}
            >
              {stepNum}
            </div>
          ))}
        </div>
      </div>

      {/* Step 1: Payment Type */}
      {step === 1 && (
        <div className="space-y-4">
          <h4 className="font-medium text-gray-900">What would you like to do?</h4>
          {paymentTypes.map((type) => (
            <button
              key={type.id}
              onClick={() => {
                setPaymentData(prev => ({ ...prev, type: type.id }));
                setStep(2);
              }}
              className="w-full p-4 border border-gray-200 rounded-lg hover:border-brand-300 hover:bg-brand-50 transition-all text-left"
            >
              <div className="flex items-center">
                {type.icon}
                <div className="ml-3">
                  <div className="font-medium text-gray-900 flex items-center">
                    {type.title}
                    {type.recommended && (
                      <span className="ml-2 px-2 py-1 bg-green-100 text-green-700 text-xs rounded-full">
                        Recommended
                      </span>
                    )}
                  </div>
                  <div className="text-sm text-gray-600">{type.description}</div>
                </div>
              </div>
            </button>
          ))}
        </div>
      )}

      {/* Step 2: Amount Selection */}
      {step === 2 && (
        <div className="space-y-4">
          <button
            onClick={() => setStep(1)}
            className="text-sm text-gray-600 hover:text-gray-800"
          >
            ← Back
          </button>
          <h4 className="font-medium text-gray-900">Select Amount</h4>
          <div className="grid grid-cols-2 gap-3">
            {amounts.map((amount) => (
              <button
                key={amount.value}
                onClick={() => {
                  setPaymentData(prev => ({ ...prev, amount: amount.value }));
                  setStep(3);
                }}
                className="p-3 border border-gray-200 rounded-lg hover:border-brand-300 hover:bg-brand-50 transition-all text-center"
              >
                <div className="font-medium text-gray-900">{amount.label}</div>
                {amount.usd > 0 && (
                  <div className="text-sm text-gray-600">${amount.usd}</div>
                )}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Step 3: Confirmation */}
      {step === 3 && (
        <div className="space-y-4">
          <button
            onClick={() => setStep(2)}
            className="text-sm text-gray-600 hover:text-gray-800"
          >
            ← Back
          </button>
          <h4 className="font-medium text-gray-900">Confirm Payment</h4>
          
          <div className="bg-gray-50 rounded-lg p-4">
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Type:</span>
                <span className="font-medium">
                  {paymentTypes.find(t => t.id === paymentData.type)?.title}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Amount:</span>
                <span className="font-medium">{paymentData.amount} ETH</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Network:</span>
                <span className="font-medium">Zircuit</span>
              </div>
            </div>
          </div>

          <ImTokenPayButton
            payment={{
              recipient: process.env.NEXT_PUBLIC_EKWH_CONTRACT || '0x0000000000000000000000000000000000000000',
              amount: paymentData.amount,
              chainId: paymentData.chainId
            }}
            className="w-full"
            onSuccess={() => {
              toast.success('Payment completed!');
              setStep(1);
              setPaymentData({ type: '', amount: '', recipient: '', token: 'ETH', chainId: 48899 });
            }}
          >
            Pay with imToken
          </ImTokenPayButton>
        </div>
      )}
    </div>
  );
}

// Deep link URL generator utility
export const generateImTokenDeepLink = (params: {
  action: 'connect' | 'send' | 'crosschain' | 'dapp';
  chainId?: number;
  address?: string;
  amount?: string;
  data?: string;
  dappUrl?: string;
  callbackUrl?: string;
}) => {
  const baseUrl = 'imtoken://';
  const { action, ...otherParams } = params;
  
  const queryParams = new URLSearchParams();
  
  Object.entries(otherParams).forEach(([key, value]) => {
    if (value !== undefined) {
      queryParams.append(key, value.toString());
    }
  });
  
  return `${baseUrl}${action}?${queryParams.toString()}`;
};

// QR Code component for sharing payment links
export function ImTokenQRCode({ 
  payment,
  size = 200 
}: { 
  payment: any;
  size?: number;
}) {
  const deepLink = generateImTokenDeepLink({
    action: 'send',
    address: payment.recipient,
    amount: payment.amount,
    chainId: payment.chainId
  });

  return (
    <div className="text-center">
      <div className="inline-block p-4 bg-white border-2 border-gray-200 rounded-lg">
        {/* QR Code placeholder - in production, use a QR library like qrcode.js */}
        <div 
          className="bg-gray-100 flex items-center justify-center text-gray-500"
          style={{ width: size, height: size }}
        >
          QR Code
          <br />
          {size}x{size}
        </div>
      </div>
      <p className="text-sm text-gray-600 mt-2">
        Scan with imToken to pay
      </p>
      <p className="text-xs text-gray-500 mt-1 font-mono break-all">
        {deepLink.slice(0, 50)}...
      </p>
    </div>
  );
}