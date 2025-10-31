// FILE: contracts/MockVerifier.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVerifier.sol";

/**
 * @title MockVerifier
 * @dev Mock implementation of IVerifier for testing and development
 * @notice This is a simplified verifier that can be configured for testing scenarios
 */
contract MockVerifier is IVerifier, Ownable {
    // ==================== State Variables ====================
    
    /// @notice Whether to always return valid results (for testing)
    bool public alwaysValid;
    
    /// @notice Whether to always return invalid results (for testing)
    bool public alwaysInvalid;
    
    /// @notice Custom rejection reason for testing
    string public customRejectionReason;
    
    /// @notice Minimum confirmations required
    uint256 public minConfirmations;
    
    /// @notice Maximum proof age in seconds
    uint256 public maxProofAge;
    
    /// @notice Processed operations to prevent replay
    mapping(bytes32 => bool) public processedOperations;
    
    /// @notice Valid merkle roots for testing
    mapping(bytes32 => bool) public validMerkleRoots;
    
    /// @notice Valid signers for testing
    mapping(address => bool) public validSigners;
    
    // ==================== Constructor ====================
    
    constructor(
        address _owner,
        uint256 _minConfirmations,
        uint256 _maxProofAge
    ) {
        require(_owner != address(0), "MockVerifier: owner cannot be zero");
        
        _transferOwnership(_owner);
        minConfirmations = _minConfirmations;
        maxProofAge = _maxProofAge;
        
        // Set reasonable defaults
        alwaysValid = false;
        alwaysInvalid = false;
        customRejectionReason = "Mock verification failed";
    }
    
    // ==================== IVerifier Implementation ====================
    
    /**
     * @notice Verify Sui state proof for bridge operation
     * @param proof Sui state proof data
     * @param operation Bridge operation details
     * @return valid Whether the proof is valid
     * @return reason Reason for rejection (if invalid)
     */
    function verifyProof(
        SuiProof calldata proof,
        BridgeOperation calldata operation
    ) external override returns (bool valid, string memory reason) {
        // Check if operation already processed
        if (processedOperations[operation.operationId]) {
            emit ProofRejected(operation.operationId, "Operation already processed", block.timestamp);
            return (false, "Operation already processed");
        }
        
        // Test mode: always valid
        if (alwaysValid) {
            processedOperations[operation.operationId] = true;
            emit ProofVerified(
                operation.operationId,
                proof.merkleRoot,
                operation.recipient,
                operation.amount,
                block.timestamp
            );
            return (true, "");
        }
        
        // Test mode: always invalid
        if (alwaysInvalid) {
            emit ProofRejected(operation.operationId, customRejectionReason, block.timestamp);
            return (false, customRejectionReason);
        }
        
        // Basic validations
        if (proof.timestamp == 0) {
            emit ProofRejected(operation.operationId, "Invalid timestamp", block.timestamp);
            return (false, "Invalid timestamp");
        }
        
        if (proof.blockHeight == 0) {
            emit ProofRejected(operation.operationId, "Invalid block height", block.timestamp);
            return (false, "Invalid block height");
        }
        
        if (bytes(proof.proofHash).length == 0) {
            emit ProofRejected(operation.operationId, "Invalid proof hash", block.timestamp);
            return (false, "Invalid proof hash");
        }
        
        // Check proof age
        if (block.timestamp > proof.timestamp + maxProofAge) {
            emit ProofRejected(operation.operationId, "Proof too old", block.timestamp);
            return (false, "Proof too old");
        }
        
        // Check if merkle root is in whitelist (if configured)
        if (validMerkleRoots[proof.merkleRoot] == false && _hasValidMerkleRoots()) {
            emit ProofRejected(operation.operationId, "Invalid merkle root", block.timestamp);
            return (false, "Invalid merkle root");
        }
        
        // Verify signature (simplified mock verification)
        if (!_verifySignature(proof)) {
            emit ProofRejected(operation.operationId, "Invalid signature", block.timestamp);
            return (false, "Invalid signature");
        }
        
        // Mark as processed
        processedOperations[operation.operationId] = true;
        
        emit ProofVerified(
            operation.operationId,
            proof.merkleRoot,
            operation.recipient,
            operation.amount,
            block.timestamp
        );
        
        return (true, "");
    }
    
    /**
     * @notice Check if a proof has been used before
     * @param operationId Operation identifier to check
     * @return used Whether the operation has been used
     */
    function isProofUsed(bytes32 operationId) external view override returns (bool used) {
        return processedOperations[operationId];
    }
    
    /**
     * @notice Get verifier configuration
     * @return name Verifier implementation name
     * @return version Verifier version
     * @return supportedProofTypes Supported proof type identifiers
     */
    function getVerifierInfo() external pure override returns (
        string memory name,
        string memory version,
        string[] memory supportedProofTypes
    ) {
        name = "MockVerifier";
        version = "1.0.0";
        supportedProofTypes = new string[](2);
        supportedProofTypes[0] = "sui_merkle_proof";
        supportedProofTypes[1] = "sui_state_proof";
    }
    
    /**
     * @notice Get minimum required confirmations
     * @return confirmations Number of confirmations required
     */
    function getMinConfirmations() external view override returns (uint256 confirmations) {
        return minConfirmations;
    }
    
    /**
     * @notice Get maximum proof age allowed
     * @return maxAge Maximum age in seconds
     */
    function getMaxProofAge() external view override returns (uint256 maxAge) {
        return maxProofAge;
    }
    
    // ==================== Admin Functions ====================
    
    /**
     * @notice Set test mode to always return valid
     * @param _alwaysValid Whether to always return valid
     */
    function setAlwaysValid(bool _alwaysValid) external onlyOwner {
        alwaysValid = _alwaysValid;
        if (_alwaysValid) {
            alwaysInvalid = false;
        }
    }
    
    /**
     * @notice Set test mode to always return invalid
     * @param _alwaysInvalid Whether to always return invalid
     * @param _reason Custom rejection reason
     */
    function setAlwaysInvalid(bool _alwaysInvalid, string calldata _reason) external onlyOwner {
        alwaysInvalid = _alwaysInvalid;
        if (_alwaysInvalid) {
            alwaysValid = false;
            customRejectionReason = _reason;
        }
    }
    
    /**
     * @notice Add valid merkle root for testing
     * @param merkleRoot Merkle root to whitelist
     */
    function addValidMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        validMerkleRoots[merkleRoot] = true;
    }
    
    /**
     * @notice Remove valid merkle root
     * @param merkleRoot Merkle root to remove from whitelist
     */
    function removeValidMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        validMerkleRoots[merkleRoot] = false;
    }
    
    /**
     * @notice Add valid signer for testing
     * @param signer Signer address to whitelist
     */
    function addValidSigner(address signer) external onlyOwner {
        require(signer != address(0), "MockVerifier: invalid signer");
        validSigners[signer] = true;
    }
    
    /**
     * @notice Remove valid signer
     * @param signer Signer address to remove from whitelist
     */
    function removeValidSigner(address signer) external onlyOwner {
        validSigners[signer] = false;
    }
    
    /**
     * @notice Update minimum confirmations
     * @param _minConfirmations New minimum confirmations
     */
    function updateMinConfirmations(uint256 _minConfirmations) external onlyOwner {
        minConfirmations = _minConfirmations;
    }
    
    /**
     * @notice Update maximum proof age
     * @param _maxProofAge New maximum proof age in seconds
     */
    function updateMaxProofAge(uint256 _maxProofAge) external onlyOwner {
        require(_maxProofAge > 0, "MockVerifier: max proof age must be positive");
        maxProofAge = _maxProofAge;
    }
    
    /**
     * @notice Reset processed operation (for testing)
     * @param operationId Operation ID to reset
     */
    function resetProcessedOperation(bytes32 operationId) external onlyOwner {
        processedOperations[operationId] = false;
    }
    
    // ==================== View Functions ====================
    
    /**
     * @notice Check if merkle root is valid
     * @param merkleRoot Merkle root to check
     * @return valid Whether the merkle root is valid
     */
    function isValidMerkleRoot(bytes32 merkleRoot) external view returns (bool valid) {
        return !_hasValidMerkleRoots() || validMerkleRoots[merkleRoot];
    }
    
    /**
     * @notice Check if signer is valid
     * @param signer Signer address to check
     * @return valid Whether the signer is valid
     */
    function isValidSigner(address signer) external view returns (bool valid) {
        return !_hasValidSigners() || validSigners[signer];
    }
    
    /**
     * @notice Get verification mode
     * @return mode Current verification mode
     */
    function getVerificationMode() external view returns (string memory mode) {
        if (alwaysValid) {
            return "ALWAYS_VALID";
        } else if (alwaysInvalid) {
            return "ALWAYS_INVALID";
        } else {
            return "NORMAL";
        }
    }
    
    // ==================== Internal Functions ====================
    
    /**
     * @notice Verify signature (mock implementation)
     * @param proof Proof data containing signature
     * @return valid Whether signature is valid
     */
    function _verifySignature(SuiProof calldata proof) internal view returns (bool valid) {
        // In a real implementation, this would verify the signature against
        // known validator public keys from Sui network
        
        // For mock: if no signers are configured, accept any signature
        if (!_hasValidSigners()) {
            return proof.signature.length > 0;
        }
        
        // For mock: try to recover signer and check against whitelist
        if (proof.signature.length != 65) {
            return false;
        }
        
        // Create a simple message hash for testing
        bytes32 messageHash = keccak256(abi.encodePacked(
            proof.merkleRoot,
            proof.blockHeight,
            proof.timestamp,
            proof.proofHash
        ));
        
        // Recover signer (simplified)
        try this.recoverSigner(messageHash, proof.signature) returns (address signer) {
            return validSigners[signer];
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Check if any valid merkle roots are configured
     * @return hasRoots Whether valid merkle roots are configured
     */
    function _hasValidMerkleRoots() internal view returns (bool hasRoots) {
        // This is a simplified check - in practice, you might track this more efficiently
        return false; // For simplicity in mock, assume no whitelist by default
    }
    
    /**
     * @notice Check if any valid signers are configured
     * @return hasSigners Whether valid signers are configured
     */
    function _hasValidSigners() internal view returns (bool hasSigners) {
        // This is a simplified check - in practice, you might track this more efficiently
        return false; // For simplicity in mock, assume no whitelist by default
    }
    
    // ==================== External Helper Functions ====================
    
    /**
     * @notice Recover signer from message hash and signature
     * @param messageHash Hash of the message
     * @param signature Signature bytes
     * @return signer Recovered signer address
     */
    function recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) external pure returns (address signer) {
        return messageHash.toEthSignedMessageHash().recover(signature);
    }
}