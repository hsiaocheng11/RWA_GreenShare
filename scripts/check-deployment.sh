#!/bin/bash
# FILE: scripts/check-deployment.sh
# GreenShare Deployment Verification Script

set -e

echo "🔍 GreenShare Deployment Verification"
echo "====================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✅ $1 is installed${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 is not installed${NC}"
        return 1
    fi
}

# Function to check environment variable
check_env_var() {
    if [ -n "${!1}" ]; then
        echo -e "${GREEN}✅ $1 is set${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  $1 is not set${NC}"
        return 1
    fi
}

# Function to check network connectivity
check_network() {
    local url="$1"
    local name="$2"
    
    if curl -s --max-time 10 "$url" > /dev/null; then
        echo -e "${GREEN}✅ $name is accessible${NC}"
        return 0
    else
        echo -e "${RED}❌ $name is not accessible${NC}"
        return 1
    fi
}

# Function to check file exists
check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✅ $1 exists${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 not found${NC}"
        return 1
    fi
}

# Check prerequisites
echo -e "\n${BLUE}📋 Checking Prerequisites${NC}"
echo "------------------------"

PREREQ_ERRORS=0

check_command "node" || PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
check_command "npm" || PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
check_command "cargo" || PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
check_command "docker" || PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
check_command "sui" || PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
check_command "forge" || PREREQ_ERRORS=$((PREREQ_ERRORS + 1))

# Check version requirements
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version | cut -d'v' -f2)
    if [[ "$(printf '%s\n' "18.0.0" "$NODE_VERSION" | sort -V | head -n1)" = "18.0.0" ]]; then
        echo -e "${GREEN}✅ Node.js version $NODE_VERSION >= 18.0.0${NC}"
    else
        echo -e "${RED}❌ Node.js version $NODE_VERSION < 18.0.0${NC}"
        PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
    fi
fi

# Check environment configuration
echo -e "\n${BLUE}🔧 Checking Environment Configuration${NC}"
echo "------------------------------------"

# Load environment variables
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✅ .env file found and loaded${NC}"
elif [ -f ".env.example" ]; then
    echo -e "${YELLOW}⚠️  .env not found, using .env.example${NC}"
    source .env.example
else
    echo -e "${RED}❌ No environment file found${NC}"
    PREREQ_ERRORS=$((PREREQ_ERRORS + 1))
fi

ENV_ERRORS=0

# Check critical environment variables
check_env_var "ROFL_ENDPOINT" || ENV_ERRORS=$((ENV_ERRORS + 1))
check_env_var "SUI_NETWORK" || ENV_ERRORS=$((ENV_ERRORS + 1))
check_env_var "ZIRCUIT_RPC_URL" || ENV_ERRORS=$((ENV_ERRORS + 1))
check_env_var "CELO_RPC_URL" || ENV_ERRORS=$((ENV_ERRORS + 1))
check_env_var "WALRUS_GATEWAY_URL" || ENV_ERRORS=$((ENV_ERRORS + 1))

# Check network connectivity
echo -e "\n${BLUE}🌐 Checking Network Connectivity${NC}"
echo "-------------------------------"

NETWORK_ERRORS=0

check_network "https://fullnode.testnet.sui.io:443" "Sui Testnet" || NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
check_network "https://zircuit-testnet.drpc.org" "Zircuit Testnet" || NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
check_network "https://alfajores-forno.celo-testnet.org" "Celo Alfajores" || NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
check_network "https://aggregator-devnet.walrus.space" "Walrus Gateway" || NETWORK_ERRORS=$((NETWORK_ERRORS + 1))

# Check project files
echo -e "\n${BLUE}📁 Checking Project Files${NC}"
echo "------------------------"

FILE_ERRORS=0

check_file "package.json" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "Cargo.toml" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "Move.toml" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "foundry.toml" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "docker-compose.yml" || FILE_ERRORS=$((FILE_ERRORS + 1))

# Check key source files
check_file "src/main.rs" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "sources/sKWH.move" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "contracts/eKWH.sol" || FILE_ERRORS=$((FILE_ERRORS + 1))
check_file "lib/config/contracts.ts" || FILE_ERRORS=$((FILE_ERRORS + 1))

# Check dependencies
echo -e "\n${BLUE}📦 Checking Dependencies${NC}"
echo "------------------------"

DEP_ERRORS=0

if [ -f "package.json" ]; then
    if [ -d "node_modules" ]; then
        echo -e "${GREEN}✅ Node.js dependencies installed${NC}"
    else
        echo -e "${YELLOW}⚠️  Node.js dependencies not installed. Run: npm install${NC}"
        DEP_ERRORS=$((DEP_ERRORS + 1))
    fi
fi

if [ -f "Cargo.toml" ]; then
    if cargo check &> /dev/null; then
        echo -e "${GREEN}✅ Rust dependencies resolved${NC}"
    else
        echo -e "${YELLOW}⚠️  Rust dependencies need resolution. Run: cargo check${NC}"
        DEP_ERRORS=$((DEP_ERRORS + 1))
    fi
fi

# Test compilation
echo -e "\n${BLUE}🔨 Testing Compilation${NC}"
echo "--------------------"

COMPILE_ERRORS=0

# Test TypeScript compilation
if [ -f "package.json" ] && [ -d "node_modules" ]; then
    if npm run type-check &> /dev/null; then
        echo -e "${GREEN}✅ TypeScript compilation successful${NC}"
    else
        echo -e "${RED}❌ TypeScript compilation failed${NC}"
        COMPILE_ERRORS=$((COMPILE_ERRORS + 1))
    fi
fi

# Test Rust compilation
if [ -f "Cargo.toml" ]; then
    if cargo build --quiet &> /dev/null; then
        echo -e "${GREEN}✅ Rust compilation successful${NC}"
    else
        echo -e "${RED}❌ Rust compilation failed${NC}"
        COMPILE_ERRORS=$((COMPILE_ERRORS + 1))
    fi
fi

# Test Move compilation
if [ -f "Move.toml" ] && command -v sui &> /dev/null; then
    if sui move build &> /dev/null; then
        echo -e "${GREEN}✅ Move compilation successful${NC}"
    else
        echo -e "${RED}❌ Move compilation failed${NC}"
        COMPILE_ERRORS=$((COMPILE_ERRORS + 1))
    fi
fi

# Test Solidity compilation
if [ -f "foundry.toml" ] && command -v forge &> /dev/null; then
    if forge build &> /dev/null; then
        echo -e "${GREEN}✅ Solidity compilation successful${NC}"
    else
        echo -e "${RED}❌ Solidity compilation failed${NC}"
        COMPILE_ERRORS=$((COMPILE_ERRORS + 1))
    fi
fi

# Run basic tests
echo -e "\n${BLUE}🧪 Running Tests${NC}"
echo "---------------"

TEST_ERRORS=0

if [ -f "package.json" ] && [ -d "node_modules" ]; then
    if npm test &> /dev/null; then
        echo -e "${GREEN}✅ JavaScript/TypeScript tests passed${NC}"
    else
        echo -e "${YELLOW}⚠️  JavaScript/TypeScript tests failed or skipped${NC}"
        TEST_ERRORS=$((TEST_ERRORS + 1))
    fi
fi

if [ -f "Cargo.toml" ]; then
    if cargo test --quiet &> /dev/null; then
        echo -e "${GREEN}✅ Rust tests passed${NC}"
    else
        echo -e "${YELLOW}⚠️  Rust tests failed or skipped${NC}"
        TEST_ERRORS=$((TEST_ERRORS + 1))
    fi
fi

# Summary
echo -e "\n${BLUE}📊 Summary${NC}"
echo "--------"

TOTAL_ERRORS=$((PREREQ_ERRORS + ENV_ERRORS + NETWORK_ERRORS + FILE_ERRORS + DEP_ERRORS + COMPILE_ERRORS + TEST_ERRORS))

if [ $TOTAL_ERRORS -eq 0 ]; then
    echo -e "${GREEN}🎉 All checks passed! The project is ready for deployment.${NC}"
    exit 0
else
    echo -e "${RED}❌ $TOTAL_ERRORS issues found:${NC}"
    echo "   - Prerequisites: $PREREQ_ERRORS"
    echo "   - Environment: $ENV_ERRORS"
    echo "   - Network: $NETWORK_ERRORS"
    echo "   - Files: $FILE_ERRORS"
    echo "   - Dependencies: $DEP_ERRORS"
    echo "   - Compilation: $COMPILE_ERRORS"
    echo "   - Tests: $TEST_ERRORS"
    echo ""
    echo -e "${YELLOW}Please fix the issues above before deploying.${NC}"
    exit 1
fi