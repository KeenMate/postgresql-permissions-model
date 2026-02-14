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

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

# Load environment
if [ -f "debee.env" ]; then
    source debee.env
fi
if [ -f ".debee.env" ]; then
    source .debee.env
fi

run_test() {
    local test_file="$1"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${BOLD}Running: $test_file${NC}"
    echo -e "${CYAN}==========================================${NC}"
    ./exec-sql.sh -f "$test_file" 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -qE 'PASS:'; then
            echo -e "${GREEN}${line}${NC}"
        elif echo "$line" | grep -qE 'FAIL:|ERROR:'; then
            echo -e "${RED}${line}${NC}"
        else
            echo "$line"
        fi
    done
    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}FAILED: $test_file (exit code: $exit_code)${NC}"
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
    group_members|delete_tenant)
        run_test "tests/test_group_members_and_delete_tenant.sql"
        if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        ;;
    event|event_code|event_management)
        run_test "tests/test_event_code_management.sql"
        if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        ;;
    language|translation|language_translation)
        run_test "tests/test_language_translation.sql"
        if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        ;;
    auth_group|member|tenant_access)
        run_test "tests/test_auth_group_member_tenant.sql"
        if [ $? -eq 0 ]; then ((PASSED++)); else ((FAILED++)); fi
        ;;
    short_code|short|permission_short_code)
        run_test "tests/test_short_code.sql"
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
echo -e "${BOLD}==========================================${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${BOLD}Test Summary: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
    echo -e "${BOLD}==========================================${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}Test Summary: $PASSED passed, 0 failed${NC}"
    echo -e "${BOLD}==========================================${NC}"
    exit 0
fi
