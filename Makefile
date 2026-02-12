.PHONY: test test-cache test-disabled test-correlation setup update sql

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

# Database operations (via debee.ps1)
setup:
	powershell.exe -File ./debee.ps1 -Operations fullService

update:
	powershell.exe -File ./debee.ps1 -Operations updateDatabase

# Run arbitrary SQL
sql:
	./exec-sql.sh
