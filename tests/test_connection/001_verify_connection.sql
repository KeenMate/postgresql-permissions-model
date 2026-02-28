-- Test: Verify database connectivity
-- Expected: Returns "PASS" if connection works

SELECT CASE
    WHEN 1 = 1 THEN 'PASS: database connection works'
    ELSE 'FAIL: database connection failed'
END AS test_connection;
