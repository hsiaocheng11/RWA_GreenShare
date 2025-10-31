// FILE: jest.integration.config.js
module.exports = {
  displayName: 'Integration Tests',
  testMatch: ['<rootDir>/tests/**/*.test.ts', '<rootDir>/tests/**/*.test.js'],
  testEnvironment: 'node',
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
  moduleNameMapping: {
    '^@/(.*)$': '<rootDir>/$1',
  },
  collectCoverageFrom: [
    'src/**/*.{js,ts}',
    'scripts/**/*.{js,ts}',
    '!**/*.d.ts',
    '!**/node_modules/**',
  ],
}