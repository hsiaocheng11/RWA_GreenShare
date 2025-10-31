// FILE: contracts/Bridge.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IVerifier.sol";
import "./eKWH.sol";

/**
 * @title Bridge
 * @dev Cross-chain bridge for transferring sKWH from Sui to eKWH on Zircuit
 * @notice Verifies Sui state proofs and mints corresponding eKWH tokens
 */
contract Bridge is AccessControl, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;
    
    // ==================== Constants ====================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VERIFIER_MANAGER_ROLE = keccak256("VERIFIER_MANAGER_ROLE");
    
    // ==================== State Variables ====================
    
    /// @notice eKWH token contract
    eKWH public immutable ekwhToken;
    
    /// @notice Current verifier implementation
    IVerifier public verifier;
    
    /// @notice Minimum amount for bridge operations
    uint256 public minBridgeAmount;
    
    /// @notice Maximum amount for single bridge operation
    uint256 public maxBridgeAmount;
    
    /// @notice Bridge fee in basis points (1/10000)
    uint256 public bridgeFee;
    
    /// @notice Fee recipient address
    address public feeRecipient;
    
    /// @notice Total fees collected
    uint256 public totalFeesCollected;
    
    /// @notice Nonce for each user to prevent replay attacks
    mapping(address => uint256) public userNonces;
    
    /// @notice Processed operations to prevent double-spending
    mapping(bytes32 => bool) public processedOperations;
    
    /// @notice Bridge statistics
    struct BridgeStats {
        uint256 totalOperations;
        uint256 totalVolume;
        uint256 successfulOperations;
        uint256 failedOperations;
    }
    
    BridgeStats public bridgeStats;
    
    // ==================== Events ====================
    
    event BridgeOperationInitiated(
        bytes32 indexed operationId,
        address indexed recipient,
        uint256 amount,
        uint256 fee,
        string suiTxHash,
        uint256 timestamp
    );
    
    event BridgeOperationCompleted(
        bytes32 indexed operationId,
        address indexed recipient,
        uint256 amount,
        uint256 actualAmount,
        uint256 timestamp
    );
    
    event BridgeOperationFailed(
        bytes32 indexed operationId,
        address indexed recipient,
        string reason,
        uint256 timestamp
    );
    
    event VerifierUpdated(
        address indexed oldVerifier,
        address indexed newVerifier,
        address indexed updatedBy,
        uint256 timestamp
    );
    
    event BridgeLimitsUpdated(
        uint256 oldMinAmount,
        uint256 newMinAmount,
        uint256 oldMaxAmount,
        uint256 newMaxAmount,
        uint256 timestamp
    );
    
    event BridgeFeeUpdated(
        uint256 oldFee,
        uint256 newFee,
        address indexed feeRecipient,
        uint256 timestamp
    );
    
    // ==================== Constructor ====================
    
    constructor(
        address _ekwhToken,
        address _verifier,
        address _admin,
        uint256 _minBridgeAmount,
        uint256 _maxBridgeAmount,
        uint256 _bridgeFee,
        address _feeRecipient
    ) {
        require(_ekwhToken != address(0), "Bridge: eKWH token cannot be zero");
        require(_verifier != address(0), "Bridge: verifier cannot be zero");
        require(_admin != address(0), "Bridge: admin cannot be zero");
        require(_minBridgeAmount > 0, "Bridge: min amount must be positive");
        require(_maxBridgeAmount > _minBridgeAmount, "Bridge: max amount must be greater than min");
        require(_bridgeFee <= 1000, "Bridge: fee cannot exceed 10%"); // Max 10%
        require(_feeRecipient != address(0), "Bridge: fee recipient cannot be zero");
        
        ekwhToken = eKWH(_ekwhToken);
        verifier = IVerifier(_verifier);
        minBridgeAmount = _minBridgeAmount;
        maxBridgeAmount = _maxBridgeAmount;
        bridgeFee = _bridgeFee;
        feeRecipient = _feeRecipient;
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(VERIFIER_MANAGER_ROLE, _admin);
    }
    
    // ==================== Bridge Functions ====================
    
    /**
     * @notice Process bridge operation from Sui to Zircuit
     * @param proof Sui state proof
     * @param operation Bridge operation details
     */
    function processBridgeIn(
        IVerifier.SuiProof calldata proof,
        IVerifier.BridgeOperation calldata operation
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused nonReentrant {
        // Validate operation
        require(operation.recipient != address(0), "Bridge: invalid recipient");
        require(operation.amount >= minBridgeAmount, "Bridge: amount below minimum");
        require(operation.amount <= maxBridgeAmount, "Bridge: amount exceeds maximum");
        require(!processedOperations[operation.operationId], "Bridge: operation already processed");
        require(bytes(operation.suiTxHash).length > 0, "Bridge: invalid Sui tx hash");
        
        // Update statistics
        bridgeStats.totalOperations++;
        
        emit BridgeOperationInitiated(
            operation.operationId,
            operation.recipient,
            operation.amount,
            _calculateFee(operation.amount),
            operation.suiTxHash,
            block.timestamp
        );
        
        // Verify proof
        (bool isValid, string memory reason) = verifier.verifyProof(proof, operation);
        
        if (!isValid) {
            bridgeStats.failedOperations++;
            emit BridgeOperationFailed(operation.operationId, operation.recipient, reason, block.timestamp);
            return;
        }
        
        // Mark operation as processed
        processedOperations[operation.operationId] = true;
        
        // Calculate fee and net amount
        uint256 fee = _calculateFee(operation.amount);
        uint256 netAmount = operation.amount - fee;
        
        // Update statistics
        bridgeStats.successfulOperations++;
        bridgeStats.totalVolume += operation.amount;
        totalFeesCollected += fee;
        
        // Mint tokens to recipient
        ekwhToken.bridgeIn(
            operation.recipient,
            netAmount,
            operation.operationId,
            operation.suiTxHash
        );
        
        // Mint fee to fee recipient if fee > 0
        if (fee > 0) {
            bytes32 feeOperationId = keccak256(abi.encodePacked(operation.operationId, "fee"));
            ekwhToken.bridgeIn(
                feeRecipient,
                fee,
                feeOperationId,
                operation.suiTxHash
            );
        }
        
        emit BridgeOperationCompleted(
            operation.operationId,
            operation.recipient,
            operation.amount,
            netAmount,
            block.timestamp
        );
    }
    
    /**
     * @notice Initiate bridge out operation (burn eKWH to bridge back to Sui)
     * @param amount Amount to bridge out
     * @param suiAddress Destination address on Sui
     */
    function initiateBridgeOut(
        uint256 amount,
        string calldata suiAddress
    ) external whenNotPaused nonReentrant {
        require(amount >= minBridgeAmount, "Bridge: amount below minimum");
        require(amount <= maxBridgeAmount, "Bridge: amount exceeds maximum");
        require(bytes(suiAddress).length > 0, "Bridge: invalid Sui address");
        require(ekwhToken.balanceOf(msg.sender) >= amount, "Bridge: insufficient balance");
        
        // Generate operation ID
        uint256 nonce = userNonces[msg.sender]++;
        bytes32 operationId = keccak256(abi.encodePacked(
            msg.sender,
            amount,
            nonce,
            block.number,
            "bridge_out"
        ));
        
        // Bridge out tokens (this will burn them)
        ekwhToken.bridgeOut(amount, operationId, suiAddress);
        
        // Update statistics
        bridgeStats.totalOperations++;
        bridgeStats.successfulOperations++;
        
        emit BridgeOperationCompleted(
            operationId,
            msg.sender,
            amount,
            amount, // No fee for bridge out
            block.timestamp
        );
    }
    
    // ==================== Admin Functions ====================
    
    /**
     * @notice Update verifier implementation
     * @param newVerifier New verifier contract address
     */
    function updateVerifier(address newVerifier) external onlyRole(VERIFIER_MANAGER_ROLE) {
        require(newVerifier != address(0), "Bridge: verifier cannot be zero");
        require(newVerifier != address(verifier), "Bridge: same verifier");
        
        address oldVerifier = address(verifier);
        verifier = IVerifier(newVerifier);
        
        emit VerifierUpdated(oldVerifier, newVerifier, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Update bridge amount limits
     * @param newMinAmount New minimum bridge amount
     * @param newMaxAmount New maximum bridge amount
     */
    function updateBridgeLimits(
        uint256 newMinAmount,
        uint256 newMaxAmount
    ) external onlyRole(ADMIN_ROLE) {
        require(newMinAmount > 0, "Bridge: min amount must be positive");
        require(newMaxAmount > newMinAmount, "Bridge: max must be greater than min");
        
        uint256 oldMinAmount = minBridgeAmount;
        uint256 oldMaxAmount = maxBridgeAmount;
        
        minBridgeAmount = newMinAmount;
        maxBridgeAmount = newMaxAmount;
        
        emit BridgeLimitsUpdated(
            oldMinAmount,
            newMinAmount,
            oldMaxAmount,
            newMaxAmount,
            block.timestamp
        );
    }
    
    /**
     * @notice Update bridge fee
     * @param newFee New fee in basis points
     * @param newFeeRecipient New fee recipient address
     */
    function updateBridgeFee(
        uint256 newFee,
        address newFeeRecipient
    ) external onlyRole(ADMIN_ROLE) {
        require(newFee <= 1000, "Bridge: fee cannot exceed 10%");
        require(newFeeRecipient != address(0), "Bridge: fee recipient cannot be zero");
        
        uint256 oldFee = bridgeFee;
        bridgeFee = newFee;
        feeRecipient = newFeeRecipient;
        
        emit BridgeFeeUpdated(oldFee, newFee, newFeeRecipient, block.timestamp);
    }
    
    /**
     * @notice Pause bridge operations
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause bridge operations
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Emergency function to mark operation as processed
     * @param operationId Operation to mark as processed
     */
    function markOperationProcessed(bytes32 operationId) external onlyRole(ADMIN_ROLE) {
        require(!processedOperations[operationId], "Bridge: already processed");
        processedOperations[operationId] = true;
    }
    
    // ==================== View Functions ====================
    
    /**
     * @notice Calculate fee for given amount
     * @param amount Amount to calculate fee for
     * @return fee Fee amount
     */
    function calculateFee(uint256 amount) external view returns (uint256 fee) {
        return _calculateFee(amount);
    }
    
    /**
     * @notice Get bridge statistics
     * @return stats Bridge statistics
     */
    function getBridgeStats() external view returns (BridgeStats memory stats) {
        return bridgeStats;
    }
    
    /**
     * @notice Check if operation is processed
     * @param operationId Operation ID to check
     * @return processed Whether operation is processed
     */
    function isOperationProcessed(bytes32 operationId) external view returns (bool processed) {
        return processedOperations[operationId];
    }
    
    /**
     * @notice Get user's next nonce
     * @param user User address
     * @return nonce Next nonce for user
     */
    function getUserNonce(address user) external view returns (uint256 nonce) {
        return userNonces[user];
    }
    
    /**
     * @notice Get verifier information
     * @return verifierAddress Current verifier address
     * @return name Verifier name
     * @return version Verifier version
     */
    function getVerifierInfo() external view returns (
        address verifierAddress,
        string memory name,
        string memory version
    ) {
        verifierAddress = address(verifier);
        (name, version,) = verifier.getVerifierInfo();
    }
    
    // ==================== Internal Functions ====================
    
    /**
     * @notice Calculate fee for amount
     * @param amount Amount to calculate fee for
     * @return fee Fee amount in same units
     */
    function _calculateFee(uint256 amount) internal view returns (uint256 fee) {
        return (amount * bridgeFee) / 10000;
    }
}