// FILE: contracts/interfaces/IVerifier.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVerifier
 * @dev Interface for verifying cross-chain proofs from Sui network
 * @notice Supports pluggable verification strategies for different proof types
 */
interface IVerifier {
    // ==================== Structs ====================
    
    /**
     * @dev Sui state proof data
     * @param merkleRoot Merkle root from Sui ROFL proof
     * @param blockHeight Sui block height
     * @param timestamp Proof timestamp
     * @param signature Validator signature
     * @param proofHash Original proof hash from ROFL
     */
    struct SuiProof {
        bytes32 merkleRoot;
        uint256 blockHeight;
        uint256 timestamp;
        bytes signature;
        string proofHash;
    }
    
    /**
     * @dev Bridge operation data
     * @param recipient Target recipient address
     * @param amount Amount to bridge
     * @param operationId Unique operation identifier
     * @param suiTxHash Source transaction hash on Sui
     */
    struct BridgeOperation {
        address recipient;
        uint256 amount;
        bytes32 operationId;
        string suiTxHash;
    }
    
    // ==================== Events ====================
    
    event ProofVerified(
        bytes32 indexed operationId,
        bytes32 merkleRoot,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );
    
    event ProofRejected(
        bytes32 indexed operationId,
        string reason,
        uint256 timestamp
    );
    
    // ==================== Functions ====================
    
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
    ) external returns (bool valid, string memory reason);
    
    /**
     * @notice Check if a proof has been used before
     * @param operationId Operation identifier to check
     * @return used Whether the operation has been used
     */
    function isProofUsed(bytes32 operationId) external view returns (bool used);
    
    /**
     * @notice Get verifier configuration
     * @return name Verifier implementation name
     * @return version Verifier version
     * @return supportedProofTypes Supported proof type identifiers
     */
    function getVerifierInfo() external view returns (
        string memory name,
        string memory version,
        string[] memory supportedProofTypes
    );
    
    /**
     * @notice Get minimum required confirmations
     * @return confirmations Number of confirmations required
     */
    function getMinConfirmations() external view returns (uint256 confirmations);
    
    /**
     * @notice Get maximum proof age allowed
     * @return maxAge Maximum age in seconds
     */
    function getMaxProofAge() external view returns (uint256 maxAge);
}