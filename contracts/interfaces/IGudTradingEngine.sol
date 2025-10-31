// FILE: contracts/interfaces/IGudTradingEngine.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IGudTradingEngine
 * @dev Interface for Gud Trading Engine integration
 */
interface IGudTradingEngine {
    struct Order {
        address trader;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        bytes signature;
    }

    struct OrderResult {
        uint256 amountOut;
        uint256 executedAt;
        bytes32 orderId;
    }

    event OrderExecuted(
        bytes32 indexed orderId,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event OrderCancelled(bytes32 indexed orderId, address indexed trader);

    /**
     * @dev Execute a trading order
     * @param order The order details
     * @return result The execution result
     */
    function executeOrder(Order calldata order) external returns (OrderResult memory result);

    /**
     * @dev Cancel an existing order
     * @param orderId The order ID to cancel
     */
    function cancelOrder(bytes32 orderId) external;

    /**
     * @dev Get order status
     * @param orderId The order ID
     * @return executed Whether the order was executed
     * @return cancelled Whether the order was cancelled
     * @return result The execution result (if executed)
     */
    function getOrderStatus(bytes32 orderId) external view returns (
        bool executed,
        bool cancelled,
        OrderResult memory result
    );

    /**
     * @dev Get quote for token swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     */
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
}