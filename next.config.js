// FILE: next.config.js
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  swcMinify: true,
  images: {
    domains: ['localhost'],
  },
  webpack: (config, { webpack }) => {
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      net: false,
      tls: false,
      crypto: require.resolve('crypto-browserify'),
      stream: require.resolve('stream-browserify'),
      buffer: require.resolve('buffer'),
    }
    config.resolve.alias = {
      ...(config.resolve.alias || {}),
      'wagmi/connectors/injected': require('path').join(process.cwd(), 'lib/shims/wagmi-injected.ts'),
      '@wagmi/connectors/injected': require('path').join(process.cwd(), 'lib/shims/wagmi-injected.ts'),
    }
    config.plugins.push(
      new webpack.ProvidePlugin({
        Buffer: ['buffer', 'Buffer'],
      })
    )
    return config
  },
  eslint: {
    ignoreDuringBuilds: true,
  },
  env: {
    NEXT_PUBLIC_APP_NAME: process.env.NEXT_PUBLIC_APP_NAME,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    NEXT_PUBLIC_ROFL_ENDPOINT: process.env.NEXT_PUBLIC_ROFL_ENDPOINT,
    NEXT_PUBLIC_SUI_NETWORK: process.env.NEXT_PUBLIC_SUI_NETWORK,
    NEXT_PUBLIC_ZIRCUIT_CHAIN_ID: process.env.NEXT_PUBLIC_ZIRCUIT_CHAIN_ID,
    NEXT_PUBLIC_CELO_CHAIN_ID: process.env.NEXT_PUBLIC_CELO_CHAIN_ID,
  },
}

module.exports = nextConfig