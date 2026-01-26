FROM python:3.11-slim

# Install system dependencies required for py-libp2p and health checks
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    git \
    redis-tools \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies with fallback handling
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt || \
    (echo "Warning: Some dependencies failed to install, continuing with available packages" && \
     pip install --no-cache-dir pytest pytest-trio pytest-asyncio trio redis pydantic structlog hypothesis)

# Copy source code
COPY src/ ./src/
COPY pytest.ini .

# Create lib directory and copy health check script
RUN mkdir -p ./lib
COPY health-check.sh ./lib/health-check.sh

# Set environment variables
ENV PYTHONPATH=/app/src
ENV PYTHONUNBUFFERED=1

# Environment variables for libp2p configuration
ENV TRANSPORT=tcp
ENV SECURITY=noise
ENV MUXER=yamux
ENV IS_DIALER=true
ENV REDIS_ADDR=redis:6379
ENV TEST_TIMEOUT=30

# Create a startup script that handles JSON output formatting
RUN cat > /app/run_tests.py << 'EOF'
#!/usr/bin/env python3
"""Test runner with JSON output formatting for containerized execution."""

import sys
import json
import os
import subprocess
import time
from datetime import datetime
from typing import Dict, List, Any

def run_tests_with_json_output():
    """Run tests and format output as JSON for container consumption."""
    
    # Environment configuration
    env_config = {
        "TRANSPORT": os.getenv("TRANSPORT", "tcp"),
        "SECURITY": os.getenv("SECURITY", "noise"), 
        "MUXER": os.getenv("MUXER", "yamux"),
        "IS_DIALER": os.getenv("IS_DIALER", "true"),
        "REDIS_ADDR": os.getenv("REDIS_ADDR", "redis:6379"),
        "TEST_TIMEOUT": os.getenv("TEST_TIMEOUT", "30")
    }
    
    # Log configuration to stderr
    print(f"Starting Python Test Harness with configuration:", file=sys.stderr)
    for key, value in env_config.items():
        print(f"  {key}={value}", file=sys.stderr)
    print("", file=sys.stderr)
    
    start_time = time.time()
    
    try:
        # Run pytest with JSON output, targeting only test files
        result = subprocess.run([
            sys.executable, "-m", "pytest",
            "-v",
            "--tb=short", 
            "--strict-markers",
            "--strict-config",
            "src/test_*.py",  # Only run actual test files
            "-p", "no:warnings"
        ], capture_output=True, text=True, timeout=300)
        
        duration = time.time() - start_time
        
        # Parse pytest output for results
        test_results = parse_pytest_output(result.stdout, result.stderr, env_config)
        
        # Create test suite result
        suite_result = {
            "results": test_results,
            "summary": {
                "total": len(test_results),
                "passed": len([r for r in test_results if r["status"] == "passed"]),
                "failed": len([r for r in test_results if r["status"] == "failed"]),
                "skipped": len([r for r in test_results if r["status"] == "skipped"])
            },
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "environment": env_config,
            "duration": duration,
            "exit_code": result.returncode
        }
        
        # Output JSON to stdout
        print(json.dumps(suite_result, indent=2))
        
        # Log summary to stderr
        print(f"Test execution completed in {duration:.2f}s", file=sys.stderr)
        print(f"Results: {suite_result['summary']}", file=sys.stderr)
        
        return result.returncode
        
    except subprocess.TimeoutExpired:
        error_result = {
            "results": [],
            "summary": {"total": 0, "passed": 0, "failed": 1, "skipped": 0},
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "environment": env_config,
            "duration": time.time() - start_time,
            "exit_code": 124,
            "error": "Test execution timed out after 300 seconds"
        }
        print(json.dumps(error_result, indent=2))
        print("ERROR: Test execution timed out", file=sys.stderr)
        return 124
        
    except Exception as e:
        error_result = {
            "results": [],
            "summary": {"total": 0, "passed": 0, "failed": 1, "skipped": 0},
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "environment": env_config,
            "duration": time.time() - start_time,
            "exit_code": 1,
            "error": str(e)
        }
        print(json.dumps(error_result, indent=2))
        print(f"ERROR: Test execution failed: {e}", file=sys.stderr)
        return 1

def parse_pytest_output(stdout: str, stderr: str, env_config: Dict[str, str]) -> List[Dict[str, Any]]:
    """Parse pytest output to extract test results."""
    results = []
    
    # Simple parsing - in a real implementation, you might use pytest-json-report plugin
    lines = stdout.split('\n')
    
    for line in lines:
        if '::' in line and ('PASSED' in line or 'FAILED' in line or 'SKIPPED' in line):
            parts = line.split()
            if len(parts) >= 2:
                test_name = parts[0].replace('::', '_').replace('/', '_')
                status_part = parts[-1]
                
                if 'PASSED' in status_part:
                    status = "passed"
                elif 'FAILED' in status_part:
                    status = "failed"
                elif 'SKIPPED' in status_part:
                    status = "skipped"
                else:
                    continue
                
                result = {
                    "test_name": test_name,
                    "status": status,
                    "duration": 0.0,  # pytest output doesn't easily provide individual durations
                    "implementation": "py-libp2p",
                    "version": "v0.4.0",
                    "transport": env_config["TRANSPORT"],
                    "security": env_config["SECURITY"],
                    "muxer": env_config["MUXER"],
                    "metadata": {}
                }
                
                if status == "failed":
                    # Try to extract error from stderr
                    result["error"] = "Test failed - see logs for details"
                
                results.append(result)
    
    # If no tests were parsed, create a default result
    if not results:
        # Check if there were any tests found at all
        if "collected 0 items" in stdout or "no tests ran" in stdout.lower():
            results.append({
                "test_name": "test_collection",
                "status": "skipped",
                "duration": 0.0,
                "implementation": "py-libp2p", 
                "version": "v0.4.0",
                "transport": env_config["TRANSPORT"],
                "security": env_config["SECURITY"],
                "muxer": env_config["MUXER"],
                "error": "No tests found to execute",
                "metadata": {"reason": "no_tests_collected"}
            })
        else:
            results.append({
                "test_name": "test_harness_execution",
                "status": "failed" if stderr else "passed",
                "duration": 0.0,
                "implementation": "py-libp2p", 
                "version": "v0.4.0",
                "transport": env_config["TRANSPORT"],
                "security": env_config["SECURITY"],
                "muxer": env_config["MUXER"],
                "error": stderr[:200] if stderr else None,
                "metadata": {}
            })
    
    return results

if __name__ == "__main__":
    exit_code = run_tests_with_json_output()
    sys.exit(exit_code)
EOF

# Make the script executable
RUN chmod +x /app/run_tests.py

# Default command runs the JSON-formatted test runner
CMD ["python", "/app/run_tests.py"]