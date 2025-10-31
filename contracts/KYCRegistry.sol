// FILE: contracts/KYCRegistry.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title KYCRegistry
 * @dev Registry for KYC verification using Celo Self Onchain SDK minimal disclosure proofs
 */
contract KYCRegistry is Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct KYCProof {
        address user;
        bytes32 proofHash;
        uint256 timestamp;
        uint256 expiryTime;
        bool isValid;
        string metadataURI; // IPFS URI for additional metadata
    }

    struct MinimalDisclosureProof {
        bytes32 commitment;
        bytes32 nullifier;
        bytes proof;
        uint256[] publicSignals;
    }

    // KYC status mapping
    mapping(address => KYCProof) public kycProofs;
    mapping(bytes32 => bool) public usedNullifiers;
    
    // Authorized verifiers (Celo Self Onchain SDK verifiers)
    mapping(address => bool) public authorizedVerifiers;
    
    // KYC validity period (default 1 year)
    uint256 public kycValidityPeriod = 365 days;
    
    // Minimum age requirement (in seconds since epoch)
    uint256 public minimumAge = 18 * 365 days;
    
    event KYCVerified(address indexed user, bytes32 proofHash, uint256 expiryTime);
    event KYCRevoked(address indexed user, string reason);
    event VerifierAuthorized(address indexed verifier, bool authorized);
    event KYCValidityPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    modifier onlyAuthorizedVerifier() {
        require(authorizedVerifiers[msg.sender], "KYCRegistry: Not authorized verifier");
        _;
    }

    modifier onlyValidKYC(address user) {
        require(isKYCValid(user), "KYCRegistry: Invalid or expired KYC");
        _;
    }

    constructor(address initialVerifier) {
        require(initialVerifier != address(0), "KYCRegistry: Invalid verifier");
        authorizedVerifiers[initialVerifier] = true;
        emit VerifierAuthorized(initialVerifier, true);
    }

    /**
     * @dev Submit KYC verification with minimal disclosure proof
     * @param user User address to verify
     * @param proof Minimal disclosure proof from Celo Self Onchain SDK
     * @param metadataURI IPFS URI for additional metadata
     */
    function submitKYC(
        address user,
        MinimalDisclosureProof calldata proof,
        string calldata metadataURI
    ) external onlyAuthorizedVerifier {
        require(user != address(0), "KYCRegistry: Invalid user address");
        require(proof.commitment != bytes32(0), "KYCRegistry: Invalid commitment");
        require(!usedNullifiers[proof.nullifier], "KYCRegistry: Nullifier already used");
        
        // Verify the minimal disclosure proof
        require(verifyMinimalDisclosureProof(proof), "KYCRegistry: Invalid proof");
        
        // Check age requirement from public signals
        require(proof.publicSignals.length > 0, "KYCRegistry: Missing age proof");
        uint256 birthTimestamp = proof.publicSignals[0];
        require(block.timestamp - birthTimestamp >= minimumAge, "KYCRegistry: User too young");
        
        bytes32 proofHash = keccak256(abi.encodePacked(
            proof.commitment,
            proof.nullifier,
            proof.proof
        ));
        
        uint256 expiryTime = block.timestamp + kycValidityPeriod;
        
        // Store KYC proof
        kycProofs[user] = KYCProof({
            user: user,
            proofHash: proofHash,
            timestamp: block.timestamp,
            expiryTime: expiryTime,
            isValid: true,
            metadataURI: metadataURI
        });
        
        // Mark nullifier as used to prevent double-spending
        usedNullifiers[proof.nullifier] = true;
        
        emit KYCVerified(user, proofHash, expiryTime);
    }

    /**
     * @dev Verify minimal disclosure proof (simplified for MVP)
     * @param proof The minimal disclosure proof
     * @return valid Whether the proof is valid
     */
    function verifyMinimalDisclosureProof(MinimalDisclosureProof calldata proof) 
        internal 
        pure 
        returns (bool valid) 
    {
        // Implement actual zk-SNARK proof verification
        // For production, integrate with Celo's zk-SNARK verifier
        require(proof.length == 128, "Invalid proof length"); // 4 * 32 bytes for proof elements
        require(publicSignals.length > 0, "Public signals required");
        
        // Mock verification - replace with actual verifier contract call
        // return IVerifier(verifierContract).verifyProof(proof, publicSignals);
        
        // Temporary mock verification for development
        bytes32 proofHash = keccak256(proof);
        bytes32 signalsHash = keccak256(abi.encodePacked(publicSignals));
        return proofHash != bytes32(0) && signalsHash != bytes32(0);
        // For MVP, we perform basic validation
        
        // Check that commitment and nullifier are not zero
        if (proof.commitment == bytes32(0) || proof.nullifier == bytes32(0)) {
            return false;
        }
        
        // Check that proof is not empty
        if (proof.proof.length == 0) {
            return false;
        }
        
        // Check that public signals contain required data
        if (proof.publicSignals.length == 0) {
            return false;
        }
        
        // Add actual zk-SNARK verification using Celo's verifier contract
        if (verifierContract != address(0)) {
            try IVerifier(verifierContract).verifyProof(proof, publicSignals) returns (bool result) {
                return result;
            } catch {
                return false;
            }
        }
        // For now, return true for valid structure
        return true;
    }

    /**
     * @dev Check if user has valid KYC
     * @param user User address
     * @return valid Whether KYC is valid and not expired
     */
    function isKYCValid(address user) public view returns (bool valid) {
        KYCProof memory proof = kycProofs[user];
        return proof.isValid && 
               proof.expiryTime > block.timestamp && 
               proof.timestamp > 0;
    }

    /**
     * @dev Get KYC proof details
     * @param user User address
     * @return proof The KYC proof details
     */
    function getKYCProof(address user) external view returns (KYCProof memory proof) {
        return kycProofs[user];
    }

    /**
     * @dev Revoke KYC for a user
     * @param user User address
     * @param reason Reason for revocation
     */
    function revokeKYC(address user, string calldata reason) external onlyOwner {
        require(kycProofs[user].timestamp > 0, "KYCRegistry: No KYC found");
        
        kycProofs[user].isValid = false;
        emit KYCRevoked(user, reason);
    }

    /**
     * @dev Authorize or deauthorize a verifier
     * @param verifier Verifier address
     * @param authorized Whether to authorize the verifier
     */
    function setAuthorizedVerifier(address verifier, bool authorized) external onlyOwner {
        require(verifier != address(0), "KYCRegistry: Invalid verifier");
        authorizedVerifiers[verifier] = authorized;
        emit VerifierAuthorized(verifier, authorized);
    }

    /**
     * @dev Update KYC validity period
     * @param newPeriod New validity period in seconds
     */
    function setKYCValidityPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "KYCRegistry: Invalid period");
        require(newPeriod <= 5 * 365 days, "KYCRegistry: Period too long");
        
        uint256 oldPeriod = kycValidityPeriod;
        kycValidityPeriod = newPeriod;
        emit KYCValidityPeriodUpdated(oldPeriod, newPeriod);
    }

    /**
     * @dev Update minimum age requirement
     * @param newMinimumAge New minimum age in seconds
     */
    function setMinimumAge(uint256 newMinimumAge) external onlyOwner {
        require(newMinimumAge > 0, "KYCRegistry: Invalid age");
        minimumAge = newMinimumAge;
    }

    /**
     * @dev Get all verified users count (for statistics)
     * @return count Number of users with valid KYC
     */
    function getVerifiedUsersCount() external view returns (uint256 count) {
        // Implement efficient counting mechanism
        uint256 count = 0;
        // In production, consider using a separate mapping to track count
        // for gas efficiency: mapping(address => uint256) public userKYCCount;
        for (uint256 i = 0; i < userProofs[user].length; i++) {
            if (userProofs[user][i].isValid && !userProofs[user][i].isRevoked) {
                count++;
            }
        }
        return count;
        // For MVP, this would require off-chain indexing
        return 0;
    }
}