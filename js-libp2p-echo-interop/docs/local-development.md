# Local Development Guide

This guide explains how to build, test, and develop the JS-libp2p Echo Interoperability Tests locally.

## Prerequisites

Before you begin, ensure you have the following tools installed:

- **Docker** (version 20.10 or later)
- **Docker Compose** (version 1.29 or later)
- **Node.js** (version 18 or later)
- **Python 3** (version 3.9 or later)
- **Git**

### Verification

You can verify your installation by running:

```bash
docker --version
docker-compose --version
node --version
python3 --version
```

## Quick Start

1. **Clone the repository** (if not already done):
   ```bash
   git clone <repository-url>
   cd js-libp2p-echo-interop
   ```

2. **Build the Docker images**:
   ```bash
   ./scripts/build-local.sh
   ```

3. **Run all tests**:
   ```bash
   ./scripts/test-local.sh
   ```

4. **Start the test environment**:
   ```bash
   docker-compose up
   ```

## Detailed Workflow

### Building Images

The build script creates Docker images for both components:

```bash
# Build with default settings
./scripts/build-local.sh

# Build without cache (clean build)
BUILD_CACHE=false ./scripts/build-local.sh

# Build with verbose output
VERBOSE=true ./scripts/build-local.sh

# Clean up images and cache
./scripts/build-local.sh clean
```

The build process includes:
- Configuration validation
- Docker image building
- Image functionality verification
- Unit test execution
- Build report generation

### Running Tests

The test script provides several testing modes:

```bash
# Run all tests
./scripts/test-local.sh

# Run only property-based tests
./scripts/test-local.sh property

# Run only unit tests
./scripts/test-local.sh unit

# Run only integration tests
./scripts/test-local.sh integration

# Run only configuration tests
./scripts/test-local.sh config
```

#### Test Environment Variables

You can customize test execution with environment variables:

```bash
# Set test timeout (default: 300 seconds)
TEST_TIMEOUT=600 ./scripts/test-local.sh

# Enable verbose output
VERBOSE=true ./scripts/test-local.sh

# Enable parallel execution (where supported)
PARALLEL=true ./scripts/test-local.sh
```

### Manual Testing

For manual testing and development, you can start individual components:

#### Start Redis (required for coordination)

```bash
docker run -d --name echo-redis -p 6379:6379 redis:7-alpine
```

#### Start JS Echo Server

```bash
# Basic configuration
docker run --rm --name echo-server \
  --link echo-redis:redis \
  -e TRANSPORT=tcp \
  -e SECURITY=noise \
  -e MUXER=yamux \
  -e REDIS_ADDR=redis:6379 \
  js-libp2p-echo-server:latest

# With custom configuration
docker run --rm --name echo-server \
  --link echo-redis:redis \
  -e TRANSPORT=tcp \
  -e SECURITY=noise \
  -e MUXER=mplex \
  -e DEBUG=true \
  js-libp2p-echo-server:latest
```

#### Run Python Test Harness

```bash
# Run specific test
docker run --rm --name echo-client \
  --link echo-redis:redis \
  --link echo-server:server \
  -e TRANSPORT=tcp \
  -e SECURITY=noise \
  -e MUXER=yamux \
  -e REDIS_ADDR=redis:6379 \
  py-test-harness:latest python3 -m pytest src/test_echo_protocol.py -v

# Run property tests
docker run --rm --name echo-client \
  --link echo-redis:redis \
  -e TRANSPORT=tcp \
  -e SECURITY=noise \
  -e MUXER=yamux \
  py-test-harness:latest python3 -m pytest src/test_echo_properties.py -v
```

### Docker Compose Testing

For full integration testing, use Docker Compose:

```bash
# Start all services
docker-compose up

# Start with specific protocol configuration
TRANSPORT=tcp SECURITY=noise MUXER=yamux docker-compose up

# Run tests and exit
docker-compose up --abort-on-container-exit --exit-code-from py-test-harness

# View logs
docker-compose logs js-echo-server
docker-compose logs py-test-harness

# Clean up
docker-compose down --remove-orphans --volumes
```

## Development Workflow

### Making Changes

1. **Modify source code** in `images/js-echo-server/src/` or `images/py-test-harness/src/`

2. **Rebuild affected images**:
   ```bash
   # Rebuild JS server only
   cd images/js-echo-server
   docker build -t js-libp2p-echo-server:latest .
   
   # Rebuild Python client only
   cd images/py-test-harness
   docker build -t py-test-harness:latest .
   ```

3. **Run tests** to verify changes:
   ```bash
   ./scripts/test-local.sh
   ```

### Adding New Tests

#### Property-Based Tests

Add new property tests to `images/py-test-harness/src/test_echo_properties.py`:

```python
@pytest.mark.trio
@pytest.mark.property
@given(
    # Your hypothesis strategies here
)
@settings(
    max_examples=50,
    deadline=30000
)
async def test_property_your_new_property(
    # Your test parameters
):
    """**Feature: js-libp2p-echo-interop, Property X: Your Property Name**
    
    Description of what this property tests.
    
    **Validates: Requirements X.Y, Z.A**
    """
    # Your test implementation
```

#### Unit Tests

Add unit tests to appropriate test files:
- JS tests: `images/js-echo-server/src/*.test.js`
- Python tests: `images/py-test-harness/src/test_*.py`

### Configuration Testing

Test different protocol combinations:

```bash
# Test TCP + Noise + Yamux
TRANSPORT=tcp SECURITY=noise MUXER=yamux ./scripts/test-local.sh integration

# Test TCP + Noise + Mplex
TRANSPORT=tcp SECURITY=noise MUXER=mplex ./scripts/test-local.sh integration
```

### Debugging

#### View Container Logs

```bash
# View all logs
docker-compose logs

# View specific service logs
docker-compose logs js-echo-server
docker-compose logs py-test-harness
docker-compose logs redis

# Follow logs in real-time
docker-compose logs -f py-test-harness
```

#### Interactive Debugging

```bash
# Start containers in background
docker-compose up -d

# Execute commands in running containers
docker-compose exec js-echo-server node --version
docker-compose exec py-test-harness python3 -c "import trio; print('Trio available')"

# Start interactive shell
docker-compose exec py-test-harness bash
```

#### Debug Property Tests

```bash
# Run single property test with verbose output
cd images/py-test-harness
python3 -m pytest src/test_echo_properties.py::test_property_echo_data_integrity -v -s

# Run with Hypothesis debugging
python3 -m pytest src/test_echo_properties.py::test_property_echo_data_integrity -v -s --hypothesis-show-statistics
```

## Troubleshooting

### Common Issues

#### Docker Build Failures

```bash
# Clear Docker cache and rebuild
BUILD_CACHE=false ./scripts/build-local.sh

# Check Docker daemon
docker info

# Free up disk space
docker system prune -f
```

#### Test Failures

```bash
# Run tests with verbose output
VERBOSE=true ./scripts/test-local.sh

# Run specific test suite
./scripts/test-local.sh unit
./scripts/test-local.sh property

# Check configuration
./lib/validate-config.sh
```

#### Network Issues

```bash
# Reset Docker networks
docker network prune -f

# Check container connectivity
docker-compose exec py-test-harness ping redis
docker-compose exec py-test-harness ping js-echo-server
```

#### Permission Issues

```bash
# Fix script permissions
chmod +x scripts/*.sh
chmod +x lib/*.sh

# Check Docker permissions (Linux)
sudo usermod -aG docker $USER
# Then log out and back in
```

### Getting Help

1. **Check build/test reports**:
   - `build-report.json` - Build information
   - `test-report.json` - Test results

2. **Review logs**:
   - Container logs: `docker-compose logs`
   - Build logs: `./scripts/build-local.sh` with `VERBOSE=true`

3. **Validate configuration**:
   ```bash
   ./lib/validate-config.sh help
   DEBUG=true ./lib/validate-config.sh
   ```

4. **Check system resources**:
   ```bash
   docker system df
   docker stats
   ```

## Integration with Test-Plans Repository

This project is designed to integrate with the libp2p/test-plans repository structure:

### File Structure Compatibility

```
js-libp2p-echo-interop/
├── images/                 # Container images
├── lib/                   # Shared utilities
├── scripts/               # Build and test scripts
├── docs/                  # Documentation
├── docker-compose.yml     # Main compose file
├── images.yaml           # Image definitions
└── run.sh                # Main execution script
```

### Test-Plans Integration

The project follows test-plans conventions:
- **Image naming**: Consistent with other interop tests
- **Environment variables**: Standard configuration approach
- **Output format**: JSON results compatible with test-plans
- **Makefile support**: Can be integrated with test-plans Makefile

### CI/CD Integration

The local scripts are designed to work in CI environments:

```bash
# CI build
BUILD_CACHE=false VERBOSE=true ./scripts/build-local.sh

# CI test
TEST_TIMEOUT=600 VERBOSE=true ./scripts/test-local.sh

# Generate reports for CI
cat build-report.json
cat test-report.json
```

## Next Steps

After successful local development:

1. **Submit to test-plans**: Follow the test-plans contribution guidelines
2. **CI Integration**: Ensure compatibility with test-plans CI/CD
3. **Documentation**: Update test-plans documentation
4. **Monitoring**: Set up monitoring for the interop tests

For more information, see:
- [Test-Plans Repository](https://github.com/libp2p/test-plans)
- [libp2p Documentation](https://docs.libp2p.io/)
- [Docker Documentation](https://docs.docker.com/)