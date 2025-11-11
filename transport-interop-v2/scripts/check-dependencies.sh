#!/bin/bash
# Check for required dependencies and their versions

set -euo pipefail

echo "Checking dependencies..."
echo ""

has_error=false

# Function to compare semantic versions
version_compare() {
    # $1 = version to check, $2 = minimum required version
    local IFS=.
    local i ver1=($1) ver2=($2)
    # Fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    # Compare each part
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            echo 1; return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            echo -1; return
        fi
    done
    echo 0
}

# Check bash
if [ -n "${BASH_VERSION:-}" ]; then
    bash_version="${BASH_VERSION%.*}"
    if [[ $(version_compare "$bash_version" "4.0") -ge 0 ]]; then
        echo "✓ bash $bash_version (minimum: 4.0)"
    else
        echo "✗ bash $bash_version is too old (minimum: 4.0)"
        has_error=true
    fi
else
    echo "✗ bash not detected"
    has_error=true
fi

# Check git
if command -v git &> /dev/null; then
    git_version=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ $(version_compare "$git_version" "2.0.0") -ge 0 ]]; then
        echo "✓ git $git_version (minimum: 2.0.0)"
    else
        echo "✗ git $git_version is too old (minimum: 2.0.0)"
        has_error=true
    fi
else
    echo "✗ git is not installed"
    has_error=true
fi

# Check docker
if command -v docker &> /dev/null; then
    docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ $(version_compare "$docker_version" "20.10.0") -ge 0 ]]; then
        echo "✓ docker $docker_version (minimum: 20.10.0)"
    else
        echo "✗ docker $docker_version is too old (minimum: 20.10.0)"
        has_error=true
    fi

    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        echo "  ✓ Docker daemon is running"
    else
        echo "  ✗ Docker daemon is not running"
        has_error=true
    fi
else
    echo "✗ docker is not installed"
    has_error=true
fi

# Check docker compose (prefer new 'docker compose' over old 'docker-compose')
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    # New docker compose plugin
    compose_version=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "✓ docker compose $compose_version (using 'docker compose')"
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    # Old standalone docker-compose
    compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "✓ docker-compose $compose_version (using 'docker-compose')"
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "✗ docker compose is not installed"
    echo "  Install: docker compose plugin (recommended) or standalone docker-compose"
    has_error=true
fi

# Export the docker compose command for use by other scripts
if [ -n "$DOCKER_COMPOSE_CMD" ]; then
    echo "$DOCKER_COMPOSE_CMD" > /tmp/docker-compose-cmd.txt
fi

# Check yq
if command -v yq &> /dev/null; then
    yq_version=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$yq_version" ]; then
        if [[ $(version_compare "$yq_version" "4.0.0") -ge 0 ]]; then
            echo "✓ yq $yq_version (minimum: 4.0.0)"
        else
            echo "✗ yq $yq_version is too old (minimum: 4.0.0)"
            has_error=true
        fi
    else
        echo "✓ yq is installed"
    fi
else
    echo "✗ yq is not installed"
    echo "  Install: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    echo "           sudo chmod +x /usr/local/bin/yq"
    has_error=true
fi

# Check wget
if command -v wget &> /dev/null; then
    echo "✓ wget is installed"
else
    echo "✗ wget is not installed"
    has_error=true
fi

# Check unzip
if command -v unzip &> /dev/null; then
    echo "✓ unzip is installed"
else
    echo "✗ unzip is not installed"
    has_error=true
fi

echo ""

if [ "$has_error" = true ]; then
    echo "╲ ✗ Some dependencies are missing or outdated"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    exit 1
else
    echo "╲ ✓ All dependencies are satisfied"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
fi
