-- Setup: Create temporary table for connectivity tests
CREATE TEMPORARY TABLE IF NOT EXISTS _test_connectivity (
    id serial PRIMARY KEY,
    value text NOT NULL,
    created_at timestamp DEFAULT now()
);

INSERT INTO _test_connectivity (value) VALUES ('test_value');
