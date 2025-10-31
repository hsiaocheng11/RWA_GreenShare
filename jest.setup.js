// FILE: jest.setup.js
import '@testing-library/jest-dom'

// Mock environment variables
process.env.NEXT_PUBLIC_APP_NAME = 'GreenShare'
process.env.NEXT_PUBLIC_ROFL_ENDPOINT = 'http://localhost:8080'
process.env.NEXT_PUBLIC_SUI_NETWORK = 'testnet'
process.env.NEXT_PUBLIC_ZIRCUIT_CHAIN_ID = '48899'
process.env.NEXT_PUBLIC_CELO_CHAIN_ID = '44787'

// Mock Next.js router
jest.mock('next/router', () => ({
  useRouter() {
    return {
      route: '/',
      pathname: '/',
      query: {},
      asPath: '/',
      push: jest.fn(),
      pop: jest.fn(),
      reload: jest.fn(),
      back: jest.fn(),
      prefetch: jest.fn().mockResolvedValue(undefined),
      beforePopState: jest.fn(),
      events: {
        on: jest.fn(),
        off: jest.fn(),
        emit: jest.fn(),
      },
    }
  },
}))

// Mock window methods
Object.defineProperty(window, 'location', {
  value: {
    href: 'http://localhost:3000',
    assign: jest.fn(),
    reload: jest.fn(),
  },
  writable: true,
})

// Mock crypto for testing
Object.defineProperty(global, 'crypto', {
  value: {
    getRandomValues: arr => crypto.getRandomValues(arr),
    subtle: {
      digest: jest.fn(),
    },
  },
})