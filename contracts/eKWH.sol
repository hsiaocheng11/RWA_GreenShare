// FILE: contracts/eKWH.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title eKWH - Ethereum Kilowatt-Hour Token
 * @dev ERC20 token representing renewable energy assets on Zircuit L2
 * @notice Cross-chain bridged version of Sui sKWH tokens
 */
contract eKWH is ERC20, ERC20Burnable, AccessControl, Pausable, ReentrancyGuard {
    // ==================== Constants ====================
    
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint8 private constant DECIMALS = 6; // Match Sui sKWH precision (micro-kWH)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**DECIMALS; // 1 billion eKWH
    
    // ==================== State Variables ====================
    
    /// @notice Maximum amount that can be minted per bridge operation
    uint256 public mintLimit;
    
    /// @notice Total amount minted through bridge operations
    uint256 public totalBridgedIn;
    
    /// @notice Total amount burned through bridge operations
    uint256 public totalBridgedOut;
    
    /// @notice Mapping to track bridge operation nonces (prevent replay attacks)
    mapping(bytes32 => bool) public processedOperations;
    
    // ==================== Events ====================
    
    event BridgedIn(
        address indexed recipient,
        uint256 amount,
        bytes32 indexed operationId,
        string suiTxHash,
        uint256 timestamp
    );
    
    event BridgedOut(
        address indexed sender,
        uint256 amount,
        bytes32 indexed operationId,
        string suiAddress,
        uint256 timestamp
    );
    
    event MintLimitUpdated(
        uint256 oldLimit,
        uint256 newLimit,
        address indexed updatedBy,
        uint256 timestamp
    );
    
    event OperationProcessed(
        bytes32 indexed operationId,
        address indexed processor,
        uint256 timestamp
    );
    
    // ==================== Constructor ====================
    
    constructor(
        address _admin,
        address _bridge,
        uint256 _initialMintLimit
    ) ERC20("Ethereum Kilowatt-Hour", "eKWH") {
        require(_admin != address(0), "eKWH: admin cannot be zero address");
        require(_bridge != address(0), "eKWH: bridge cannot be zero address");
        require(_initialMintLimit > 0, "eKWH: mint limit must be positive");
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(BRIDGE_ROLE, _bridge);
        _grantRole(PAUSER_ROLE, _admin);
        
        // Set initial mint limit
        mintLimit = _initialMintLimit;
        
        emit MintLimitUpdated(0, _initialMintLimit, _admin, block.timestamp);
    }
    
    // ==================== View Functions ====================
    
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    
    /**
     * @notice Get bridge statistics
     * @return bridgedIn Total amount bridged in from Sui
     * @return bridgedOut Total amount bridged out to Sui
     * @return netSupply Net supply from bridge operations
     */
    function getBridgeStats() external view returns (
        uint256 bridgedIn,
        uint256 bridgedOut,
        uint256 netSupply
    ) {
        bridgedIn = totalBridgedIn;
        bridgedOut = totalBridgedOut;
        netSupply = totalBridgedIn - totalBridgedOut;
    }
    
    /**
     * @notice Check if operation has been processed
     * @param operationId Unique operation identifier
     * @return processed Whether the operation has been processed
     */
    function isOperationProcessed(bytes32 operationId) external view returns (bool processed) {
        return processedOperations[operationId];
    }
    
    /**
     * @notice Get remaining mint capacity
     * @return remaining Remaining amount that can be minted
     */
    function getRemainingMintCapacity() external view returns (uint256 remaining) {
        uint256 currentSupply = totalSupply();
        if (currentSupply >= MAX_SUPPLY) {
            return 0;
        }
        return MAX_SUPPLY - currentSupply;
    }
    
    // ==================== Bridge Functions ====================
    
    /**
     * @notice Mint tokens for bridge-in operation
     * @dev Only callable by bridge contract after verification
     * @param to Recipient address
     * @param amount Amount to mint (in wei, 6 decimals)
     * @param operationId Unique operation identifier to prevent replay
     * @param suiTxHash Sui transaction hash for reference
     */
    function bridgeIn(
        address to,
        uint256 amount,
        bytes32 operationId,
        string calldata suiTxHash
    ) external onlyRole(BRIDGE_ROLE) whenNotPaused nonReentrant {
        require(to != address(0), "eKWH: cannot mint to zero address");
        require(amount > 0, "eKWH: amount must be positive");
        require(amount <= mintLimit, "eKWH: amount exceeds mint limit");
        require(!processedOperations[operationId], "eKWH: operation already processed");
        require(bytes(suiTxHash).length > 0, "eKWH: invalid Sui tx hash");
        
        // Check supply limits
        require(totalSupply() + amount <= MAX_SUPPLY, "eKWH: would exceed max supply");
        
        // Mark operation as processed
        processedOperations[operationId] = true;
        
        // Update bridge statistics
        totalBridgedIn += amount;
        
        // Mint tokens
        _mint(to, amount);
        
        emit BridgedIn(to, amount, operationId, suiTxHash, block.timestamp);
        emit OperationProcessed(operationId, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Burn tokens for bridge-out operation
     * @dev Burns tokens from sender and records bridge-out
     * @param amount Amount to burn and bridge out
     * @param operationId Unique operation identifier
     * @param suiAddress Destination address on Sui network
     */
    function bridgeOut(
        uint256 amount,
        bytes32 operationId,
        string calldata suiAddress
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "eKWH: amount must be positive");
        require(!processedOperations[operationId], "eKWH: operation already processed");
        require(bytes(suiAddress).length > 0, "eKWH: invalid Sui address");
        require(balanceOf(msg.sender) >= amount, "eKWH: insufficient balance");
        
        // Mark operation as processed
        processedOperations[operationId] = true;
        
        // Update bridge statistics
        totalBridgedOut += amount;
        
        // Burn tokens
        _burn(msg.sender, amount);
        
        emit BridgedOut(msg.sender, amount, operationId, suiAddress, block.timestamp);
        emit OperationProcessed(operationId, msg.sender, block.timestamp);
    }
    
    // ==================== Admin Functions ====================
    
    /**
     * @notice Update mint limit for bridge operations
     * @dev Only callable by admin
     * @param newLimit New mint limit per operation
     */
    function updateMintLimit(uint256 newLimit) external onlyRole(ADMIN_ROLE) {
        require(newLimit > 0, "eKWH: mint limit must be positive");
        require(newLimit <= MAX_SUPPLY, "eKWH: mint limit cannot exceed max supply");
        
        uint256 oldLimit = mintLimit;
        mintLimit = newLimit;
        
        emit MintLimitUpdated(oldLimit, newLimit, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Pause contract in emergency
     * @dev Only callable by pauser role
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause contract
     * @dev Only callable by pauser role
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Emergency function to mark operation as processed
     * @dev Only callable by admin in case of failed but valid operations
     * @param operationId Operation ID to mark as processed
     */
    function markOperationProcessed(bytes32 operationId) external onlyRole(ADMIN_ROLE) {
        require(!processedOperations[operationId], "eKWH: operation already processed");
        
        processedOperations[operationId] = true;
        emit OperationProcessed(operationId, msg.sender, block.timestamp);
    }
    
    // ==================== Internal Functions ====================
    
    /**
     * @notice Hook called before token transfers
     * @dev Prevents transfers when contract is paused
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
    
    // ==================== Utility Functions ====================
    
    /**
     * @notice Convert eKWH to micro-eKWH (for frontend display)
     * @param ekwhAmount Amount in eKWH (human readable)
     * @return microAmount Amount in micro-eKWH (contract units)
     */
    function toMicroEKWH(uint256 ekwhAmount) external pure returns (uint256 microAmount) {
        return ekwhAmount * 10**DECIMALS;
    }
    
    /**
     * @notice Convert micro-eKWH to eKWH (for frontend display)
     * @param microAmount Amount in micro-eKWH (contract units)
     * @return ekwhAmount Amount in eKWH (human readable)
     */
    function fromMicroEKWH(uint256 microAmount) external pure returns (uint256 ekwhAmount) {
        return microAmount / 10**DECIMALS;
    }
    
    /**
     * @notice Generate operation ID from parameters
     * @dev Helper function for generating unique operation IDs
     * @param user User address
     * @param amount Amount
     * @param nonce User nonce
     * @param blockNumber Block number
     * @return operationId Generated operation ID
     */
    function generateOperationId(
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 blockNumber
    ) external pure returns (bytes32 operationId) {
        return keccak256(abi.encodePacked(user, amount, nonce, blockNumber));
    }
}