#!/bin/bash
# FILE: scripts/deploy-all.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
NETWORKS=()
DEPLOY_SUI=false
DEPLOY_ZIRCUIT=false
DEPLOY_CELO=false
DRY_RUN=false
FORCE=false
SKIP_TESTS=false

# Deployment results
DEPLOYMENT_RESULTS=()

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate environment
validate_environment() {
    print_status "Validating deployment environment..."
    
    local missing_deps=()
    local missing_env=()
    
    # Check required tools
    if [ "$DEPLOY_SUI" = true ] && ! command_exists sui; then
        missing_deps+=("sui CLI")
    fi
    
    if [ "$DEPLOY_ZIRCUIT" = true ] && ! command_exists forge; then
        missing_deps+=("foundry/forge")
    fi
    
    if [ "$DEPLOY_CELO" = true ] && ! command_exists npx; then
        missing_deps+=("npx/hardhat")
    fi
    
    # Check environment variables
    if [ ! -f ".env" ]; then
        print_error ".env file not found"
        exit 1
    fi
    
    # Load environment
    source .env
    
    # Check network-specific environment variables
    if [ "$DEPLOY_SUI" = true ]; then
        [ -z "$SUI_PRIVATE_KEY" ] && missing_env+=("SUI_PRIVATE_KEY")
        [ -z "$SUI_NETWORK" ] && missing_env+=("SUI_NETWORK")
    fi
    
    if [ "$DEPLOY_ZIRCUIT" = true ]; then
        [ -z "$ZIRCUIT_PRIVATE_KEY" ] && missing_env+=("ZIRCUIT_PRIVATE_KEY")
        [ -z "$ZIRCUIT_RPC_URL" ] && missing_env+=("ZIRCUIT_RPC_URL")
    fi
    
    if [ "$DEPLOY_CELO" = true ]; then
        [ -z "$CELO_PRIVATE_KEY" ] && missing_env+=("CELO_PRIVATE_KEY")
        [ -z "$CELO_RPC_URL" ] && missing_env+=("CELO_RPC_URL")
    fi
    
    # Report missing dependencies
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    if [ ${#missing_env[@]} -ne 0 ]; then
        print_error "Missing environment variables: ${missing_env[*]}"
        exit 1
    fi
    
    print_success "Environment validation passed"
}

# Function to run pre-deployment tests
run_tests() {
    if [ "$SKIP_TESTS" = true ]; then
        print_status "Skipping tests as requested"
        return 0
    fi
    
    print_status "Running pre-deployment tests..."
    
    # TypeScript type checking
    if [ -f "package.json" ]; then
        print_status "Running TypeScript type check..."
        if command_exists pnpm; then
            pnpm type-check
        else
            npm run type-check
        fi
    fi
    
    # Rust tests
    if [ -f "Cargo.toml" ]; then
        print_status "Running Rust tests..."
        cargo test
    fi
    
    # Move tests
    if [ "$DEPLOY_SUI" = true ] && [ -d "sources" ]; then
        print_status "Running Sui Move tests..."
        sui move test
    fi
    
    # Solidity tests
    if [ "$DEPLOY_ZIRCUIT" = true ] && [ -f "foundry.toml" ]; then
        print_status "Running Solidity tests..."
        forge test
    fi
    
    print_success "All tests passed"
}

# Function to deploy to Sui
deploy_sui() {
    print_status "🔷 Deploying to Sui Network ($SUI_NETWORK)..."
    
    local start_time=$(date +%s)
    local deployment_file="deployments/sui-${SUI_NETWORK}.json"
    
    # Create deployments directory
    mkdir -p deployments
    
    # Build Move packages
    print_status "Building Sui Move packages..."
    sui move build
    
    # Deploy packages
    print_status "Publishing Sui packages..."
    local publish_output
    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN: Would publish Sui packages"
        publish_output="DRY_RUN_PACKAGE_ID"
    else
        publish_output=$(sui client publish --gas-budget 100000000 --json)
    fi
    
    # Parse deployment results
    local package_id
    if [ "$DRY_RUN" = true ]; then
        package_id="DRY_RUN_PACKAGE_ID"
    else
        package_id=$(echo "$publish_output" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
    fi
    
    # Save deployment info
    local deployment_info=$(cat << EOF
{
  "network": "$SUI_NETWORK",
  "packageId": "$package_id",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$(sui client active-address)",
  "gasUsed": "$(echo "$publish_output" | jq -r '.balanceChanges[0].amount // "0"')",
  "transactionDigest": "$(echo "$publish_output" | jq -r '.digest // "dry-run"')"
}
EOF
    )
    
    echo "$deployment_info" > "$deployment_file"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    DEPLOYMENT_RESULTS+=("✅ Sui: $package_id (${duration}s)")
    
    print_success "Sui deployment completed in ${duration}s"
    print_status "Package ID: $package_id"
    print_status "Deployment saved to: $deployment_file"
}

# Function to deploy to Zircuit
deploy_zircuit() {
    print_status "⚡ Deploying to Zircuit Network..."
    
    local start_time=$(date +%s)
    local deployment_file="deployments/zircuit-testnet.json"
    
    # Create deployments directory
    mkdir -p deployments
    
    # Build contracts
    print_status "Building Solidity contracts..."
    forge build
    
    # Deploy contracts
    print_status "Deploying contracts to Zircuit..."
    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN: Would deploy contracts to Zircuit"
        local deploy_output='{"success": true, "contracts": {"eKWH": "0xDRY_RUN_ADDRESS"}}'
    else
        # Run the deployment script
        local deploy_output=$(npx hardhat run scripts/deploy.ts --network zircuit-testnet)
    fi
    
    # Parse deployment results
    local deployment_addresses
    if [ "$DRY_RUN" = true ]; then
        deployment_addresses='{"eKWH": "0xDRY_RUN_ADDRESS", "Bridge": "0xDRY_RUN_ADDRESS", "GudAdapter": "0xDRY_RUN_ADDRESS"}'
    else
        # Extract addresses from deployment output
        deployment_addresses=$(echo "$deploy_output" | grep -o '0x[a-fA-F0-9]\{40\}' | head -3 | jq -R . | jq -s '{"eKWH": .[0], "Bridge": .[1], "GudAdapter": .[2]}')
    fi
    
    # Save deployment info
    local deployment_info=$(cat << EOF
{
  "network": "zircuit-testnet",
  "chainId": 48899,
  "contracts": $deployment_addresses,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$(cast wallet address --private-key $ZIRCUIT_PRIVATE_KEY)",
  "rpcUrl": "$ZIRCUIT_RPC_URL"
}
EOF
    )
    
    echo "$deployment_info" > "$deployment_file"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local ekwh_address=$(echo "$deployment_addresses" | jq -r '.eKWH')
    DEPLOYMENT_RESULTS+=("✅ Zircuit: $ekwh_address (${duration}s)")
    
    print_success "Zircuit deployment completed in ${duration}s"
    print_status "eKWH Contract: $ekwh_address"
    print_status "Deployment saved to: $deployment_file"
}

# Function to deploy to Celo
deploy_celo() {
    print_status "🟡 Deploying to Celo Network..."
    
    local start_time=$(date +%s)
    local deployment_file="deployments/celo-alfajores.json"
    
    # Create deployments directory
    mkdir -p deployments
    
    # Build contracts
    print_status "Building Celo contracts..."
    if [ -f "hardhat.config.js" ] || [ -f "hardhat.config.ts" ]; then
        npx hardhat compile
    else
        forge build
    fi
    
    # Deploy KYC Registry
    print_status "Deploying KYC Registry to Celo..."
    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN: Would deploy KYC Registry to Celo"
        local kyc_address="0xDRY_RUN_KYC_ADDRESS"
    else
        # Deploy KYC Registry contract
        local deploy_script="scripts/deploy-celo.ts"
        if [ -f "$deploy_script" ]; then
            local deploy_output=$(npx hardhat run "$deploy_script" --network celo-alfajores)
            local kyc_address=$(echo "$deploy_output" | grep -o '0x[a-fA-F0-9]\{40\}' | head -1)
        else
            # Fallback deployment
            local kyc_address=$(forge create contracts/KYCRegistry.sol:KYCRegistry \
                --private-key "$CELO_PRIVATE_KEY" \
                --rpc-url "$CELO_RPC_URL" \
                --constructor-args "$(cast wallet address --private-key $CELO_PRIVATE_KEY)" \
                | grep "Deployed to:" | awk '{print $3}')
        fi
    fi
    
    # Save deployment info
    local deployment_info=$(cat << EOF
{
  "network": "celo-alfajores",
  "chainId": 44787,
  "contracts": {
    "KYCRegistry": "$kyc_address"
  },
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$(cast wallet address --private-key $CELO_PRIVATE_KEY)",
  "rpcUrl": "$CELO_RPC_URL"
}
EOF
    )
    
    echo "$deployment_info" > "$deployment_file"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    DEPLOYMENT_RESULTS+=("✅ Celo: $kyc_address (${duration}s)")
    
    print_success "Celo deployment completed in ${duration}s"
    print_status "KYC Registry: $kyc_address"
    print_status "Deployment saved to: $deployment_file"
}

# Function to update configuration files
update_config() {
    print_status "Updating configuration files..."
    
    # Update frontend config
    if [ -f "lib/config/contracts.ts" ]; then
        print_status "Updating contracts configuration..."
        
        # Read deployment files and update config
        local sui_config=""
        local zircuit_config=""
        local celo_config=""
        
        if [ -f "deployments/sui-${SUI_NETWORK}.json" ]; then
            sui_config=$(cat "deployments/sui-${SUI_NETWORK}.json")
        fi
        
        if [ -f "deployments/zircuit-testnet.json" ]; then
            zircuit_config=$(cat "deployments/zircuit-testnet.json")
        fi
        
        if [ -f "deployments/celo-alfajores.json" ]; then
            celo_config=$(cat "deployments/celo-alfajores.json")
        fi
        
        # Generate updated config file
        cat > "lib/config/contracts.ts" << EOF
// FILE: lib/config/contracts.ts
// Auto-generated by deploy-all.sh at $(date)

export const CONTRACTS = {
  sui: ${sui_config:-'{}'},
  zircuit: ${zircuit_config:-'{}'},
  celo: ${celo_config:-'{}'}
};

export const getContractAddress = (network: string, contract: string): string => {
  const config = CONTRACTS[network as keyof typeof CONTRACTS];
  if (!config || !config.contracts) {
    throw new Error(\`No configuration found for network: \${network}\`);
  }
  
  const address = config.contracts[contract];
  if (!address) {
    throw new Error(\`Contract \${contract} not found for network \${network}\`);
  }
  
  return address;
};
EOF
        
        print_success "Updated contracts configuration"
    fi
    
    # Update README with deployment addresses
    if [ -f "README.md" ]; then
        print_status "Updating README with deployment addresses..."
        
        # Create deployment section
        local deployment_section=$(cat << 'EOF'

## 🚀 Deployment Addresses

### Testnet Deployments

EOF
        )
        
        if [ ${#DEPLOYMENT_RESULTS[@]} -gt 0 ]; then
            deployment_section+="\`\`\`\n"
            for result in "${DEPLOYMENT_RESULTS[@]}"; do
                deployment_section+="$result\n"
            done
            deployment_section+="\`\`\`\n"
        fi
        
        # Add timestamp
        deployment_section+="\n*Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)*\n"
        
        # Update README (append or replace deployment section)
        if grep -q "## 🚀 Deployment Addresses" README.md; then
            # Replace existing section
            sed -i '/## 🚀 Deployment Addresses/,$d' README.md
        fi
        
        echo "$deployment_section" >> README.md
        
        print_success "Updated README with deployment information"
    fi
}

# Function to verify deployments
verify_deployments() {
    print_status "Verifying deployments..."
    
    local verification_errors=()
    
    # Verify Sui deployment
    if [ "$DEPLOY_SUI" = true ] && [ -f "deployments/sui-${SUI_NETWORK}.json" ]; then
        local package_id=$(jq -r '.packageId' "deployments/sui-${SUI_NETWORK}.json")
        if [ "$package_id" != "null" ] && [ "$package_id" != "DRY_RUN_PACKAGE_ID" ]; then
            if sui client object "$package_id" >/dev/null 2>&1; then
                print_success "Sui package verified: $package_id"
            else
                verification_errors+=("Sui package not found: $package_id")
            fi
        fi
    fi
    
    # Verify Zircuit deployment
    if [ "$DEPLOY_ZIRCUIT" = true ] && [ -f "deployments/zircuit-testnet.json" ]; then
        local ekwh_address=$(jq -r '.contracts.eKWH' "deployments/zircuit-testnet.json")
        if [ "$ekwh_address" != "null" ] && [ "$ekwh_address" != "0xDRY_RUN_ADDRESS" ]; then
            if cast code "$ekwh_address" --rpc-url "$ZIRCUIT_RPC_URL" | grep -q "0x"; then
                print_success "Zircuit contract verified: $ekwh_address"
            else
                verification_errors+=("Zircuit contract not found: $ekwh_address")
            fi
        fi
    fi
    
    # Verify Celo deployment
    if [ "$DEPLOY_CELO" = true ] && [ -f "deployments/celo-alfajores.json" ]; then
        local kyc_address=$(jq -r '.contracts.KYCRegistry' "deployments/celo-alfajores.json")
        if [ "$kyc_address" != "null" ] && [ "$kyc_address" != "0xDRY_RUN_KYC_ADDRESS" ]; then
            if cast code "$kyc_address" --rpc-url "$CELO_RPC_URL" | grep -q "0x"; then
                print_success "Celo contract verified: $kyc_address"
            else
                verification_errors+=("Celo contract not found: $kyc_address")
            fi
        fi
    fi
    
    if [ ${#verification_errors[@]} -gt 0 ]; then
        print_error "Verification errors:"
        for error in "${verification_errors[@]}"; do
            print_error "  - $error"
        done
        return 1
    fi
    
    print_success "All deployments verified successfully"
}

# Function to show deployment summary
show_summary() {
    print_status "Deployment Summary:"
    echo "===================================="
    
    if [ ${#DEPLOYMENT_RESULTS[@]} -gt 0 ]; then
        for result in "${DEPLOYMENT_RESULTS[@]}"; do
            echo "$result"
        done
    else
        echo "No deployments executed"
    fi
    
    echo ""
    echo "Deployment files:"
    if [ -d "deployments" ]; then
        find deployments -name "*.json" -exec echo "  - {}" \;
    fi
    
    echo "===================================="
}

# Main function
main() {
    print_status "🚀 GreenShare Multi-Chain Deployment"
    echo "====================================="
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sui)
                DEPLOY_SUI=true
                NETWORKS+=("sui")
                shift
                ;;
            --zircuit)
                DEPLOY_ZIRCUIT=true
                NETWORKS+=("zircuit")
                shift
                ;;
            --celo)
                DEPLOY_CELO=true
                NETWORKS+=("celo")
                shift
                ;;
            --all)
                DEPLOY_SUI=true
                DEPLOY_ZIRCUIT=true
                DEPLOY_CELO=true
                NETWORKS+=("sui" "zircuit" "celo")
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Networks:"
                echo "  --sui          Deploy to Sui network"
                echo "  --zircuit      Deploy to Zircuit network"
                echo "  --celo         Deploy to Celo network"
                echo "  --all          Deploy to all networks"
                echo ""
                echo "Options:"
                echo "  --dry-run      Simulate deployment without executing"
                echo "  --force        Force deployment even if tests fail"
                echo "  --skip-tests   Skip pre-deployment tests"
                echo "  --help, -h     Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 --all                     # Deploy to all networks"
                echo "  $0 --sui --zircuit          # Deploy to Sui and Zircuit only"
                echo "  $0 --all --dry-run          # Simulate deployment to all networks"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check if any networks selected
    if [ ${#NETWORKS[@]} -eq 0 ]; then
        print_error "No networks selected for deployment"
        print_error "Use --help to see available options"
        exit 1
    fi
    
    print_status "Selected networks: ${NETWORKS[*]}"
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No actual deployments will be executed"
    fi
    
    # Validate environment
    validate_environment
    
    # Run tests unless forced or skipped
    if [ "$FORCE" = false ]; then
        run_tests
    else
        print_warning "Skipping tests due to --force flag"
    fi
    
    # Confirm deployment unless dry run
    if [ "$DRY_RUN" = false ]; then
        echo ""
        print_warning "This will deploy contracts to the following networks: ${NETWORKS[*]}"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled by user"
            exit 1
        fi
    fi
    
    # Execute deployments
    echo ""
    print_status "Starting deployments..."
    
    local deployment_start_time=$(date +%s)
    
    # Deploy in order: Sui -> Zircuit -> Celo
    if [ "$DEPLOY_SUI" = true ]; then
        deploy_sui
        echo ""
    fi
    
    if [ "$DEPLOY_ZIRCUIT" = true ]; then
        deploy_zircuit
        echo ""
    fi
    
    if [ "$DEPLOY_CELO" = true ]; then
        deploy_celo
        echo ""
    fi
    
    # Update configuration
    update_config
    
    # Verify deployments
    if [ "$DRY_RUN" = false ]; then
        verify_deployments
    fi
    
    local deployment_end_time=$(date +%s)
    local total_duration=$((deployment_end_time - deployment_start_time))
    
    # Show summary
    echo ""
    show_summary
    
    print_success "🎉 Multi-chain deployment completed in ${total_duration}s!"
    
    if [ "$DRY_RUN" = false ]; then
        echo ""
        print_status "Next steps:"
        echo "1. Update frontend environment variables with new contract addresses"
        echo "2. Test contract interactions on each network"
        echo "3. Set up monitoring and alerting"
        echo "4. Update documentation with new addresses"
    fi
}

# Run main function
main "$@"