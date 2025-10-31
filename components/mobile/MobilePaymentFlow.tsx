// FILE: components/mobile/MobilePaymentFlow.tsx
import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import { toast } from 'react-hot-toast';
import { 
  DevicePhoneMobileIcon,
  QrCodeIcon,
  ArrowRightIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  InformationCircleIcon
} from '@heroicons/react/24/outline';
import { useImTokenDetection, useImTokenDeepLinkTest } from '../../lib/hooks/useImTokenDetection';
import { generateImTokenDeepLink, ImTokenQRCode } from '../ImTokenDeepLink';
import { clsx } from 'clsx';

interface MobilePaymentFlowProps {
  payment: {
    recipient: string;
    amount: string;
    token?: string;
    chainId?: number;
    description?: string;
  };
  onSuccess?: (result: any) => void;
  onError?: (error: Error) => void;
}

export default function MobilePaymentFlow({ 
  payment, 
  onSuccess, 
  onError 
}: MobilePaymentFlowProps) {
  const router = useRouter();
  const detection = useImTokenDetection();
  const { testDeepLink, lastTestResult } = useImTokenDeepLinkTest();
  
  const [currentStep, setCurrentStep] = useState<'detect' | 'connect' | 'pay' | 'confirm'>('detect');
  const [showQR, setShowQR] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);

  // Generate deep links
  const connectLink = generateImTokenDeepLink({
    action: 'connect',
    dappUrl: window.location.origin,
    callbackUrl: `${window.location.origin}/callback`
  });

  const paymentLink = generateImTokenDeepLink({
    action: 'send',
    address: payment.recipient,
    amount: payment.amount,
    chainId: payment.chainId || 48899
  });

  // Auto-advance steps based on detection
  useEffect(() => {
    if (detection.isInstalled && currentStep === 'detect') {
      setCurrentStep('connect');
    }
  }, [detection.isInstalled, currentStep]);

  const handleInstallImToken = () => {
    const installUrl = detection.platform === 'ios' 
      ? 'https://apps.apple.com/app/imtoken2/id1384798940'
      : 'https://play.google.com/store/apps/details?id=im.token.app';
    
    window.open(installUrl, '_blank');
  };

  const handleConnectWallet = async () => {
    setIsProcessing(true);
    try {
      const success = await testDeepLink(connectLink);
      if (success) {
        setCurrentStep('pay');
        toast.success('Opening imToken...');
      }
    } catch (error) {
      onError?.(error as Error);
      toast.error('Failed to open imToken');
    } finally {
      setIsProcessing(false);
    }
  };

  const handlePayment = async () => {
    setIsProcessing(true);
    try {
      const success = await testDeepLink(paymentLink);
      if (success) {
        setCurrentStep('confirm');
        toast.success('Payment initiated in imToken');
        
        // Simulate payment completion for demo
        setTimeout(() => {
          onSuccess?.({ txHash: '0x' + Math.random().toString(16).slice(2, 66) });
        }, 3000);
      }
    } catch (error) {
      onError?.(error as Error);
      toast.error('Payment failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const renderDetectionStep = () => (
    <div className="text-center py-8">
      <DevicePhoneMobileIcon className="mx-auto h-16 w-16 text-gray-400 mb-4" />
      <h3 className="text-lg font-semibold text-gray-900 mb-2">Mobile Detection</h3>
      
      <div className="space-y-3 mb-6">
        <div className={clsx(
          "flex items-center justify-between p-3 rounded-lg",
          detection.isMobile ? "bg-green-50 text-green-800" : "bg-red-50 text-red-800"
        )}>
          <span>Mobile Device</span>
          {detection.isMobile ? (
            <CheckCircleIcon className="h-5 w-5 text-green-600" />
          ) : (
            <ExclamationTriangleIcon className="h-5 w-5 text-red-600" />
          )}
        </div>

        <div className={clsx(
          "flex items-center justify-between p-3 rounded-lg",
          detection.isInstalled ? "bg-green-50 text-green-800" : "bg-yellow-50 text-yellow-800"
        )}>
          <span>imToken Installed</span>
          {detection.isInstalled ? (
            <CheckCircleIcon className="h-5 w-5 text-green-600" />
          ) : (
            <ExclamationTriangleIcon className="h-5 w-5 text-yellow-600" />
          )}
        </div>

        <div className={clsx(
          "flex items-center justify-between p-3 rounded-lg",
          detection.isAvailable ? "bg-green-50 text-green-800" : "bg-red-50 text-red-800"
        )}>
          <span>Deep Links Supported</span>
          {detection.isAvailable ? (
            <CheckCircleIcon className="h-5 w-5 text-green-600" />
          ) : (
            <ExclamationTriangleIcon className="h-5 w-5 text-red-600" />
          )}
        </div>
      </div>

      {!detection.isMobile && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-4">
          <InformationCircleIcon className="h-5 w-5 text-blue-600 inline mr-2" />
          <span className="text-blue-800 text-sm">
            For best experience, open this page on your mobile device
          </span>
        </div>
      )}

      {!detection.isInstalled ? (
        <button
          onClick={handleInstallImToken}
          className="w-full px-6 py-3 bg-brand-600 text-white rounded-lg hover:bg-brand-700 transition-colors"
        >
          Install imToken
        </button>
      ) : (
        <button
          onClick={() => setCurrentStep('connect')}
          className="w-full px-6 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
        >
          Continue to Payment
        </button>
      )}
    </div>
  );

  const renderConnectStep = () => (
    <div className="text-center py-8">
      <div className="w-16 h-16 bg-brand-100 rounded-full flex items-center justify-center mx-auto mb-4">
        <DevicePhoneMobileIcon className="h-8 w-8 text-brand-600" />
      </div>
      
      <h3 className="text-lg font-semibold text-gray-900 mb-2">Connect imToken</h3>
      <p className="text-gray-600 mb-6">
        Connect your imToken wallet to continue with the payment
      </p>

      <div className="grid grid-cols-1 gap-4 mb-6">
        <button
          onClick={handleConnectWallet}
          disabled={isProcessing}
          className="flex items-center justify-center px-6 py-3 bg-brand-600 text-white rounded-lg hover:bg-brand-700 disabled:opacity-50 transition-colors"
        >
          {isProcessing ? 'Opening...' : 'Open imToken'}
          <ArrowRightIcon className="ml-2 h-4 w-4" />
        </button>

        <button
          onClick={() => setShowQR(!showQR)}
          className="flex items-center justify-center px-6 py-3 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
        >
          <QrCodeIcon className="mr-2 h-4 w-4" />
          {showQR ? 'Hide' : 'Show'} QR Code
        </button>
      </div>

      {showQR && (
        <div className="mb-6">
          <ImTokenQRCode 
            payment={{ 
              recipient: 'connect',
              amount: '0',
              chainId: 48899
            }}
            size={200}
          />
        </div>
      )}

      <div className="text-xs text-gray-500">
        Connect URL: <code className="bg-gray-100 px-1 rounded">{connectLink.slice(0, 50)}...</code>
      </div>
    </div>
  );

  const renderPaymentStep = () => (
    <div className="text-center py-8">
      <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
        <CheckCircleIcon className="h-8 w-8 text-green-600" />
      </div>
      
      <h3 className="text-lg font-semibold text-gray-900 mb-2">Ready to Pay</h3>
      <p className="text-gray-600 mb-6">
        {payment.description || 'Complete your payment in imToken'}
      </p>

      <div className="bg-gray-50 rounded-lg p-4 mb-6">
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-600">Amount:</span>
            <span className="font-medium">{payment.amount} {payment.token || 'ETH'}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-600">To:</span>
            <span className="font-mono text-xs">
              {payment.recipient.slice(0, 6)}...{payment.recipient.slice(-4)}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-600">Network:</span>
            <span className="font-medium">
              {payment.chainId === 48899 ? 'Zircuit' : 'Ethereum'}
            </span>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 mb-6">
        <button
          onClick={handlePayment}
          disabled={isProcessing}
          className="flex items-center justify-center px-6 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
        >
          {isProcessing ? 'Processing...' : 'Pay with imToken'}
          <ArrowRightIcon className="ml-2 h-4 w-4" />
        </button>

        <button
          onClick={() => setShowQR(!showQR)}
          className="flex items-center justify-center px-6 py-3 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
        >
          <QrCodeIcon className="mr-2 h-4 w-4" />
          {showQR ? 'Hide' : 'Show'} Payment QR
        </button>
      </div>

      {showQR && (
        <div className="mb-6">
          <ImTokenQRCode payment={payment} size={200} />
        </div>
      )}

      <div className="text-xs text-gray-500">
        Payment URL: <code className="bg-gray-100 px-1 rounded">{paymentLink.slice(0, 50)}...</code>
      </div>
    </div>
  );

  const renderConfirmStep = () => (
    <div className="text-center py-8">
      <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
        <CheckCircleIcon className="h-8 w-8 text-green-600" />
      </div>
      
      <h3 className="text-lg font-semibold text-gray-900 mb-2">Payment Initiated</h3>
      <p className="text-gray-600 mb-6">
        Your payment has been sent to imToken. Please complete the transaction in the app.
      </p>

      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
        <InformationCircleIcon className="h-5 w-5 text-yellow-600 inline mr-2" />
        <span className="text-yellow-800 text-sm">
          Don't close this page. We'll update you when the payment is confirmed.
        </span>
      </div>

      <button
        onClick={() => router.push('/dashboard')}
        className="px-6 py-3 bg-brand-600 text-white rounded-lg hover:bg-brand-700 transition-colors"
      >
        Go to Dashboard
      </button>
    </div>
  );

  return (
    <div className="max-w-md mx-auto bg-white rounded-2xl border border-gray-200 p-6">
      {/* Progress Indicator */}
      <div className="flex justify-center space-x-2 mb-6">
        {['detect', 'connect', 'pay', 'confirm'].map((step, index) => (
          <div
            key={step}
            className={clsx(
              "w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium transition-colors",
              currentStep === step
                ? "bg-brand-600 text-white"
                : index < ['detect', 'connect', 'pay', 'confirm'].indexOf(currentStep)
                ? "bg-green-600 text-white"
                : "bg-gray-200 text-gray-600"
            )}
          >
            {index + 1}
          </div>
        ))}
      </div>

      {/* Step Content */}
      {currentStep === 'detect' && renderDetectionStep()}
      {currentStep === 'connect' && renderConnectStep()}
      {currentStep === 'pay' && renderPaymentStep()}
      {currentStep === 'confirm' && renderConfirmStep()}

      {/* Debug Info (Development Only) */}
      {process.env.NODE_ENV === 'development' && (
        <div className="mt-6 p-3 bg-gray-100 rounded-lg text-xs">
          <details>
            <summary className="cursor-pointer font-medium">Debug Info</summary>
            <pre className="mt-2 text-xs overflow-auto">
              {JSON.stringify({
                detection,
                currentStep,
                lastTestResult,
                payment
              }, null, 2)}
            </pre>
          </details>
        </div>
      )}
    </div>
  );
}