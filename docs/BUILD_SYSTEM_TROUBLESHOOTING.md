# Unified Build System - Troubleshooting Guide

Common issues and solutions for the YAML-based Docker image build system.

---

## Quick Diagnostics

### Check Dependencies
```bash
cd /srv/test-plans/transport  # or perf, or hole-punch
./run_tests.sh --check-deps
```

Should show:
```
✓ bash 5.2
✓ docker 29.1.2
✓ yq 4.48.1
✓ wget is installed
✓ ssh is installed
✓ scp is installed
```

### Test Build Script Directly
```bash
# Create test YAML
cat > /tmp/test-build.yaml <<EOF
imageName: test-debug
sourceType: local
cacheDir: /srv/cache
forceRebuild: true
outputStyle: clean
local:
  path: /srv/test-plans/perf/impls/rust/v0.56
  dockerfile: Dockerfile
EOF

# Run build
./lib/build-single-image.sh /tmp/test-build.yaml
```

### Inspect YAML Files
```bash
# View generated YAML files
ls -la /srv/cache/build-yamls/

# Check a specific build configuration
cat /srv/cache/build-yamls/docker-build-rust-v0.56.yaml
```

---

## Common Issues

### Issue 1: "YAML file not found"

**Error:**
```
✗ Error: YAML file not found: /srv/cache/build-yamls/docker-build-rust-v0.56.yaml
```

**Cause:** The orchestrator script failed to create the YAML file.

**Solution:**
```bash
# Check if build-yamls directory exists
ls -la /srv/cache/build-yamls/

# Create it if missing
mkdir -p /srv/cache/build-yamls

# Re-run with debug
bash -x lib/build-images.sh "rust-v0.56" "false" 2>&1 | grep "yaml"
```

---

### Issue 2: "Unknown source type"

**Error:**
```
✗ Error: Unknown source type: <type>
  Valid types: github, local, browser
```

**Cause:** Invalid `sourceType` in YAML file.

**Solution:**
```bash
# Check the YAML file
cat /srv/cache/build-yamls/docker-build-<name>.yaml

# Verify sourceType is one of: github, local, browser
# Check impls.yaml for correct source type
yq eval '.implementations[] | select(.id == "rust-v0.56") | .source.type' impls.yaml
```

---

### Issue 3: "Base image not found" (Browser)

**Error:**
```
✗ Base image not found: transport-interop-js-v3.x
  Please build js-v3.x first
```

**Cause:** Browser implementations require base image to exist.

**Solution:**
```bash
# Build base image first
cd /srv/test-plans/transport
bash lib/build-images.sh "js-v3.x" "false"

# Then build browser image
bash lib/build-images.sh "chromium-js-v3.x" "false"
```

**Build Order:**
1. Base implementation (js-v3.x)
2. Browser variants (chromium-js-v3.x, firefox-js-v3.x, etc.)

---

### Issue 4: "Failed to download snapshot"

**Error:**
```
  → [MISS] Downloading snapshot...
✗ Failed to download snapshot
```

**Causes:**
1. Network connectivity issues
2. Invalid GitHub URL
3. Commit hash not found in repository
4. wget not installed

**Solutions:**
```bash
# Test wget
wget --version

# Test GitHub connectivity
wget -O /tmp/test.zip https://github.com/libp2p/rust-libp2p/archive/70082df7.zip

# Verify commit exists
# Go to: https://github.com/libp2p/rust-libp2p/commit/70082df7

# Check impls.yaml for correct commit
yq eval '.implementations[] | select(.id == "rust-v0.56") | .source.commit' impls.yaml
```

---

### Issue 5: "Failed to extract snapshot"

**Error:**
```
→ Extracting snapshot...
✗ Failed to extract snapshot
```

**Causes:**
1. Corrupted zip file
2. Insufficient disk space
3. Permission issues

**Solutions:**
```bash
# Test unzip
unzip -l /srv/cache/snapshots/<commit>.zip

# Remove corrupted snapshot (will re-download)
rm /srv/cache/snapshots/<commit>.zip

# Check disk space
df -h /srv/cache

# Check permissions
ls -la /srv/cache/snapshots/
```

---

### Issue 6: "Docker build failed"

**Error:**
```
→ Building Docker image...
[docker output]
✗ Docker build failed
```

**Causes:** Dockerfile errors, missing dependencies, etc.

**Debug Steps:**
```bash
# 1. Check the YAML file
cat /srv/cache/build-yamls/docker-build-<name>.yaml

# 2. Run build manually for detailed output
./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-<name>.yaml

# 3. Try docker build directly
cd /path/to/source
docker build -f Dockerfile -t test-debug .

# 4. Check Dockerfile
cat /path/to/source/Dockerfile
```

---

### Issue 7: Remote Build Fails

**Error:**
```
→ Building on remote: user@host
  → Copying build parameters...
✗ Remote build failed for rust-v0.56
```

**Causes:**
1. SSH authentication failure
2. Remote server unreachable
3. Docker not installed on remote
4. Permission issues

**Solutions:**
```bash
# Test SSH connectivity
ssh user@hostname

# Test with key authentication
ssh -i ~/.ssh/id_rsa user@hostname

# Verify Docker on remote
ssh user@hostname "docker --version"

# Test remote connectivity function
cd /srv/test-plans/perf
source lib/lib-perf.sh
source ../lib/lib-remote-execution.sh

test_all_remote_servers "impls.yaml" \
    "get_server_config" \
    "get_remote_hostname" \
    "get_remote_username" \
    "is_remote_server"
```

**Expected output:**
```
╲ Testing remote server connectivity...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Testing perf-server-1 (testuser@perf1.example.com)... ✓ Connected

╲ ✓ All remote servers are reachable
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
```

---

### Issue 8: "Path not found" (Local Source)

**Error:**
```
✗ Local path not found: impls/rust/v0.56
```

**Causes:**
1. Incorrect path in impls.yaml
2. Working directory is wrong
3. Implementation not yet created

**Solutions:**
```bash
# Check impls.yaml
yq eval '.implementations[] | select(.id == "rust-v0.56") | .source.path' impls.yaml

# Verify path exists
ls -la impls/rust/v0.56/

# Check current directory
pwd

# Use absolute path in YAML if needed
```

---

### Issue 9: Output Not Streaming in Real-Time (Remote)

**Symptom:** Remote build output appears all at once at the end instead of streaming.

**Cause:** Missing `-tt` flag in SSH command.

**Solution:**
Verify `lib/lib-remote-execution.sh` uses:
```bash
ssh -tt "${username}@${hostname}" "bash $remote_script $remote_yaml" 2>&1
#    ^^
#    This is critical for output streaming
```

---

### Issue 10: "yq: command not found"

**Error:**
```
build-images.sh: line 42: yq: command not found
```

**Solution:**
```bash
# Install yq
sudo wget -qO /usr/local/bin/yq \
    https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Verify
yq --version
```

---

## Debug Mode

### Enable Verbose Output

**For orchestrator:**
```bash
bash -x lib/build-images.sh "rust-v0.56" "false" 2>&1 | less
```

**For executor:**
```bash
bash -x ./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-rust-v0.56.yaml
```

### Inspect Generated YAML

```bash
# View all generated YAML files
ls -lh /srv/cache/build-yamls/

# Examine specific file
cat /srv/cache/build-yamls/docker-build-rust-v0.56.yaml

# Validate YAML syntax
yq eval '.' /srv/cache/build-yamls/docker-build-rust-v0.56.yaml
```

### Check Docker Images

```bash
# List all test images
docker images | grep -E "(transport-interop|perf-|hole-punch)"

# Inspect specific image
docker image inspect transport-interop-rust-v0.56

# Check image layers
docker history transport-interop-rust-v0.56
```

---

## Performance Issues

### Slow GitHub Downloads

**Symptom:** Snapshot downloads are slow.

**Solutions:**
```bash
# Use GitHub token for higher rate limits
export GITHUB_TOKEN=ghp_...

# Pre-download snapshots
cd /srv/cache/snapshots
wget https://github.com/libp2p/rust-libp2p/archive/<commit>.zip

# Use mirror or local git clone (advanced)
```

### Disk Space Issues

**Check space:**
```bash
df -h /srv/cache
du -sh /srv/cache/snapshots
du -sh /srv/cache/build-yamls
```

**Cleanup:**
```bash
# Remove old snapshots
find /srv/cache/snapshots -mtime +30 -delete

# Remove YAML files (regenerated on next run)
rm -rf /srv/cache/build-yamls/*

# Prune Docker images
docker image prune -a
```

---

## Getting Help

### Check Logs

**Build logs are in:**
- Console output (shown in real-time)
- YAML files: `/srv/cache/build-yamls/`
- Docker build context (temporary)

### Report Issues

Include:
1. YAML file contents
2. Full error output
3. `docker version` output
4. `yq --version` output
5. Source type (github/local/browser)
6. Build location (local/remote)

### Useful Commands

```bash
# Test all dependencies
./run_tests.sh --check-deps

# List all implementations
./run_tests.sh --list-impls

# Test connectivity (perf only)
source lib/lib-perf.sh
source ../lib/lib-remote-execution.sh
test_all_remote_servers impls.yaml ...

# Clean rebuild
bash lib/build-images.sh "" "true"  # Rebuild all

# Debug single image
./lib/build-single-image.sh <yaml-file>
```

---

## See Also

- `/srv/test-plans/docs/DOCKER_BUILD_YAML_SCHEMA.md` - Complete YAML reference
- `/srv/test-plans/tests/test-unified-build-system.sh` - Integration tests
