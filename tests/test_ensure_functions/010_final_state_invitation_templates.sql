set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 52: _is_final_state=true with null source raises error
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
BEGIN
    RAISE NOTICE 'TEST 52: ensure_invitation_templates - final_state with null source raises error';

    BEGIN
        PERFORM auth.ensure_invitation_templates(
            'test_ef', __user_id, __correlation_id,
            '[{"code": "dummy_tmpl", "title": "Dummy"}]'::jsonb,
            1,      -- _tenant_id
            null,   -- _source = null
            true    -- _is_final_state = true
        );
        RAISE EXCEPTION '  FAIL: Expected error was not thrown for null source with _is_final_state=true';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%_source is required%' THEN
                RAISE NOTICE '  PASS: Correctly raised error for null source (sqlerrm=%)', SQLERRM;
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 53: Default does NOT remove templates
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
BEGIN
    RAISE NOTICE 'TEST 53: ensure_invitation_templates - default does NOT remove templates';

    -- Create 2 templates with source 'fs_tmpl_test'
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[
            {"code": "fs_tmpl_alpha", "title": "FS Alpha"},
            {"code": "fs_tmpl_beta", "title": "FS Beta"}
        ]'::jsonb,
        1,
        'fs_tmpl_test'
    );

    SELECT count(*) INTO __count_before
    FROM auth.invitation_template WHERE source = 'fs_tmpl_test' AND tenant_id = 1;

    -- Call with only 1 template, _is_final_state defaults to false
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{"code": "fs_tmpl_alpha", "title": "FS Alpha"}]'::jsonb,
        1,
        'fs_tmpl_test'
    );

    SELECT count(*) INTO __count_after
    FROM auth.invitation_template WHERE source = 'fs_tmpl_test' AND tenant_id = 1;

    IF __count_before = __count_after AND __count_after = 2 THEN
        RAISE NOTICE '  PASS: Default mode did not remove templates (before=%, after=%)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Default mode should not remove (before=%, after=%)', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 54: _is_final_state=true removes unlisted same-source templates
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count          int;
    __alpha_exists   boolean;
    __beta_exists    boolean;
BEGIN
    RAISE NOTICE 'TEST 54: ensure_invitation_templates - final_state removes unlisted same-source templates';

    -- Call with only Alpha, final_state=true => Beta should be removed
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{"code": "fs_tmpl_alpha", "title": "FS Alpha"}]'::jsonb,
        1,
        'fs_tmpl_test',
        true  -- _is_final_state
    );

    SELECT count(*) INTO __count FROM auth.invitation_template WHERE source = 'fs_tmpl_test' AND tenant_id = 1;

    SELECT
        exists(SELECT 1 FROM auth.invitation_template WHERE code = 'fs_tmpl_alpha' AND tenant_id = 1),
        exists(SELECT 1 FROM auth.invitation_template WHERE code = 'fs_tmpl_beta' AND tenant_id = 1)
    INTO __alpha_exists, __beta_exists;

    IF __count = 1 AND __alpha_exists AND NOT __beta_exists THEN
        RAISE NOTICE '  PASS: Final state removed Beta (count=%, alpha=%, beta=%)', __count, __alpha_exists, __beta_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Final state removal wrong (count=%, alpha=%, beta=%)', __count, __alpha_exists, __beta_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 55: _is_final_state=true does NOT remove different-source templates
-- ============================================================================
DO $$
DECLARE
    __user_id          bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id   text   := current_setting('test_ef.correlation_id');
    __count_other      int;
BEGIN
    RAISE NOTICE 'TEST 55: ensure_invitation_templates - final_state does NOT remove different source';

    -- Create a template with a different source
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{"code": "other_src_tmpl", "title": "Other Source"}]'::jsonb,
        1,
        'other_tmpl_source'
    );

    -- Run final state for 'fs_tmpl_test' source
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{"code": "fs_tmpl_alpha", "title": "FS Alpha"}]'::jsonb,
        1,
        'fs_tmpl_test',
        true
    );

    SELECT count(*) INTO __count_other
    FROM auth.invitation_template WHERE source = 'other_tmpl_source' AND tenant_id = 1;

    IF __count_other = 1 THEN
        RAISE NOTICE '  PASS: Different source template untouched (count=%)', __count_other;
    ELSE
        RAISE EXCEPTION '  FAIL: Different source template affected (count=%)', __count_other;
    END IF;
END $$;

-- ============================================================================
-- TEST 56: _is_final_state=true cascades to template actions
-- ============================================================================
DO $$
DECLARE
    __user_id          bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id   text   := current_setting('test_ef.correlation_id');
    __doomed_id        int;
    __action_count     int;
    __tmpl_exists      boolean;
BEGIN
    RAISE NOTICE 'TEST 56: ensure_invitation_templates - final_state cascades to template actions';

    -- Create a doomed template with actions
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{
            "code": "fs_doomed_tmpl",
            "title": "Doomed Template",
            "actions": [
                {"action_type_code": "add_tenant_user", "phase_code": "on_accept", "sequence": 0},
                {"action_type_code": "notify_inviter", "phase_code": "on_reject", "sequence": 0}
            ]
        }]'::jsonb,
        1,
        'fs_tmpl_test'
    );

    SELECT template_id INTO __doomed_id
    FROM auth.invitation_template WHERE code = 'fs_doomed_tmpl' AND tenant_id = 1;

    -- Verify actions exist
    SELECT count(*) INTO __action_count
    FROM auth.invitation_template_action WHERE template_id = __doomed_id;

    IF __action_count <> 2 THEN
        RAISE EXCEPTION '  FAIL: Setup - expected 2 actions, got %', __action_count;
    END IF;

    -- Remove doomed template via final_state
    PERFORM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{"code": "fs_tmpl_alpha", "title": "FS Alpha"}]'::jsonb,
        1,
        'fs_tmpl_test',
        true
    );

    SELECT exists(SELECT 1 FROM auth.invitation_template WHERE template_id = __doomed_id)
    INTO __tmpl_exists;

    SELECT count(*) INTO __action_count
    FROM auth.invitation_template_action WHERE template_id = __doomed_id;

    IF NOT __tmpl_exists AND __action_count = 0 THEN
        RAISE NOTICE '  PASS: Template and actions removed (tmpl=%, actions=%)', __tmpl_exists, __action_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Cascade failed (tmpl=%, actions=%)', __tmpl_exists, __action_count;
    END IF;
END $$;
