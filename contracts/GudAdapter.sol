// FILE: contracts/GudAdapter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IGudTradingEngine.sol";
import "./eKWH.sol";

/**
 * @title GudAdapter
 * @dev Adapter contract for integrating eKWH trading with Gud Trading Engine
 */
contract GudAdapter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IGudTradingEngine public immutable gudEngine;
    eKWH public immutable eKWHToken;
    
    // Trading fees (in basis points, 10000 = 100%)
    uint256 public tradingFee = 30; // 0.3%
    address public feeRecipient;
    
    // Supported trading pairs
    mapping(address => bool) public supportedTokens;
    
    // Order tracking
    mapping(bytes32 => address) public orderTraders;
    mapping(address => bytes32[]) public userOrders;
    
    event TradingFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event TokenSupportUpdated(address token, bool supported);
    event OrderPlaced(bytes32 indexed orderId, address indexed trader, address tokenIn, address tokenOut, uint256 amountIn);
    
    modifier onlyValidToken(address token) {
        require(token == address(eKWHToken) || supportedTokens[token], "GudAdapter: Unsupported token");
        _;
    }
    
    constructor(
        address _gudEngine,
        address _eKWHToken,
        address _feeRecipient
    ) {
        require(_gudEngine != address(0), "GudAdapter: Invalid gud engine");
        require(_eKWHToken != address(0), "GudAdapter: Invalid eKWH token");
        require(_feeRecipient != address(0), "GudAdapter: Invalid fee recipient");
        
        gudEngine = IGudTradingEngine(_gudEngine);
        eKWHToken = eKWH(_eKWHToken);
        feeRecipient = _feeRecipient;
        
        // eKWH is always supported
        supportedTokens[_eKWHToken] = true;
    }
    
    /**
     * @dev Place a trading order through Gud Engine
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param minAmountOut Minimum output amount
     * @param deadline Order deadline
     */
    function placeOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant onlyValidToken(tokenIn) onlyValidToken(tokenOut) returns (bytes32 orderId) {
        require(amountIn > 0, "GudAdapter: Invalid amount");
        require(deadline > block.timestamp, "GudAdapter: Expired deadline");
        require(tokenIn != tokenOut, "GudAdapter: Same tokens");
        
        // Transfer tokens from user
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Calculate fee
        uint256 feeAmount = (amountIn * tradingFee) / 10000;
        uint256 netAmount = amountIn - feeAmount;
        
        // Transfer fee to recipient
        if (feeAmount > 0) {
            IERC20(tokenIn).safeTransfer(feeRecipient, feeAmount);
        }
        
        // Approve gud engine to spend tokens
        IERC20(tokenIn).safeApprove(address(gudEngine), netAmount);
        
        // Create order signature (simplified for MVP)
        bytes memory signature = abi.encodePacked(
            keccak256(abi.encode(msg.sender, tokenIn, tokenOut, netAmount, minAmountOut, deadline))
        );
        
        // Prepare order
        IGudTradingEngine.Order memory order = IGudTradingEngine.Order({
            trader: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: netAmount,
            minAmountOut: minAmountOut,
            deadline: deadline,
            signature: signature
        });
        
        // Execute order through Gud Engine
        IGudTradingEngine.OrderResult memory result = gudEngine.executeOrder(order);
        orderId = result.orderId;
        
        // Track order
        orderTraders[orderId] = msg.sender;
        userOrders[msg.sender].push(orderId);
        
        // Transfer output tokens to user
        IERC20(tokenOut).safeTransfer(msg.sender, result.amountOut);
        
        emit OrderPlaced(orderId, msg.sender, tokenIn, tokenOut, amountIn);
        
        return orderId;
    }
    
    /**
     * @dev Get quote for token swap including fees
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Expected output amount after fees
     */
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view onlyValidToken(tokenIn) onlyValidToken(tokenOut) returns (uint256 amountOut) {
        uint256 feeAmount = (amountIn * tradingFee) / 10000;
        uint256 netAmount = amountIn - feeAmount;
        
        return gudEngine.getQuote(tokenIn, tokenOut, netAmount);
    }
    
    /**
     * @dev Get user's order history
     * @param user User address
     * @return orderIds Array of order IDs
     */
    function getUserOrders(address user) external view returns (bytes32[] memory orderIds) {
        return userOrders[user];
    }
    
    /**
     * @dev Set trading fee
     * @param _tradingFee New trading fee in basis points
     */
    function setTradingFee(uint256 _tradingFee) external onlyOwner {
        require(_tradingFee <= 1000, "GudAdapter: Fee too high"); // Max 10%
        uint256 oldFee = tradingFee;
        tradingFee = _tradingFee;
        emit TradingFeeUpdated(oldFee, _tradingFee);
    }
    
    /**
     * @dev Set fee recipient
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "GudAdapter: Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }
    
    /**
     * @dev Update token support status
     * @param token Token address
     * @param supported Whether the token is supported
     */
    function setSupportedToken(address token, bool supported) external onlyOwner {
        require(token != address(eKWHToken), "GudAdapter: Cannot disable eKWH");
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }
    
    /**
     * @dev Emergency token recovery
     * @param token Token address
     * @param amount Amount to recover
     */
    function emergencyRecovery(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}