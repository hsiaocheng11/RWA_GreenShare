// FILE: pages/kyc.tsx
import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import { useConnect, useAccount, useDisconnect } from 'wagmi';
import { InjectedConnector } from '@wagmi/connectors/injected';
import Head from 'next/head';

// Contract ABI imports (simplified for demo)
const VERIFIER_ABI = [
  "function verifyProof((string,bytes,uint256[],bytes32,bytes32)) external returns ((bool,bytes32,uint256))",
  "function getSupportedProofTypes() external view returns (string[])",
  "function getKYCRequirements() external view returns ((bool,bool,bool,string[],uint256))",
  "function getVerificationResult(address,string) external view returns ((bool,bytes32,uint256))",
  "event ProofVerified(address indexed user, bytes32 indexed proofHash, string proofType, bytes32 nullifierHash, uint256 timestamp)",
  "event ProofRejected(address indexed user, string proofType, string reason, uint256 timestamp)"
];

const KYC_REGISTRY_ABI = [
  "function processKYCVerification(address,string[]) external",
  "function getUserKYCInfo(address) external view returns ((uint8,bool,uint256,uint256,uint256,uint256,string[],bool))",
  "function isWhitelisted(address) external view returns (bool)",
  "function getKYCLevel(address) external view returns (uint8)",
  "function getBridgeLimit(address) external view returns (uint256)",
  "function getTradingLimit(address) external view returns (uint256)",
  "event KYCStatusUpdated(address indexed user, uint8 oldLevel, uint8 newLevel, bool whitelisted, uint256 timestamp)"
];

// Contract addresses (should come from environment)
const CONTRACT_ADDRESSES = {
  verifier: process.env.NEXT_PUBLIC_VERIFIER_ADDRESS || "0x...",
  kycRegistry: process.env.NEXT_PUBLIC_KYC_REGISTRY_ADDRESS || "0x..."
};

interface IdentityProof {
  proofType: string;
  proofData: string;
  publicSignals: number[];
  nullifierHash: string;
  merkleRoot: string;
}

interface KYCInfo {
  kycLevel: number;
  isWhitelisted: boolean;
  bridgeLimit: string;
  tradingLimit: string;
  lastVerification: number;
  verificationExpiry: number;
  completedProofs: string[];
  isActive: boolean;
}

interface ProofGenerationData {
  age: number;
  country: string;
  sanctionsStatus: boolean;
  documentType: string;
  documentNumber: string;
}

const KYCPage: React.FC = () => {
  // Wallet connection
  const { address, isConnected } = useAccount();
  const { connect } = useConnect({
    connector: new InjectedConnector(),
  });
  const { disconnect } = useDisconnect();

  // State
  const [loading, setLoading] = useState(false);
  const [currentStep, setCurrentStep] = useState(1);
  const [proofData, setProofData] = useState<ProofGenerationData>({
    age: 18,
    country: '',
    sanctionsStatus: false,
    documentType: 'passport',
    documentNumber: ''
  });
  const [generatedProofs, setGeneratedProofs] = useState<IdentityProof[]>([]);
  const [verificationResults, setVerificationResults] = useState<any[]>([]);
  const [kycInfo, setKYCInfo] = useState<KYCInfo | null>(null);
  const [supportedProofs, setSupportedProofs] = useState<string[]>([]);
  const [kycRequirements, setKYCRequirements] = useState<any>(null);

  // Load contract data on mount
  useEffect(() => {
    if (isConnected && address) {
      loadContractData();
      loadUserKYCInfo();
    }
  }, [isConnected, address]);

  const loadContractData = async () => {
    try {
      if (!window.ethereum) return;
      
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const verifierContract = new ethers.Contract(
        CONTRACT_ADDRESSES.verifier,
        VERIFIER_ABI,
        provider
      );

      // Load supported proof types
      const proofTypes = await verifierContract.getSupportedProofTypes();
      setSupportedProofs(proofTypes);

      // Load KYC requirements
      const requirements = await verifierContract.getKYCRequirements();
      setKYCRequirements({
        requireAgeProof: requirements[0],
        requireSanctionsProof: requirements[1],
        requireCountryProof: requirements[2],
        allowedCountries: requirements[3],
        minAge: requirements[4].toNumber()
      });

    } catch (error) {
      console.error('Error loading contract data:', error);
    }
  };

  const loadUserKYCInfo = async () => {
    try {
      if (!window.ethereum || !address) return;
      
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const kycContract = new ethers.Contract(
        CONTRACT_ADDRESSES.kycRegistry,
        KYC_REGISTRY_ABI,
        provider
      );

      const userInfo = await kycContract.getUserKYCInfo(address);
      setKYCInfo({
        kycLevel: userInfo[0],
        isWhitelisted: userInfo[1],
        bridgeLimit: ethers.utils.formatUnits(userInfo[2], 6),
        tradingLimit: ethers.utils.formatUnits(userInfo[3], 6),
        lastVerification: userInfo[4].toNumber(),
        verificationExpiry: userInfo[5].toNumber(),
        completedProofs: userInfo[6],
        isActive: userInfo[7]
      });

    } catch (error) {
      console.error('Error loading user KYC info:', error);
    }
  };

  const generateMockProof = (proofType: string): IdentityProof => {
    // This is a mock proof generator for demonstration
    // In a real implementation, this would use the Celo Self Onchain SDK
    
    let publicSignals: number[] = [];
    
    if (proofType === 'age_verification') {
      publicSignals = [proofData.age];
    } else if (proofType === 'sanctions_verification') {
      publicSignals = [proofData.sanctionsStatus ? 1 : 0];
    } else if (proofType === 'country_verification') {
      // Simple country code mapping
      const countryCode = getCountryCode(proofData.country);
      publicSignals = [countryCode];
    } else if (proofType === 'composite_verification') {
      publicSignals = [
        proofData.age,
        proofData.sanctionsStatus ? 1 : 0,
        getCountryCode(proofData.country)
      ];
    }

    return {
      proofType,
      proofData: ethers.utils.hexlify(ethers.utils.randomBytes(64)),
      publicSignals,
      nullifierHash: ethers.utils.keccak256(
        ethers.utils.toUtf8Bytes(`${address}_${proofType}_${Date.now()}`)
      ),
      merkleRoot: ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test_merkle_root_1"))
    };
  };

  const getCountryCode = (country: string): number => {
    const codes: { [key: string]: number } = {
      'US': 1, 'CA': 2, 'GB': 3, 'DE': 4, 'FR': 5,
      'JP': 6, 'KR': 7, 'SG': 8, 'AU': 9, 'NZ': 10
    };
    return codes[country] || 0;
  };

  const generateProofs = async () => {
    setLoading(true);
    try {
      const proofs: IdentityProof[] = [];
      
      // Generate required proofs based on requirements
      if (kycRequirements?.requireAgeProof) {
        proofs.push(generateMockProof('age_verification'));
      }
      
      if (kycRequirements?.requireSanctionsProof) {
        proofs.push(generateMockProof('sanctions_verification'));
      }
      
      if (kycRequirements?.requireCountryProof) {
        proofs.push(generateMockProof('country_verification'));
      }

      // Or generate composite proof if all are required
      if (kycRequirements?.requireAgeProof && 
          kycRequirements?.requireSanctionsProof && 
          kycRequirements?.requireCountryProof) {
        proofs.length = 0; // Clear individual proofs
        proofs.push(generateMockProof('composite_verification'));
      }

      setGeneratedProofs(proofs);
      setCurrentStep(3);
      
    } catch (error) {
      console.error('Error generating proofs:', error);
      alert('Failed to generate proofs. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const submitProofs = async () => {
    if (!window.ethereum || !address) return;
    
    setLoading(true);
    try {
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      
      const verifierContract = new ethers.Contract(
        CONTRACT_ADDRESSES.verifier,
        VERIFIER_ABI,
        signer
      );

      const results = [];

      // Submit each proof
      for (const proof of generatedProofs) {
        console.log('Submitting proof:', proof.proofType);
        
        const tx = await verifierContract.verifyProof([
          proof.proofType,
          proof.proofData,
          proof.publicSignals,
          proof.nullifierHash,
          proof.merkleRoot
        ]);
        
        const receipt = await tx.wait();
        console.log('Proof verification receipt:', receipt);
        
        // Parse events to get result
        const events = receipt.events?.filter((x: any) => x.event === 'ProofVerified' || x.event === 'ProofRejected');
        results.push({
          proofType: proof.proofType,
          success: events?.some((e: any) => e.event === 'ProofVerified'),
          txHash: receipt.transactionHash
        });
      }

      setVerificationResults(results);

      // If all proofs verified successfully, process KYC
      const allSuccessful = results.every(r => r.success);
      if (allSuccessful) {
        await processKYCVerification();
      }

      setCurrentStep(4);
      
    } catch (error) {
      console.error('Error submitting proofs:', error);
      alert('Failed to submit proofs. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const processKYCVerification = async () => {
    if (!window.ethereum || !address) return;
    
    try {
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      
      const kycContract = new ethers.Contract(
        CONTRACT_ADDRESSES.kycRegistry,
        KYC_REGISTRY_ABI,
        signer
      );

      const proofTypes = generatedProofs.map(p => p.proofType);
      
      console.log('Processing KYC verification for proofs:', proofTypes);
      
      const tx = await kycContract.processKYCVerification(address, proofTypes);
      await tx.wait();
      
      // Reload user KYC info
      await loadUserKYCInfo();
      
    } catch (error) {
      console.error('Error processing KYC verification:', error);
      // Note: This might fail if called by non-KYC_MANAGER, which is expected in this demo
    }
  };

  const renderStepContent = () => {
    switch (currentStep) {
      case 1:
        return (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold text-gray-800">Connect Your Wallet</h2>
            <p className="text-gray-600">
              Connect your wallet to start the KYC verification process.
            </p>
            
            {!isConnected ? (
              <button
                onClick={() => connect()}
                className="w-full bg-blue-600 text-white py-3 px-6 rounded-lg hover:bg-blue-700 transition-colors"
              >
                Connect Wallet
              </button>
            ) : (
              <div className="space-y-4">
                <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
                  <p className="text-green-800">✅ Wallet Connected: {address}</p>
                </div>
                <button
                  onClick={() => setCurrentStep(2)}
                  className="w-full bg-green-600 text-white py-3 px-6 rounded-lg hover:bg-green-700 transition-colors"
                >
                  Continue to Identity Verification
                </button>
              </div>
            )}
          </div>
        );

      case 2:
        return (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold text-gray-800">Identity Information</h2>
            <p className="text-gray-600">
              Please provide your identity information to generate verification proofs.
            </p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Age
                </label>
                <input
                  type="number"
                  min="13"
                  max="100"
                  value={proofData.age}
                  onChange={(e) => setProofData({...proofData, age: parseInt(e.target.value)})}
                  className="w-full p-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Country
                </label>
                <select
                  value={proofData.country}
                  onChange={(e) => setProofData({...proofData, country: e.target.value})}
                  className="w-full p-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">Select Country</option>
                  <option value="US">United States</option>
                  <option value="CA">Canada</option>
                  <option value="GB">United Kingdom</option>
                  <option value="DE">Germany</option>
                  <option value="FR">France</option>
                  <option value="JP">Japan</option>
                  <option value="KR">South Korea</option>
                  <option value="SG">Singapore</option>
                  <option value="AU">Australia</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Document Type
                </label>
                <select
                  value={proofData.documentType}
                  onChange={(e) => setProofData({...proofData, documentType: e.target.value})}
                  className="w-full p-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="passport">Passport</option>
                  <option value="national_id">National ID</option>
                  <option value="driver_license">Driver's License</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Document Number
                </label>
                <input
                  type="text"
                  value={proofData.documentNumber}
                  onChange={(e) => setProofData({...proofData, documentNumber: e.target.value})}
                  placeholder="Enter document number"
                  className="w-full p-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
            </div>

            <div className="flex items-center space-x-2">
              <input
                type="checkbox"
                id="sanctions"
                checked={!proofData.sanctionsStatus}
                onChange={(e) => setProofData({...proofData, sanctionsStatus: !e.target.checked})}
                className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
              />
              <label htmlFor="sanctions" className="text-sm text-gray-700">
                I confirm that I am not on any sanctions list
              </label>
            </div>

            {kycRequirements && (
              <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <h3 className="font-medium text-blue-900 mb-2">Required Verifications:</h3>
                <ul className="text-sm text-blue-800 space-y-1">
                  {kycRequirements.requireAgeProof && (
                    <li>✓ Age verification (minimum: {kycRequirements.minAge})</li>
                  )}
                  {kycRequirements.requireSanctionsProof && (
                    <li>✓ Sanctions list verification</li>
                  )}
                  {kycRequirements.requireCountryProof && (
                    <li>✓ Country verification</li>
                  )}
                </ul>
              </div>
            )}

            <button
              onClick={generateProofs}
              disabled={loading || !proofData.country || !proofData.documentNumber}
              className="w-full bg-blue-600 text-white py-3 px-6 rounded-lg hover:bg-blue-700 disabled:bg-gray-400 transition-colors"
            >
              {loading ? 'Generating Proofs...' : 'Generate Identity Proofs'}
            </button>
          </div>
        );

      case 3:
        return (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold text-gray-800">Review Generated Proofs</h2>
            <p className="text-gray-600">
              Review your generated identity proofs before submitting to the blockchain.
            </p>

            <div className="space-y-4">
              {generatedProofs.map((proof, index) => (
                <div key={index} className="p-4 bg-gray-50 border border-gray-200 rounded-lg">
                  <h3 className="font-medium text-gray-900 mb-2">
                    {proof.proofType.replace('_', ' ').toUpperCase()}
                  </h3>
                  <div className="text-sm text-gray-600 space-y-1">
                    <p><strong>Public Signals:</strong> [{proof.publicSignals.join(', ')}]</p>
                    <p><strong>Nullifier:</strong> {proof.nullifierHash.slice(0, 20)}...</p>
                    <p><strong>Merkle Root:</strong> {proof.merkleRoot.slice(0, 20)}...</p>
                  </div>
                </div>
              ))}
            </div>

            <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
              <p className="text-yellow-800 text-sm">
                ⚠️ This is a demo using mock proofs. In production, these would be generated using the Celo Self Onchain SDK with real identity credentials.
              </p>
            </div>

            <button
              onClick={submitProofs}
              disabled={loading}
              className="w-full bg-green-600 text-white py-3 px-6 rounded-lg hover:bg-green-700 disabled:bg-gray-400 transition-colors"
            >
              {loading ? 'Submitting Proofs...' : 'Submit Proofs to Blockchain'}
            </button>
          </div>
        );

      case 4:
        return (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold text-gray-800">Verification Results</h2>
            
            <div className="space-y-4">
              {verificationResults.map((result, index) => (
                <div key={index} className={`p-4 border rounded-lg ${
                  result.success ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'
                }`}>
                  <div className="flex items-center justify-between">
                    <h3 className="font-medium">
                      {result.proofType.replace('_', ' ').toUpperCase()}
                    </h3>
                    <span className={`px-2 py-1 rounded text-sm ${
                      result.success ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
                    }`}>
                      {result.success ? 'Verified' : 'Rejected'}
                    </span>
                  </div>
                  <p className="text-sm text-gray-600 mt-2">
                    Transaction: <a 
                      href={`https://explorer.zircuit.com/tx/${result.txHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-blue-600 hover:underline"
                    >
                      {result.txHash.slice(0, 20)}...
                    </a>
                  </p>
                </div>
              ))}
            </div>

            {kycInfo && (
              <div className="p-6 bg-blue-50 border border-blue-200 rounded-lg">
                <h3 className="font-medium text-blue-900 mb-4">Your KYC Status</h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-blue-700">KYC Level:</span>
                    <span className="ml-2 font-medium">{kycInfo.kycLevel}</span>
                  </div>
                  <div>
                    <span className="text-blue-700">Whitelisted:</span>
                    <span className={`ml-2 font-medium ${kycInfo.isWhitelisted ? 'text-green-600' : 'text-red-600'}`}>
                      {kycInfo.isWhitelisted ? 'Yes' : 'No'}
                    </span>
                  </div>
                  <div>
                    <span className="text-blue-700">Bridge Limit:</span>
                    <span className="ml-2 font-medium">{kycInfo.bridgeLimit} eKWH</span>
                  </div>
                  <div>
                    <span className="text-blue-700">Trading Limit:</span>
                    <span className="ml-2 font-medium">{kycInfo.tradingLimit} eKWH</span>
                  </div>
                </div>
              </div>
            )}

            <button
              onClick={() => {
                setCurrentStep(1);
                setGeneratedProofs([]);
                setVerificationResults([]);
              }}
              className="w-full bg-gray-600 text-white py-3 px-6 rounded-lg hover:bg-gray-700 transition-colors"
            >
              Start New Verification
            </button>
          </div>
        );

      default:
        return null;
    }
  };

  return (
    <>
      <Head>
        <title>KYC Verification - GreenShare</title>
        <meta name="description" content="Complete your KYC verification using Celo Self Onchain SDK" />
      </Head>

      <div className="min-h-screen bg-gray-100 py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-2xl mx-auto">
          <div className="bg-white shadow-xl rounded-lg overflow-hidden">
            {/* Header */}
            <div className="bg-gradient-to-r from-blue-600 to-green-600 px-6 py-4">
              <h1 className="text-2xl font-bold text-white">KYC Verification</h1>
              <p className="text-blue-100 mt-1">Verify your identity using Celo Self Onchain SDK</p>
            </div>

            {/* Progress Bar */}
            <div className="px-6 py-4 bg-gray-50 border-b">
              <div className="flex items-center justify-between">
                {[1, 2, 3, 4].map((step) => (
                  <div key={step} className="flex items-center">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                      step <= currentStep 
                        ? 'bg-blue-600 text-white' 
                        : 'bg-gray-300 text-gray-600'
                    }`}>
                      {step}
                    </div>
                    {step < 4 && (
                      <div className={`w-20 h-1 mx-2 ${
                        step < currentStep ? 'bg-blue-600' : 'bg-gray-300'
                      }`} />
                    )}
                  </div>
                ))}
              </div>
              <div className="flex justify-between mt-2 text-xs text-gray-600">
                <span>Connect</span>
                <span>Identity</span>
                <span>Proofs</span>
                <span>Results</span>
              </div>
            </div>

            {/* Content */}
            <div className="px-6 py-8">
              {renderStepContent()}
            </div>

            {/* Footer */}
            <div className="px-6 py-4 bg-gray-50 border-t">
              <p className="text-xs text-gray-500 text-center">
                Powered by Celo Self Onchain SDK • GreenShare KYC System
              </p>
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

export default KYCPage;