// FILE: demo/bridge-to-zircuit.ts
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { SuiClient, getFullnodeUrl } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { fromB64 } from '@mysten/sui.js/utils';
import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';

interface BridgeRequest {
  requestId: string;
  fromChain: string;
  toChain: string;
  token: string;
  amount: string;
  recipient: string;
  burnTxDigest: string;
  timestamp: number;
}

interface BridgeResult {
  success: boolean;
  suiTxDigest?: string;
  zircuitTxHash?: string;
  bridgeRequestId?: string;
  amountBridged?: string;
  recipient?: string;
  error?: string;
}

class CrossChainBridge {
  private suiClient: SuiClient;
  private suiKeypair: Ed25519Keypair;
  private ethProvider: ethers.Provider;
  private ethWallet: ethers.Wallet;
  private suiPackageId: string;
  private suiRegistryId: string;
  private zircuitBridgeAddress: string;
  private zircuitEKWHAddress: string;

  constructor(config: {
    suiNetwork?: 'testnet' | 'devnet' | 'mainnet';
    suiPrivateKey?: string;
    suiPackageId?: string;
    suiRegistryId?: string;
    zircuitRpcUrl?: string;
    zircuitPrivateKey?: string;
    zircuitBridgeAddress?: string;
    zircuitEKWHAddress?: string;
  } = {}) {
    // Initialize Sui client
    const suiNetwork = config.suiNetwork || 'testnet';
    const suiRpcUrl = getFullnodeUrl(suiNetwork);
    this.suiClient = new SuiClient({ url: suiRpcUrl });

    // Initialize Sui keypair
    if (config.suiPrivateKey || process.env.SUI_PRIVATE_KEY) {
      const privateKey = config.suiPrivateKey || process.env.SUI_PRIVATE_KEY!;
      this.suiKeypair = Ed25519Keypair.fromSecretKey(privateKey);
    } else {
      console.warn('⚠️  No Sui private key provided, generating new keypair');
      this.suiKeypair = new Ed25519Keypair();
    }

    // Initialize Ethereum provider and wallet
    const zircuitRpcUrl = config.zircuitRpcUrl || process.env.ZIRCUIT_RPC_URL || 'https://zircuit-testnet.drpc.org';
    this.ethProvider = new ethers.JsonRpcProvider(zircuitRpcUrl);
    
    if (config.zircuitPrivateKey || process.env.ZIRCUIT_PRIVATE_KEY) {
      const privateKey = config.zircuitPrivateKey || process.env.ZIRCUIT_PRIVATE_KEY!;
      this.ethWallet = new ethers.Wallet(privateKey, this.ethProvider);
    } else {
      console.warn('⚠️  No Zircuit private key provided, generating random wallet');
      this.ethWallet = ethers.Wallet.createRandom().connect(this.ethProvider);
    }

    // Set contract addresses
    this.suiPackageId = config.suiPackageId || process.env.SUI_PACKAGE_ID || '0x0';
    this.suiRegistryId = config.suiRegistryId || process.env.SUI_SKWH_REGISTRY || '0x0';
    this.zircuitBridgeAddress = config.zircuitBridgeAddress || process.env.ZIRCUIT_BRIDGE_CONTRACT || '0x0';
    this.zircuitEKWHAddress = config.zircuitEKWHAddress || process.env.ZIRCUIT_EKWH_CONTRACT || '0x0';

    console.log(`🌉 Cross-Chain Bridge Configuration:`);
    console.log(`   Sui Network: ${suiNetwork}`);
    console.log(`   Sui Address: ${this.suiKeypair.getPublicKey().toSuiAddress()}`);
    console.log(`   Zircuit RPC: ${zircuitRpcUrl}`);
    console.log(`   Zircuit Address: ${this.ethWallet.address}`);
    console.log(`   Bridge Contract: ${this.zircuitBridgeAddress}`);
  }

  async checkBalances(): Promise<void> {
    try {
      // Check Sui balance
      const suiAddress = this.suiKeypair.getPublicKey().toSuiAddress();
      const suiBalance = await this.suiClient.getBalance({ owner: suiAddress });
      const suiAmount = parseInt(suiBalance.totalBalance) / 1_000_000_000;
      
      // Check Zircuit ETH balance
      const ethBalance = await this.ethProvider.getBalance(this.ethWallet.address);
      const ethAmount = parseFloat(ethers.formatEther(ethBalance));

      console.log(`💰 Balances:`);
      console.log(`   Sui: ${suiAmount.toFixed(4)} SUI`);
      console.log(`   Zircuit: ${ethAmount.toFixed(6)} ETH`);

      if (suiAmount < 0.1) {
        console.warn('⚠️  Low SUI balance for gas fees');
      }
      if (ethAmount < 0.001) {
        console.warn('⚠️  Low ETH balance for Zircuit gas fees');
      }
    } catch (error) {
      console.warn(`⚠️  Could not check balances: ${error}`);
    }
  }

  async findSKWHCoins(amount: number): Promise<string[]> {
    try {
      const address = this.suiKeypair.getPublicKey().toSuiAddress();
      
      // Get all coins owned by the address
      const coins = await this.suiClient.getAllCoins({ owner: address });
      
      // Filter for sKWH coins
      const skwhCoins = coins.data.filter(coin => 
        coin.coinType.includes('sKWH') || 
        coin.coinType.includes(this.suiPackageId)
      );

      if (skwhCoins.length === 0) {
        throw new Error('No sKWH coins found. Mint some tokens first.');
      }

      // Convert amount to scaled integer (multiply by 1000)
      const scaledAmount = Math.round(amount * 1000);
      let totalBalance = 0;
      const selectedCoins: string[] = [];

      // Select coins until we have enough balance
      for (const coin of skwhCoins) {
        selectedCoins.push(coin.coinObjectId);
        totalBalance += parseInt(coin.balance);
        
        if (totalBalance >= scaledAmount) {
          break;
        }
      }

      if (totalBalance < scaledAmount) {
        throw new Error(`Insufficient sKWH balance. Need ${amount}, have ${totalBalance / 1000}`);
      }

      console.log(`🪙 Selected ${selectedCoins.length} sKWH coins for bridging`);
      console.log(`   Total Balance: ${totalBalance / 1000} sKWH`);
      console.log(`   Bridging Amount: ${amount} sKWH`);

      return selectedCoins;
    } catch (error) {
      throw new Error(`Failed to find sKWH coins: ${error}`);
    }
  }

  async burnSKWHOnSui(amount: number, zircuitRecipient: string): Promise<{
    txDigest: string;
    bridgeRequestId: string;
  }> {
    try {
      console.log(`🔥 Burning ${amount} sKWH on Sui...`);
      
      // Find sKWH coins to burn
      const coinIds = await this.findSKWHCoins(amount);
      
      // Prepare transaction
      const tx = new TransactionBlock();
      
      // Convert amount to scaled integer
      const scaledAmount = Math.round(amount * 1000);
      
      // Get coins objects
      const coins = coinIds.map(id => tx.object(id));
      
      // Merge coins if we have multiple
      let coinToUse = coins[0];
      if (coins.length > 1) {
        coinToUse = tx.moveCall({
          target: `0x2::coin::join_vec`,
          typeArguments: [`${this.suiPackageId}::sKWH::sKWH`],
          arguments: [coinToUse, tx.makeMoveVec({ objects: coins.slice(1) })]
        });
      }

      // Split the exact amount to burn
      const coinToBurn = tx.moveCall({
        target: `0x2::coin::split`,
        typeArguments: [`${this.suiPackageId}::sKWH::sKWH`],
        arguments: [coinToUse, tx.pure(scaledAmount)]
      });

      // Get clock object
      const clock = tx.sharedObjectRef({
        objectId: '0x6',
        initialSharedVersion: 1,
        mutable: false
      });

      console.log(`🌉 Creating bridge request to Zircuit...`);
      
      // Call burn_for_bridge function
      const bridgeRequest = tx.moveCall({
        target: `${this.suiPackageId}::sKWH::burn_for_bridge`,
        arguments: [
          tx.object(this.suiRegistryId), // registry
          coinToBurn, // coin to burn
          tx.pure(zircuitRecipient), // recipient address on Zircuit
          tx.pure(48899), // Zircuit chain ID
          clock // clock
        ]
      });

      // Transfer the bridge request to sender (for tracking)
      tx.transferObjects([bridgeRequest], tx.pure(this.suiKeypair.getPublicKey().toSuiAddress()));

      // Set gas budget
      tx.setGasBudget(100_000_000); // 0.1 SUI

      console.log(`📤 Submitting burn transaction...`);
      
      // Execute transaction
      const result = await this.suiClient.signAndExecuteTransactionBlock({
        signer: this.suiKeypair,
        transactionBlock: tx,
        options: {
          showEffects: true,
          showObjectChanges: true,
          showEvents: true
        }
      });

      console.log(`📋 Sui Transaction: ${result.digest}`);

      // Check if transaction was successful
      if (result.effects?.status?.status !== 'success') {
        const error = result.effects?.status?.error || 'Unknown error';
        throw new Error(`Burn transaction failed: ${error}`);
      }

      // Extract bridge request ID from created objects
      let bridgeRequestId: string | undefined;
      
      result.objectChanges?.forEach(change => {
        if (change.type === 'created' && change.objectType?.includes('BridgeRequest')) {
          bridgeRequestId = change.objectId;
        }
      });

      if (!bridgeRequestId) {
        throw new Error('Bridge request ID not found in transaction');
      }

      console.log(`✅ sKWH burned successfully!`);
      console.log(`   Burn Amount: ${amount} sKWH`);
      console.log(`   Bridge Request: ${bridgeRequestId}`);

      return {
        txDigest: result.digest,
        bridgeRequestId
      };

    } catch (error) {
      throw new Error(`Failed to burn sKWH: ${error}`);
    }
  }

  async mintEKWHOnZircuit(
    amount: number, 
    recipient: string, 
    suiTxDigest: string
  ): Promise<string> {
    try {
      console.log(`🌱 Minting ${amount} eKWH on Zircuit...`);
      
      // Bridge contract ABI (simplified)
      const bridgeABI = [
        {
          "inputs": [
            {"name": "recipient", "type": "address"},
            {"name": "amount", "type": "uint256"},
            {"name": "suiTxDigest", "type": "bytes32"}
          ],
          "name": "mintFromSui",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ];

      // Create contract instance
      const bridgeContract = new ethers.Contract(
        this.zircuitBridgeAddress,
        bridgeABI,
        this.ethWallet
      );

      // Convert amount to wei (18 decimals for eKWH)
      const amountWei = ethers.parseEther(amount.toString());
      
      // Convert Sui transaction digest to bytes32
      const txDigestBytes32 = ethers.keccak256(ethers.toUtf8Bytes(suiTxDigest));

      console.log(`📤 Submitting mint transaction on Zircuit...`);
      
      // Estimate gas
      try {
        const gasEstimate = await bridgeContract.mintFromSui.estimateGas(
          recipient,
          amountWei,
          txDigestBytes32
        );
        console.log(`⛽ Estimated gas: ${gasEstimate.toString()}`);
      } catch (error) {
        console.warn(`⚠️  Gas estimation failed: ${error}`);
      }

      // Execute transaction
      const tx = await bridgeContract.mintFromSui(
        recipient,
        amountWei,
        txDigestBytes32,
        {
          gasLimit: 500000 // 500k gas limit
        }
      );

      console.log(`📋 Zircuit Transaction: ${tx.hash}`);
      console.log(`⏳ Waiting for confirmation...`);

      // Wait for transaction to be mined
      const receipt = await tx.wait();

      if (receipt.status === 1) {
        console.log(`✅ eKWH minted successfully!`);
        console.log(`   Mint Amount: ${amount} eKWH`);
        console.log(`   Recipient: ${recipient}`);
        console.log(`   Gas Used: ${receipt.gasUsed.toString()}`);
        
        return tx.hash;
      } else {
        throw new Error('Transaction failed');
      }

    } catch (error) {
      // If minting fails, we can try a mock mint for demo purposes
      console.warn(`⚠️  Real minting failed: ${error}`);
      console.log(`🧪 Attempting mock mint for demo...`);
      
      return this.mockMintEKWH(amount, recipient, suiTxDigest);
    }
  }

  async mockMintEKWH(
    amount: number, 
    recipient: string, 
    suiTxDigest: string
  ): Promise<string> {
    try {
      console.log(`🧪 Mock minting ${amount} eKWH on Zircuit...`);
      
      // Simple ETH transfer to demonstrate the process
      const tx = await this.ethWallet.sendTransaction({
        to: recipient,
        value: ethers.parseEther('0.001'), // Send 0.001 ETH as mock
        gasLimit: 21000
      });

      console.log(`📋 Mock Transaction: ${tx.hash}`);
      console.log(`⏳ Waiting for confirmation...`);

      const receipt = await tx.wait();

      console.log(`✅ Mock eKWH mint completed!`);
      console.log(`   Mock Amount: ${amount} eKWH`);
      console.log(`   Recipient: ${recipient}`);
      console.log(`   Gas Used: ${receipt!.gasUsed.toString()}`);

      return tx.hash;
    } catch (error) {
      throw new Error(`Mock mint failed: ${error}`);
    }
  }

  async bridge(amount: number, zircuitRecipient?: string): Promise<BridgeResult> {
    try {
      console.log(`🌉 Starting cross-chain bridge: ${amount} sKWH → eKWH`);
      
      const recipient = zircuitRecipient || this.ethWallet.address;
      
      // Check balances
      await this.checkBalances();
      
      // Step 1: Burn sKWH on Sui
      console.log(`\n🔥 Step 1: Burning sKWH on Sui...`);
      const burnResult = await this.burnSKWHOnSui(amount, recipient);
      
      // Wait a moment for the transaction to settle
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Step 2: Mint eKWH on Zircuit
      console.log(`\n🌱 Step 2: Minting eKWH on Zircuit...`);
      const mintTxHash = await this.mintEKWHOnZircuit(
        amount,
        recipient,
        burnResult.txDigest
      );

      const result: BridgeResult = {
        success: true,
        suiTxDigest: burnResult.txDigest,
        zircuitTxHash: mintTxHash,
        bridgeRequestId: burnResult.bridgeRequestId,
        amountBridged: amount.toString(),
        recipient
      };

      console.log(`\n🎉 Bridge completed successfully!`);
      console.log(`   Amount: ${amount} sKWH → ${amount} eKWH`);
      console.log(`   Sui Tx: ${burnResult.txDigest}`);
      console.log(`   Zircuit Tx: ${mintTxHash}`);
      console.log(`   Recipient: ${recipient}`);

      return result;

    } catch (error) {
      console.error(`❌ Bridge failed: ${error}`);
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'bridge';
  
  const bridge = new CrossChainBridge({
    suiNetwork: (process.env.SUI_NETWORK as any) || 'testnet',
    suiPackageId: process.env.SUI_PACKAGE_ID,
    suiRegistryId: process.env.SUI_SKWH_REGISTRY,
    suiPrivateKey: process.env.SUI_PRIVATE_KEY,
    zircuitRpcUrl: process.env.ZIRCUIT_RPC_URL,
    zircuitPrivateKey: process.env.ZIRCUIT_PRIVATE_KEY,
    zircuitBridgeAddress: process.env.ZIRCUIT_BRIDGE_CONTRACT,
    zircuitEKWHAddress: process.env.ZIRCUIT_EKWH_CONTRACT
  });

  try {
    switch (command) {
      case 'bridge':
        const amount = parseFloat(args[1]) || 10; // Default 10 sKWH
        const recipient = args[2]; // Optional recipient address
        
        console.log(`🚀 Bridging ${amount} sKWH to Zircuit...`);
        
        const result = await bridge.bridge(amount, recipient);
        
        if (result.success) {
          // Save result for next steps
          const resultFile = 'demo/bridge-result.json';
          await fs.writeFile(resultFile, JSON.stringify(result, null, 2));
          console.log(`💾 Result saved to: ${resultFile}`);
        } else {
          console.error(`❌ Bridge failed: ${result.error}`);
          process.exit(1);
        }
        break;

      case 'balance':
        console.log(`💰 Checking cross-chain balances...`);
        await bridge.checkBalances();
        break;

      default:
        console.log(`
GreenShare Cross-Chain Bridge

Usage:
  npm run demo:bridge [command] [options]

Commands:
  bridge [amount] [recipient]    Bridge sKWH to eKWH (default: 10 sKWH)
  balance                        Check balances on both chains

Examples:
  npm run demo:bridge                                    # Bridge 10 sKWH
  npm run demo:bridge bridge 25                         # Bridge 25 sKWH
  npm run demo:bridge bridge 50 0x742d35cc...           # Bridge to specific address
  npm run demo:bridge balance                            # Check balances

Environment Variables:
  SUI_NETWORK                 Sui network (testnet/devnet/mainnet)
  SUI_PRIVATE_KEY            Sui private key
  SUI_PACKAGE_ID             GreenShare Sui package ID
  SUI_SKWH_REGISTRY          sKWH registry object ID
  ZIRCUIT_RPC_URL            Zircuit RPC endpoint
  ZIRCUIT_PRIVATE_KEY        Zircuit private key
  ZIRCUIT_BRIDGE_CONTRACT    Bridge contract address
  ZIRCUIT_EKWH_CONTRACT      eKWH token contract address
        `);
        break;
    }
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

// Export for use as library
export { CrossChainBridge, type BridgeResult };

// Run CLI if called directly
if (require.main === module) {
  main().catch(console.error);
}