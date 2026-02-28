-- Verify: Check database connectivity and temp table operations

SELECT CASE
    WHEN count(*) > 0 THEN 'PASS: temporary table created and populated'
    ELSE 'FAIL: temporary table is empty'
END AS test_temp_table
FROM _test_connectivity;

SELECT CASE
    WHEN current_database() IS NOT NULL THEN 'PASS: connected to database ' || current_database()
    ELSE 'FAIL: could not determine current database'
END AS test_current_db;

SELECT CASE
    WHEN current_user IS NOT NULL THEN 'PASS: authenticated as ' || current_user
    ELSE 'FAIL: could not determine current user'
END AS test_current_user;
