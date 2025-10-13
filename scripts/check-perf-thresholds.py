#!/usr/bin/env python3
"""
Check performance thresholds for HOSS validation (RFC 0004)
"""
import argparse
import json
import sys
from pathlib import Path


def load_json(file_path):
    """Load JSON file"""
    with open(file_path, 'r') as f:
        return json.load(f)


def check_thresholds(thresholds_file, result_file, tier):
    """Check if performance results meet thresholds"""

    # Load configuration
    config = load_json(thresholds_file)
    result = load_json(result_file)

    # Get threshold for tier
    if tier not in config['thresholds']:
        print(f"ERROR: Unknown tier: {tier}", file=sys.stderr)
        print(f"Valid tiers: {', '.join(config['thresholds'].keys())}", file=sys.stderr)
        return 1

    threshold = config['thresholds'][tier]
    tolerance = config['tolerances']

    # Extract metrics from result
    validation_time_ms = result.get('validationTimeMs', 0)
    peak_memory_kb = result.get('peakMemoryKB', 0)
    peak_memory_mb = peak_memory_kb / 1024

    # Calculate thresholds with tolerance
    max_time_ms = threshold['maxTimeMs'] * tolerance['time']
    max_memory_mb = threshold['maxMemoryMB'] * tolerance['memory']

    # Check thresholds
    time_ok = validation_time_ms <= max_time_ms
    memory_ok = peak_memory_mb <= max_memory_mb

    # Print results
    print(f"Tier: {tier}")
    print(f"Description: {threshold['description']}")
    print("")
    print(f"Time:   {validation_time_ms:>6}ms / {int(max_time_ms):>6}ms (threshold) - {'✅ PASS' if time_ok else '❌ FAIL'}")
    print(f"Memory: {peak_memory_mb:>6.1f}MB / {int(max_memory_mb):>6}MB (threshold) - {'✅ PASS' if memory_ok else '❌ FAIL'}")
    print("")

    # Handle XL tier specially (informational only)
    if tier == 'xl':
        print("ℹ️  XL tier is stress test - failures are informational only")
        print("✅ Performance check complete (XL tier)")
        return 0

    # Exit based on results
    if time_ok and memory_ok:
        print("✅ Performance thresholds met")
        return 0
    else:
        print("❌ Performance regression detected")
        if not time_ok:
            overage_ms = int(validation_time_ms - max_time_ms)
            print(f"   Time exceeded by {overage_ms}ms")
        if not memory_ok:
            overage_mb = peak_memory_mb - max_memory_mb
            print(f"   Memory exceeded by {overage_mb:.1f}MB")
        return 1


def main():
    parser = argparse.ArgumentParser(
        description='Check HOSS performance thresholds',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check medium tier performance
  %(prog)s --thresholds docs/performance-thresholds.json \\
           --result .artifacts/perf-medium-result.json \\
           --tier medium

  # Check large tier (will fail if thresholds exceeded)
  %(prog)s --thresholds docs/performance-thresholds.json \\
           --result .artifacts/perf-large-result.json \\
           --tier large
        """
    )

    parser.add_argument(
        '--thresholds',
        required=True,
        help='Path to performance thresholds JSON file'
    )
    parser.add_argument(
        '--result',
        required=True,
        help='Path to performance result JSON file'
    )
    parser.add_argument(
        '--tier',
        required=True,
        choices=['small', 'medium', 'large', 'xl'],
        help='Performance tier to check'
    )

    args = parser.parse_args()

    # Check files exist
    if not Path(args.thresholds).exists():
        print(f"ERROR: Thresholds file not found: {args.thresholds}", file=sys.stderr)
        return 1

    if not Path(args.result).exists():
        print(f"ERROR: Result file not found: {args.result}", file=sys.stderr)
        return 1

    # Run threshold check
    try:
        return check_thresholds(args.thresholds, args.result, args.tier)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
