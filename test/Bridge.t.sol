// FILE: test/Bridge.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/eKWH.sol";
import "../contracts/Bridge.sol";
import "../contracts/MockVerifier.sol";
import "../contracts/interfaces/IVerifier.sol";

contract BridgeTest is Test {
    eKWH public ekwhToken;
    Bridge public bridge;
    MockVerifier public verifier;
    
    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address feeRecipient = makeAddr("feeRecipient");
    
    uint256 constant MINT_LIMIT = 10_000_000 * 1e6;
    uint256 constant MIN_BRIDGE_AMOUNT = 1 * 1e6;
    uint256 constant MAX_BRIDGE_AMOUNT = 1_000_000 * 1e6;
    uint256 constant BRIDGE_FEE = 100; // 1%
    uint256 constant TEST_AMOUNT = 1000 * 1e6;
    uint256 constant MIN_CONFIRMATIONS = 6;
    uint256 constant MAX_PROOF_AGE = 24 * 60 * 60; // 24 hours
    
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
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy eKWH token (bridge address will be set later)
        ekwhToken = new eKWH(admin, address(0), MINT_LIMIT);
        
        // Deploy verifier
        verifier = new MockVerifier(admin, MIN_CONFIRMATIONS, MAX_PROOF_AGE);
        
        // Deploy bridge
        bridge = new Bridge(
            address(ekwhToken),
            address(verifier),
            admin,
            MIN_BRIDGE_AMOUNT,
            MAX_BRIDGE_AMOUNT,
            BRIDGE_FEE,
            feeRecipient
        );
        
        // Grant bridge role to bridge contract
        ekwhToken.grantRole(ekwhToken.BRIDGE_ROLE(), address(bridge));
        
        // Grant operator role
        bridge.grantRole(bridge.OPERATOR_ROLE(), operator);
        
        // Set verifier to always valid for basic tests
        verifier.setAlwaysValid(true);
        
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertEq(address(bridge.ekwhToken()), address(ekwhToken));
        assertEq(address(bridge.verifier()), address(verifier));
        assertEq(bridge.minBridgeAmount(), MIN_BRIDGE_AMOUNT);
        assertEq(bridge.maxBridgeAmount(), MAX_BRIDGE_AMOUNT);
        assertEq(bridge.bridgeFee(), BRIDGE_FEE);
        assertEq(bridge.feeRecipient(), feeRecipient);
        assertTrue(bridge.hasRole(bridge.ADMIN_ROLE(), admin));
        assertTrue(bridge.hasRole(bridge.OPERATOR_ROLE(), operator));
    }
    
    function testSuccessfulBridgeIn() public {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        uint256 expectedFee = bridge.calculateFee(TEST_AMOUNT);
        uint256 expectedNetAmount = TEST_AMOUNT - expectedFee;
        
        vm.expectEmit(true, true, true, true);
        emit BridgeOperationInitiated(
            operation.operationId,
            user1,
            TEST_AMOUNT,
            expectedFee,
            operation.suiTxHash,
            block.timestamp
        );
        
        vm.expectEmit(true, true, true, true);
        emit BridgeOperationCompleted(
            operation.operationId,
            user1,
            TEST_AMOUNT,
            expectedNetAmount,
            block.timestamp
        );
        
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        assertEq(ekwhToken.balanceOf(user1), expectedNetAmount);
        assertEq(ekwhToken.balanceOf(feeRecipient), expectedFee);
        assertTrue(bridge.isOperationProcessed(operation.operationId));
        
        Bridge.BridgeStats memory stats = bridge.getBridgeStats();
        assertEq(stats.totalOperations, 1);
        assertEq(stats.successfulOperations, 1);
        assertEq(stats.totalVolume, TEST_AMOUNT);
    }
    
    function testBridgeInFailsWithInvalidProof() public {
        // Set verifier to always invalid
        vm.prank(admin);
        verifier.setAlwaysInvalid(true, "Invalid proof signature");
        
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit BridgeOperationFailed(operation.operationId, user1, "Invalid proof signature", block.timestamp);
        
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        assertEq(ekwhToken.balanceOf(user1), 0);
        assertFalse(bridge.isOperationProcessed(operation.operationId));
        
        Bridge.BridgeStats memory stats = bridge.getBridgeStats();
        assertEq(stats.totalOperations, 1);
        assertEq(stats.failedOperations, 1);
    }
    
    function testBridgeInFailsWithDuplicateOperation() public {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        // First operation should succeed
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        // Second operation with same ID should fail
        vm.expectRevert("Bridge: operation already processed");
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
    }
    
    function testBridgeInFailsWithAmountTooSmall() public {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, MIN_BRIDGE_AMOUNT - 1);
        
        vm.expectRevert("Bridge: amount below minimum");
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
    }
    
    function testBridgeInFailsWithAmountTooLarge() public {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, MAX_BRIDGE_AMOUNT + 1);
        
        vm.expectRevert("Bridge: amount exceeds maximum");
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
    }
    
    function testBridgeInFailsFromNonOperator() public {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        vm.expectRevert();
        vm.prank(user1);
        bridge.processBridgeIn(proof, operation);
    }
    
    function testSuccessfulBridgeOut() public {
        // First bridge in some tokens
        _bridgeInTokens(user1, TEST_AMOUNT);
        
        string memory suiAddress = "0xabc123...";
        
        vm.expectEmit(true, false, false, true);
        emit BridgeOperationCompleted(
            bytes32(0), // Operation ID will be generated
            user1,
            TEST_AMOUNT,
            TEST_AMOUNT, // No fee for bridge out
            block.timestamp
        );
        
        vm.prank(user1);
        bridge.initiateBridgeOut(TEST_AMOUNT, suiAddress);
        
        assertEq(ekwhToken.balanceOf(user1), 0); // Tokens burned
    }
    
    function testBridgeOutFailsWithInsufficientBalance() public {
        string memory suiAddress = "0xabc123...";
        
        vm.expectRevert("Bridge: insufficient balance");
        vm.prank(user1);
        bridge.initiateBridgeOut(TEST_AMOUNT, suiAddress);
    }
    
    function testBridgeOutFailsWithAmountTooSmall() public {
        _bridgeInTokens(user1, TEST_AMOUNT);
        
        string memory suiAddress = "0xabc123...";
        
        vm.expectRevert("Bridge: amount below minimum");
        vm.prank(user1);
        bridge.initiateBridgeOut(MIN_BRIDGE_AMOUNT - 1, suiAddress);
    }
    
    function testUpdateVerifier() public {
        MockVerifier newVerifier = new MockVerifier(admin, MIN_CONFIRMATIONS, MAX_PROOF_AGE);
        
        vm.prank(admin);
        bridge.updateVerifier(address(newVerifier));
        
        assertEq(address(bridge.verifier()), address(newVerifier));
    }
    
    function testUpdateBridgeLimits() public {
        uint256 newMinAmount = 5 * 1e6;
        uint256 newMaxAmount = 2_000_000 * 1e6;
        
        vm.prank(admin);
        bridge.updateBridgeLimits(newMinAmount, newMaxAmount);
        
        assertEq(bridge.minBridgeAmount(), newMinAmount);
        assertEq(bridge.maxBridgeAmount(), newMaxAmount);
    }
    
    function testUpdateBridgeFee() public {
        uint256 newFee = 200; // 2%
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        vm.prank(admin);
        bridge.updateBridgeFee(newFee, newFeeRecipient);
        
        assertEq(bridge.bridgeFee(), newFee);
        assertEq(bridge.feeRecipient(), newFeeRecipient);
    }
    
    function testPauseAndUnpause() public {
        // Pause bridge
        vm.prank(admin);
        bridge.pause();
        assertTrue(bridge.paused());
        
        // Should fail when paused
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        vm.expectRevert("Pausable: paused");
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        // Unpause bridge
        vm.prank(admin);
        bridge.unpause();
        assertFalse(bridge.paused());
        
        // Should work after unpause
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        assertGt(ekwhToken.balanceOf(user1), 0);
    }
    
    function testCalculateFee() public {
        uint256 amount = 10000 * 1e6;
        uint256 expectedFee = (amount * BRIDGE_FEE) / 10000;
        
        assertEq(bridge.calculateFee(amount), expectedFee);
    }
    
    function testGetVerifierInfo() public {
        (address verifierAddr, string memory name, string memory version) = bridge.getVerifierInfo();
        
        assertEq(verifierAddr, address(verifier));
        assertEq(name, "MockVerifier");
        assertEq(version, "1.0.0");
    }
    
    function testUserNonces() public {
        assertEq(bridge.getUserNonce(user1), 0);
        
        // Bridge out increments nonce
        _bridgeInTokens(user1, TEST_AMOUNT);
        
        vm.prank(user1);
        bridge.initiateBridgeOut(TEST_AMOUNT / 2, "0xabc123...");
        
        assertEq(bridge.getUserNonce(user1), 1);
        
        vm.prank(user1);
        bridge.initiateBridgeOut(TEST_AMOUNT / 2, "0xdef456...");
        
        assertEq(bridge.getUserNonce(user1), 2);
    }
    
    function testReplayAttackPrevention() public {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        // First operation succeeds
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        // Same operation should fail
        vm.expectRevert("Bridge: operation already processed");
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        // Verifier should also prevent replay
        assertTrue(verifier.isProofUsed(operation.operationId));
    }
    
    function testExcessiveMintingPrevention() public {
        // Set mint limit very low
        vm.prank(admin);
        ekwhToken.updateMintLimit(100 * 1e6);
        
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, TEST_AMOUNT);
        
        vm.expectRevert("eKWH: amount exceeds mint limit");
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
    }
    
    // Helper functions
    function _createValidProof() internal view returns (IVerifier.SuiProof memory) {
        return IVerifier.SuiProof({
            merkleRoot: keccak256("test_merkle_root"),
            blockHeight: 12345,
            timestamp: block.timestamp - 100,
            signature: abi.encodePacked(bytes32("r"), bytes32("s"), uint8(27)),
            proofHash: "test_proof_hash_12345"
        });
    }
    
    function _createBridgeOperation(address recipient, uint256 amount) internal view returns (IVerifier.BridgeOperation memory) {
        bytes32 operationId = keccak256(abi.encodePacked(
            recipient,
            amount,
            block.timestamp,
            "test_operation"
        ));
        
        return IVerifier.BridgeOperation({
            recipient: recipient,
            amount: amount,
            operationId: operationId,
            suiTxHash: "sui_tx_hash_12345"
        });
    }
    
    function _bridgeInTokens(address user, uint256 amount) internal {
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user, amount);
        
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
    }
    
    // Fuzz testing
    function testFuzzBridgeIn(uint256 amount) public {
        amount = bound(amount, MIN_BRIDGE_AMOUNT, MAX_BRIDGE_AMOUNT);
        
        IVerifier.SuiProof memory proof = _createValidProof();
        IVerifier.BridgeOperation memory operation = _createBridgeOperation(user1, amount);
        
        vm.prank(operator);
        bridge.processBridgeIn(proof, operation);
        
        uint256 expectedFee = bridge.calculateFee(amount);
        uint256 expectedNetAmount = amount - expectedFee;
        
        assertEq(ekwhToken.balanceOf(user1), expectedNetAmount);
        assertTrue(bridge.isOperationProcessed(operation.operationId));
    }
    
    function testFuzzBridgeOut(uint256 bridgeInAmount, uint256 bridgeOutAmount) public {
        bridgeInAmount = bound(bridgeInAmount, MIN_BRIDGE_AMOUNT, MAX_BRIDGE_AMOUNT);
        bridgeOutAmount = bound(bridgeOutAmount, MIN_BRIDGE_AMOUNT, bridgeInAmount);
        
        // Bridge in first
        _bridgeInTokens(user1, bridgeInAmount);
        
        uint256 userBalance = ekwhToken.balanceOf(user1);
        bridgeOutAmount = bound(bridgeOutAmount, MIN_BRIDGE_AMOUNT, userBalance);
        
        // Bridge out
        vm.prank(user1);
        bridge.initiateBridgeOut(bridgeOutAmount, "fuzz_sui_address");
        
        assertEq(ekwhToken.balanceOf(user1), userBalance - bridgeOutAmount);
    }
}