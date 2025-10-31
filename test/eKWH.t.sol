// FILE: test/eKWH.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/eKWH.sol";

contract eKWHTest is Test {
    eKWH public token;
    
    address admin = makeAddr("admin");
    address bridge = makeAddr("bridge");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    
    uint256 constant INITIAL_MINT_LIMIT = 10_000_000 * 1e6; // 10M eKWH
    uint256 constant TEST_AMOUNT = 1000 * 1e6; // 1000 eKWH
    
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
    
    function setUp() public {
        vm.startPrank(admin);
        token = new eKWH(admin, bridge, INITIAL_MINT_LIMIT);
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertEq(token.name(), "Ethereum Kilowatt-Hour");
        assertEq(token.symbol(), "eKWH");
        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), 0);
        assertEq(token.mintLimit(), INITIAL_MINT_LIMIT);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.BRIDGE_ROLE(), bridge));
    }
    
    function testBridgeIn() public {
        bytes32 operationId = keccak256("test_operation_1");
        string memory suiTxHash = "sui_tx_12345";
        
        vm.expectEmit(true, true, true, true);
        emit BridgedIn(user1, TEST_AMOUNT, operationId, suiTxHash, block.timestamp);
        
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, suiTxHash);
        
        assertEq(token.balanceOf(user1), TEST_AMOUNT);
        assertEq(token.totalSupply(), TEST_AMOUNT);
        assertEq(token.totalBridgedIn(), TEST_AMOUNT);
        assertTrue(token.isOperationProcessed(operationId));
    }
    
    function testBridgeInFailsWithDuplicateOperation() public {
        bytes32 operationId = keccak256("test_operation_duplicate");
        string memory suiTxHash = "sui_tx_duplicate";
        
        // First bridge in should succeed
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, suiTxHash);
        
        // Second bridge in with same operation ID should fail
        vm.expectRevert("eKWH: operation already processed");
        vm.prank(bridge);
        token.bridgeIn(user2, TEST_AMOUNT, operationId, suiTxHash);
    }
    
    function testBridgeInFailsWithExcessiveAmount() public {
        bytes32 operationId = keccak256("test_operation_excessive");
        string memory suiTxHash = "sui_tx_excessive";
        uint256 excessiveAmount = INITIAL_MINT_LIMIT + 1;
        
        vm.expectRevert("eKWH: amount exceeds mint limit");
        vm.prank(bridge);
        token.bridgeIn(user1, excessiveAmount, operationId, suiTxHash);
    }
    
    function testBridgeInFailsFromNonBridge() public {
        bytes32 operationId = keccak256("test_operation_unauthorized");
        string memory suiTxHash = "sui_tx_unauthorized";
        
        vm.expectRevert();
        vm.prank(user1);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, suiTxHash);
    }
    
    function testBridgeOut() public {
        // First bridge in some tokens
        bytes32 bridgeInOpId = keccak256("bridge_in_op");
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, bridgeInOpId, "sui_tx_in");
        
        // Then bridge out
        bytes32 bridgeOutOpId = keccak256("bridge_out_op");
        string memory suiAddress = "0xabc123...";
        uint256 bridgeOutAmount = TEST_AMOUNT / 2;
        
        vm.expectEmit(true, true, true, true);
        emit BridgedOut(user1, bridgeOutAmount, bridgeOutOpId, suiAddress, block.timestamp);
        
        vm.prank(user1);
        token.bridgeOut(bridgeOutAmount, bridgeOutOpId, suiAddress);
        
        assertEq(token.balanceOf(user1), TEST_AMOUNT - bridgeOutAmount);
        assertEq(token.totalBridgedOut(), bridgeOutAmount);
        assertTrue(token.isOperationProcessed(bridgeOutOpId));
    }
    
    function testBridgeOutFailsWithInsufficientBalance() public {
        bytes32 operationId = keccak256("bridge_out_insufficient");
        string memory suiAddress = "0xabc123...";
        
        vm.expectRevert("eKWH: insufficient balance");
        vm.prank(user1);
        token.bridgeOut(TEST_AMOUNT, operationId, suiAddress);
    }
    
    function testUpdateMintLimit() public {
        uint256 newLimit = 20_000_000 * 1e6;
        
        vm.expectEmit(true, true, true, true);
        emit MintLimitUpdated(INITIAL_MINT_LIMIT, newLimit, admin, block.timestamp);
        
        vm.prank(admin);
        token.updateMintLimit(newLimit);
        
        assertEq(token.mintLimit(), newLimit);
    }
    
    function testUpdateMintLimitFailsFromNonAdmin() public {
        uint256 newLimit = 20_000_000 * 1e6;
        
        vm.expectRevert();
        vm.prank(user1);
        token.updateMintLimit(newLimit);
    }
    
    function testPauseAndUnpause() public {
        // Pause contract
        vm.prank(admin);
        token.pause();
        assertTrue(token.paused());
        
        // Should fail to bridge in when paused
        bytes32 operationId = keccak256("paused_operation");
        vm.expectRevert("Pausable: paused");
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, "sui_tx_paused");
        
        // Unpause contract
        vm.prank(admin);
        token.unpause();
        assertFalse(token.paused());
        
        // Should work after unpause
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, "sui_tx_unpaused");
        assertEq(token.balanceOf(user1), TEST_AMOUNT);
    }
    
    function testBurn() public {
        // Bridge in some tokens first
        bytes32 operationId = keccak256("burn_test_operation");
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, "sui_tx_burn");
        
        // Burn tokens
        uint256 burnAmount = TEST_AMOUNT / 2;
        vm.prank(user1);
        token.burn(burnAmount);
        
        assertEq(token.balanceOf(user1), TEST_AMOUNT - burnAmount);
        assertEq(token.totalSupply(), TEST_AMOUNT - burnAmount);
    }
    
    function testGetBridgeStats() public {
        // Bridge in some tokens
        bytes32 bridgeInOpId = keccak256("stats_bridge_in");
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, bridgeInOpId, "sui_tx_stats_in");
        
        // Bridge out some tokens
        bytes32 bridgeOutOpId = keccak256("stats_bridge_out");
        uint256 bridgeOutAmount = TEST_AMOUNT / 3;
        vm.prank(user1);
        token.bridgeOut(bridgeOutAmount, bridgeOutOpId, "sui_addr_stats");
        
        (uint256 bridgedIn, uint256 bridgedOut, uint256 netSupply) = token.getBridgeStats();
        
        assertEq(bridgedIn, TEST_AMOUNT);
        assertEq(bridgedOut, bridgeOutAmount);
        assertEq(netSupply, TEST_AMOUNT - bridgeOutAmount);
    }
    
    function testMaxSupplyLimit() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        
        // Try to mint more than max supply
        vm.prank(admin);
        token.updateMintLimit(maxSupply + 1);
        
        bytes32 operationId = keccak256("max_supply_test");
        vm.expectRevert("eKWH: would exceed max supply");
        vm.prank(bridge);
        token.bridgeIn(user1, maxSupply + 1, operationId, "sui_tx_max");
    }
    
    function testUtilityFunctions() public {
        uint256 ekwhAmount = 100;
        uint256 microAmount = token.toMicroEKWH(ekwhAmount);
        assertEq(microAmount, ekwhAmount * 1e6);
        
        uint256 convertedBack = token.fromMicroEKWH(microAmount);
        assertEq(convertedBack, ekwhAmount);
    }
    
    function testGenerateOperationId() public {
        address user = user1;
        uint256 amount = TEST_AMOUNT;
        uint256 nonce = 12345;
        uint256 blockNumber = block.number;
        
        bytes32 operationId = token.generateOperationId(user, amount, nonce, blockNumber);
        bytes32 expectedId = keccak256(abi.encodePacked(user, amount, nonce, blockNumber));
        
        assertEq(operationId, expectedId);
    }
    
    function testMarkOperationProcessed() public {
        bytes32 operationId = keccak256("manual_operation");
        
        assertFalse(token.isOperationProcessed(operationId));
        
        vm.prank(admin);
        token.markOperationProcessed(operationId);
        
        assertTrue(token.isOperationProcessed(operationId));
    }
    
    function testGetRemainingMintCapacity() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        assertEq(token.getRemainingMintCapacity(), maxSupply);
        
        // Bridge in some tokens
        bytes32 operationId = keccak256("capacity_test");
        vm.prank(bridge);
        token.bridgeIn(user1, TEST_AMOUNT, operationId, "sui_tx_capacity");
        
        assertEq(token.getRemainingMintCapacity(), maxSupply - TEST_AMOUNT);
    }
    
    // Fuzz testing
    function testFuzzBridgeIn(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT_LIMIT);
        
        bytes32 operationId = keccak256(abi.encodePacked("fuzz_operation", amount));
        string memory suiTxHash = "fuzz_sui_tx";
        
        vm.prank(bridge);
        token.bridgeIn(user1, amount, operationId, suiTxHash);
        
        assertEq(token.balanceOf(user1), amount);
        assertTrue(token.isOperationProcessed(operationId));
    }
    
    function testFuzzBridgeOut(uint256 bridgeInAmount, uint256 bridgeOutAmount) public {
        bridgeInAmount = bound(bridgeInAmount, 1, INITIAL_MINT_LIMIT);
        bridgeOutAmount = bound(bridgeOutAmount, 1, bridgeInAmount);
        
        // Bridge in first
        bytes32 bridgeInOpId = keccak256(abi.encodePacked("fuzz_bridge_in", bridgeInAmount));
        vm.prank(bridge);
        token.bridgeIn(user1, bridgeInAmount, bridgeInOpId, "fuzz_sui_tx_in");
        
        // Bridge out
        bytes32 bridgeOutOpId = keccak256(abi.encodePacked("fuzz_bridge_out", bridgeOutAmount));
        vm.prank(user1);
        token.bridgeOut(bridgeOutAmount, bridgeOutOpId, "fuzz_sui_addr");
        
        assertEq(token.balanceOf(user1), bridgeInAmount - bridgeOutAmount);
        assertEq(token.totalBridgedOut(), bridgeOutAmount);
    }
}