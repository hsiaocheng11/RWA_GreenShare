// FILE: test/GudAdapter.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/eKWH.sol";
import "../contracts/GudAdapter.sol";
import "../contracts/MockGudEngine.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GudAdapterTest is Test {
    eKWH public ekwhToken;
    MockGudEngine public gudEngine;
    GudAdapter public adapter;
    MockToken public usdc;
    MockToken public weth;
    
    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    
    uint256 constant MINT_LIMIT = 10_000_000 * 1e6;
    uint24 constant DEFAULT_FEE_TIER = 3000;
    uint256 constant DEFAULT_SLIPPAGE = 100; // 1%
    uint256 constant TEST_AMOUNT = 1000 * 1e6;
    
    event EKWHPoolCreated(
        address indexed tokenPair,
        uint24 fee,
        address indexed pool,
        address indexed creator,
        uint256 timestamp
    );
    
    event EKWHLiquidityAdded(
        address indexed provider,
        address indexed tokenPair,
        uint256 ekwhAmount,
        uint256 pairAmount,
        uint128 liquidity,
        uint256 timestamp
    );
    
    event EKWHTrade(
        address indexed trader,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy tokens
        ekwhToken = new eKWH(admin, address(0), MINT_LIMIT);
        usdc = new MockToken("USD Coin", "USDC");
        weth = new MockToken("Wrapped Ether", "WETH");
        
        // Deploy Gud Engine
        gudEngine = new MockGudEngine(admin);
        
        // Deploy adapter
        adapter = new GudAdapter(
            address(ekwhToken),
            address(gudEngine),
            admin,
            DEFAULT_FEE_TIER,
            DEFAULT_SLIPPAGE
        );
        
        // Grant bridge role to adapter for testing
        ekwhToken.grantRole(ekwhToken.BRIDGE_ROLE(), address(adapter));
        
        // Fund engine and users with tokens
        _setupTokens();
        
        vm.stopPrank();
    }
    
    function _setupTokens() internal {
        // Mint eKWH tokens to users and adapter
        ekwhToken.bridgeIn(user1, 10000 * 1e6, keccak256("setup1"), "setup_tx1");
        ekwhToken.bridgeIn(user2, 10000 * 1e6, keccak256("setup2"), "setup_tx2");
        ekwhToken.bridgeIn(address(adapter), 100000 * 1e6, keccak256("setup_adapter"), "setup_tx_adapter");
        
        // Fund users with test tokens
        usdc.mint(user1, 10000 * 1e18);
        usdc.mint(user2, 10000 * 1e18);
        weth.mint(user1, 100 * 1e18);
        weth.mint(user2, 100 * 1e18);
        
        // Fund Gud Engine for trading
        usdc.mint(address(gudEngine), 100000 * 1e18);
        weth.mint(address(gudEngine), 1000 * 1e18);
        gudEngine.fundEngine(address(ekwhToken), 100000 * 1e6);
        gudEngine.fundEngine(address(usdc), 100000 * 1e18);
        gudEngine.fundEngine(address(weth), 1000 * 1e18);
    }
    
    function testInitialState() public {
        assertEq(address(adapter.ekwhToken()), address(ekwhToken));
        assertEq(address(adapter.gudEngine()), address(gudEngine));
        assertEq(adapter.defaultFeeTier(), DEFAULT_FEE_TIER);
        assertEq(adapter.defaultSlippageTolerance(), DEFAULT_SLIPPAGE);
        assertTrue(adapter.hasRole(adapter.ADMIN_ROLE(), admin));
    }
    
    function testCreateEKWHPool() public {
        vm.expectEmit(true, true, true, true);
        emit EKWHPoolCreated(address(usdc), DEFAULT_FEE_TIER, address(0), admin, block.timestamp);
        
        vm.prank(admin);
        address pool = adapter.createEKWHPool(address(usdc), 0); // Use default fee tier
        
        assertTrue(pool != address(0));
        assertTrue(adapter.ekwhPoolExists(address(usdc), 0));
    }
    
    function testCreateEKWHPoolWithCustomFee() public {
        uint24 customFee = 10000; // 1%
        
        vm.prank(admin);
        address pool = adapter.createEKWHPool(address(usdc), customFee);
        
        assertTrue(pool != address(0));
        assertTrue(adapter.ekwhPoolExists(address(usdc), customFee));
    }
    
    function testCreateEKWHPoolFailsWithInvalidToken() public {
        vm.expectRevert("GudAdapter: invalid token pair");
        vm.prank(admin);
        adapter.createEKWHPool(address(0), 0);
        
        vm.expectRevert("GudAdapter: cannot pair with self");
        vm.prank(admin);
        adapter.createEKWHPool(address(ekwhToken), 0);
    }
    
    function testAddEKWHLiquidity() public {
        // Create pool first
        vm.prank(admin);
        adapter.createEKWHPool(address(usdc), 0);
        
        uint256 ekwhAmount = 1000 * 1e6;
        uint256 usdcAmount = 1000 * 1e18;
        uint256 minEKWH = adapter.calculateMinAmount(ekwhAmount, 0);
        uint256 minUSDC = adapter.calculateMinAmount(usdcAmount, 0);
        uint256 deadline = block.timestamp + 3600;
        
        // Approve tokens
        vm.startPrank(user1);
        ekwhToken.approve(address(adapter), ekwhAmount);
        usdc.approve(address(adapter), usdcAmount);
        
        vm.expectEmit(true, true, true, true);
        emit EKWHLiquidityAdded(user1, address(usdc), ekwhAmount, usdcAmount, 0, block.timestamp);
        
        uint128 liquidity = adapter.addEKWHLiquidity(
            address(usdc),
            ekwhAmount,
            usdcAmount,
            minEKWH,
            minUSDC,
            deadline
        );
        
        assertGt(liquidity, 0);
        vm.stopPrank();
    }
    
    function testSwapToEKWH() public {
        // Create pool and add liquidity
        _setupPool(address(usdc));
        
        uint256 usdcIn = 100 * 1e18;
        uint256 minEKWHOut = adapter.calculateMinAmount(
            adapter.getQuoteToEKWH(address(usdc), usdcIn),
            0
        );
        uint256 deadline = block.timestamp + 3600;
        
        vm.startPrank(user1);
        usdc.approve(address(adapter), usdcIn);
        
        vm.expectEmit(true, true, true, true);
        emit EKWHTrade(user1, address(usdc), address(ekwhToken), usdcIn, 0, block.timestamp);
        
        uint256 ekwhOut = adapter.swapToEKWH(
            address(usdc),
            usdcIn,
            minEKWHOut,
            deadline
        );
        
        assertGt(ekwhOut, 0);
        assertEq(ekwhToken.balanceOf(user1), 10000 * 1e6 + ekwhOut);
        vm.stopPrank();
    }
    
    function testSwapFromEKWH() public {
        // Create pool and add liquidity
        _setupPool(address(usdc));
        
        uint256 ekwhIn = 100 * 1e6;
        uint256 minUSDCOut = adapter.calculateMinAmount(
            adapter.getQuoteFromEKWH(address(usdc), ekwhIn),
            0
        );
        uint256 deadline = block.timestamp + 3600;
        
        vm.startPrank(user1);
        ekwhToken.approve(address(adapter), ekwhIn);
        
        vm.expectEmit(true, true, true, true);
        emit EKWHTrade(user1, address(ekwhToken), address(usdc), ekwhIn, 0, block.timestamp);
        
        uint256 usdcOut = adapter.swapFromEKWH(
            address(usdc),
            ekwhIn,
            minUSDCOut,
            deadline
        );
        
        assertGt(usdcOut, 0);
        vm.stopPrank();
    }
    
    function testSwapFailsWithSameToken() public {
        vm.expectRevert("GudAdapter: cannot swap eKWH to eKWH");
        vm.prank(user1);
        adapter.swapToEKWH(address(ekwhToken), TEST_AMOUNT, 0, block.timestamp + 3600);
        
        vm.expectRevert("GudAdapter: cannot swap eKWH to eKWH");
        vm.prank(user1);
        adapter.swapFromEKWH(address(ekwhToken), TEST_AMOUNT, 0, block.timestamp + 3600);
    }
    
    function testSwapFailsWithExpiredDeadline() public {
        _setupPool(address(usdc));
        
        vm.expectRevert("GudAdapter: deadline passed");
        vm.prank(user1);
        adapter.swapToEKWH(address(usdc), TEST_AMOUNT, 0, block.timestamp - 1);
    }
    
    function testPlaceLimitOrder() public {
        _setupPool(address(usdc));
        
        uint256 amountIn = 100 * 1e18;
        uint256 amountOut = 95 * 1e6; // Expect less eKWH for USDC
        uint256 deadline = block.timestamp + 3600;
        
        vm.startPrank(user1);
        usdc.approve(address(adapter), amountIn);
        
        bytes32 orderId = adapter.placeLimitOrder(
            address(usdc),
            amountIn,
            amountOut,
            true, // Buy eKWH
            deadline
        );
        
        assertTrue(orderId != bytes32(0));
        vm.stopPrank();
    }
    
    function testGetQuotes() public {
        uint256 amountIn = 100 * 1e18;
        
        uint256 quoteToEKWH = adapter.getQuoteToEKWH(address(usdc), amountIn);
        uint256 quoteFromEKWH = adapter.getQuoteFromEKWH(address(usdc), amountIn);
        
        assertGt(quoteToEKWH, 0);
        assertGt(quoteFromEKWH, 0);
    }
    
    function testCalculateMinAmount() public {
        uint256 amount = 1000 * 1e6;
        uint256 minAmount = adapter.calculateMinAmount(amount, DEFAULT_SLIPPAGE);
        uint256 expectedMin = (amount * (10000 - DEFAULT_SLIPPAGE)) / 10000;
        
        assertEq(minAmount, expectedMin);
    }
    
    function testUpdateGudEngine() public {
        MockGudEngine newEngine = new MockGudEngine(admin);
        
        vm.prank(admin);
        adapter.updateGudEngine(address(newEngine));
        
        assertEq(address(adapter.gudEngine()), address(newEngine));
    }
    
    function testUpdateDefaultFeeTier() public {
        uint24 newFeeTier = 10000; // 1%
        
        vm.prank(admin);
        adapter.updateDefaultFeeTier(newFeeTier);
        
        assertEq(adapter.defaultFeeTier(), newFeeTier);
    }
    
    function testUpdateSlippageTolerance() public {
        uint256 newTolerance = 200; // 2%
        
        vm.prank(admin);
        adapter.updateSlippageTolerance(newTolerance);
        
        assertEq(adapter.defaultSlippageTolerance(), newTolerance);
    }
    
    function testSetMinLiquidityAmount() public {
        uint256 minAmount = 100 * 1e6;
        
        vm.prank(admin);
        adapter.setMinLiquidityAmount(address(usdc), minAmount);
        
        assertEq(adapter.minLiquidityAmounts(address(usdc)), minAmount);
    }
    
    function testPauseAndUnpause() public {
        // Pause adapter
        vm.prank(admin);
        adapter.pause();
        assertTrue(adapter.paused());
        
        // Should fail when paused
        vm.expectRevert("Pausable: paused");
        vm.prank(user1);
        adapter.swapToEKWH(address(usdc), TEST_AMOUNT, 0, block.timestamp + 3600);
        
        // Unpause adapter
        vm.prank(admin);
        adapter.unpause();
        assertFalse(adapter.paused());
    }
    
    function testGetUserStats() public {
        _setupPool(address(usdc));
        
        // Perform some trades
        vm.startPrank(user1);
        usdc.approve(address(adapter), 1000 * 1e18);
        adapter.swapToEKWH(address(usdc), 100 * 1e18, 0, block.timestamp + 3600);
        adapter.swapToEKWH(address(usdc), 50 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();
        
        GudAdapter.TradingStats memory userStats = adapter.getUserStats(user1);
        assertEq(userStats.totalTrades, 2);
        assertEq(userStats.totalVolume, 150 * 1e18);
        
        GudAdapter.TradingStats memory globalStats = adapter.stats();
        assertEq(globalStats.totalTrades, 2);
        assertEq(globalStats.totalVolume, 150 * 1e18);
    }
    
    function testAdminOnlyFunctions() public {
        // Non-admin should fail
        vm.expectRevert();
        vm.prank(user1);
        adapter.updateDefaultFeeTier(5000);
        
        vm.expectRevert();
        vm.prank(user1);
        adapter.updateSlippageTolerance(300);
        
        vm.expectRevert();
        vm.prank(user1);
        adapter.pause();
    }
    
    // Helper function to setup a pool with liquidity
    function _setupPool(address token) internal {
        vm.startPrank(admin);
        adapter.createEKWHPool(token, 0);
        vm.stopPrank();
        
        uint256 ekwhAmount = 10000 * 1e6;
        uint256 tokenAmount = token == address(usdc) ? 10000 * 1e18 : 10 * 1e18;
        
        vm.startPrank(user2);
        ekwhToken.approve(address(adapter), ekwhAmount);
        MockToken(token).approve(address(adapter), tokenAmount);
        
        adapter.addEKWHLiquidity(
            token,
            ekwhAmount,
            tokenAmount,
            ekwhAmount * 99 / 100,
            tokenAmount * 99 / 100,
            block.timestamp + 3600
        );
        vm.stopPrank();
    }
    
    // Fuzz testing
    function testFuzzSwapToEKWH(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 * 1e18, 1000 * 1e18);
        _setupPool(address(usdc));
        
        vm.startPrank(user1);
        usdc.approve(address(adapter), amountIn);
        
        uint256 ekwhOut = adapter.swapToEKWH(
            address(usdc),
            amountIn,
            0,
            block.timestamp + 3600
        );
        
        assertGt(ekwhOut, 0);
        vm.stopPrank();
    }
    
    function testFuzzSwapFromEKWH(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 * 1e6, 1000 * 1e6);
        _setupPool(address(usdc));
        
        vm.startPrank(user1);
        ekwhToken.approve(address(adapter), amountIn);
        
        uint256 usdcOut = adapter.swapFromEKWH(
            address(usdc),
            amountIn,
            0,
            block.timestamp + 3600
        );
        
        assertGt(usdcOut, 0);
        vm.stopPrank();
    }
}