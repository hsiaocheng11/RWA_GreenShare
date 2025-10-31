// FILE: lib/utils/format.ts
/**
 * Utility functions for formatting numbers, currencies, and other data
 */

/**
 * Format a number with specified decimal places
 * @param value - The number to format
 * @param decimals - Number of decimal places (default: 2)
 * @param suffix - Optional suffix to append
 * @returns Formatted string
 */
export function formatNumber(value: number, decimals: number = 2, suffix?: string): string {
  if (isNaN(value) || value === null || value === undefined) {
    return '0';
  }

  const formatted = value.toLocaleString('en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: decimals,
  });

  return suffix ? `${formatted} ${suffix}` : formatted;
}

/**
 * Format a token amount with appropriate decimals based on token type
 * @param amount - The amount to format
 * @param symbol - Token symbol
 * @returns Formatted token amount with symbol
 */
export function formatTokenAmount(amount: number, symbol: string): string {
  const decimals = getTokenDecimals(symbol);
  return formatNumber(amount, decimals, symbol);
}

/**
 * Get appropriate decimal places for different token types
 * @param symbol - Token symbol
 * @returns Number of decimal places
 */
export function getTokenDecimals(symbol: string): number {
  switch (symbol.toLowerCase()) {
    case 'sui':
      return 4;
    case 'eth':
      return 6;
    case 'celo':
      return 4;
    case 'skwh':
    case 'ekwh':
      return 3; // Energy tokens with 3 decimal precision
    default:
      return 2;
  }
}

/**
 * Format USD currency
 * @param amount - Amount in USD
 * @returns Formatted USD string
 */
export function formatUSD(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

/**
 * Format energy amount (kWh)
 * @param kwh - Energy amount in kWh
 * @returns Formatted energy string
 */
export function formatEnergy(kwh: number): string {
  if (kwh >= 1000) {
    return formatNumber(kwh / 1000, 2, 'MWh');
  }
  return formatNumber(kwh, 3, 'kWh');
}

/**
 * Format time duration
 * @param seconds - Duration in seconds
 * @returns Human-readable duration string
 */
export function formatDuration(seconds: number): string {
  if (seconds < 60) {
    return `${seconds}s`;
  } else if (seconds < 3600) {
    return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  } else if (seconds < 86400) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
  } else {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    return `${days}d ${hours}h`;
  }
}

/**
 * Format date for display
 * @param date - Date object or timestamp
 * @param includeTime - Whether to include time (default: true)
 * @returns Formatted date string
 */
export function formatDate(date: Date | number, includeTime: boolean = true): string {
  const dateObj = typeof date === 'number' ? new Date(date) : date;
  
  if (includeTime) {
    return dateObj.toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } else {
    return dateObj.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  }
}

/**
 * Format relative time (e.g., "2 hours ago")
 * @param date - Date object or timestamp
 * @returns Relative time string
 */
export function formatRelativeTime(date: Date | number): string {
  const dateObj = typeof date === 'number' ? new Date(date) : date;
  const now = new Date();
  const diffMs = now.getTime() - dateObj.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHour = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHour / 24);

  if (diffSec < 60) return 'just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHour < 24) return `${diffHour}h ago`;
  if (diffDay < 7) return `${diffDay}d ago`;
  
  return formatDate(dateObj, false);
}

/**
 * Format percentage
 * @param value - Decimal value (0.1 = 10%)
 * @param decimals - Number of decimal places (default: 1)
 * @returns Formatted percentage string
 */
export function formatPercentage(value: number, decimals: number = 1): string {
  return `${formatNumber(value * 100, decimals)}%`;
}

/**
 * Format address for display (truncated)
 * @param address - Full address
 * @param startChars - Number of characters to show at start (default: 6)
 * @param endChars - Number of characters to show at end (default: 4)
 * @returns Truncated address
 */
export function formatAddress(address: string, startChars: number = 6, endChars: number = 4): string {
  if (!address || address.length <= startChars + endChars) {
    return address;
  }
  
  return `${address.slice(0, startChars)}...${address.slice(-endChars)}`;
}

/**
 * Format transaction hash for display
 * @param txHash - Transaction hash
 * @returns Formatted transaction hash
 */
export function formatTxHash(txHash: string): string {
  return formatAddress(txHash, 8, 6);
}

/**
 * Format file size
 * @param bytes - Size in bytes
 * @returns Human-readable file size
 */
export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B';
  
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  
  return `${formatNumber(bytes / Math.pow(k, i), 1)} ${sizes[i]}`;
}

/**
 * Format large numbers with appropriate units (K, M, B)
 * @param value - Number to format
 * @param decimals - Number of decimal places (default: 1)
 * @returns Formatted number with unit
 */
export function formatLargeNumber(value: number, decimals: number = 1): string {
  if (value >= 1e9) {
    return formatNumber(value / 1e9, decimals, 'B');
  } else if (value >= 1e6) {
    return formatNumber(value / 1e6, decimals, 'M');
  } else if (value >= 1e3) {
    return formatNumber(value / 1e3, decimals, 'K');
  }
  
  return formatNumber(value, 0);
}

/**
 * Parse formatted number back to number
 * @param formatted - Formatted number string
 * @returns Parsed number
 */
export function parseFormattedNumber(formatted: string): number {
  // Remove commas and other formatting
  const cleaned = formatted.replace(/[,\s]/g, '');
  return parseFloat(cleaned) || 0;
}