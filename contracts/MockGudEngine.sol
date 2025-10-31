// FILE: contracts/MockGudEngine.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IGudTradingEngine.sol";

/**
 * @title MockGudEngine
 * @dev Mock implementation of Gud Trading Engine for testing
 */
contract MockGudEngine is IGudTradingEngine {
    using SafeERC20 for IERC20;
    
    mapping(bytes32 => OrderResult) public orderResults;
    mapping(bytes32 => bool) public cancelledOrders;
    mapping(address => mapping(address => uint256)) public exchangeRates;
    
    uint256 private nonce;
    
    constructor() {
        // Set some mock exchange rates (rate * 1e18 for precision)
        exchangeRates[address(0x1)][address(0x2)] = 1.5e18; // Token1 -> Token2
        exchangeRates[address(0x2)][address(0x1)] = 0.667e18; // Token2 -> Token1
    }
    
    function executeOrder(Order calldata order) external override returns (OrderResult memory result) {
        require(order.deadline > block.timestamp, "MockGud: Order expired");
        require(order.amountIn > 0, "MockGud: Invalid amount");
        
        bytes32 orderId = keccak256(abi.encodePacked(
            order.trader,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.deadline,
            nonce++
        ));
        
        require(orderResults[orderId].orderId == bytes32(0), "MockGud: Order exists");
        require(!cancelledOrders[orderId], "MockGud: Order cancelled");
        
        // Calculate output amount using mock exchange rate
        uint256 rate = exchangeRates[order.tokenIn][order.tokenOut];
        if (rate == 0) {
            rate = 1e18; // 1:1 default rate
        }
        
        uint256 amountOut = (order.amountIn * rate) / 1e18;
        require(amountOut >= order.minAmountOut, "MockGud: Insufficient output");
        
        // Transfer tokens
        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), order.amountIn);
        IERC20(order.tokenOut).safeTransfer(order.trader, amountOut);
        
        result = OrderResult({
            amountOut: amountOut,
            executedAt: block.timestamp,
            orderId: orderId
        });
        
        orderResults[orderId] = result;
        
        emit OrderExecuted(
            orderId,
            order.trader,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            amountOut
        );
        
        return result;
    }
    
    function cancelOrder(bytes32 orderId) external override {
        require(orderResults[orderId].orderId != bytes32(0), "MockGud: Order not found");
        require(!cancelledOrders[orderId], "MockGud: Already cancelled");
        
        cancelledOrders[orderId] = true;
        emit OrderCancelled(orderId, msg.sender);
    }
    
    function getOrderStatus(bytes32 orderId) external view override returns (
        bool executed,
        bool cancelled,
        OrderResult memory result
    ) {
        executed = orderResults[orderId].orderId != bytes32(0);
        cancelled = cancelledOrders[orderId];
        result = orderResults[orderId];
    }
    
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) {
            rate = 1e18; // 1:1 default rate
        }
        
        return (amountIn * rate) / 1e18;
    }
    
    // Admin functions for testing
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
    }
    
    function addLiquidity(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}