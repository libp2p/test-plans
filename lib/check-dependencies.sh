#!/bin/bash
# Check for required dependencies and their versions

set -euo pipefail

has_error=false

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_this_script_dir/lib-output-formatting.sh"
fi

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
    if [ -z "${ver2[i]}" ]; then
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
  if [ $(version_compare "$bash_version" "4.0") -ge 0 ]; then
    print_success "bash $bash_version (minimum: 4.0)"
  else
    print_error "bash $bash_version is too old (minimum: 4.0)"
    has_error=true
  fi
else
  print_error "bash not detected"
  has_error=true
fi

# Check docker
if command -v docker &> /dev/null; then
  docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ $(version_compare "$docker_version" "20.10.0") -ge 0 ]; then
    print_success "docker $docker_version (minimum: 20.10.0)"
  else
    print_error "docker $docker_version is too old (minimum: 20.10.0)"
    has_error=true
  fi

  indent
  # Check if Docker daemon is running
  if docker info &> /dev/null; then
    print_success "Docker daemon is running"
  else
    print_error "Docker daemon is not running"
    has_error=true
  fi
  unindent
else
  print_error "docker is not installed"
  has_error=true
fi

# Check docker compose (prefer new 'docker compose' over old 'docker-compose')
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null; then
  # New docker compose plugin
  compose_version=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  print_success "docker compose $compose_version (using 'docker compose')"
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  # Old standalone docker-compose
  compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  print_success "docker-compose $compose_version (using 'docker-compose')"
  DOCKER_COMPOSE_CMD="docker-compose"
else
  print_error "docker compose is not installed"
  indent
  print_message "Install: docker compose plugin (recommended) or standalone docker-compose"
  unindent
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
    if [ $(version_compare "$yq_version" "4.0.0") -ge 0 ]; then
      print_success "yq $yq_version (minimum: 4.0.0)"
    else
      print_error "yq $yq_version is too old (minimum: 4.0.0)"
      has_error=true
    fi
  else
    print_success "yq is installed"
  fi
else
  print_error "yq is not installed"
  indent
  print_message "Install: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
  print_message "         sudo chmod +x /usr/local/bin/yq"
  unindent
  has_error=true
fi

# Check wget
if command -v wget &> /dev/null; then
  print_success "wget is installed"
else
  print_error "wget is not installed"
  has_error=true
fi

# Check zip
if command -v zip &> /dev/null; then
  print_success "zip is installed"
else
  print_error "zip is not installed"
  has_error=true
fi

# Check unzip
if command -v unzip &> /dev/null; then
  print_success "unzip is installed"
else
  print_error "unzip is not installed"
  has_error=true
fi

# Check cut
if command -v cut &> /dev/null; then
  print_success "cut is installed"
else
  print_error "cut is not installed"
  has_error=true
fi

# Check awk
if command -v awk &> /dev/null; then
  print_success "awk is installed"
else
  print_error "awk is not installed"
  has_error=true
fi

# Check sha256sum
if command -v sha256sum &> /dev/null; then
  print_success "sha256sum is installed"
else
  print_error "sha256sum is not installed"
  has_error=true
fi

# Check ssh (required for remote builds)
if command -v ssh &> /dev/null; then
  print_success "ssh is installed"
else
  print_error "ssh is not installed (required for remote builds)"
  has_error=true
fi

# Check scp (required for remote builds)
if command -v scp &> /dev/null; then
  print_success "scp is installed"
else
  print_error "scp is not installed (required for remote builds)"
  has_error=true
fi

# Check gnuplot (optional - for box plot generation)
if command -v gnuplot &> /dev/null; then
  gnuplot_version=$(gnuplot --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
  print_success "gnuplot $gnuplot_version (for box plot generation)"
else
  print_error "gnuplot not found (box plots will be skipped)"
  indent
  print_message "Install: apt-get install gnuplot"
  unindent
fi

echo ""

if [ "$has_error" == "true" ]; then
  print_error "Some dependencies are missing or outdated"
  exit 1
else
  print_success "All dependencies are satisfied"
fi
