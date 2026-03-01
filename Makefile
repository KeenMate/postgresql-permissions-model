.PHONY: help test test-cache test-disabled test-correlation test-search setup update sql

# Show available targets
help:
	@echo "Usage: make [target] [FILTER=name]"
	@echo ""
	@echo "Tests:"
	@echo "  test              Run all tests (or FILTER=name for subset)"
	@echo "  test-cache        Run cache invalidation tests"
	@echo "  test-disabled     Run disabled user tests"
	@echo "  test-correlation  Run correlation tests"
	@echo "  test-search       Run search function tests"
	@echo ""
	@echo "Database:"
	@echo "  setup             Full database setup (recreate + restore + update)"
	@echo "  update            Run database migrations"
	@echo "  sql               Open interactive psql session"

# Run all tests (use FILTER= for subset, e.g. make test FILTER=resource)
test:
ifdef FILTER
	powershell.exe -File ./debee.ps1 -Operations runTests -TestFilter $(FILTER)
else
	powershell.exe -File ./debee.ps1 -Operations runTests
endif

# Run specific test suites
test-cache:
	powershell.exe -File ./debee.ps1 -Operations runTests -TestFilter cache

test-disabled:
	powershell.exe -File ./debee.ps1 -Operations runTests -TestFilter disabled

test-correlation:
	powershell.exe -File ./debee.ps1 -Operations runTests -TestFilter correlation

test-search:
	powershell.exe -File ./debee.ps1 -Operations runTests -TestFilter search_functions

# Database operations
setup:
	powershell.exe -File ./debee.ps1 -Operations fullService

update:
	powershell.exe -File ./debee.ps1 -Operations updateDatabase

# Interactive psql session
sql:
	powershell.exe -File ./debee.ps1 -Operations execSql
