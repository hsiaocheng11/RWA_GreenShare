// FILE: components/dashboard/BalanceCard.tsx
import React from 'react';
import { ArrowUpRightIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline';
import { clsx } from 'clsx';
import { formatNumber } from '../../lib/utils/format';

interface Balance {
  symbol: string;
  amount: number;
  chain: string;
}

interface BalanceCardProps {
  title: string;
  balance?: number;
  balances?: Balance[];
  symbol?: string;
  chain?: string;
  loading?: boolean;
  error?: string | null;
  icon?: React.ReactNode;
  gradient?: string;
  isMultiBalance?: boolean;
}

export default function BalanceCard({
  title,
  balance,
  balances,
  symbol,
  chain,
  loading,
  error,
  icon,
  gradient = "from-blue-500 to-blue-600",
  isMultiBalance = false,
}: BalanceCardProps) {
  if (loading) {
    return (
      <div className="bg-white rounded-2xl shadow-soft border border-gray-200 p-6">
        <div className="animate-pulse">
          <div className="flex items-center justify-between mb-4">
            <div className="h-4 bg-gray-200 rounded w-1/2"></div>
            <div className="h-8 w-8 bg-gray-200 rounded-lg"></div>
          </div>
          <div className="h-8 bg-gray-200 rounded w-3/4 mb-2"></div>
          <div className="h-4 bg-gray-200 rounded w-1/3"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white rounded-2xl shadow-soft border border-red-200 p-6">
        <div className="flex items-center text-red-600">
          <ExclamationTriangleIcon className="h-5 w-5 mr-2" />
          <span className="text-sm">Failed to load balance</span>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-2xl shadow-soft border border-gray-200 overflow-hidden">
      {/* Header with gradient */}
      <div className={clsx("bg-gradient-to-r p-6 text-white", gradient)}>
        <div className="flex items-center justify-between mb-2">
          <h3 className="text-lg font-semibold">{title}</h3>
          {icon && (
            <div className="bg-white/20 p-2 rounded-lg">
              {icon}
            </div>
          )}
        </div>
        
        {isMultiBalance ? (
          <div className="space-y-3">
            {balances?.map((bal, index) => (
              <div key={bal.symbol} className="flex items-center justify-between">
                <div className="flex items-center">
                  <span className="text-sm opacity-90">{bal.symbol}</span>
                  <span className="text-xs opacity-70 ml-2">({bal.chain})</span>
                </div>
                <span className="font-bold">
                  {formatNumber(bal.amount, bal.symbol === 'SUI' ? 4 : 6)}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <>
            <div className="text-3xl font-bold mb-1">
              {formatNumber(balance || 0, symbol === 'SUI' ? 4 : 6)}
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm opacity-90">{symbol}</span>
              {chain && (
                <span className="text-xs bg-white/20 px-2 py-1 rounded-full">
                  {chain}
                </span>
              )}
            </div>
          </>
        )}
      </div>

      {/* Action buttons */}
      <div className="p-4">
        <div className="grid grid-cols-2 gap-3">
          <button className="flex items-center justify-center px-4 py-2 bg-gray-50 hover:bg-gray-100 text-gray-700 rounded-lg transition-colors text-sm font-medium">
            Send
          </button>
          <button className="flex items-center justify-center px-4 py-2 bg-brand-50 hover:bg-brand-100 text-brand-700 rounded-lg transition-colors text-sm font-medium">
            <ArrowUpRightIcon className="h-4 w-4 mr-1" />
            Trade
          </button>
        </div>
      </div>
    </div>
  );
}