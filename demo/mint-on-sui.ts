// FILE: demo/mint-on-sui.ts
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { SuiClient, getFullnodeUrl } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { fromB64 } from '@mysten/sui.js/utils';
import fs from 'fs/promises';
import path from 'path';

interface ProofData {
  proof_id: string;
  aggregate_kwh: number;
  merkle_root: string;
  record_count: number;
  window_start: string;
  window_end: string;
  generated_at: string;
  meter_ids: string[];
  walrus_cid?: string;
  seal_hash?: string;
  version: string;
}

interface MintResult {
  success: boolean;
  transactionDigest?: string;
  certificateId?: string;
  skwhCoinId?: string;
  error?: string;
  gasUsed?: string;
}

class SuiMinter {
  private client: SuiClient;
  private keypair: Ed25519Keypair;
  private packageId: string;
  private registryId: string;
  private kioskId?: string;

  constructor(config: {
    network?: 'testnet' | 'devnet' | 'mainnet';
    privateKey?: string;
    packageId?: string;
    registryId?: string;
    rpcUrl?: string;
  } = {}) {
    // Initialize Sui client
    const network = config.network || 'testnet';
    const rpcUrl = config.rpcUrl || getFullnodeUrl(network);
    this.client = new SuiClient({ url: rpcUrl });

    // Initialize keypair
    if (config.privateKey) {
      if (config.privateKey.startsWith('0x')) {
        const keyBytes = fromB64(config.privateKey.slice(2));
        this.keypair = Ed25519Keypair.fromSecretKey(keyBytes);
      } else {
        this.keypair = Ed25519Keypair.fromSecretKey(config.privateKey);
      }
    } else if (process.env.SUI_PRIVATE_KEY) {
      this.keypair = Ed25519Keypair.fromSecretKey(process.env.SUI_PRIVATE_KEY);
    } else {
      console.warn('⚠️  No private key provided, generating new keypair for demo');
      this.keypair = new Ed25519Keypair();
    }

    // Set contract addresses
    this.packageId = config.packageId || process.env.SUI_PACKAGE_ID || '0x0';
    this.registryId = config.registryId || process.env.SUI_SKWH_REGISTRY || '0x0';

    console.log(`🔗 Connected to Sui ${network} (${rpcUrl})`);
    console.log(`📍 Deployer address: ${this.keypair.getPublicKey().toSuiAddress()}`);
    console.log(`📦 Package ID: ${this.packageId}`);
    console.log(`🗃️  Registry ID: ${this.registryId}`);
  }

  async readProofFile(filePath: string): Promise<ProofData> {
    try {
      console.log(`📖 Reading proof file: ${filePath}`);
      
      const fileContent = await fs.readFile(filePath, 'utf-8');
      const proofData = JSON.parse(fileContent) as ProofData;
      
      console.log(`✅ Proof loaded: ${proofData.proof_id}`);
      console.log(`   Total Energy: ${proofData.aggregate_kwh} kWh`);
      console.log(`   Records: ${proofData.record_count}`);
      console.log(`   Meters: ${proofData.meter_ids.length}`);
      
      return proofData;
    } catch (error) {
      throw new Error(`Failed to read proof file: ${error}`);
    }
  }

  async checkBalance(): Promise<void> {
    try {
      const address = this.keypair.getPublicKey().toSuiAddress();
      const balance = await this.client.getBalance({ owner: address });
      
      const suiBalance = parseInt(balance.totalBalance) / 1_000_000_000; // Convert MIST to SUI
      console.log(`💰 SUI Balance: ${suiBalance.toFixed(4)} SUI`);
      
      if (suiBalance < 0.1) {
        console.warn('⚠️  Low SUI balance! You may need more SUI for gas fees.');
        console.log('💡 Get testnet SUI from: https://testnet.sui.io/faucet');
      }
    } catch (error) {
      console.warn(`⚠️  Could not check balance: ${error}`);
    }
  }

  async findOrCreateKiosk(): Promise<string> {
    if (this.kioskId) {
      return this.kioskId;
    }

    try {
      const address = this.keypair.getPublicKey().toSuiAddress();
      
      // Look for existing kiosks owned by this address
      const ownedObjects = await this.client.getOwnedObjects({
        owner: address,
        filter: {
          StructType: '0x2::kiosk::Kiosk'
        }
      });

      if (ownedObjects.data.length > 0) {
        this.kioskId = ownedObjects.data[0].data?.objectId;
        console.log(`🏪 Found existing kiosk: ${this.kioskId}`);
        return this.kioskId!;
      }

      // Create new kiosk
      console.log('🏪 Creating new kiosk...');
      const tx = new TransactionBlock();
      
      tx.moveCall({
        target: '0x2::kiosk::default',
        arguments: []
      });

      const result = await this.client.signAndExecuteTransactionBlock({
        signer: this.keypair,
        transactionBlock: tx,
        options: {
          showEffects: true,
          showObjectChanges: true
        }
      });

      // Find kiosk ID from object changes
      const kioskChange = result.objectChanges?.find(
        change => change.type === 'created' && 
        change.objectType?.includes('kiosk::Kiosk')
      );

      if (kioskChange && 'objectId' in kioskChange) {
        this.kioskId = kioskChange.objectId;
        console.log(`✅ Created new kiosk: ${this.kioskId}`);
        return this.kioskId;
      } else {
        throw new Error('Failed to create kiosk');
      }
    } catch (error) {
      throw new Error(`Kiosk creation failed: ${error}`);
    }
  }

  async mintFromProof(proofData: ProofData): Promise<MintResult> {
    try {
      console.log(`🌱 Starting mint process for proof: ${proofData.proof_id}`);
      
      // Check prerequisites
      await this.checkBalance();
      const kioskId = await this.findOrCreateKiosk();
      
      // Prepare transaction
      const tx = new TransactionBlock();
      
      // Convert kWh to scaled integer (multiply by 1000 for 3 decimal precision)
      const scaledKwh = Math.round(proofData.aggregate_kwh * 1000);
      
      // Prepare proof data for contract
      const proofDataBytes = Array.from(new TextEncoder().encode(JSON.stringify({
        version: proofData.version || '1.0.0',
        merkle_root: proofData.merkle_root,
        record_count: proofData.record_count,
        window_start: proofData.window_start,
        window_end: proofData.window_end,
        meter_ids: proofData.meter_ids
      })));

      // Get current clock
      const clock = tx.sharedObjectRef({
        objectId: '0x6',
        initialSharedVersion: 1,
        mutable: false
      });

      console.log(`💎 Minting ${proofData.aggregate_kwh} sKWH tokens...`);
      
      // Call mint_skwh function
      const mintResult = tx.moveCall({
        target: `${this.packageId}::sKWH::mint_skwh`,
        arguments: [
          tx.object(this.registryId), // sKWH registry
          tx.pure(proofData.proof_id), // certificate_id (string)
          tx.pure(scaledKwh), // kwh_amount (u64)
          tx.pure(proofDataBytes), // proof_data (vector<u8>)
          tx.pure(proofData.walrus_cid || ''), // walrus_blob_url (string)
          clock, // clock
        ]
      });

      // If we have a kiosk, we can optionally place the certificate NFT in it
      if (kioskId) {
        console.log(`🏪 Placing certificate in kiosk: ${kioskId}`);
        // This would require additional kiosk operations
        // For now, we'll keep it simple and just mint
      }

      // Set gas budget
      tx.setGasBudget(100_000_000); // 0.1 SUI

      console.log(`📤 Submitting transaction...`);
      
      // Execute transaction
      const result = await this.client.signAndExecuteTransactionBlock({
        signer: this.keypair,
        transactionBlock: tx,
        options: {
          showEffects: true,
          showObjectChanges: true,
          showEvents: true
        }
      });

      console.log(`📋 Transaction: ${result.digest}`);

      // Check if transaction was successful
      if (result.effects?.status?.status !== 'success') {
        const error = result.effects?.status?.error || 'Unknown error';
        throw new Error(`Transaction failed: ${error}`);
      }

      // Extract created objects
      let certificateId: string | undefined;
      let skwhCoinId: string | undefined;

      result.objectChanges?.forEach(change => {
        if (change.type === 'created') {
          if (change.objectType?.includes('certificate::Certificate')) {
            certificateId = change.objectId;
          } else if (change.objectType?.includes('coin::Coin')) {
            skwhCoinId = change.objectId;
          }
        }
      });

      // Extract gas used
      const gasUsed = result.effects?.gasUsed?.computationCost || '0';
      const gasCostSui = (parseInt(gasUsed) / 1_000_000_000).toFixed(6);

      console.log(`✅ Mint successful!`);
      console.log(`   Transaction: ${result.digest}`);
      console.log(`   Certificate NFT: ${certificateId || 'Not found'}`);
      console.log(`   sKWH Coin: ${skwhCoinId || 'Not found'}`);
      console.log(`   Gas Used: ${gasCostSui} SUI`);

      // Show events
      if (result.events && result.events.length > 0) {
        console.log(`📢 Events emitted:`);
        result.events.forEach((event, index) => {
          console.log(`   ${index + 1}. ${event.type}`);
        });
      }

      return {
        success: true,
        transactionDigest: result.digest,
        certificateId,
        skwhCoinId,
        gasUsed: gasCostSui
      };

    } catch (error) {
      console.error(`❌ Mint failed: ${error}`);
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }

  async verifyMint(transactionDigest: string): Promise<void> {
    try {
      console.log(`🔍 Verifying transaction: ${transactionDigest}`);
      
      const txDetails = await this.client.getTransactionBlock({
        digest: transactionDigest,
        options: {
          showEffects: true,
          showObjectChanges: true,
          showEvents: true
        }
      });

      const status = txDetails.effects?.status?.status;
      console.log(`📊 Transaction Status: ${status}`);

      if (status === 'success') {
        console.log(`✅ Transaction verified successfully`);
        
        // Show created objects
        const createdObjects = txDetails.objectChanges?.filter(c => c.type === 'created') || [];
        if (createdObjects.length > 0) {
          console.log(`📦 Created Objects:`);
          createdObjects.forEach(obj => {
            if ('objectId' in obj) {
              console.log(`   ${obj.objectType}: ${obj.objectId}`);
            }
          });
        }
      } else {
        console.log(`❌ Transaction failed verification`);
      }
    } catch (error) {
      console.error(`⚠️  Verification failed: ${error}`);
    }
  }

  async getTokenBalance(): Promise<number> {
    try {
      const address = this.keypair.getPublicKey().toSuiAddress();
      
      // Get all coins owned by the address
      const coins = await this.client.getAllCoins({ owner: address });
      
      // Filter for sKWH coins
      const skwhCoins = coins.data.filter(coin => 
        coin.coinType.includes('sKWH') || 
        coin.coinType.includes(this.packageId)
      );

      let totalBalance = 0;
      skwhCoins.forEach(coin => {
        totalBalance += parseInt(coin.balance);
      });

      // Convert back from scaled integer
      return totalBalance / 1000;
    } catch (error) {
      console.warn(`⚠️  Could not fetch token balance: ${error}`);
      return 0;
    }
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'mint';
  
  const minter = new SuiMinter({
    network: (process.env.SUI_NETWORK as any) || 'testnet',
    packageId: process.env.SUI_PACKAGE_ID,
    registryId: process.env.SUI_SKWH_REGISTRY,
    privateKey: process.env.SUI_PRIVATE_KEY
  });

  try {
    switch (command) {
      case 'mint':
        const proofFile = args[1] || 'demo/proofs/latest_proof.json';
        
        console.log(`🚀 Minting sKWH tokens from proof...`);
        
        // Check if proof file exists
        try {
          await fs.access(proofFile);
        } catch {
          console.error(`❌ Proof file not found: ${proofFile}`);
          console.log(`💡 Run 'npm run demo:proof' to generate a proof first`);
          process.exit(1);
        }

        const proofData = await minter.readProofFile(proofFile);
        const result = await minter.mintFromProof(proofData);
        
        if (result.success) {
          console.log(`\n🎉 Minting completed successfully!`);
          
          // Save result for next steps
          const resultFile = 'demo/mint-result.json';
          await fs.writeFile(resultFile, JSON.stringify(result, null, 2));
          console.log(`💾 Result saved to: ${resultFile}`);
          
          if (result.transactionDigest) {
            await minter.verifyMint(result.transactionDigest);
          }
        } else {
          console.error(`❌ Minting failed: ${result.error}`);
          process.exit(1);
        }
        break;

      case 'balance':
        console.log(`💰 Checking sKWH token balance...`);
        const balance = await minter.getTokenBalance();
        console.log(`   Current Balance: ${balance.toFixed(3)} sKWH`);
        break;

      case 'verify':
        const txDigest = args[1];
        if (!txDigest) {
          console.error(`❌ Transaction digest required`);
          console.log(`Usage: npm run demo:mint verify <transaction-digest>`);
          process.exit(1);
        }
        await minter.verifyMint(txDigest);
        break;

      default:
        console.log(`
GreenShare Sui Minter

Usage:
  npm run demo:mint [command] [options]

Commands:
  mint [proof-file]     Mint sKWH tokens from proof (default: demo/proofs/latest_proof.json)
  balance               Check sKWH token balance
  verify <tx-digest>    Verify a mint transaction

Examples:
  npm run demo:mint                                    # Mint from latest proof
  npm run demo:mint mint demo/proofs/proof_123.json   # Mint from specific proof
  npm run demo:mint balance                            # Check balance
  npm run demo:mint verify 0x1234...                  # Verify transaction

Environment Variables:
  SUI_NETWORK           Sui network (testnet/devnet/mainnet)
  SUI_PRIVATE_KEY       Private key for minting
  SUI_PACKAGE_ID        GreenShare package ID
  SUI_SKWH_REGISTRY     sKWH registry object ID
        `);
        break;
    }
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

// Export for use as library
export { SuiMinter, type ProofData, type MintResult };

// Run CLI if called directly
if (require.main === module) {
  main().catch(console.error);
}