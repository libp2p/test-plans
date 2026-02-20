#!/bin/bash

# Script to run gossipsub interop tests using Docker
# This script handles the Docker setup and provides easy access to the Shadow simulator

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if we're on macOS and warn about Shadow compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    print_warning "Running on macOS. Shadow simulator only supports Linux, so we're using Docker."
fi

# Build the Docker image if it doesn't exist or if --build is passed
if [[ "$1" == "--build" ]] || ! docker images | grep -q gossipsub-interop; then
    print_info "Building Docker image for gossipsub interop tests..."
    docker-compose build
    shift # Remove --build from arguments
fi

# If no arguments provided, show help
if [ $# -eq 0 ]; then
    print_info "Running gossipsub interop tests with Docker"
    print_info "Usage: $0 [--build] [gossipsub-interop-arguments]"
    print_info "Examples:"
    print_info "  $0 --help                                    # Show help"
    print_info "  $0 --node_count 100 --composition rust-and-go --scenario subnet-blob-msg"
    print_info "  $0 --build --node_count 50 --composition all-go --scenario simple-fanout"
    echo
    print_info "Running help command..."
    docker-compose run --rm gossipsub-interop --help
    exit 0
fi

# Run the gossipsub interop tests with the provided arguments
print_info "Running gossipsub interop tests with arguments: $*"
docker-compose run --rm gossipsub-interop "$@"

# Check if output directory was created and show results
if [ -d "*.data" ]; then
    print_info "Test completed! Results are available in the .data directory"
    print_info "You can view the plots and analysis in the plots/ subdirectory"
else
    print_warning "No output directory found. The test may not have completed successfully."
fi
