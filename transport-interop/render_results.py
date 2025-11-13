#!/usr/bin/env python3
"""
Render results.csv into a readable markdown report.

This script analyzes test results from results.csv and generates a comprehensive
markdown report with:
- TLDR summary with quick stats
- Detailed test summary by implementation, configuration, and direction
- All failed tests with log snippets
- Prioritized TODO list for fixes
"""

import csv
import sys
import os
import argparse
from collections import defaultdict
from pathlib import Path


def parse_test_name(name):
    """Parse test name into components."""
    if " x " not in name:
        return None, None, None
    
    parts = name.split(" x ")
    dialer = parts[0].strip()
    listener_part = parts[1]
    
    # Extract listener and config
    if "(" in listener_part:
        listener = listener_part.split(" (")[0].strip()
        config = listener_part.split("(")[1].split(")")[0].strip()
    else:
        listener = listener_part.strip()
        config = ""
    
    return dialer, listener, config


def analyze_results(results_file="results.csv"):
    """Analyze results.csv and return structured data."""
    results = []
    
    with open(results_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            results.append(row)
    
    # Statistics
    total = len(results)
    successes = sum(1 for r in results if r['outcome'] == 'success')
    failures = total - successes
    success_rate = (successes / total * 100) if total > 0 else 0
    
    # Group by implementation
    by_impl = defaultdict(lambda: {"success": 0, "failure": 0, "tests": []})
    by_config = defaultdict(lambda: {"success": 0, "failure": 0})
    by_direction = defaultdict(lambda: {"success": 0, "failure": 0})
    
    failed_tests = []
    
    for row in results:
        name = row['name']
        outcome = row['outcome']
        
        dialer, listener, config = parse_test_name(name)
        if not dialer or not listener:
            continue
        
        # Determine if Python is involved and which role
        is_python_dialer = "python-v0.4" in dialer
        is_python_listener = "python-v0.4" in listener
        
        # Get implementation name (the non-Python one, or both if Python vs Python)
        if is_python_dialer and not is_python_listener:
            impl = listener
            direction = "Python dialer"
        elif is_python_listener and not is_python_dialer:
            impl = dialer
            direction = "Python listener"
        elif is_python_dialer and is_python_listener:
            impl = "python-v0.4"
            direction = "Python vs Python"
        else:
            impl = f"{dialer} vs {listener}"
            direction = "Other"
        
        # Count by implementation
        if outcome == "success":
            by_impl[impl]["success"] += 1
        else:
            by_impl[impl]["failure"] += 1
            failed_tests.append({
                "name": name,
                "dialer": dialer,
                "listener": listener,
                "config": config,
                "direction": direction,
                "impl": impl
            })
        
        by_impl[impl]["tests"].append({
            "name": name,
            "outcome": outcome,
            "config": config,
            "direction": direction
        })
        
        # Count by configuration
        if config:
            if outcome == "success":
                by_config[config]["success"] += 1
            else:
                by_config[config]["failure"] += 1
        
        # Count by direction
        if outcome == "success":
            by_direction[direction]["success"] += 1
        else:
            by_direction[direction]["failure"] += 1
    
    return {
        "total": total,
        "successes": successes,
        "failures": failures,
        "success_rate": success_rate,
        "by_impl": dict(by_impl),
        "by_config": dict(by_config),
        "by_direction": dict(by_direction),
        "failed_tests": failed_tests
    }


def generate_tldr(data):
    """Generate TLDR section."""
    lines = []
    lines.append("# Section 1 - TLDR")
    lines.append("")
    lines.append(f"**Total Tests**: {data['total']}")
    lines.append(f"**Successes**: {data['successes']} ({data['success_rate']:.1f}%)")
    lines.append(f"**Failures**: {data['failures']}")
    lines.append("")
    
    # Quick stats by implementation - calculate accurate stats for all implementations
    lines.append("### Quick Stats by Implementation")
    lines.append("")
    
    # Recalculate implementation stats accurately (count each impl in all tests it's involved in)
    impl_stats = defaultdict(lambda: {"success": 0, "failure": 0})
    
    for test in data['by_impl'].values():
        for test_item in test.get('tests', []):
            # Parse the test name to get both implementations
            name = test_item['name']
            dialer, listener, _ = parse_test_name(name)
            if dialer and listener:
                outcome = test_item['outcome']
                # Count for both dialer and listener
                for impl in [dialer, listener]:
                    if outcome == "success":
                        impl_stats[impl]["success"] += 1
                    else:
                        impl_stats[impl]["failure"] += 1
    
    # Sort: failures first (by failure count descending, then success rate ascending), then successes (by success rate descending)
    impls = sorted(
        impl_stats.items(),
        key=lambda x: (
            x[1]['failure'] == 0,  # False (failures) come before True (no failures)
            -x[1]['failure'] if x[1]['failure'] > 0 else 0,  # For failures: sort by failure count descending
            (x[1]['success'] / (x[1]['success'] + x[1]['failure']) if (x[1]['success'] + x[1]['failure']) > 0 else 0) if x[1]['failure'] > 0 else 0,  # For failures: then by success rate ascending
            -(x[1]['success'] / (x[1]['success'] + x[1]['failure']) if (x[1]['success'] + x[1]['failure']) > 0 else 0),  # For successes: by success rate descending
            x[0]  # Then alphabetically
        )
    )
    
    # Show all implementations (no limit - show everything)
    for impl, stats in impls:
        total_impl = stats['success'] + stats['failure']
        if total_impl > 0:
            success_rate = (stats['success'] / total_impl) * 100
            status = "✅" if stats['failure'] == 0 else "⚠️" if success_rate > 50 else "❌"
            lines.append(f"- {status} **{impl}**: {stats['success']}/{total_impl} ({success_rate:.1f}%)")
    
    lines.append("")
    return "\n".join(lines)


def generate_tests_summary(data):
    """Generate tests summary section."""
    lines = []
    lines.append("# Section 2 - Tests Summary")
    lines.append("")
    
    # By implementation
    lines.append("## By Implementation")
    lines.append("")
    lines.append("| Implementation | Success | Failure | Total | Success Rate |")
    lines.append("|----------------|---------|---------|-------|--------------|")
    
    impls = sorted(data['by_impl'].items(), key=lambda x: x[0])
    for impl, stats in impls:
        total_impl = stats['success'] + stats['failure']
        if total_impl > 0:
            success_rate = (stats['success'] / total_impl) * 100
            status = "✅" if stats['failure'] == 0 else "⚠️" if success_rate > 50 else "❌"
            lines.append(f"| {status} {impl} | {stats['success']} | {stats['failure']} | {total_impl} | {success_rate:.1f}% |")
    
    lines.append("")
    
    # By configuration
    lines.append("## By Configuration")
    lines.append("")
    lines.append("| Configuration | Success | Failure | Total | Success Rate |")
    lines.append("|---------------|---------|---------|-------|--------------|")
    
    configs = sorted(data['by_config'].items(), key=lambda x: x[0])
    for config, stats in configs:
        total_config = stats['success'] + stats['failure']
        if total_config > 0:
            success_rate = (stats['success'] / total_config) * 100
            status = "✅" if stats['failure'] == 0 else "⚠️" if success_rate > 50 else "❌"
            lines.append(f"| {status} {config} | {stats['success']} | {stats['failure']} | {total_config} | {success_rate:.1f}% |")
    
    lines.append("")
    
    # By direction
    lines.append("## By Direction")
    lines.append("")
    lines.append("| Direction | Success | Failure | Total | Success Rate |")
    lines.append("|-----------|---------|---------|-------|--------------|")
    
    directions = sorted(data['by_direction'].items(), key=lambda x: x[0])
    for direction, stats in directions:
        total_dir = stats['success'] + stats['failure']
        if total_dir > 0:
            success_rate = (stats['success'] / total_dir) * 100
            status = "✅" if stats['failure'] == 0 else "⚠️" if success_rate > 50 else "❌"
            lines.append(f"| {status} {direction} | {stats['success']} | {stats['failure']} | {total_dir} | {success_rate:.1f}% |")
    
    lines.append("")
    return "\n".join(lines)


def find_log_files(test_name):
    """Find log files that might contain output for this test."""
    log_files = []
    
    # First, check standardized logs directory (from compose-runner.ts)
    logs_dir = os.getenv("LOGS_DIR", os.path.join(os.getcwd(), "logs"))
    if os.path.exists(logs_dir):
        # Sanitize test name to match log file naming (same as compose-runner.ts)
        # compose-runner.ts uses: namespace.replace(/[^a-zA-Z0-9]/g, "-")
        # This replaces ALL non-alphanumeric chars with "-", including spaces, parens, etc.
        sanitized = "".join(c if c.isalnum() else "-" for c in test_name)
        # Note: compose-runner.ts doesn't collapse dashes, so "--" stays as "--"
        
        log_file = os.path.join(logs_dir, f"{sanitized}.log")
        if os.path.exists(log_file):
            log_files.append(log_file)
        
        # Also search all log files and match by test name content
        try:
            for filename in os.listdir(logs_dir):
                if filename.endswith('.log'):
                    # Check if filename contains key parts of test name
                    test_parts = [p.strip() for p in test_name.replace("(", "").replace(")", "").split(" x ")]
                    filename_lower = filename.lower()
                    # Match if filename contains both implementation names
                    if len(test_parts) >= 2:
                        part1 = test_parts[0].lower().replace(" ", "-")
                        part2 = test_parts[1].split("(")[0].strip().lower().replace(" ", "-")
                        if part1 in filename_lower and part2 in filename_lower:
                            full_path = os.path.join(logs_dir, filename)
                            if full_path not in log_files:
                                log_files.append(full_path)
        except Exception:
            pass
    
    # Also check /tmp for manually saved logs (backward compatibility)
    tmpdir_path = "/tmp"
    
    # Extract key components from test name
    test_name_lower = test_name.lower()
    key_components = []
    
    # Extract implementation names
    if "python" in test_name_lower:
        key_components.append("python")
    if "c-v0.0.1" in test_name_lower or "c-v0" in test_name_lower:
        key_components.append("c")
    if "rust" in test_name_lower:
        key_components.append("rust")
    if "go" in test_name_lower:
        key_components.append("go")
    if "jvm" in test_name_lower:
        key_components.append("jvm")
    
    # Extract transport/security/muxer
    if "tcp" in test_name_lower:
        key_components.append("tcp")
    if "quic" in test_name_lower:
        key_components.append("quic")
    if "ws" in test_name_lower or "websocket" in test_name_lower:
        key_components.append("ws")
    
    try:
        if os.path.exists(tmpdir_path):
            for filename in os.listdir(tmpdir_path):
                if filename.endswith('.log'):
                    filepath = os.path.join(tmpdir_path, filename)
                    if os.path.isfile(filepath):
                        filename_lower = filename.lower()
                        
                        # Check if filename contains key components
                        matches = sum(1 for comp in key_components if comp in filename_lower)
                        # Require at least 2 matches (e.g., "python" and "c") or test name substring
                        if matches >= 2 or any(part in filename_lower for part in ["python", "all", "test"]):
                            # Also check if file content contains the test name
                            try:
                                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                                    content = f.read(8192).lower()  # Read first 8KB
                                    if test_name_lower in content or any(comp in content for comp in key_components[:2]):
                                        log_files.append(filepath)
                            except Exception:
                                # If we can't read it, still include if filename matches well
                                if matches >= 2:
                                    log_files.append(filepath)
    except Exception:
        pass  # Ignore errors when searching
    
    return log_files


def extract_log_snippets(test_name, log_files, max_lines=30):
    """Extract relevant log snippets from log files, prioritizing errors and failures."""
    snippets = []
    
    for log_file in log_files[:2]:  # Limit to first 2 matching files
        try:
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
            
            if not lines:
                continue
            
            test_name_lower = test_name.lower()
            test_name_simple = test_name.replace("(", "").replace(")", "").lower()
            
            # Priority 1: Find high-priority error messages (ERROR, FATAL, exceptions)
            high_priority_keywords = ['[error]', '[fatal]', 'exception', 'traceback', 'stack trace', 
                                     'panic', 'abort', 'crashed', 'failed with', 'error:']
            high_priority_errors = []
            
            for i, line in enumerate(lines):
                line_lower = line.lower()
                # Check for high-priority error indicators
                if any(keyword in line_lower for keyword in high_priority_keywords):
                    # Get more context for high-priority errors
                    start = max(0, i - 5)
                    end = min(len(lines), i + 15)
                    section = lines[start:end]
                    high_priority_errors.append((i, section, line))
            
            # Priority 2: Find other error/failure lines with context
            error_keywords = ['error', 'failed', 'failure', 'timeout', 'eof', 'exit code']
            error_sections = []
            
            for i, line in enumerate(lines):
                line_lower = line.lower()
                # Skip if already captured as high-priority
                if any(keyword in line_lower for keyword in high_priority_keywords):
                    continue
                # Check for other error keywords
                if any(keyword in line_lower for keyword in error_keywords):
                    # Get context around error (more lines after than before)
                    start = max(0, i - 3)
                    end = min(len(lines), i + 10)
                    section = lines[start:end]
                    error_sections.append((i, section, line))
            
            # Priority 2: Find failure-related messages (exit codes, connection issues, etc.)
            failure_keywords = ['exit code', 'connection refused', 'connection reset', 'connection closed',
                              'handshake', 'protocol', 'negotiation', 'dialer', 'listener']
            failure_sections = []
            
            for i, line in enumerate(lines):
                line_lower = line.lower()
                if any(keyword in line_lower for keyword in failure_keywords):
                    # Check if this looks like a failure (not just normal operation)
                    if any(indicator in line_lower for indicator in ['failed', 'error', 'timeout', 'closed', 'refused']):
                        start = max(0, i - 2)
                        end = min(len(lines), i + 8)
                        section = lines[start:end]
                        failure_sections.append((i, section, line))
            
            # Build snippet from errors and failures
            relevant_lines = []
            seen = set()
            
            # Add high-priority errors first (most important)
            for i, section, error_line in high_priority_errors[-5:]:  # Last 5 high-priority errors
                for line in section:
                    if line not in seen:
                        seen.add(line)
                        relevant_lines.append((i, line))
            
            # Add other error sections
            for i, section, error_line in error_sections[-10:]:  # Last 10 errors
                for line in section:
                    if line not in seen:
                        seen.add(line)
                        relevant_lines.append((i, line))
            
            # Add failure sections
            for i, section, failure_line in failure_sections[-5:]:  # Last 5 failures
                for line in section:
                    if line not in seen:
                        seen.add(line)
                        relevant_lines.append((i, line))
            
            # If we have errors/failures, use them
            if relevant_lines:
                # Sort by line number to maintain chronological order
                relevant_lines.sort(key=lambda x: x[0])
                # Take lines with some context, limit to max_lines
                snippet_lines = [line for _, line in relevant_lines[:max_lines]]
                
                # Also include last 15 lines of log (where failures often appear)
                # This ensures we capture the final error state
                last_lines = lines[-15:]
                for line in reversed(last_lines):
                    if line not in seen and len(snippet_lines) < max_lines:
                        snippet_lines.append(line)
                        seen.add(line)
                
                # Filter out excessive DEBUG noise, but keep ERROR/INFO/WARNING
                # Prioritize: ERROR/FATAL > WARNING > INFO > ERROR keywords > DEBUG (limited)
                filtered_lines = []
                debug_count = 0
                for line in snippet_lines:
                    line_lower = line.lower()
                    is_debug = '[debug]' in line_lower
                    is_error_level = '[error]' in line_lower or '[fatal]' in line_lower
                    is_warning = '[warn]' in line_lower
                    is_info = '[info]' in line_lower
                    has_error_keyword = any(keyword in line_lower for keyword in ['error:', 'failed', 'failure', 'exception', 'timeout', 'eof', 'traceback'])
                    
                    # Always include ERROR/FATAL level messages
                    if is_error_level:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Always include WARNING level
                    elif is_warning:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Include INFO if it's relevant
                    elif is_info and has_error_keyword:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Include lines with error keywords (even if DEBUG)
                    elif has_error_keyword:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Include non-DEBUG lines
                    elif not is_debug:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Limit DEBUG lines to max 2 consecutive
                    elif is_debug and debug_count < 2:
                        filtered_lines.append(line)
                        debug_count += 1
                    # Skip excessive DEBUG lines
                
                if filtered_lines:
                    snippets.append({
                        'file': os.path.basename(log_file),
                        'lines': filtered_lines[:max_lines]
                    })
            else:
                # Fallback: Show last portion of log (where failures typically occur)
                # Filter out excessive DEBUG noise, prioritize errors
                last_lines = lines[-max_lines:]
                filtered_lines = []
                debug_count = 0
                for line in last_lines:
                    line_lower = line.lower()
                    is_debug = '[debug]' in line_lower
                    is_error_level = '[error]' in line_lower or '[fatal]' in line_lower
                    is_warning = '[warn]' in line_lower
                    is_info = '[info]' in line_lower
                    has_error_keyword = any(keyword in line_lower for keyword in ['error:', 'failed', 'failure', 'exception', 'timeout', 'eof', 'traceback'])
                    
                    # Always include ERROR/FATAL level messages
                    if is_error_level:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Always include WARNING level
                    elif is_warning:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Include INFO if it's relevant
                    elif is_info and has_error_keyword:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Include lines with error keywords (even if DEBUG)
                    elif has_error_keyword:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Include non-DEBUG lines
                    elif not is_debug:
                        filtered_lines.append(line)
                        debug_count = 0
                    # Limit DEBUG lines to max 2 consecutive
                    elif is_debug and debug_count < 2:
                        filtered_lines.append(line)
                        debug_count += 1
                
                if filtered_lines:
                    snippets.append({
                        'file': os.path.basename(log_file),
                        'lines': filtered_lines[:max_lines]
                    })
                    
        except Exception as e:
            # Skip files that can't be read
            continue
    
    return snippets


def get_log_locations(test_name):
    """Get potential log locations for a test."""
    # Sanitize test name for directory matching (similar to compose-runner.ts)
    sanitized = test_name.replace(" ", "-").replace("(", "").replace(")", "").replace(",", "-")
    sanitized = sanitized.replace(" x ", "-x-").replace("--", "-").lower()
    # Remove special characters
    sanitized = "".join(c if c.isalnum() or c in "-_" else "-" for c in sanitized)
    sanitized = "-".join(filter(None, sanitized.split("-")))  # Remove empty parts
    
    log_locations = []
    
    # Check for compose-runner directory (may be cleaned up, but worth checking)
    tmpdir_path = os.path.join(os.path.expanduser("~"), ".tmp") if "HOME" in os.environ else "/tmp"
    compose_dir = os.path.join(tmpdir_path, "compose-runner", sanitized)
    if os.path.exists(compose_dir):
        log_locations.append(f"    - ✅ Compose directory exists: `{compose_dir}`")
    else:
        log_locations.append(f"    - Compose logs: `/tmp/compose-runner/{sanitized}/` (cleaned up after test)")
    
    # Implementation-specific log hints
    if "python" in test_name.lower():
        log_locations.append(f"    - Python debug logs: `/tmp/py-libp2p_*.log` (inside container)")
        log_locations.append(f"    - Enable debug: Set `LIBP2P_DEBUG=DEBUG` environment variable")
    
    if "rust" in test_name.lower():
        log_locations.append(f"    - Rust debug logs: Set `RUST_LOG=debug` environment variable")
    
    if "c-v0.0.1" in test_name:
        log_locations.append(f"    - C debug logs: Set `LIBP2P_LOG_LEVEL=debug` environment variable")
    
    # Generic Docker log info
    log_locations.append(f"    - To capture logs: Run test individually and check stdout/stderr before cleanup")
    
    return log_locations


def generate_failed_tests(data):
    """Generate failed tests section."""
    lines = []
    lines.append("# Section 3 - All Failed Tests")
    lines.append("")
    
    if not data['failed_tests']:
        lines.append("✅ **No failed tests!**")
        lines.append("")
        return "\n".join(lines)
    
    lines.append(f"Total failed tests: **{len(data['failed_tests'])}**")
    lines.append("")
    lines.append("> **Note**: Logs are typically stored in `/tmp/compose-runner/{test-name}/` but are cleaned up after tests.")
    lines.append("> To capture logs for failed tests, run tests individually or check Docker container logs before cleanup.")
    lines.append("")
    
    # Group by implementation
    by_impl = defaultdict(list)
    for test in data['failed_tests']:
        by_impl[test['impl']].append(test)
    
    for impl in sorted(by_impl.keys()):
        tests = by_impl[impl]
        lines.append(f"## {impl} ({len(tests)} failures)")
        lines.append("")
        
        for test in tests:
            lines.append(f"- **{test['name']}**")
            lines.append(f"  - Direction: {test['direction']}")
            lines.append(f"  - Config: {test['config']}")
            
            # Try to find and extract log snippets
            log_files = find_log_files(test['name'])
            if log_files:
                log_snippets = extract_log_snippets(test['name'], log_files, max_lines=25)
                if log_snippets:
                    lines.append("  - Log snippets:")
                    for snippet in log_snippets[:2]:  # Limit to 2 snippets per test
                        lines.append(f"    - From `{snippet['file']}`:")
                        lines.append("      ```")
                        # Show relevant lines (limit to 20 lines per snippet)
                        snippet_lines = snippet['lines'][:20]
                        for line in snippet_lines:
                            # Clean up line and limit length
                            clean_line = line.rstrip()
                            if len(clean_line) > 120:
                                clean_line = clean_line[:117] + "..."
                            lines.append(f"      {clean_line}")
                        if len(snippet['lines']) > 20:
                            lines.append(f"      ... ({len(snippet['lines']) - 20} more lines)")
                        lines.append("      ```")
            
            # Add log location information
            log_locs = get_log_locations(test['name'])
            if log_locs:
                lines.append("  - Log locations:")
                lines.extend(log_locs[:3])  # Show first 3 log locations
            
            lines.append("")
    
    lines.append("")
    return "\n".join(lines)


def generate_todo(data):
    """Generate TODO section with actionable items."""
    lines = []
    lines.append("# Section 4 - TODO to Fix")
    lines.append("")
    
    if not data['failed_tests']:
        lines.append("✅ **No fixes needed!**")
        lines.append("")
        return "\n".join(lines)
    
    # Group failures by pattern
    by_impl = defaultdict(list)
    by_config = defaultdict(list)
    by_direction = defaultdict(list)
    
    for test in data['failed_tests']:
        by_impl[test['impl']].append(test)
        by_config[test['config']].append(test)
        by_direction[test['direction']].append(test)
    
    # Priority 1: High-impact fixes (affecting multiple tests)
    lines.append("## Priority 1: High-Impact Issues")
    lines.append("")
    
    # Find implementations with most failures
    impl_failures = sorted(by_impl.items(), key=lambda x: len(x[1]), reverse=True)
    for impl, tests in impl_failures[:5]:
        if len(tests) >= 2:  # At least 2 failures
            lines.append(f"### {impl} - {len(tests)} failures")
            lines.append("")
            
            # Analyze pattern
            configs = defaultdict(list)
            directions = defaultdict(list)
            for test in tests:
                configs[test['config']].append(test)
                directions[test['direction']].append(test)
            
            # Determine likely cause
            if len(directions) == 1:
                direction = list(directions.keys())[0]
                lines.append(f"**Pattern**: All failures when {direction}")
                lines.append("")
            
            # Group by config
            for config, config_tests in sorted(configs.items()):
                lines.append(f"- **{config}**: {len(config_tests)} test(s)")
                for test in config_tests[:3]:  # Show first 3
                    lines.append(f"  - {test['name']}")
                if len(config_tests) > 3:
                    lines.append(f"  - ... and {len(config_tests) - 3} more")
            
            # Suggested action
            configs_list = [t['config'] for t in tests]
            has_quic = any("quic" in c for c in configs_list)
            has_tcp = any("tcp" in c for c in configs_list)
            
            if "c-v0.0.1" in impl:
                if has_tcp and not has_quic:
                    lines.append("")
                    lines.append("**Suggested Action**: Check C retry mechanism - TCP tests failing when Python is dialer")
                elif has_quic and has_tcp:
                    lines.append("")
                    lines.append("**Suggested Action**: QUIC failures are expected (Python QUIC listener issue). TCP failures need investigation - check C retry mechanism.")
                elif has_quic:
                    lines.append("")
                    lines.append("**Suggested Action**: Known Python QUIC listener issue")
            elif "jvm" in impl.lower():
                lines.append("")
                lines.append("**Suggested Action**: Investigate JVM interop issues - multiple transport failures")
            elif has_quic and all("Python listener" in t['direction'] for t in tests):
                lines.append("")
                lines.append("**Suggested Action**: Known Python QUIC listener issue")
            
            lines.append("")
    
    # Priority 2: Configuration-specific issues
    lines.append("## Priority 2: Configuration-Specific Issues")
    lines.append("")
    
    config_failures = sorted(by_config.items(), key=lambda x: len(x[1]), reverse=True)
    for config, tests in config_failures:
        if len(tests) >= 2:
            lines.append(f"### {config} - {len(tests)} failures")
            lines.append("")
            
            # Group by implementation
            impls = defaultdict(list)
            for test in tests:
                impls[test['impl']].append(test)
            
            for impl, impl_tests in sorted(impls.items()):
                lines.append(f"- **{impl}**: {len(impl_tests)} test(s)")
                for test in impl_tests[:2]:
                    lines.append(f"  - {test['name']}")
            
            # Suggested action
            if "quic-v1" in config:
                lines.append("")
                lines.append("**Suggested Action**: Python QUIC listener issue - affects all implementations")
            elif "ws" in config.lower():
                lines.append("")
                lines.append("**Suggested Action**: Investigate WebSocket-specific issues")
            
            lines.append("")
    
    # Priority 3: Direction-specific issues
    lines.append("## Priority 3: Direction-Specific Issues")
    lines.append("")
    
    direction_failures = sorted(by_direction.items(), key=lambda x: len(x[1]), reverse=True)
    for direction, tests in direction_failures:
        if len(tests) >= 2:
            lines.append(f"### {direction} - {len(tests)} failures")
            lines.append("")
            
            # Group by implementation
            impls = defaultdict(list)
            for test in tests:
                impls[test['impl']].append(test)
            
            for impl, impl_tests in sorted(impls.items()):
                lines.append(f"- **{impl}**: {len(impl_tests)} test(s)")
                for test in impl_tests[:2]:
                    lines.append(f"  - {test['name']}")
            
            # Suggested action
            if "Python listener" in direction:
                lines.append("")
                lines.append("**Suggested Action**: Python listener issues - check connection handling")
            elif "Python dialer" in direction:
                lines.append("")
                lines.append("**Suggested Action**: Python dialer issues - check connection establishment")
            
            lines.append("")
    
    # Individual failures
    if len(data['failed_tests']) > 0:
        lines.append("## Individual Failures")
        lines.append("")
        lines.append("Tests that don't fit into the above patterns:")
        lines.append("")
        
        # Find tests that are unique
        unique_tests = []
        for test in data['failed_tests']:
            impl_count = len(by_impl[test['impl']])
            config_count = len(by_config[test['config']])
            direction_count = len(by_direction[test['direction']])
            
            if impl_count < 2 and config_count < 2 and direction_count < 2:
                unique_tests.append(test)
        
        if unique_tests:
            for test in unique_tests:
                lines.append(f"- {test['name']}")
                lines.append(f"  - Implementation: {test['impl']}")
                lines.append(f"  - Config: {test['config']}")
                lines.append(f"  - Direction: {test['direction']}")
                lines.append("")
        else:
            lines.append("(All failures fit into the above patterns)")
            lines.append("")
    
    lines.append("")
    return "\n".join(lines)


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Render results.csv into a readable markdown report",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Generate results_report.md from results.csv
  %(prog)s -o my_report.md           # Generate custom report file
  %(prog)s -i custom_results.csv     # Use custom input CSV file
  %(prog)s -i results.csv -o report.md  # Specify both input and output
        """
    )
    parser.add_argument(
        "-i", "--input",
        default="results.csv",
        help="Input CSV file with test results (default: results.csv)"
    )
    parser.add_argument(
        "-o", "--output",
        default="results_report.md",
        help="Output markdown file (default: results_report.md). Use '-' for stdout"
    )
    
    args = parser.parse_args()
    
    # Check if input file exists
    if not Path(args.input).exists():
        print(f"Error: Input file '{args.input}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Analyze results
    data = analyze_results(args.input)
    
    # Generate sections
    sections = [
        generate_tldr(data),
        generate_tests_summary(data),
        generate_failed_tests(data),
        generate_todo(data)
    ]
    
    # Output
    output = "\n".join(sections)
    
    if args.output == "-":
        # Write to stdout
        print(output)
    else:
        # Write to file
        try:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(output)
            print(f"✅ Report generated: {args.output}", file=sys.stderr)
        except Exception as e:
            print(f"Error writing to '{args.output}': {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()

