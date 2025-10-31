// FILE: script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/eKWH.sol";
import "../contracts/Bridge.sol";
import "../contracts/MockVerifier.sol";
import "../contracts/MockGudEngine.sol";
import "../contracts/GudAdapter.sol";

/**
 * @title Deploy
 * @dev Deployment script for GreenShare Zircuit contracts
 * @notice Deploys eKWH, Bridge, MockVerifier, MockGudEngine, and GudAdapter contracts
 */
contract Deploy is Script {
    // ==================== Configuration ====================
    
    // Default configuration values
    uint256 constant DEFAULT_MINT_LIMIT = 10_000_000 * 1e6; // 10M eKWH in micro-eKWH
    uint256 constant DEFAULT_MIN_BRIDGE_AMOUNT = 1 * 1e6;   // 1 eKWH minimum
    uint256 constant DEFAULT_MAX_BRIDGE_AMOUNT = 1_000_000 * 1e6; // 1M eKWH maximum
    uint256 constant DEFAULT_BRIDGE_FEE = 100;              // 1% bridge fee
    uint24 constant DEFAULT_GUD_FEE_TIER = 3000;            // 0.3% trading fee
    uint256 constant DEFAULT_SLIPPAGE_TOLERANCE = 100;      // 1% slippage
    uint256 constant DEFAULT_MIN_CONFIRMATIONS = 6;         // Minimum confirmations
    uint256 constant DEFAULT_MAX_PROOF_AGE = 24 * 60 * 60;  // 24 hours
    
    // ==================== State Variables ====================
    
    struct DeploymentConfig {
        address admin;
        address feeRecipient;
        uint256 mintLimit;
        uint256 minBridgeAmount;
        uint256 maxBridgeAmount;
        uint256 bridgeFee;
        uint24 gudFeeTier;
        uint256 slippageTolerance;
        uint256 minConfirmations;
        uint256 maxProofAge;
    }
    
    struct DeployedContracts {
        address ekwh;
        address bridge;
        address verifier;
        address gudEngine;
        address gudAdapter;
    }
    
    // ==================== Main Deployment Function ====================
    
    function run() external returns (DeployedContracts memory deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== GreenShare Zircuit Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        // Load configuration
        DeploymentConfig memory config = _loadConfig(deployer);
        _logConfig(config);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contracts in order
        deployed = _deployContracts(config);
        
        // Setup initial configuration
        _setupContracts(deployed, config);
        
        vm.stopBroadcast();
        
        // Log deployment results
        _logDeployment(deployed);
        
        return deployed;
    }
    
    // ==================== Configuration Loading ====================
    
    function _loadConfig(address deployer) internal view returns (DeploymentConfig memory config) {
        config.admin = vm.envOr("ADMIN_ADDRESS", deployer);
        config.feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        config.mintLimit = vm.envOr("MINT_LIMIT", DEFAULT_MINT_LIMIT);
        config.minBridgeAmount = vm.envOr("MIN_BRIDGE_AMOUNT", DEFAULT_MIN_BRIDGE_AMOUNT);
        config.maxBridgeAmount = vm.envOr("MAX_BRIDGE_AMOUNT", DEFAULT_MAX_BRIDGE_AMOUNT);
        config.bridgeFee = vm.envOr("BRIDGE_FEE", DEFAULT_BRIDGE_FEE);
        config.gudFeeTier = uint24(vm.envOr("GUD_FEE_TIER", uint256(DEFAULT_GUD_FEE_TIER)));
        config.slippageTolerance = vm.envOr("SLIPPAGE_TOLERANCE", DEFAULT_SLIPPAGE_TOLERANCE);
        config.minConfirmations = vm.envOr("MIN_CONFIRMATIONS", DEFAULT_MIN_CONFIRMATIONS);
        config.maxProofAge = vm.envOr("MAX_PROOF_AGE", DEFAULT_MAX_PROOF_AGE);
    }
    
    function _logConfig(DeploymentConfig memory config) internal view {
        console.log("=== Deployment Configuration ===");
        console.log("Admin:", config.admin);
        console.log("Fee Recipient:", config.feeRecipient);
        console.log("Mint Limit:", config.mintLimit);
        console.log("Min Bridge Amount:", config.minBridgeAmount);
        console.log("Max Bridge Amount:", config.maxBridgeAmount);
        console.log("Bridge Fee (bp):", config.bridgeFee);
        console.log("Gud Fee Tier:", config.gudFeeTier);
        console.log("Slippage Tolerance (bp):", config.slippageTolerance);
        console.log("Min Confirmations:", config.minConfirmations);
        console.log("Max Proof Age (seconds):", config.maxProofAge);
        console.log("");
    }
    
    // ==================== Contract Deployment ====================
    
    function _deployContracts(DeploymentConfig memory config) 
        internal 
        returns (DeployedContracts memory deployed) 
    {
        console.log("=== Deploying Contracts ===");
        
        // 1. Deploy eKWH token
        console.log("Deploying eKWH token...");
        deployed.ekwh = address(new eKWH(
            config.admin,
            address(0), // Bridge address will be set later
            config.mintLimit
        ));
        console.log("eKWH deployed at:", deployed.ekwh);
        
        // 2. Deploy MockVerifier
        console.log("Deploying MockVerifier...");
        deployed.verifier = address(new MockVerifier(
            config.admin,
            config.minConfirmations,
            config.maxProofAge
        ));
        console.log("MockVerifier deployed at:", deployed.verifier);
        
        // 3. Deploy Bridge
        console.log("Deploying Bridge...");
        deployed.bridge = address(new Bridge(
            deployed.ekwh,
            deployed.verifier,
            config.admin,
            config.minBridgeAmount,
            config.maxBridgeAmount,
            config.bridgeFee,
            config.feeRecipient
        ));
        console.log("Bridge deployed at:", deployed.bridge);
        
        // 4. Deploy MockGudEngine
        console.log("Deploying MockGudEngine...");
        deployed.gudEngine = address(new MockGudEngine(config.admin));
        console.log("MockGudEngine deployed at:", deployed.gudEngine);
        
        // 5. Deploy GudAdapter
        console.log("Deploying GudAdapter...");
        deployed.gudAdapter = address(new GudAdapter(
            deployed.ekwh,
            deployed.gudEngine,
            config.admin,
            config.gudFeeTier,
            config.slippageTolerance
        ));
        console.log("GudAdapter deployed at:", deployed.gudAdapter);
        
        console.log("");
    }
    
    // ==================== Contract Setup ====================
    
    function _setupContracts(DeployedContracts memory deployed, DeploymentConfig memory config) internal {
        console.log("=== Setting up Contracts ===");
        
        // Grant bridge role to bridge contract in eKWH
        console.log("Granting BRIDGE_ROLE to Bridge contract...");
        eKWH ekwhToken = eKWH(deployed.ekwh);
        ekwhToken.grantRole(ekwhToken.BRIDGE_ROLE(), deployed.bridge);
        
        // Setup MockVerifier for testing
        console.log("Setting up MockVerifier...");
        MockVerifier verifier = MockVerifier(deployed.verifier);
        verifier.setAlwaysValid(true); // For initial testing
        
        // Add some test merkle roots
        bytes32 testMerkleRoot1 = keccak256("test_merkle_root_1");
        bytes32 testMerkleRoot2 = keccak256("test_merkle_root_2");
        verifier.addValidMerkleRoot(testMerkleRoot1);
        verifier.addValidMerkleRoot(testMerkleRoot2);
        console.log("Added test merkle roots");
        
        // Fund MockGudEngine with some initial tokens (if this is testnet)
        if (block.chainid != 1) { // Not mainnet
            console.log("Funding MockGudEngine for testing...");
            MockGudEngine gudEngine = MockGudEngine(deployed.gudEngine);
            
            // Create some test tokens in the engine
            uint256 fundAmount = 1_000_000 * 1e6; // 1M tokens
            ekwhToken.mint(deployed.gudEngine, fundAmount);
        }
        
        console.log("Setup completed!");
        console.log("");
    }
    
    // ==================== Logging ====================
    
    function _logDeployment(DeployedContracts memory deployed) internal view {
        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("📋 Contract Addresses:");
        console.log("eKWH Token:      ", deployed.ekwh);
        console.log("Bridge:          ", deployed.bridge);
        console.log("MockVerifier:    ", deployed.verifier);
        console.log("MockGudEngine:   ", deployed.gudEngine);
        console.log("GudAdapter:      ", deployed.gudAdapter);
        console.log("");
        
        console.log("🔧 Environment Variables for .env:");
        console.log("EKWH_TOKEN_ADDRESS=", deployed.ekwh);
        console.log("BRIDGE_ADDRESS=", deployed.bridge);
        console.log("VERIFIER_ADDRESS=", deployed.verifier);
        console.log("GUD_ENGINE_ADDRESS=", deployed.gudEngine);
        console.log("GUD_ADAPTER_ADDRESS=", deployed.gudAdapter);
        console.log("");
        
        console.log("✅ Next Steps:");
        console.log("1. Update .env file with contract addresses");
        console.log("2. Verify contracts on block explorer");
        console.log("3. Test bridge functionality with test proofs");
        console.log("4. Set up real Gud Trading Engine integration");
        console.log("5. Configure production verifier settings");
        console.log("");
    }
    
    // ==================== Utility Functions ====================
    
    /**
     * @notice Deploy only specific contracts (for testing/development)
     */
    function deployTestContracts() external returns (DeployedContracts memory deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        DeploymentConfig memory config = _loadConfig(deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy minimal set for testing
        deployed.ekwh = address(new eKWH(deployer, address(0), config.mintLimit));
        deployed.verifier = address(new MockVerifier(deployer, config.minConfirmations, config.maxProofAge));
        deployed.gudEngine = address(new MockGudEngine(deployer));
        
        vm.stopBroadcast();
        
        return deployed;
    }
    
    /**
     * @notice Upgrade existing deployment (for contract upgrades)
     */
    function upgradeContracts() external {
        // Load existing addresses from environment
        address existingEKWH = vm.envAddress("EKWH_TOKEN_ADDRESS");
        address existingBridge = vm.envAddress("BRIDGE_ADDRESS");
        address existingVerifier = vm.envAddress("VERIFIER_ADDRESS");
        address existingGudEngine = vm.envAddress("GUD_ENGINE_ADDRESS");
        address existingAdapter = vm.envAddress("GUD_ADAPTER_ADDRESS");
        
        console.log("=== Upgrading Contracts ===");
        console.log("Current eKWH:", existingEKWH);
        console.log("Current Bridge:", existingBridge);
        console.log("Current Verifier:", existingVerifier);
        console.log("Current GudEngine:", existingGudEngine);
        console.log("Current Adapter:", existingAdapter);
        
        // Add upgrade logic here based on specific needs
        // This is a placeholder for future upgrade functionality
        
        console.log("Upgrade logic not yet implemented");
    }
}