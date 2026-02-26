.PHONY: help test test-cache test-disabled test-correlation test-search setup update sql

# Show available targets
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Tests:"
	@echo "  test              Run all tests"
	@echo "  test-cache        Run cache invalidation tests"
	@echo "  test-disabled     Run disabled user tests"
	@echo "  test-correlation  Run correlation tests"
	@echo "  test-search       Run search function tests"
	@echo ""
	@echo "Database:"
	@echo "  setup             Full database setup (recreate + restore + update)"
	@echo "  update            Run database migrations"
	@echo "  sql               Open interactive psql session"

# Run all tests
test:
	./tests/run-tests.sh

# Run specific test suites
test-cache:
	./tests/run-tests.sh cache

test-disabled:
	./tests/run-tests.sh disabled

test-correlation:
	./tests/run-tests.sh correlation

test-search:
	./tests/run-tests.sh search_functions

# Database operations (via debee.ps1)
setup:
	powershell.exe -File ./debee.ps1 -Operations fullService

update:
	powershell.exe -File ./debee.ps1 -Operations updateDatabase

# Run arbitrary SQL
sql:
	./exec-sql.sh
