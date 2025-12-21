# Perf Tests Quick Start Guide

## Prerequisites

- **Docker** 20.10+ ([Installation](https://docs.docker.com/engine/install/))
- **bash** 4.0+
- **yq** 4.0+ ([Installation](https://github.com/mikefarah/yq#install))
- **ssh** (for remote servers)
- **(Optional) pandoc** (for HTML dashboard generation)

## Setup

### Option 1: Local Testing (Single Machine)

All tests run in Docker containers on a single machine. Suitable for development and quick testing.

#### 1. Clone repository

```bash
git clone https://github.com/libp2p/test-plans.git
cd test-plans/perf
```

#### 2. Verify prerequisites

```bash
bash ../scripts/check-dependencies.sh docker yq
```

#### 3. Run tests

```bash
# Run all implementations with default settings
./run_tests.sh

# Run specific implementation
./run_tests.sh --test-select "go-libp2p"

# Quick test (reduced iterations)
./run_tests.sh --test-select "go-libp2p" --iterations 3
```

---

### Option 2: Remote Server Testing (Two Machines)

Use a remote machine as the server for realistic network conditions and better performance isolation.

**Architecture:**
- **Computer 1 (Test Runner):** Runs clients and orchestrates tests
- **Computer 2 (Server):** Runs perf servers

#### Computer 1 (Test Runner) Setup

**1. Generate SSH key**

```bash
# Generate dedicated key for perf testing
ssh-keygen -t ed25519 -f ~/.ssh/perf_server -N ""
```

This creates:
- `~/.ssh/perf_server` (private key)
- `~/.ssh/perf_server.pub` (public key)

**2. Copy public key to Computer 2**

```bash
# Replace with your server's username and IP/hostname
ssh-copy-id -i ~/.ssh/perf_server.pub perfuser@192.168.1.100
```

You'll be prompted for the password once. After this, SSH will use key-based authentication.

**3. Test SSH connection**

```bash
# Should connect without password prompt
ssh -i ~/.ssh/perf_server perfuser@192.168.1.100 "echo 'Connection successful'"
```

**4. Add to SSH config** (recommended)

This makes SSH commands simpler:

```bash
cat >> ~/.ssh/config <<EOF
Host perf-server
  HostName 192.168.1.100
  User perfuser
  IdentityFile ~/.ssh/perf_server
  StrictHostKeyChecking no
EOF
```

Now you can use `ssh perf-server` instead of the full command.

**5. Add key to SSH agent** (optional, for GitHub Actions)

```bash
eval $(ssh-agent)
ssh-add ~/.ssh/perf_server
```

#### Computer 2 (Server) Setup

**1. Install Docker**

```bash
# Official Docker installation script
curl -fsSL https://get.docker.com | sh

# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker

# Verify Docker works without sudo
docker run hello-world
```

**2. Verify Docker permissions**

```bash
# This should work without sudo
docker ps
```

If you get a permission error, ensure you logged out and back in after step 1.

**3. Configure firewall** (if enabled)

```bash
# Check if firewall is active
sudo ufw status

# If active, allow perf protocol port
sudo ufw allow 4001/tcp comment 'libp2p perf protocol'

# Ensure SSH is allowed
sudo ufw allow 22/tcp comment 'SSH'

# Reload firewall
sudo ufw reload
```

**4. Test from Computer 1**

From Computer 1, verify you can run Docker commands on Computer 2:

```bash
ssh perfuser@192.168.1.100 "docker run --rm hello-world"
```

#### Configure impls.yaml for Remote Server

Edit `perf/impls.yaml` on Computer 1:

```yaml
servers:
  # Add your remote server configuration
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"  # Your Computer 2 IP/hostname
    username: "perfuser"        # Your Computer 2 SSH username
    description: "Remote Debian 13 server"

implementations:
  - id: rust-libp2p-v0.53
    name: "rust-libp2p v0.53"
    # ... other config ...
    server: remote-1  # Use remote server for this implementation
```

**Tips:**
- Use static IP or DNS name for consistency
- You can define multiple remote servers
- Mix local and remote servers for different implementations

#### Run Tests with Remote Server

```bash
# Test a single implementation on remote server
./run_tests.sh --test-select "rust-libp2p"

# Run all implementations
./run_tests.sh

# Create snapshot for reproducibility
./run_tests.sh --snapshot
```

---

## Common Usage Patterns

### Basic Commands

```bash
# Run all tests with default settings (10 iterations)
./run_tests.sh

# Run specific implementation
./run_tests.sh --test-select "go-libp2p-v0.32"

# Run multiple implementations (pipe-separated)
./run_tests.sh --test-select "go-libp2p|rust-libp2p"

# Use test aliases (defined in impls.yaml)
./run_tests.sh --test-select "~libp2p"    # All libp2p implementations
./run_tests.sh --test-select "~baseline"  # Baseline implementations only

# Exclude implementations
./run_tests.sh --test-ignore "js-libp2p"

# Combine selection and exclusion
./run_tests.sh --test-select "~libp2p" --test-ignore "js-libp2p"
```

### Performance Tuning

```bash
# Quick test (fewer iterations)
./run_tests.sh --iterations 3

# Custom data sizes
./run_tests.sh --upload-bytes 5368709120 --download-bytes 5368709120  # 5GB each

# Skip confirmation prompt
./run_tests.sh --yes

# Enable debug output
./run_tests.sh --debug
```

### Snapshot Creation

```bash
# Create snapshot for reproducibility
./run_tests.sh --snapshot

# Snapshot includes:
# - All test results
# - Docker images
# - Test configuration
# - Baseline results (ping, iperf)
```

### Force Rebuilds

```bash
# Force test matrix regeneration
./run_tests.sh --force-matrix-rebuild

# Force Docker image rebuilds
./run_tests.sh --force-image-rebuild

# Force both
./run_tests.sh --force-matrix-rebuild --force-image-rebuild
```

---

## View Results

Results are saved to `/srv/cache/test-runs/perf-HHMMSS-DD-MM-YYYY/`:

```bash
# Find latest test run
ls -td /srv/cache/test-runs/perf-* | head -1

# View results
TEST_DIR=$(ls -td /srv/cache/test-runs/perf-* | head -1)
cat $TEST_DIR/results.yaml    # Structured data
cat $TEST_DIR/results.md      # Markdown dashboard
open $TEST_DIR/results.html   # HTML dashboard (if pandoc installed)
```

### Results Structure

```
perf-HHMMSS-DD-MM-YYYY/
├── results.yaml           # Structured results (YAML)
├── results.md             # Markdown dashboard
├── results.html           # HTML dashboard
├── test-matrix.yaml       # Generated test matrix
├── logs/                  # Individual test logs
│   ├── go-libp2p-v0.32-tcp-upload.log
│   ├── rust-libp2p-v0.53-quic-download.log
│   └── ...
├── baseline/              # Baseline test results
│   ├── ping-results.txt
│   ├── ping-stats.yaml
│   ├── iperf-results.json
│   └── iperf-stats.yaml
└── results/               # Individual test result files
    ├── go-libp2p-v0.32-tcp-upload.yaml
    ├── rust-libp2p-v0.53-quic-download.yaml
    └── ...
```

---

## Troubleshooting

### SSH Connection Issues

**Problem:** `ssh: connect to host 192.168.1.100 port 22: Connection refused`

**Solution:**
```bash
# Check if SSH server is running on Computer 2
systemctl status ssh

# Start SSH server if not running
sudo systemctl start ssh
sudo systemctl enable ssh
```

---

**Problem:** `Permission denied (publickey)`

**Solution:**
```bash
# Verify SSH key permissions on Computer 1
chmod 600 ~/.ssh/perf_server
chmod 644 ~/.ssh/perf_server.pub

# Verify authorized_keys on Computer 2
ssh perfuser@192.168.1.100 "cat ~/.ssh/authorized_keys"

# Re-copy public key if needed
ssh-copy-id -i ~/.ssh/perf_server.pub perfuser@192.168.1.100

# Test with verbose output
ssh -vvv -i ~/.ssh/perf_server perfuser@192.168.1.100
```

---

**Problem:** `Host key verification failed`

**Solution:**
```bash
# Remove old host key
ssh-keygen -R 192.168.1.100

# Accept new host key
ssh-keyscan -H 192.168.1.100 >> ~/.ssh/known_hosts

# Or disable host key checking (less secure)
ssh -o StrictHostKeyChecking=no perfuser@192.168.1.100
```

---

### Docker Issues

**Problem:** `docker: permission denied` on Computer 2

**Solution:**
```bash
# On Computer 2: Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker

# Verify
docker ps
```

---

**Problem:** `Cannot connect to the Docker daemon`

**Solution:**
```bash
# Check if Docker is running
systemctl status docker

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker
```

---

### Network Issues

**Problem:** `Error: Cannot reach server at 192.168.1.100:4001`

**Solution:**
```bash
# On Computer 2: Check if port is open
sudo lsof -i :4001

# Check firewall
sudo ufw status

# Allow port 4001
sudo ufw allow 4001/tcp
```

---

**Problem:** Tests extremely slow or timing out

**Solution:**
```bash
# Test baseline network performance
ping -c 100 192.168.1.100

# Run iperf3 manually
# On Computer 2:
iperf3 -s

# On Computer 1:
iperf3 -c 192.168.1.100 -t 10

# Check for network issues, switch ports, or use wired connection
```

---

### Test Failures

**Problem:** Tests failing with "server not responding"

**Solution:**
```bash
# Check server logs
TEST_DIR=$(ls -td /srv/cache/test-runs/perf-* | head -1)
cat $TEST_DIR/logs/failing-test.log

# Verify Docker image built successfully
docker images | grep perf-

# Try rebuilding images
./run_tests.sh --force-image-rebuild --test-select "failing-impl"

# Run with debug output
./run_tests.sh --debug --test-select "failing-impl"
```

---

**Problem:** `Error: Could not find test pass directory`

**Solution:**
```bash
# Ensure /srv/cache directory exists and is writable
mkdir -p /srv/cache/test-runs
chmod 755 /srv/cache

# Or use custom cache directory
export CACHE_DIR=/tmp/perf-cache
./run_tests.sh
```

---

### Dependencies

**Problem:** `Command not found: yq`

**Solution:**
```bash
# Install yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Verify
yq --version
```

---

## Best Practices

### For Accurate Results

1. **Use dedicated hardware**: Avoid running other workloads during tests
2. **Stable network**: Use wired connection, avoid WiFi for production tests
3. **Multiple iterations**: Use at least 10 iterations (default) for statistical significance
4. **Warm-up**: First iteration is often slower (cache warming, JIT compilation)
5. **Consistent environment**: Same OS, kernel version, Docker version across runs
6. **Monitor resources**: Check CPU, memory, network during tests

### For Development

1. **Quick iterations**: Use `--iterations 1` or `--iterations 3` for faster feedback
2. **Test selection**: Focus on specific implementations with `--test-select`
3. **Debug mode**: Use `--debug` for verbose output
4. **Local servers**: Use local servers for development, remote for final benchmarks

### For CI/CD

1. **Snapshots**: Enable `--snapshot` to archive complete test environment
2. **Artifacts**: Upload results.yaml, results.md to GitHub Actions artifacts
3. **SSH keys**: Store SSH private key in GitHub Secrets
4. **Self-hosted runners**: Required for consistent hardware and network

---

## Next Steps

- See [README.md](README.md) for detailed documentation
- Check `impls.yaml` for implementation configurations
- Review `scripts/` directory for available helper scripts
- Explore existing implementations in `impl/` for examples

## Getting Help

- **GitHub Issues**: https://github.com/libp2p/test-plans/issues
- **Documentation**: Check README.md and script comments
- **Examples**: Look at hole-punch and transport tests for similar patterns
