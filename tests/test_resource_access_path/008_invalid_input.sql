set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 008: Invalid input — must provide path or non-empty id; invalid ltree rejected
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __caught boolean;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 008: Invalid input handling ---';

    -- TEST 1: assign with neither path nor id raises
    __caught := false;
    BEGIN
        PERFORM auth.assign_resource_access(
            _created_by     := 'test',
            _user_id        := __user_1,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := __user_2,
            _access_flags   := ARRAY['read']
        );
    EXCEPTION WHEN sqlstate '35005' THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE 'PASS: Empty id + null path rejected (35005)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected rejection';
    END IF;

    -- TEST 2: Invalid ltree label (slash) rejected
    __caught := false;
    BEGIN
        PERFORM 'has/slash.not_allowed'::ext.ltree;
    EXCEPTION WHEN others THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE 'PASS: Invalid ltree label rejected at cast';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected ltree validation error on slash';
    END IF;

    -- TEST 3: helpers.path_to_ltree with default '/' separator
    DECLARE
        __sanitized ext.ltree;
    BEGIN
        __sanitized := helpers.path_to_ltree('/srv/data/organization-123/report.pdf');
        IF __sanitized::text = 'srv.data.organization_123.report_pdf' THEN
            RAISE NOTICE 'PASS: helpers.path_to_ltree with default / separator';
        ELSE
            RAISE EXCEPTION 'FAIL: Unexpected default-sep result: %', __sanitized::text;
        END IF;

        -- Custom dot separator (e.g. Java package, dot-delimited namespace)
        __sanitized := helpers.path_to_ltree('com.example.module', '.');
        IF __sanitized::text = 'com.example.module' THEN
            RAISE NOTICE 'PASS: helpers.path_to_ltree with . separator';
        ELSE
            RAISE EXCEPTION 'FAIL: Unexpected dot-sep result: %', __sanitized::text;
        END IF;

        -- Pipe separator
        __sanitized := helpers.path_to_ltree('a|b|c', '|');
        IF __sanitized::text = 'a.b.c' THEN
            RAISE NOTICE 'PASS: helpers.path_to_ltree with | separator';
        ELSE
            RAISE EXCEPTION 'FAIL: Unexpected pipe-sep result: %', __sanitized::text;
        END IF;

        -- Empty separator is rejected
        BEGIN
            __sanitized := helpers.path_to_ltree('abc', '');
            RAISE EXCEPTION 'FAIL: Empty separator should have raised';
        EXCEPTION WHEN sqlstate '22023' THEN
            RAISE NOTICE 'PASS: empty separator rejected (22023)';
        END;
    END;

    -- TEST 4: Check constraint enforced at direct insert too
    __caught := false;
    BEGIN
        INSERT INTO auth.resource_access (
            created_by, updated_by, tenant_id, resource_type, root_type,
            resource_id, resource_path, user_id, access_flag, is_deny
        ) VALUES (
            'test', 'test', 1, 'fsitem', 'fsitem',
            '{}'::jsonb, null, __user_2, 'read', false
        );
    EXCEPTION WHEN check_violation THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE 'PASS: ra_path_or_id constraint rejects empty id + null path';
    ELSE
        RAISE EXCEPTION 'FAIL: Check constraint not enforced';
    END IF;
END $$;
