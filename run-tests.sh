#!/bin/bash

echo "🧪 Running PingMonitor Test Suite..."
echo "=================================="

# Run the tests and capture the exit code
./PingMonitorTests.swift > test_output.log 2>&1
EXIT_CODE=$?

# Extract summary from output
echo "$(tail -n 15 test_output.log)"

# Clean up
rm -f test_output.log

# Exit with the same code as the tests
exit $EXIT_CODE