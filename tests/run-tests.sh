#!/bin/bash
#
# Test Runner for PostgreSQL Permissions Model
# Usage: ./tests/run-tests.sh [test_name]
#
# Examples:
#   ./tests/run-tests.sh                    # Run all tests
#   ./tests/run-tests.sh cache              # Run cache invalidation tests
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Load environment
if [ -f "debee.env" ]; then
    source debee.env
fi
if [ -f ".debee.env" ]; then
    source .debee.env
fi

run_test() {
    local test_file="$1"
    echo "=========================================="
    echo "Running: $test_file"
    echo "=========================================="
    ./exec-sql.sh -f "$test_file"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "FAILED: $test_file (exit code: $exit_code)"
        return 1
    fi
    return 0
}

# Determine which tests to run
TEST_FILTER="${1:-all}"
FAILED=0
PASSED=0

case "$TEST_FILTER" in
    all)
        for test_file in tests/test_*.sql; do
            if [ -f "$test_file" ]; then
                if run_test "$test_file"; then
                    ((PASSED++))
                else
                    ((FAILED++))
                fi
            fi
        done
        ;;
    cache|cache_invalidation)
        run_test "tests/test_permission_cache_invalidation.sql"
        if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        ;;
    disabled|locked|user_status)
        run_test "tests/test_disabled_locked_users.sql"
        if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        ;;
    *)
        # Try to find a matching test file
        if [ -f "tests/test_${TEST_FILTER}.sql" ]; then
            run_test "tests/test_${TEST_FILTER}.sql"
            if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        elif [ -f "tests/${TEST_FILTER}" ]; then
            run_test "tests/${TEST_FILTER}"
            if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        else
            echo "Unknown test: $TEST_FILTER"
            echo "Available tests:"
            ls -1 tests/test_*.sql 2>/dev/null | sed 's|tests/test_||;s|\.sql||'
            exit 1
        fi
        ;;
esac

echo ""
echo "=========================================="
echo "Test Summary: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
