#!/bin/bash
# FILE: demo/make-proof.sh

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
ROFL_ENDPOINT=${ROFL_ENDPOINT:-"http://localhost:8080"}
OUTPUT_DIR=${OUTPUT_DIR:-"demo/proofs"}
WALRUS_ENDPOINT=${WALRUS_PUBLISHER_URL:-"http://localhost:8081/mock"}
FORCE_AGGREGATION=${FORCE_AGGREGATION:-false}
MAX_WAIT_TIME=${MAX_WAIT_TIME:-60}

# Function to check if ROFL is running
check_rofl_health() {
    print_status "Checking ROFL enclave health..."
    
    local response
    if response=$(curl -s -f "$ROFL_ENDPOINT/health" 2>/dev/null); then
        local status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "unknown")
        if [ "$status" = "healthy" ]; then
            print_success "ROFL enclave is healthy"
            return 0
        else
            print_error "ROFL enclave is not healthy: $status"
            return 1
        fi
    else
        print_error "ROFL enclave is not responding at $ROFL_ENDPOINT"
        return 1
    fi
}

# Function to get current aggregation status
get_aggregation_status() {
    print_status "Getting aggregation status..."
    
    local response
    if response=$(curl -s -f "$ROFL_ENDPOINT/api/v1/status" 2>/dev/null); then
        echo "$response"
        return 0
    else
        print_error "Failed to get aggregation status"
        return 1
    fi
}

# Function to trigger aggregation
trigger_aggregation() {
    print_status "Triggering proof aggregation..."
    
    local payload='{"force": true, "seal_to_walrus": true}'
    local response
    
    if response=$(curl -s -f -X POST "$ROFL_ENDPOINT/api/v1/aggregate" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null); then
        
        local success=$(echo "$response" | jq -r '.success' 2>/dev/null || echo "false")
        if [ "$success" = "true" ]; then
            print_success "Aggregation triggered successfully"
            local proof_id=$(echo "$response" | jq -r '.proof_id' 2>/dev/null || echo "unknown")
            print_status "Proof ID: $proof_id"
            echo "$proof_id"
            return 0
        else
            local error=$(echo "$response" | jq -r '.error' 2>/dev/null || echo "unknown error")
            print_error "Aggregation failed: $error"
            return 1
        fi
    else
        print_error "Failed to trigger aggregation"
        return 1
    fi
}

# Function to wait for proof generation
wait_for_proof() {
    local proof_id=$1
    local wait_time=0
    
    print_status "Waiting for proof generation (max ${MAX_WAIT_TIME}s)..."
    
    while [ $wait_time -lt $MAX_WAIT_TIME ]; do
        local response
        if response=$(curl -s -f "$ROFL_ENDPOINT/api/v1/proofs/latest" 2>/dev/null); then
            local latest_proof_id=$(echo "$response" | jq -r '.proof_id' 2>/dev/null || echo "")
            local status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "unknown")
            
            if [ "$latest_proof_id" = "$proof_id" ] && [ "$status" = "completed" ]; then
                print_success "Proof generation completed!"
                echo "$response"
                return 0
            elif [ "$status" = "failed" ]; then
                print_error "Proof generation failed"
                return 1
            else
                print_status "Proof generation in progress... ($wait_time/${MAX_WAIT_TIME}s)"
            fi
        else
            print_warning "Failed to check proof status, retrying..."
        fi
        
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    print_error "Timeout waiting for proof generation"
    return 1
}

# Function to download proof
download_proof() {
    local proof_id=$1
    
    print_status "Downloading proof: $proof_id"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    local proof_file="$OUTPUT_DIR/proof_${proof_id}.json"
    local response
    
    if response=$(curl -s -f "$ROFL_ENDPOINT/api/v1/proofs/$proof_id" 2>/dev/null); then
        echo "$response" > "$proof_file"
        print_success "Proof saved to: $proof_file"
        
        # Also save as latest proof
        local latest_file="$OUTPUT_DIR/latest_proof.json"
        cp "$proof_file" "$latest_file"
        print_success "Latest proof link created: $latest_file"
        
        # Show proof summary
        show_proof_summary "$proof_file"
        
        echo "$proof_file"
        return 0
    else
        print_error "Failed to download proof"
        return 1
    fi
}

# Function to show proof summary
show_proof_summary() {
    local proof_file=$1
    
    if [ ! -f "$proof_file" ]; then
        print_error "Proof file not found: $proof_file"
        return 1
    fi
    
    print_status "Proof Summary:"
    echo "=================================="
    
    local proof_id=$(jq -r '.proof_id' "$proof_file" 2>/dev/null || echo "unknown")
    local aggregate_kwh=$(jq -r '.aggregate_kwh' "$proof_file" 2>/dev/null || echo "0")
    local record_count=$(jq -r '.record_count' "$proof_file" 2>/dev/null || echo "0")
    local window_start=$(jq -r '.window_start' "$proof_file" 2>/dev/null || echo "unknown")
    local window_end=$(jq -r '.window_end' "$proof_file" 2>/dev/null || echo "unknown")
    local merkle_root=$(jq -r '.merkle_root' "$proof_file" 2>/dev/null || echo "unknown")
    local walrus_cid=$(jq -r '.walrus_cid' "$proof_file" 2>/dev/null || echo "null")
    local seal_hash=$(jq -r '.seal_hash' "$proof_file" 2>/dev/null || echo "null")
    
    echo "Proof ID:       $proof_id"
    echo "Total Energy:   $aggregate_kwh kWh"
    echo "Records:        $record_count"
    echo "Time Window:    $(date -d "$window_start" 2>/dev/null || echo "$window_start") to $(date -d "$window_end" 2>/dev/null || echo "$window_end")"
    echo "Merkle Root:    ${merkle_root:0:16}...${merkle_root: -8}"
    
    if [ "$walrus_cid" != "null" ]; then
        echo "Walrus CID:     $walrus_cid"
    fi
    
    if [ "$seal_hash" != "null" ]; then
        echo "Seal Hash:      ${seal_hash:0:16}...${seal_hash: -8}"
    fi
    
    # Show meter breakdown
    local meter_count=$(jq -r '.meter_ids | length' "$proof_file" 2>/dev/null || echo "0")
    if [ "$meter_count" -gt 0 ]; then
        echo "Meters:         $meter_count meters"
        echo "Meter IDs:      $(jq -r '.meter_ids[0:3] | join(", ")' "$proof_file" 2>/dev/null || echo "unknown")$([ "$meter_count" -gt 3 ] && echo "...")"
    fi
    
    echo "=================================="
}

# Function to validate proof
validate_proof() {
    local proof_file=$1
    
    print_status "Validating proof structure..."
    
    if [ ! -f "$proof_file" ]; then
        print_error "Proof file not found: $proof_file"
        return 1
    fi
    
    # Check required fields
    local required_fields=("proof_id" "aggregate_kwh" "merkle_root" "record_count" "window_start" "window_end" "generated_at")
    
    for field in "${required_fields[@]}"; do
        local value=$(jq -r ".$field" "$proof_file" 2>/dev/null)
        if [ "$value" = "null" ] || [ -z "$value" ]; then
            print_error "Missing required field: $field"
            return 1
        fi
    done
    
    # Validate data types and ranges
    local aggregate_kwh=$(jq -r '.aggregate_kwh' "$proof_file" 2>/dev/null)
    local record_count=$(jq -r '.record_count' "$proof_file" 2>/dev/null)
    
    if ! [[ "$aggregate_kwh" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        print_error "Invalid aggregate_kwh value: $aggregate_kwh"
        return 1
    fi
    
    if ! [[ "$record_count" =~ ^[0-9]+$ ]]; then
        print_error "Invalid record_count value: $record_count"
        return 1
    fi
    
    # Check if energy amount is reasonable
    if (( $(echo "$aggregate_kwh > 10000" | bc -l) )); then
        print_warning "Very high energy amount: $aggregate_kwh kWh"
    fi
    
    if [ "$record_count" -eq 0 ]; then
        print_warning "No records in proof"
    fi
    
    print_success "Proof validation passed"
    return 0
}

# Function to upload proof to Walrus
upload_to_walrus() {
    local proof_file=$1
    
    if [ ! -f "$proof_file" ]; then
        print_error "Proof file not found: $proof_file"
        return 1
    fi
    
    print_status "Uploading proof to Walrus..."
    
    # Use the storage upload script
    local upload_result
    if upload_result=$(node -r ts-node/register scripts/upload.ts upload "$proof_file" 2>/dev/null); then
        print_success "Proof uploaded to Walrus successfully"
        echo "$upload_result"
        return 0
    else
        print_warning "Failed to upload to Walrus (continuing anyway)"
        return 1
    fi
}

# Function to check aggregation window
check_aggregation_window() {
    print_status "Checking if aggregation window is ready..."
    
    local status_response
    if status_response=$(get_aggregation_status); then
        local pending_records=$(echo "$status_response" | jq -r '.pending_records' 2>/dev/null || echo "0")
        local last_aggregation=$(echo "$status_response" | jq -r '.last_aggregation_time' 2>/dev/null || echo "null")
        local window_size=$(echo "$status_response" | jq -r '.aggregation_window_sec' 2>/dev/null || echo "300")
        
        echo "Pending Records: $pending_records"
        echo "Window Size:     ${window_size}s"
        echo "Last Aggregation: $last_aggregation"
        
        if [ "$pending_records" -gt 0 ]; then
            print_success "Ready for aggregation ($pending_records pending records)"
            return 0
        else
            print_warning "No pending records for aggregation"
            if [ "$FORCE_AGGREGATION" = "true" ]; then
                print_status "Forcing aggregation anyway..."
                return 0
            else
                return 1
            fi
        fi
    else
        print_error "Could not check aggregation status"
        return 1
    fi
}

# Main function
main() {
    print_status "🔮 GreenShare Proof Generation"
    echo "==============================="
    
    # Parse command line arguments
    FORCE_AGGREGATION=false
    SKIP_DOWNLOAD=false
    SKIP_VALIDATION=false
    UPLOAD_TO_WALRUS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_AGGREGATION=true
                shift
                ;;
            --skip-download)
                SKIP_DOWNLOAD=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --upload-walrus)
                UPLOAD_TO_WALRUS=true
                shift
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --max-wait)
                MAX_WAIT_TIME="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force            Force aggregation even if no pending records"
                echo "  --skip-download    Skip downloading the proof file"
                echo "  --skip-validation  Skip proof validation"
                echo "  --upload-walrus    Upload proof to Walrus after generation"
                echo "  --output-dir DIR   Output directory for proof files (default: demo/proofs)"
                echo "  --max-wait SEC     Maximum wait time for proof generation (default: 60)"
                echo "  --help, -h         Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  ROFL_ENDPOINT      ROFL enclave endpoint (default: http://localhost:8080)"
                echo "  OUTPUT_DIR         Output directory for proofs"
                echo "  FORCE_AGGREGATION  Force aggregation (true/false)"
                echo "  MAX_WAIT_TIME      Maximum wait time in seconds"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_status "Configuration:"
    echo "  ROFL Endpoint: $ROFL_ENDPOINT"
    echo "  Output Dir:    $OUTPUT_DIR"
    echo "  Force:         $FORCE_AGGREGATION"
    echo "  Max Wait:      ${MAX_WAIT_TIME}s"
    echo ""
    
    # Check if required tools are available
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required but not installed"
        exit 1
    fi
    
    # Check ROFL health
    if ! check_rofl_health; then
        print_error "ROFL enclave is not available"
        exit 1
    fi
    
    # Check aggregation readiness
    if ! check_aggregation_window; then
        if [ "$FORCE_AGGREGATION" != "true" ]; then
            print_error "No data ready for aggregation. Use --force to aggregate anyway."
            exit 1
        fi
    fi
    
    # Trigger aggregation
    local proof_id
    if ! proof_id=$(trigger_aggregation); then
        print_error "Failed to trigger aggregation"
        exit 1
    fi
    
    # Wait for proof generation
    local proof_data
    if ! proof_data=$(wait_for_proof "$proof_id"); then
        print_error "Proof generation failed or timed out"
        exit 1
    fi
    
    # Download proof
    local proof_file
    if [ "$SKIP_DOWNLOAD" != "true" ]; then
        if ! proof_file=$(download_proof "$proof_id"); then
            print_error "Failed to download proof"
            exit 1
        fi
    else
        proof_file="$OUTPUT_DIR/proof_${proof_id}.json"
        print_status "Skipping download, using: $proof_file"
    fi
    
    # Validate proof
    if [ "$SKIP_VALIDATION" != "true" ]; then
        if ! validate_proof "$proof_file"; then
            print_error "Proof validation failed"
            exit 1
        fi
    fi
    
    # Upload to Walrus if requested
    if [ "$UPLOAD_TO_WALRUS" = "true" ]; then
        upload_to_walrus "$proof_file" || true
    fi
    
    # Success message
    echo ""
    print_success "🎉 Proof generation completed successfully!"
    echo ""
    print_status "Generated Files:"
    echo "  Latest Proof: $OUTPUT_DIR/latest_proof.json"
    echo "  Specific:     $proof_file"
    echo ""
    print_status "Next Steps:"
    echo "  1. Mint sKWH on Sui:     npm run demo:mint"
    echo "  2. Bridge to Zircuit:    npm run demo:bridge" 
    echo "  3. Trade on Gud Engine:  npm run demo:trade"
}

# Run main function
main "$@"