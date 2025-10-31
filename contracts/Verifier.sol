// FILE: contracts/Verifier.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IProofVerifier.sol";

/**
 * @title Verifier
 * @dev Celo Self Onchain SDK proof verifier for identity credentials
 * @notice Verifies age, sanctions, and country proofs using zk-SNARKs
 */
contract Verifier is IProofVerifier, AccessControl, Pausable, ReentrancyGuard {
    // ==================== Constants ====================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIER_MANAGER_ROLE = keccak256("VERIFIER_MANAGER_ROLE");
    
    // Proof type constants
    string public constant PROOF_TYPE_AGE = "age_verification";
    string public constant PROOF_TYPE_SANCTIONS = "sanctions_verification";
    string public constant PROOF_TYPE_COUNTRY = "country_verification";
    string public constant PROOF_TYPE_COMPOSITE = "composite_verification";
    
    // ==================== State Variables ====================
    
    /// @notice Current KYC requirements
    KYCRequirements public kycRequirements;
    
    /// @notice Supported proof types
    mapping(string => bool) public supportedProofTypes;
    string[] public proofTypesList;
    
    /// @notice Used nullifiers to prevent double-spending
    mapping(bytes32 => bool) public usedNullifiers;
    
    /// @notice User verification results
    mapping(address => mapping(string => VerificationResult)) public userVerifications;
    
    /// @notice Valid merkle roots for credential verification
    mapping(bytes32 => bool) public validMerkleRoots;
    
    /// @notice Verification statistics
    struct VerificationStats {
        uint256 totalVerifications;
        uint256 successfulVerifications;
        uint256 rejectedVerifications;
        uint256 uniqueUsers;
    }
    
    VerificationStats public stats;
    
    /// @notice Track verified users
    mapping(address => bool) public verifiedUsers;
    
    // ==================== Constructor ====================
    
    constructor(address _admin) {
        require(_admin != address(0), "Verifier: admin cannot be zero address");
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(VERIFIER_MANAGER_ROLE, _admin);
        
        // Initialize supported proof types
        _addProofType(PROOF_TYPE_AGE);
        _addProofType(PROOF_TYPE_SANCTIONS);
        _addProofType(PROOF_TYPE_COUNTRY);
        _addProofType(PROOF_TYPE_COMPOSITE);
        
        // Set default KYC requirements
        kycRequirements = KYCRequirements({
            requireAgeProof: true,
            requireSanctionsProof: true,
            requireCountryProof: false,
            allowedCountries: new string[](0),
            minAge: 18
        });
    }
    
    // ==================== Main Verification Functions ====================
    
    /**
     * @notice Verify identity proof
     * @param proof Identity proof to verify
     * @return result Verification result
     */
    function verifyProof(IdentityProof calldata proof) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (VerificationResult memory result) 
    {
        stats.totalVerifications++;
        
        // Basic validation
        require(bytes(proof.proofType).length > 0, "Verifier: empty proof type");
        require(supportedProofTypes[proof.proofType], "Verifier: unsupported proof type");
        require(!usedNullifiers[proof.nullifierHash], "Verifier: nullifier already used");
        require(proof.proofData.length > 0, "Verifier: empty proof data");
        
        // Verify merkle root if specified
        if (proof.merkleRoot != bytes32(0)) {
            require(validMerkleRoots[proof.merkleRoot], "Verifier: invalid merkle root");
        }
        
        // Perform proof verification based on type
        (bool isValid, string memory reason) = _verifyProofByType(proof);
        
        if (!isValid) {
            stats.rejectedVerifications++;
            emit ProofRejected(msg.sender, proof.proofType, reason, block.timestamp);
            
            result = VerificationResult({
                isValid: false,
                proofHash: bytes32(0),
                timestamp: block.timestamp
            });
            return result;
        }
        
        // Mark nullifier as used
        usedNullifiers[proof.nullifierHash] = true;
        
        // Generate proof hash
        bytes32 proofHash = _generateProofHash(proof);
        
        // Store verification result
        result = VerificationResult({
            isValid: true,
            proofHash: proofHash,
            timestamp: block.timestamp
        });
        
        userVerifications[msg.sender][proof.proofType] = result;
        
        // Extract and store attributes
        _extractAndStoreAttributes(msg.sender, proof);
        
        // Update statistics
        stats.successfulVerifications++;
        if (!verifiedUsers[msg.sender]) {
            verifiedUsers[msg.sender] = true;
            stats.uniqueUsers++;
        }
        
        emit ProofVerified(
            msg.sender,
            proofHash,
            proof.proofType,
            proof.nullifierHash,
            block.timestamp
        );
        
        return result;
    }
    
    /**
     * @notice Batch verify multiple proofs
     * @param proofs Array of identity proofs
     * @return results Array of verification results
     */
    function batchVerifyProofs(IdentityProof[] calldata proofs)
        external
        override
        whenNotPaused
        nonReentrant
        returns (VerificationResult[] memory results)
    {
        require(proofs.length > 0, "Verifier: empty proofs array");
        require(proofs.length <= 10, "Verifier: too many proofs"); // Gas limit protection
        
        results = new VerificationResult[](proofs.length);
        
        for (uint256 i = 0; i < proofs.length; i++) {
            results[i] = this.verifyProof(proofs[i]);
        }
        
        return results;
    }
    
    // ==================== Proof Type Verification ====================
    
    /**
     * @notice Verify proof based on its type
     * @param proof Identity proof to verify
     * @return isValid Whether the proof is valid
     * @return reason Reason for rejection if invalid
     */
    function _verifyProofByType(IdentityProof calldata proof) 
        internal 
        view 
        returns (bool isValid, string memory reason) 
    {
        if (keccak256(bytes(proof.proofType)) == keccak256(bytes(PROOF_TYPE_AGE))) {
            return _verifyAgeProof(proof);
        } else if (keccak256(bytes(proof.proofType)) == keccak256(bytes(PROOF_TYPE_SANCTIONS))) {
            return _verifySanctionsProof(proof);
        } else if (keccak256(bytes(proof.proofType)) == keccak256(bytes(PROOF_TYPE_COUNTRY))) {
            return _verifyCountryProof(proof);
        } else if (keccak256(bytes(proof.proofType)) == keccak256(bytes(PROOF_TYPE_COMPOSITE))) {
            return _verifyCompositeProof(proof);
        } else {
            return (false, "Unsupported proof type");
        }
    }
    
    /**
     * @notice Verify age proof (age >= 18)
     */
    function _verifyAgeProof(IdentityProof calldata proof) 
        internal 
        view 
        returns (bool isValid, string memory reason) 
    {
        // In a real implementation, this would verify the zk-SNARK proof
        // For now, we'll do basic validation and mock verification
        
        if (proof.publicSignals.length < 1) {
            return (false, "Invalid age proof: missing age signal");
        }
        
        uint256 age = proof.publicSignals[0];
        if (age < kycRequirements.minAge) {
            return (false, "Age below minimum requirement");
        }
        
        // Mock zk-SNARK verification (would use actual verifier contract)
        if (proof.proofData.length < 32) {
            return (false, "Invalid age proof data");
        }
        
        return (true, "");
    }
    
    /**
     * @notice Verify sanctions proof (not on sanctions list)
     */
    function _verifySanctionsProof(IdentityProof calldata proof) 
        internal 
        view 
        returns (bool isValid, string memory reason) 
    {
        if (proof.publicSignals.length < 1) {
            return (false, "Invalid sanctions proof: missing signals");
        }
        
        uint256 sanctionsStatus = proof.publicSignals[0];
        if (sanctionsStatus != 0) {
            return (false, "User is on sanctions list");
        }
        
        // Mock zk-SNARK verification
        if (proof.proofData.length < 32) {
            return (false, "Invalid sanctions proof data");
        }
        
        return (true, "");
    }
    
    /**
     * @notice Verify country proof
     */
    function _verifyCountryProof(IdentityProof calldata proof) 
        internal 
        view 
        returns (bool isValid, string memory reason) 
    {
        if (proof.publicSignals.length < 1) {
            return (false, "Invalid country proof: missing country signal");
        }
        
        // If country restrictions are set, check them
        if (kycRequirements.allowedCountries.length > 0) {
            uint256 countryCode = proof.publicSignals[0];
            bool countryAllowed = false;
            
            // This is simplified - in practice, you'd have a more sophisticated mapping
            for (uint256 i = 0; i < kycRequirements.allowedCountries.length; i++) {
                // Convert country string to numeric code for comparison
                if (_countryStringToCode(kycRequirements.allowedCountries[i]) == countryCode) {
                    countryAllowed = true;
                    break;
                }
            }
            
            if (!countryAllowed) {
                return (false, "Country not in allowed list");
            }
        }
        
        // Mock zk-SNARK verification
        if (proof.proofData.length < 32) {
            return (false, "Invalid country proof data");
        }
        
        return (true, "");
    }
    
    /**
     * @notice Verify composite proof (combines multiple checks)
     */
    function _verifyCompositeProof(IdentityProof calldata proof) 
        internal 
        view 
        returns (bool isValid, string memory reason) 
    {
        if (proof.publicSignals.length < 3) {
            return (false, "Invalid composite proof: insufficient signals");
        }
        
        uint256 age = proof.publicSignals[0];
        uint256 sanctionsStatus = proof.publicSignals[1];
        uint256 countryCode = proof.publicSignals[2];
        
        // Check age requirement
        if (kycRequirements.requireAgeProof && age < kycRequirements.minAge) {
            return (false, "Age below minimum requirement");
        }
        
        // Check sanctions requirement
        if (kycRequirements.requireSanctionsProof && sanctionsStatus != 0) {
            return (false, "User is on sanctions list");
        }
        
        // Check country requirement
        if (kycRequirements.requireCountryProof && kycRequirements.allowedCountries.length > 0) {
            bool countryAllowed = false;
            for (uint256 i = 0; i < kycRequirements.allowedCountries.length; i++) {
                if (_countryStringToCode(kycRequirements.allowedCountries[i]) == countryCode) {
                    countryAllowed = true;
                    break;
                }
            }
            if (!countryAllowed) {
                return (false, "Country not in allowed list");
            }
        }
        
        // Mock zk-SNARK verification
        if (proof.proofData.length < 96) { // More data required for composite proof
            return (false, "Invalid composite proof data");
        }
        
        return (true, "");
    }
    
    // ==================== View Functions ====================
    
    /**
     * @notice Check if proof type is supported
     */
    function isProofTypeSupported(string calldata proofType) 
        external 
        view 
        override 
        returns (bool supported) 
    {
        return supportedProofTypes[proofType];
    }
    
    /**
     * @notice Get current KYC requirements
     */
    function getKYCRequirements() 
        external 
        view 
        override 
        returns (KYCRequirements memory requirements) 
    {
        return kycRequirements;
    }
    
    /**
     * @notice Check if nullifier has been used
     */
    function isNullifierUsed(bytes32 nullifierHash) 
        external 
        view 
        override 
        returns (bool used) 
    {
        return usedNullifiers[nullifierHash];
    }
    
    /**
     * @notice Get verification result for user
     */
    function getVerificationResult(address user, string calldata proofType)
        external
        view
        override
        returns (VerificationResult memory result)
    {
        return userVerifications[user][proofType];
    }
    
    /**
     * @notice Get supported proof types
     */
    function getSupportedProofTypes() 
        external 
        view 
        override 
        returns (string[] memory proofTypes) 
    {
        return proofTypesList;
    }
    
    /**
     * @notice Check if user has completed KYC
     */
    function isUserKYCCompleted(address user) external view returns (bool completed) {
        // Check if user has all required verifications
        if (kycRequirements.requireAgeProof) {
            if (!userVerifications[user][PROOF_TYPE_AGE].isValid) {
                return false;
            }
        }
        
        if (kycRequirements.requireSanctionsProof) {
            if (!userVerifications[user][PROOF_TYPE_SANCTIONS].isValid) {
                return false;
            }
        }
        
        if (kycRequirements.requireCountryProof) {
            if (!userVerifications[user][PROOF_TYPE_COUNTRY].isValid) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @notice Get verification statistics
     */
    function getVerificationStats() external view returns (VerificationStats memory) {
        return stats;
    }
    
    // ==================== Admin Functions ====================
    
    /**
     * @notice Update KYC requirements
     */
    function updateKYCRequirements(KYCRequirements calldata newRequirements) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(newRequirements.minAge >= 13, "Verifier: minimum age too low");
        require(newRequirements.minAge <= 100, "Verifier: minimum age too high");
        
        KYCRequirements memory oldRequirements = kycRequirements;
        kycRequirements = newRequirements;
        
        emit RequirementsUpdated(oldRequirements, newRequirements, block.timestamp);
    }
    
    /**
     * @notice Add valid merkle root
     */
    function addValidMerkleRoot(bytes32 merkleRoot) external onlyRole(VERIFIER_MANAGER_ROLE) {
        require(merkleRoot != bytes32(0), "Verifier: invalid merkle root");
        validMerkleRoots[merkleRoot] = true;
    }
    
    /**
     * @notice Remove valid merkle root
     */
    function removeValidMerkleRoot(bytes32 merkleRoot) external onlyRole(VERIFIER_MANAGER_ROLE) {
        validMerkleRoots[merkleRoot] = false;
    }
    
    /**
     * @notice Add supported proof type
     */
    function addProofType(string calldata proofType) external onlyRole(VERIFIER_MANAGER_ROLE) {
        _addProofType(proofType);
    }
    
    /**
     * @notice Remove supported proof type
     */
    function removeProofType(string calldata proofType) external onlyRole(VERIFIER_MANAGER_ROLE) {
        require(supportedProofTypes[proofType], "Verifier: proof type not supported");
        
        supportedProofTypes[proofType] = false;
        
        // Remove from list
        for (uint256 i = 0; i < proofTypesList.length; i++) {
            if (keccak256(bytes(proofTypesList[i])) == keccak256(bytes(proofType))) {
                proofTypesList[i] = proofTypesList[proofTypesList.length - 1];
                proofTypesList.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // ==================== Internal Functions ====================
    
    function _addProofType(string memory proofType) internal {
        require(bytes(proofType).length > 0, "Verifier: empty proof type");
        require(!supportedProofTypes[proofType], "Verifier: proof type already supported");
        
        supportedProofTypes[proofType] = true;
        proofTypesList.push(proofType);
    }
    
    function _generateProofHash(IdentityProof calldata proof) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            proof.proofType,
            proof.proofData,
            proof.publicSignals,
            proof.nullifierHash,
            proof.merkleRoot
        ));
    }
    
    function _extractAndStoreAttributes(address user, IdentityProof calldata proof) internal {
        // Extract attributes from public signals and store them
        // This is simplified - in practice, you'd have more sophisticated attribute extraction
        
        if (keccak256(bytes(proof.proofType)) == keccak256(bytes(PROOF_TYPE_AGE))) {
            if (proof.publicSignals.length > 0) {
                userVerifications[user][proof.proofType].attributes["age"] = bytes32(proof.publicSignals[0]);
            }
        } else if (keccak256(bytes(proof.proofType)) == keccak256(bytes(PROOF_TYPE_COUNTRY))) {
            if (proof.publicSignals.length > 0) {
                userVerifications[user][proof.proofType].attributes["country"] = bytes32(proof.publicSignals[0]);
            }
        }
    }
    
    function _countryStringToCode(string memory country) internal pure returns (uint256) {
        // Simplified country code mapping
        if (keccak256(bytes(country)) == keccak256(bytes("US"))) return 1;
        if (keccak256(bytes(country)) == keccak256(bytes("CA"))) return 2;
        if (keccak256(bytes(country)) == keccak256(bytes("GB"))) return 3;
        if (keccak256(bytes(country)) == keccak256(bytes("DE"))) return 4;
        if (keccak256(bytes(country)) == keccak256(bytes("FR"))) return 5;
        return 0; // Unknown country
    }
}