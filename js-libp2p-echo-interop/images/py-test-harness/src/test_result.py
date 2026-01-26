"""Test result models and JSON output formatting."""

import json
import sys
from datetime import datetime
from typing import Dict, List, Optional, Any
from pydantic import BaseModel
from .config import TestConfig


class TestResult(BaseModel):
    """Individual test result."""
    
    test_name: str
    status: str  # "passed" | "failed" | "skipped"
    duration: float  # Test execution time in seconds
    implementation: str = "py-libp2p"
    version: str = "v0.5.0"
    transport: str
    security: str
    muxer: str
    error: Optional[str] = None
    metadata: Dict[str, Any] = {}


class TestSuiteResult(BaseModel):
    """Complete test suite results."""
    
    results: List[TestResult]
    summary: Dict[str, int]
    timestamp: str
    environment: Dict[str, str]
    
    @classmethod
    def create(
        self,
        results: List[TestResult],
        environment: Dict[str, str]
    ) -> "TestSuiteResult":
        """Create test suite result with computed summary."""
        summary = {
            "total": len(results),
            "passed": len([r for r in results if r.status == "passed"]),
            "failed": len([r for r in results if r.status == "failed"]),
            "skipped": len([r for r in results if r.status == "skipped"])
        }
        
        return TestSuiteResult(
            results=results,
            summary=summary,
            timestamp=datetime.utcnow().isoformat() + "Z",
            environment=environment
        )


class TestResultCollector:
    """Collects and manages test results."""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.results: List[TestResult] = []
    
    def add_result(
        self,
        test_name: str,
        status: str,
        duration: float,
        error: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """Add a test result."""
        result = TestResult(
            test_name=test_name,
            status=status,
            duration=duration,
            transport=self.config.transport.value,
            security=self.config.security.value,
            muxer=self.config.muxer.value,
            error=error,
            metadata=metadata or {}
        )
        self.results.append(result)
    
    def get_suite_result(self) -> TestSuiteResult:
        """Get complete test suite result."""
        environment = {
            "TRANSPORT": self.config.transport.value,
            "SECURITY": self.config.security.value,
            "MUXER": self.config.muxer.value,
            "IS_DIALER": str(self.config.is_dialer).lower(),
            "REDIS_ADDR": self.config.redis_addr
        }
        
        return TestSuiteResult.create(self.results, environment)
    
    def output_json_results(self) -> None:
        """Output JSON results to stdout."""
        suite_result = self.get_suite_result()
        
        # Output to stdout for consumption by test infrastructure
        json_output = suite_result.model_dump_json(indent=2)
        print(json_output, file=sys.stdout)
        sys.stdout.flush()
    
    def log_summary(self) -> None:
        """Log test summary to stderr for debugging."""
        suite_result = self.get_suite_result()
        summary = suite_result.summary
        
        print(f"Test Summary:", file=sys.stderr)
        print(f"  Total: {summary['total']}", file=sys.stderr)
        print(f"  Passed: {summary['passed']}", file=sys.stderr)
        print(f"  Failed: {summary['failed']}", file=sys.stderr)
        print(f"  Skipped: {summary['skipped']}", file=sys.stderr)
        
        if summary['failed'] > 0:
            print(f"Failed tests:", file=sys.stderr)
            for result in suite_result.results:
                if result.status == "failed":
                    print(f"  - {result.test_name}: {result.error}", file=sys.stderr)
        
        sys.stderr.flush()