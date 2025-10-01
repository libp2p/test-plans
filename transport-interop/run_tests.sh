#!/bin/bash
set -eo pipefail

# Script to run the libp2p transport interoperability test suite locally
# Based on the GitHub Action in .github/actions/run-transport-interop-test/action.yml

# Record start time for overall execution timing
START_TIME=$(date +%s)

# Function to calculate and display execution time
display_execution_time() {
  # Calculate and display the total execution time
  local end_time=$(date +%s)
  local execution_time=$((end_time - START_TIME))
  local hours=$((execution_time / 3600))
  local minutes=$(( (execution_time % 3600) / 60 ))
  local seconds=$((execution_time % 60))

  # Format with leading zeros if needed
  local hours_fmt=$(printf "%02d" $hours)
  local minutes_fmt=$(printf "%02d" $minutes)
  local seconds_fmt=$(printf "%02d" $seconds)

  echo "Running all tests took: $hours_fmt:$minutes_fmt:$seconds_fmt"
}

# Function to detect CPU count on different platforms
detect_cpu_count() {
  local cpu_count=1

  # Try Linux
  if [ -f /proc/cpuinfo ]; then
    cpu_count=$(grep -c "^processor" /proc/cpuinfo)
  # Try macOS
  elif command -v sysctl >/dev/null 2>&1; then
    cpu_count=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  # Try Windows with wmic
  elif command -v wmic >/dev/null 2>&1; then
    cpu_count=$(wmic cpu get NumberOfCores 2>/dev/null | grep -v NumberOfCores | grep -v "^$" | awk '{s+=$1} END {print s}')
  # Try Windows with PowerShell
  elif command -v powershell >/dev/null 2>&1; then
    cpu_count=$(powershell -command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors" 2>/dev/null || echo 1)
  # Try POSIX portable way as last attempt
  elif command -v nproc >/dev/null 2>&1; then
    cpu_count=$(nproc 2>/dev/null || echo 1)
  fi

  # Fallback to 1 if detection failed
  if [ -z "$cpu_count" ] || [ "$cpu_count" -lt 1 ]; then
    cpu_count=1
  fi

  echo $((cpu_count + 1))
}

# Function to compare semantic versions
version_compare() {
  # $1 = version to check, $2 = minimum required version
  local IFS=.
  local i ver1=($1) ver2=($2)
  # Fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  # Compare each part of the version
  for ((i=0; i<${#ver1[@]}; i++)); do
    # Fill empty fields in ver2 with zeros
    if [[ -z ${ver2[i]} ]]; then
      ver2[i]=0
    fi
    # Return if greater, equal or less
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      echo 1; return
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      echo -1; return
    fi
  done
  echo 0
}

# Check required dependencies and their versions
check_dependencies() {
  local has_error=false

  # Required minimum versions
  local MIN_NODE_VERSION="16.0.0"
  local MIN_NPM_VERSION="7.0.0"
  local MIN_DOCKER_VERSION="20.10.0"

  # Check Node.js
  if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed or not in PATH"
    has_error=true
  else
    local node_version=$(node -v | sed 's/^v//')
    if [[ $(version_compare "$node_version" "$MIN_NODE_VERSION") -lt 0 ]]; then
      echo "Error: Node.js version $node_version is installed, but version $MIN_NODE_VERSION or higher is required"
      has_error=true
    else
      echo "✓ Node.js version $node_version (minimum: $MIN_NODE_VERSION)"
    fi
  fi

  # Check npm
  if ! command -v npm &> /dev/null; then
    echo "Error: npm is not installed or not in PATH"
    has_error=true
  else
    local npm_version=$(npm -v)
    if [[ $(version_compare "$npm_version" "$MIN_NPM_VERSION") -lt 0 ]]; then
      echo "Error: npm version $npm_version is installed, but version $MIN_NPM_VERSION or higher is required"
      has_error=true
    else
      echo "✓ npm version $npm_version (minimum: $MIN_NPM_VERSION)"
    fi
  fi

  # Check Docker
  if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    has_error=true
  else
    local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ $(version_compare "$docker_version" "$MIN_DOCKER_VERSION") -lt 0 ]]; then
      echo "Error: Docker version $docker_version is installed, but version $MIN_DOCKER_VERSION or higher is required"
      has_error=true
    else
      echo "✓ Docker version $docker_version (minimum: $MIN_DOCKER_VERSION)"
    fi

    # Check Docker Buildx
    if ! docker buildx version &> /dev/null; then
      if command -v docker-buildx &> /dev/null || docker help | grep -q buildx; then
        echo "Setting up Docker Buildx..."
        if ! docker buildx create --use &> /dev/null; then
          echo "Warning: Docker Buildx is available but could not be initialized"
        else 
          echo "✓ Docker Buildx installed successfully"
        fi
      else
        echo "Error: Docker Buildx is not available. Please install Docker with buildx support."
        has_error=true
      fi
    else
      echo "✓ Docker Buildx is installed"
    fi
  fi

  # Check git
  if ! command -v git &> /dev/null; then
    echo "Error: git is not installed or not in PATH"
    has_error=true
  else
    echo "✓ git is installed"
  fi

  # Optional: Check pandoc
  if ! command -v pandoc &> /dev/null; then
    echo "Warning: pandoc is not installed. HTML report generation will be skipped."
  else
    echo "✓ pandoc is installed (optional)"
  fi

  # Exit if any required dependency is missing or version is too low
  if [[ "$has_error" = true ]]; then
    echo "Please install the required dependencies with the minimum versions and try again."
    return 1
  fi

  echo "All required dependencies are installed with compatible versions."
  return 0
}

# Setup the local cache
setup_local_cache() {
  echo "Setting up local cache in $LOCAL_CACHE_DIR..."

  # Create cache directory if it doesn't exist
  mkdir -p "$LOCAL_CACHE_DIR"

  # Ensure the script is executable
  chmod +x "$(dirname "$0")/helpers/local-cache.js"
}

# Default values
TEST_FILTER=""
TEST_IGNORE=""
EXTRA_VERSIONS=""
WORKER_COUNT=$(detect_cpu_count)
TIMEOUT=""
USE_LOCAL_CACHE=true
LOCAL_CACHE_DIR="$HOME/.cache/libp2p-interop-cache"
S3_CACHE_BUCKET=""
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
CACHE_MODULES=true
NODE_MODULES_CACHE_DIR="$HOME/.cache/libp2p-interop-node-modules"

# Process command line arguments
usage() {
  local cpu_detect=$(detect_cpu_count)
  local actual_cpu=$((cpu_detect - 1))
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --test-filter VALUE       Filter which tests to run out of the created matrix"
  echo "  --test-ignore VALUE       Exclude tests from the created matrix that include this string in their name"
  echo "  --extra-versions VALUE    Space-separated paths to JSON files describing additional images"
  echo "  --worker-count VALUE      How many workers to use for the test (default: $cpu_detect = CPU count ($actual_cpu) + 1)"
  echo "  --timeout VALUE           How many seconds to let each test run for"
  echo "  --use-local-cache VALUE   Use local cache instead of S3 (default: true)"
  echo "  --local-cache-dir VALUE   Directory to use for local cache (default: $HOME/.cache/libp2p-interop-cache)"
  echo "  --s3-cache-bucket VALUE   Which S3 bucket to use for container layer caching"
  echo "  --aws-region VALUE        Which AWS region to use (default: us-east-1)"
  echo "  --aws-access-key VALUE    S3 Access key id for the cache"
  echo "  --aws-secret-key VALUE    S3 secret key id for the cache"
  echo "  --no-cache-modules        Disable caching of node_modules directory (default: false)"
  echo "  --node-modules-cache-dir VALUE  Directory to use for node_modules cache (default: $HOME/.cache/libp2p-interop-node-modules)"
  echo "  --check-deps              Check for required dependencies and their versions"
  echo "  --help                    Display this help message and exit"
  echo
  echo "Required dependencies:"
  echo "  - Node.js: >= 16.0.0"
  echo "  - npm: >= 7.0.0"
  echo "  - Docker: >= 20.10.0 with buildx support"
  echo "  - git"
  echo "Optional dependencies:"
  echo "  - pandoc: For HTML report generation"
}

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --test-filter)
      TEST_FILTER="$2"
      shift 2
      ;;
    --test-ignore)
      TEST_IGNORE="$2"
      shift 2
      ;;
    --extra-versions)
      EXTRA_VERSIONS="$2"
      shift 2
      ;;
    --worker-count)
      WORKER_COUNT="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --use-local-cache)
      USE_LOCAL_CACHE="$2"
      shift 2
      ;;
    --local-cache-dir)
      LOCAL_CACHE_DIR="$2"
      shift 2
      ;;
    --s3-cache-bucket)
      S3_CACHE_BUCKET="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --aws-access-key)
      AWS_ACCESS_KEY_ID="$2"
      shift 2
      ;;
    --aws-secret-key)
      AWS_SECRET_ACCESS_KEY="$2"
      shift 2
      ;;
    --no-cache-modules)
      CACHE_MODULES=false
      shift
      ;;
    --node-modules-cache-dir)
      NODE_MODULES_CACHE_DIR="$2"
      shift 2
      ;;
    --check-deps)
      check_dependencies
      exit $?
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Set working directory to the script location
cd "$(dirname "$0")"
WORK_DIR="$(pwd)"
echo "Working directory: $WORK_DIR"
echo "Using $WORKER_COUNT worker(s) for test execution"

# Check that all required dependencies are installed with compatible versions
check_dependencies
if [[ $? -ne 0 ]]; then
  echo "Dependency check failed. Please install the required dependencies and try again."
  exit 1
fi

# Create node_modules cache directory if it doesn't exist
if [ "$CACHE_MODULES" = "true" ]; then
  mkdir -p "$NODE_MODULES_CACHE_DIR"
  echo "Node modules cache directory: $NODE_MODULES_CACHE_DIR"

  # Create cache key based on package.json and package-lock.json
  CACHE_KEY=$(cat package.json package-lock.json | sha256sum | cut -d ' ' -f 1)
  NODE_MODULES_CACHE_PATH="$NODE_MODULES_CACHE_DIR/$CACHE_KEY.tar.gz"

  # Check if cache exists
  if [ -f "$NODE_MODULES_CACHE_PATH" ]; then
    echo "Restoring node_modules from cache..."
    rm -rf node_modules
    tar -xzf "$NODE_MODULES_CACHE_PATH" -C .
    echo "Node modules restored from cache."
  else
    echo "No cache found. Installing dependencies..."
    npm ci

    # Cache the node_modules directory
    echo "Caching node_modules for future use..."
    tar -czf "$NODE_MODULES_CACHE_PATH" node_modules
    echo "Node modules cached at: $NODE_MODULES_CACHE_PATH"
  fi
else
  # Install dependencies without caching
  echo "Installing dependencies (caching disabled)..."
  npm ci
fi

# Handle caching based on configuration
if [ "$USE_LOCAL_CACHE" = "true" ]; then
  echo "Using local cache directory: $LOCAL_CACHE_DIR"
  setup_local_cache

  # Load cache
  echo "Loading from local cache..."
  export LOCAL_CACHE_DIR="$LOCAL_CACHE_DIR"
  node "$(dirname "$0")/helpers/local-cache.js" load

  # Assert Git tree is clean
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Git tree is dirty. This means that building an impl generated something that should probably be .gitignore'd"
    git status
    exit 1
  fi

  # Push updated cache
  echo "Pushing to local cache..."
  node "$(dirname "$0")/helpers/local-cache.js" push
else
  # Use S3 cache if credentials are provided
  PUSH_CACHE=false
  if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" && -n "$S3_CACHE_BUCKET" ]]; then
    echo "Loading cache from S3..."
    PUSH_CACHE=true
    export AWS_BUCKET="$S3_CACHE_BUCKET"
    export AWS_REGION="$AWS_REGION"
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    npm run cache -- load

    # Assert Git tree is clean
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Git tree is dirty. This means that building an impl generated something that should probably be .gitignore'd"
      git status
      exit 1
    fi

    # Push cache if credentials are provided
    if [[ "$PUSH_CACHE" = true ]]; then
      echo "Pushing cache to S3..."
      npm run cache -- push
    fi
  else
    echo "No S3 credentials provided and local cache disabled. Skipping cache operations."
  fi
fi

# Set environment variables for the test
export WORKER_COUNT="$WORKER_COUNT"
export EXTRA_VERSION="$EXTRA_VERSIONS"
export NAME_FILTER="$TEST_FILTER"
export NAME_IGNORE="$TEST_IGNORE"
[[ -n "$TIMEOUT" ]] && export TIMEOUT="$TIMEOUT"

# Run the test
echo "Running tests..."
npm run test -- --extra-version="$EXTRA_VERSION" --name-filter="$NAME_FILTER" --name-ignore="$NAME_IGNORE"

# Print and render results
echo "Test results:"
cat results.csv

echo "Rendering results to dashboard.md..."
npm run renderResults > ./dashboard.md

# Convert markdown to HTML
echo "Converting markdown to HTML..."
if command -v pandoc &> /dev/null; then
  pandoc -f markdown -t html -s -o dashboard.html dashboard.md
  echo "HTML report generated at: $WORK_DIR/dashboard.html"
else
  echo "Warning: pandoc is not installed. Cannot convert markdown to HTML."
  echo "To install pandoc, run: apt-get install pandoc (Ubuntu/Debian) or brew install pandoc (macOS)"
  echo "Markdown report available at: $WORK_DIR/dashboard.md"
fi

# Check if the tests failed
if grep -q ":red_circle:" ./dashboard.md; then
  echo "Some tests failed. See results for details."
  result_code=1
else
  echo "All tests passed!"
  result_code=0
fi

# Display execution time
display_execution_time

exit $result_code
