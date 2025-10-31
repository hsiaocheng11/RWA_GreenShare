#!/bin/bash
# FILE: scripts/devnet-up.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="greenshare"
DOCKER_NETWORK="${PROJECT_NAME}_network"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is available
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1

    print_status "Waiting for $service_name to be ready on port $port..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "http://localhost:$port/health" >/dev/null 2>&1; then
            print_success "$service_name is ready!"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            print_error "$service_name failed to start after $max_attempts attempts"
            return 1
        fi
        
        print_status "Attempt $attempt/$max_attempts - waiting for $service_name..."
        sleep 2
        attempt=$((attempt + 1))
    done
}

# Function to setup environment
setup_environment() {
    print_status "Setting up environment..."
    
    # Create .env if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example "$ENV_FILE"
            print_success "Created $ENV_FILE from .env.example"
        else
            print_warning ".env.example not found, creating minimal $ENV_FILE"
            cat > "$ENV_FILE" << EOF
# GreenShare Development Environment
NODE_ENV=development

# ROFL Configuration
ROFL_ENDPOINT=http://localhost:8080
ROFL_HOST=0.0.0.0
ROFL_PORT=8080

# Mock Services
WALRUS_PUBLISHER_URL=http://localhost:8081/mock
WALRUS_GATEWAY_URL=http://localhost:8081/mock
MOCK_WALRUS_PORT=8081

# Frontend
NEXT_PUBLIC_APP_URL=http://localhost:3000
NEXT_PUBLIC_ROFL_ENDPOINT=http://localhost:8080

# Database
DATABASE_URL=postgresql://postgres:password@localhost:5432/greenshare
EOF
        fi
    else
        print_success "Using existing $ENV_FILE"
    fi

    # Load environment variables
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check Docker
    if ! command_exists docker; then
        missing_deps+=("docker")
    fi
    
    # Check Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi
    
    # Check Node.js
    if ! command_exists node; then
        missing_deps+=("node")
    fi
    
    # Check npm/pnpm
    if ! command_exists npm && ! command_exists pnpm; then
        missing_deps+=("npm or pnpm")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Function to check port availability
check_ports() {
    print_status "Checking port availability..."
    
    local required_ports=(3000 8080 8081 5432 6379)
    local occupied_ports=()
    
    for port in "${required_ports[@]}"; do
        if ! check_port $port; then
            occupied_ports+=($port)
        fi
    done
    
    if [ ${#occupied_ports[@]} -ne 0 ]; then
        print_warning "The following ports are already in use: ${occupied_ports[*]}"
        print_warning "Please stop the services using these ports or modify the configuration."
        
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Aborted by user"
            exit 1
        fi
    else
        print_success "All required ports are available"
    fi
}

# Function to build services
build_services() {
    print_status "Building services..."
    
    # Build Docker images
    if [ -f "$COMPOSE_FILE" ]; then
        docker-compose build
        print_success "Docker services built successfully"
    else
        print_warning "docker-compose.yml not found, skipping Docker build"
    fi
    
    # Install npm dependencies
    if [ -f "package.json" ]; then
        if command_exists pnpm; then
            print_status "Installing dependencies with pnpm..."
            pnpm install
        else
            print_status "Installing dependencies with npm..."
            npm install
        fi
        print_success "Node.js dependencies installed"
    fi
}

# Function to start infrastructure services
start_infrastructure() {
    print_status "Starting infrastructure services..."
    
    # Start database and cache
    if [ -f "$COMPOSE_FILE" ]; then
        docker-compose up -d postgres redis
        sleep 5
        
        # Wait for PostgreSQL
        print_status "Waiting for PostgreSQL..."
        local postgres_ready=false
        for i in {1..30}; do
            if docker-compose exec -T postgres pg_isready >/dev/null 2>&1; then
                postgres_ready=true
                break
            fi
            sleep 1
        done
        
        if [ "$postgres_ready" = true ]; then
            print_success "PostgreSQL is ready"
        else
            print_warning "PostgreSQL may not be ready, continuing anyway..."
        fi
        
        print_success "Infrastructure services started"
    fi
}

# Function to start application services
start_application_services() {
    print_status "Starting application services..."
    
    # Start ROFL enclave
    if [ -f "$COMPOSE_FILE" ]; then
        docker-compose up -d rofl-enclave
        wait_for_service "ROFL Enclave" 8080
    else
        print_status "Starting ROFL enclave locally..."
        if [ -f "Cargo.toml" ]; then
            cargo build --release
            nohup cargo run --bin rofl-enclave > logs/rofl.log 2>&1 &
            echo $! > .rofl.pid
            wait_for_service "ROFL Enclave" 8080
        else
            print_warning "Cargo.toml not found, skipping ROFL enclave"
        fi
    fi
    
    # Start Mock Walrus server
    if [ -f "scripts/mock-walrus-server.ts" ]; then
        print_status "Starting Mock Walrus server..."
        if command_exists pnpm; then
            nohup pnpm mock:walrus > logs/walrus.log 2>&1 &
        else
            nohup npm run mock:walrus > logs/walrus.log 2>&1 &
        fi
        echo $! > .walrus.pid
        wait_for_service "Mock Walrus" 8081
    fi
    
    print_success "Application services started"
}

# Function to start frontend
start_frontend() {
    print_status "Starting frontend..."
    
    if [ -f "package.json" ]; then
        if command_exists pnpm; then
            nohup pnpm dev > logs/frontend.log 2>&1 &
        else
            nohup npm run dev > logs/frontend.log 2>&1 &
        fi
        echo $! > .frontend.pid
        
        # Wait for frontend
        local frontend_ready=false
        for i in {1..60}; do
            if curl -sf "http://localhost:3000" >/dev/null 2>&1; then
                frontend_ready=true
                break
            fi
            sleep 1
        done
        
        if [ "$frontend_ready" = true ]; then
            print_success "Frontend is ready at http://localhost:3000"
        else
            print_warning "Frontend may not be ready, check logs/frontend.log"
        fi
    else
        print_warning "package.json not found, skipping frontend"
    fi
}

# Function to run database migrations
run_migrations() {
    print_status "Running database migrations..."
    
    if [ -f "prisma/schema.prisma" ]; then
        if command_exists pnpm; then
            pnpm prisma migrate dev
        else
            npm run prisma:migrate
        fi
        print_success "Database migrations completed"
    else
        print_status "No Prisma schema found, skipping migrations"
    fi
}

# Function to show service status
show_status() {
    print_status "Service Status:"
    echo "==========================================="
    
    # Check ROFL Enclave
    if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
        echo -e "🟢 ROFL Enclave: ${GREEN}Running${NC} (http://localhost:8080)"
    else
        echo -e "🔴 ROFL Enclave: ${RED}Not Running${NC}"
    fi
    
    # Check Mock Walrus
    if curl -sf "http://localhost:8081/health" >/dev/null 2>&1; then
        echo -e "🟢 Mock Walrus: ${GREEN}Running${NC} (http://localhost:8081)"
    else
        echo -e "🔴 Mock Walrus: ${RED}Not Running${NC}"
    fi
    
    # Check Frontend
    if curl -sf "http://localhost:3000" >/dev/null 2>&1; then
        echo -e "🟢 Frontend: ${GREEN}Running${NC} (http://localhost:3000)"
    else
        echo -e "🔴 Frontend: ${RED}Not Running${NC}"
    fi
    
    # Check Docker services
    if [ -f "$COMPOSE_FILE" ]; then
        echo ""
        echo "Docker Services:"
        docker-compose ps
    fi
    
    echo "==========================================="
}

# Function to setup logs directory
setup_logs() {
    if [ ! -d "logs" ]; then
        mkdir -p logs
        print_success "Created logs directory"
    fi
}

# Main function
main() {
    print_status "🚀 Starting GreenShare Development Environment"
    echo "================================================="
    
    # Parse command line arguments
    SKIP_BUILD=false
    SKIP_FRONTEND=false
    ONLY_INFRASTRUCTURE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-frontend)
                SKIP_FRONTEND=true
                shift
                ;;
            --infrastructure-only)
                ONLY_INFRASTRUCTURE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-build           Skip building services"
                echo "  --skip-frontend        Skip starting frontend"
                echo "  --infrastructure-only  Start only infrastructure services"
                echo "  --help, -h             Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Setup
    setup_logs
    setup_environment
    check_prerequisites
    check_ports
    
    # Build
    if [ "$SKIP_BUILD" = false ]; then
        build_services
    else
        print_status "Skipping build step"
    fi
    
    # Start services
    start_infrastructure
    
    if [ "$ONLY_INFRASTRUCTURE" = false ]; then
        start_application_services
        
        if [ "$SKIP_FRONTEND" = false ]; then
            start_frontend
        else
            print_status "Skipping frontend startup"
        fi
        
        run_migrations
    else
        print_status "Starting infrastructure services only"
    fi
    
    # Show status
    echo ""
    show_status
    
    # Final instructions
    echo ""
    print_success "🎉 GreenShare development environment is ready!"
    echo ""
    echo "Quick Links:"
    echo "  Frontend:      http://localhost:3000"
    echo "  ROFL API:      http://localhost:8080"
    echo "  Mock Walrus:   http://localhost:8081"
    echo "  API Docs:      http://localhost:8080/docs"
    echo ""
    echo "Useful Commands:"
    echo "  View logs:     tail -f logs/*.log"
    echo "  Stop all:      ./scripts/devnet-down.sh"
    echo "  Restart:       ./scripts/devnet-restart.sh"
    echo ""
    echo "Press Ctrl+C to stop all services"
    
    # Keep script running to handle Ctrl+C
    trap 'print_status "Shutting down..."; ./scripts/devnet-down.sh; exit 0' INT
    
    # Monitor services
    while true; do
        sleep 10
        # Check if any service died and restart if needed
        if [ ! -f .rofl.pid ] || ! kill -0 $(cat .rofl.pid) 2>/dev/null; then
            print_warning "ROFL enclave died, check logs/rofl.log"
        fi
        if [ ! -f .walrus.pid ] || ! kill -0 $(cat .walrus.pid) 2>/dev/null; then
            print_warning "Mock Walrus died, check logs/walrus.log"
        fi
        if [ ! -f .frontend.pid ] || ! kill -0 $(cat .frontend.pid) 2>/dev/null; then
            print_warning "Frontend died, check logs/frontend.log"
        fi
    done
}

# Run main function
main "$@"