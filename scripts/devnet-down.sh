#!/bin/bash
# FILE: scripts/devnet-down.sh

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

# Function to stop process by PID file
stop_process() {
    local pid_file=$1
    local service_name=$2
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            print_status "Stopping $service_name (PID: $pid)..."
            kill "$pid"
            
            # Wait for process to stop
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                print_warning "Force killing $service_name..."
                kill -9 "$pid" 2>/dev/null || true
            fi
            
            print_success "$service_name stopped"
        else
            print_status "$service_name was not running"
        fi
        rm -f "$pid_file"
    else
        print_status "No PID file found for $service_name"
    fi
}

# Function to stop Docker services
stop_docker_services() {
    print_status "Stopping Docker services..."
    
    if [ -f "docker-compose.yml" ]; then
        docker-compose down
        print_success "Docker services stopped"
    else
        print_status "No docker-compose.yml found, skipping Docker cleanup"
    fi
}

# Function to cleanup Docker resources
cleanup_docker() {
    local cleanup_volumes=false
    local cleanup_images=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --volumes)
                cleanup_volumes=true
                shift
                ;;
            --images)
                cleanup_images=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [ "$cleanup_volumes" = true ]; then
        print_status "Cleaning up Docker volumes..."
        docker-compose down -v 2>/dev/null || true
        print_success "Docker volumes cleaned"
    fi
    
    if [ "$cleanup_images" = true ]; then
        print_status "Cleaning up Docker images..."
        docker-compose down --rmi all 2>/dev/null || true
        print_success "Docker images cleaned"
    fi
}

# Function to cleanup log files
cleanup_logs() {
    print_status "Cleaning up log files..."
    
    if [ -d "logs" ]; then
        rm -f logs/*.log
        print_success "Log files cleaned"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    print_status "Cleanup Summary:"
    echo "=================================="
    
    # Check if any services are still running
    local still_running=()
    
    if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        still_running+=("Frontend (port 3000)")
    fi
    
    if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
        still_running+=("ROFL Enclave (port 8080)")
    fi
    
    if lsof -Pi :8081 -sTCP:LISTEN -t >/dev/null 2>&1; then
        still_running+=("Mock Walrus (port 8081)")
    fi
    
    if [ ${#still_running[@]} -eq 0 ]; then
        echo -e "🟢 All services stopped successfully"
    else
        echo -e "🟡 Some services may still be running:"
        for service in "${still_running[@]}"; do
            echo -e "   - $service"
        done
    fi
    
    echo "=================================="
}

# Main function
main() {
    print_status "🛑 Stopping GreenShare Development Environment"
    echo "================================================="
    
    # Parse command line arguments
    CLEANUP_VOLUMES=false
    CLEANUP_IMAGES=false
    CLEANUP_LOGS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --volumes)
                CLEANUP_VOLUMES=true
                shift
                ;;
            --images)
                CLEANUP_IMAGES=true
                shift
                ;;
            --logs)
                CLEANUP_LOGS=true
                shift
                ;;
            --all)
                CLEANUP_VOLUMES=true
                CLEANUP_IMAGES=true
                CLEANUP_LOGS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --volumes      Remove Docker volumes"
                echo "  --images       Remove Docker images"
                echo "  --logs         Clean log files"
                echo "  --all          Clean everything"
                echo "  --help, -h     Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Stop Node.js processes
    stop_process ".frontend.pid" "Frontend"
    stop_process ".rofl.pid" "ROFL Enclave"
    stop_process ".walrus.pid" "Mock Walrus"
    
    # Stop Docker services
    stop_docker_services
    
    # Cleanup if requested
    if [ "$CLEANUP_VOLUMES" = true ] || [ "$CLEANUP_IMAGES" = true ]; then
        cleanup_docker --volumes="$CLEANUP_VOLUMES" --images="$CLEANUP_IMAGES"
    fi
    
    if [ "$CLEANUP_LOGS" = true ]; then
        cleanup_logs
    fi
    
    # Show summary
    echo ""
    show_cleanup_summary
    
    print_success "🎉 GreenShare development environment stopped!"
}

# Run main function
main "$@"