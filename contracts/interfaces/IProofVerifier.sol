// FILE: contracts/interfaces/IProofVerifier.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IProofVerifier
 * @dev Interface for Celo Self Onchain SDK proof verification
 * @notice Supports various identity verification proofs
 */
interface IProofVerifier {
    // ==================== Structs ====================
    
    /**
     * @dev Identity proof structure
     * @param proofType Type of proof (age, sanctions, country, etc.)
     * @param proofData Encoded proof data
     * @param publicSignals Public signals for verification
     * @param nullifierHash Nullifier to prevent double-spending
     * @param merkleRoot Merkle root of the credential tree
     */
    struct IdentityProof {
        string proofType;
        bytes proofData;
        uint256[] publicSignals;
        bytes32 nullifierHash;
        bytes32 merkleRoot;
    }
    
    /**
     * @dev Verification result
     * @param isValid Whether the proof is valid
     * @param proofHash Hash of the verified proof
     * @param attributes Verified attributes (age>=18, country code, etc.)
     * @param timestamp Verification timestamp
     */
    struct VerificationResult {
        bool isValid;
        bytes32 proofHash;
        mapping(string => bytes32) attributes;
        uint256 timestamp;
    }
    
    /**
     * @dev KYC requirements structure
     * @param requireAgeProof Require age >= 18 proof
     * @param requireSanctionsProof Require non-sanctions list proof
     * @param requireCountryProof Require country verification
     * @param allowedCountries List of allowed country codes (empty = all allowed)
     * @param minAge Minimum required age
     */
    struct KYCRequirements {
        bool requireAgeProof;
        bool requireSanctionsProof;
        bool requireCountryProof;
        string[] allowedCountries;
        uint256 minAge;
    }
    
    // ==================== Events ====================
    
    event ProofVerified(
        address indexed user,
        bytes32 indexed proofHash,
        string proofType,
        bytes32 nullifierHash,
        uint256 timestamp
    );
    
    event ProofRejected(
        address indexed user,
        string proofType,
        string reason,
        uint256 timestamp
    );
    
    event RequirementsUpdated(
        KYCRequirements oldRequirements,
        KYCRequirements newRequirements,
        uint256 timestamp
    );
    
    // ==================== Functions ====================
    
    /**
     * @notice Verify identity proof
     * @param proof Identity proof to verify
     * @return result Verification result
     */
    function verifyProof(IdentityProof calldata proof) 
        external 
        returns (VerificationResult memory result);
    
    /**
     * @notice Batch verify multiple proofs
     * @param proofs Array of identity proofs
     * @return results Array of verification results
     */
    function batchVerifyProofs(IdentityProof[] calldata proofs)
        external
        returns (VerificationResult[] memory results);
    
    /**
     * @notice Check if proof type is supported
     * @param proofType Type of proof to check
     * @return supported Whether the proof type is supported
     */
    function isProofTypeSupported(string calldata proofType) 
        external 
        view 
        returns (bool supported);
    
    /**
     * @notice Get current KYC requirements
     * @return requirements Current KYC requirements
     */
    function getKYCRequirements() 
        external 
        view 
        returns (KYCRequirements memory requirements);
    
    /**
     * @notice Check if nullifier has been used
     * @param nullifierHash Nullifier hash to check
     * @return used Whether the nullifier has been used
     */
    function isNullifierUsed(bytes32 nullifierHash) 
        external 
        view 
        returns (bool used);
    
    /**
     * @notice Get verification result for user
     * @param user User address
     * @param proofType Type of proof
     * @return result Verification result
     */
    function getVerificationResult(address user, string calldata proofType)
        external
        view
        returns (VerificationResult memory result);
    
    /**
     * @notice Get supported proof types
     * @return proofTypes Array of supported proof type strings
     */
    function getSupportedProofTypes() 
        external 
        view 
        returns (string[] memory proofTypes);
}