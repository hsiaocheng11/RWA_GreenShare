// FILE: scripts/deploy.ts
import { ethers } from 'hardhat';
import { writeFileSync, readFileSync } from 'fs';
import { join } from 'path';

interface DeploymentAddresses {
  network: string;
  chainId: number;
  timestamp: number;
  contracts: {
    eKWH: string;
    Bridge: string;
    GudAdapter: string;
    MockGudEngine: string;
    KYCRegistry: string;
    Verifier: string;
    MockVerifier: string;
  };
  transactions: {
    eKWH: string;
    Bridge: string;
    GudAdapter: string;
    MockGudEngine: string;
    KYCRegistry: string;
    Verifier: string;
    MockVerifier: string;
  };
}

async function main() {
  console.log('🚀 Starting GreenShare contract deployment...');
  
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  
  console.log(`📋 Deployment Details:`);
  console.log(`   Network: ${network.name} (${network.chainId})`);
  console.log(`   Deployer: ${deployer.address}`);
  console.log(`   Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);
  console.log('');

  const deployment: DeploymentAddresses = {
    network: network.name,
    chainId: Number(network.chainId),
    timestamp: Date.now(),
    contracts: {} as any,
    transactions: {} as any,
  };

  // 1. Deploy MockVerifier (for testing)
  console.log('📝 1. Deploying MockVerifier...');
  const MockVerifier = await ethers.getContractFactory('MockVerifier');
  const mockVerifier = await MockVerifier.deploy();
  await mockVerifier.waitForDeployment();
  
  deployment.contracts.MockVerifier = await mockVerifier.getAddress();
  deployment.transactions.MockVerifier = mockVerifier.deploymentTransaction()?.hash || '';
  console.log(`   ✅ MockVerifier deployed to: ${deployment.contracts.MockVerifier}`);

  // 2. Deploy Verifier (production)
  console.log('📝 2. Deploying Verifier...');
  const Verifier = await ethers.getContractFactory('Verifier');
  const verifier = await Verifier.deploy(deployment.contracts.MockVerifier);
  await verifier.waitForDeployment();
  
  deployment.contracts.Verifier = await verifier.getAddress();
  deployment.transactions.Verifier = verifier.deploymentTransaction()?.hash || '';
  console.log(`   ✅ Verifier deployed to: ${deployment.contracts.Verifier}`);

  // 3. Deploy KYC Registry
  console.log('📝 3. Deploying KYC Registry...');
  const KYCRegistry = await ethers.getContractFactory('KYCRegistry');
  const kycRegistry = await KYCRegistry.deploy(deployer.address); // Initial verifier
  await kycRegistry.waitForDeployment();
  
  deployment.contracts.KYCRegistry = await kycRegistry.getAddress();
  deployment.transactions.KYCRegistry = kycRegistry.deploymentTransaction()?.hash || '';
  console.log(`   ✅ KYC Registry deployed to: ${deployment.contracts.KYCRegistry}`);

  // 4. Deploy eKWH Token
  console.log('📝 4. Deploying eKWH Token...');
  const eKWH = await ethers.getContractFactory('eKWH');
  const ekwhToken = await eKWH.deploy(
    deployment.contracts.Verifier,
    deployment.contracts.KYCRegistry
  );
  await ekwhToken.waitForDeployment();
  
  deployment.contracts.eKWH = await ekwhToken.getAddress();
  deployment.transactions.eKWH = ekwhToken.deploymentTransaction()?.hash || '';
  console.log(`   ✅ eKWH Token deployed to: ${deployment.contracts.eKWH}`);

  // 5. Deploy Bridge Contract
  console.log('📝 5. Deploying Bridge Contract...');
  const Bridge = await ethers.getContractFactory('Bridge');
  const bridge = await Bridge.deploy(
    deployment.contracts.eKWH,
    deployment.contracts.Verifier
  );
  await bridge.waitForDeployment();
  
  deployment.contracts.Bridge = await bridge.getAddress();
  deployment.transactions.Bridge = bridge.deploymentTransaction()?.hash || '';
  console.log(`   ✅ Bridge deployed to: ${deployment.contracts.Bridge}`);

  // 6. Deploy Mock Gud Engine (for testing)
  console.log('📝 6. Deploying Mock Gud Engine...');
  const MockGudEngine = await ethers.getContractFactory('MockGudEngine');
  const mockGudEngine = await MockGudEngine.deploy();
  await mockGudEngine.waitForDeployment();
  
  deployment.contracts.MockGudEngine = await mockGudEngine.getAddress();
  deployment.transactions.MockGudEngine = mockGudEngine.deploymentTransaction()?.hash || '';
  console.log(`   ✅ Mock Gud Engine deployed to: ${deployment.contracts.MockGudEngine}`);

  // 7. Deploy Gud Adapter
  console.log('📝 7. Deploying Gud Adapter...');
  const GudAdapter = await ethers.getContractFactory('GudAdapter');
  const gudAdapter = await GudAdapter.deploy(
    deployment.contracts.MockGudEngine,
    deployment.contracts.eKWH,
    deployer.address // Fee recipient
  );
  await gudAdapter.waitForDeployment();
  
  deployment.contracts.GudAdapter = await gudAdapter.getAddress();
  deployment.transactions.GudAdapter = gudAdapter.deploymentTransaction()?.hash || '';
  console.log(`   ✅ Gud Adapter deployed to: ${deployment.contracts.GudAdapter}`);

  // 8. Configure contracts
  console.log('🔧 8. Configuring contracts...');
  
  // Set bridge contract as minter for eKWH
  console.log('   Setting bridge as minter...');
  await ekwhToken.grantRole(await ekwhToken.MINTER_ROLE(), deployment.contracts.Bridge);
  
  // Set bridge contract as burner for eKWH
  console.log('   Setting bridge as burner...');
  await ekwhToken.grantRole(await ekwhToken.BURNER_ROLE(), deployment.contracts.Bridge);
  
  // Authorize verifier for KYC registry
  console.log('   Authorizing verifier for KYC...');
  await kycRegistry.setAuthorizedVerifier(deployment.contracts.Verifier, true);
  
  // Add liquidity to mock Gud engine for testing
  console.log('   Adding test liquidity to Gud engine...');
  const liquidityAmount = ethers.parseEther('1000'); // 1000 tokens
  
  // Mint some eKWH for testing
  await ekwhToken.mint(deployer.address, liquidityAmount);
  await ekwhToken.approve(deployment.contracts.MockGudEngine, liquidityAmount);
  await mockGudEngine.addLiquidity(deployment.contracts.eKWH, liquidityAmount);

  console.log('   ✅ Configuration completed');

  // 9. Save deployment addresses
  const addressesPath = join(__dirname, '../docs/addresses.json');
  const existingAddresses = (() => {
    try {
      return JSON.parse(readFileSync(addressesPath, 'utf8'));
    } catch {
      return {};
    }
  })();

  existingAddresses[network.name] = deployment;
  writeFileSync(addressesPath, JSON.stringify(existingAddresses, null, 2));
  
  console.log('💾 Deployment addresses saved to:', addressesPath);

  // 10. Verification instructions
  console.log('');
  console.log('🔍 To verify contracts on Etherscan:');
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.MockVerifier}`);
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.Verifier} ${deployment.contracts.MockVerifier}`);
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.KYCRegistry} ${deployer.address}`);
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.eKWH} ${deployment.contracts.Verifier} ${deployment.contracts.KYCRegistry}`);
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.Bridge} ${deployment.contracts.eKWH} ${deployment.contracts.Verifier}`);
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.MockGudEngine}`);
  console.log(`npx hardhat verify --network ${network.name} ${deployment.contracts.GudAdapter} ${deployment.contracts.MockGudEngine} ${deployment.contracts.eKWH} ${deployer.address}`);

  console.log('');
  console.log('🎉 Deployment completed successfully!');
  console.log('');
  console.log('📋 Summary:');
  Object.entries(deployment.contracts).forEach(([name, address]) => {
    console.log(`   ${name}: ${address}`);
  });

  console.log('');
  console.log('🔗 Next steps:');
  console.log('1. Update .env file with deployed contract addresses');
  console.log('2. Update lib/config/contracts.ts with new addresses');
  console.log('3. Deploy Sui Move contracts');
  console.log('4. Configure cross-chain bridge mappings');
  console.log('5. Start ROFL enclave with production configuration');

  return deployment;
}

// Error handling
main()
  .then((deployment) => {
    console.log('✅ Deployment script completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Deployment failed:');
    console.error(error);
    process.exit(1);
  });