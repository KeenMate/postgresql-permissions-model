set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 46: Create new invitation templates with actions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __tmpl_a_exists  boolean;
    __tmpl_b_exists  boolean;
BEGIN
    RAISE NOTICE 'TEST 46: ensure_invitation_templates - create new templates with actions';

    SELECT count(*) INTO __returned
    FROM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[
            {
                "code": "ef_invite_user",
                "title": "Invite User",
                "description": "Basic user invitation",
                "default_message": "Welcome!",
                "actions": [
                    {"action_type_code": "add_tenant_user", "phase_code": "on_accept", "condition_code": "user_not_in_tenant", "sequence": 0}
                ]
            },
            {
                "code": "ef_invite_admin",
                "title": "Invite Admin",
                "description": "Admin invitation with perm set",
                "default_message": "Welcome admin!",
                "actions": [
                    {"action_type_code": "add_tenant_user", "phase_code": "on_accept", "condition_code": "user_not_in_tenant", "sequence": 0},
                    {"action_type_code": "assign_perm_set", "phase_code": "on_accept", "sequence": 1, "payload_template": {"perm_set_code": "viewer"}}
                ]
            }
        ]'::jsonb,
        1,
        'ef_test'
    );

    SELECT
        exists(SELECT 1 FROM auth.invitation_template WHERE code = 'ef_invite_user' AND tenant_id = 1),
        exists(SELECT 1 FROM auth.invitation_template WHERE code = 'ef_invite_admin' AND tenant_id = 1)
    INTO __tmpl_a_exists, __tmpl_b_exists;

    IF __returned = 2 AND __tmpl_a_exists AND __tmpl_b_exists THEN
        RAISE NOTICE '  PASS: Created 2 templates (returned=%, user=%, admin=%)', __returned, __tmpl_a_exists, __tmpl_b_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Template creation failed (returned=%, user=%, admin=%)', __returned, __tmpl_a_exists, __tmpl_b_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 47: Actions were created correctly
-- ============================================================================
DO $$
DECLARE
    __user_actions   int;
    __admin_actions  int;
BEGIN
    RAISE NOTICE 'TEST 47: ensure_invitation_templates - actions created correctly';

    SELECT count(*) INTO __user_actions
    FROM auth.invitation_template_action ita
    INNER JOIN auth.invitation_template it ON it.template_id = ita.template_id
    WHERE it.code = 'ef_invite_user' AND it.tenant_id = 1;

    SELECT count(*) INTO __admin_actions
    FROM auth.invitation_template_action ita
    INNER JOIN auth.invitation_template it ON it.template_id = ita.template_id
    WHERE it.code = 'ef_invite_admin' AND it.tenant_id = 1;

    IF __user_actions = 1 AND __admin_actions = 2 THEN
        RAISE NOTICE '  PASS: Actions correct (user=%, admin=%)', __user_actions, __admin_actions;
    ELSE
        RAISE EXCEPTION '  FAIL: Actions wrong (user=%, admin=%)', __user_actions, __admin_actions;
    END IF;
END $$;

-- ============================================================================
-- TEST 48: Idempotent (no duplicates on re-call)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
    __returned       int;
BEGIN
    RAISE NOTICE 'TEST 48: ensure_invitation_templates - idempotent (no duplicates on re-call)';

    SELECT count(*) INTO __count_before
    FROM auth.invitation_template WHERE code IN ('ef_invite_user', 'ef_invite_admin') AND tenant_id = 1;

    SELECT count(*) INTO __returned
    FROM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[
            {"code": "ef_invite_user", "title": "Invite User"},
            {"code": "ef_invite_admin", "title": "Invite Admin"}
        ]'::jsonb,
        1,
        'ef_test'
    );

    SELECT count(*) INTO __count_after
    FROM auth.invitation_template WHERE code IN ('ef_invite_user', 'ef_invite_admin') AND tenant_id = 1;

    IF __count_before = __count_after AND __returned = 2 THEN
        RAISE NOTICE '  PASS: Idempotent (before=%, after=%, returned=%)', __count_before, __count_after, __returned;
    ELSE
        RAISE EXCEPTION '  FAIL: Not idempotent (before=%, after=%, returned=%)', __count_before, __count_after, __returned;
    END IF;
END $$;

-- ============================================================================
-- TEST 49: Mix of existing and new templates
-- ============================================================================
DO $$
DECLARE
    __user_id         bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id  text   := current_setting('test_ef.correlation_id');
    __returned        int;
    __new_exists      boolean;
BEGIN
    RAISE NOTICE 'TEST 49: ensure_invitation_templates - mix of existing and new';

    SELECT count(*) INTO __returned
    FROM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[
            {"code": "ef_invite_user", "title": "Invite User"},
            {"code": "ef_invite_manager", "title": "Invite Manager", "default_message": "Welcome manager!"}
        ]'::jsonb,
        1,
        'ef_test'
    );

    SELECT exists(SELECT 1 FROM auth.invitation_template WHERE code = 'ef_invite_manager' AND tenant_id = 1)
    INTO __new_exists;

    IF __returned = 2 AND __new_exists THEN
        RAISE NOTICE '  PASS: Mix of existing+new (returned=%, new=%)', __returned, __new_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Mix failed (returned=%, new=%)', __returned, __new_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 50: Template without actions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __action_count   int;
BEGIN
    RAISE NOTICE 'TEST 50: ensure_invitation_templates - template without actions';

    SELECT count(*) INTO __returned
    FROM auth.ensure_invitation_templates(
        'test_ef', __user_id, __correlation_id,
        '[{"code": "ef_no_actions", "title": "No Actions Template"}]'::jsonb,
        1,
        'ef_test'
    );

    SELECT count(*) INTO __action_count
    FROM auth.invitation_template_action ita
    INNER JOIN auth.invitation_template it ON it.template_id = ita.template_id
    WHERE it.code = 'ef_no_actions' AND it.tenant_id = 1;

    IF __returned = 1 AND __action_count = 0 THEN
        RAISE NOTICE '  PASS: Template created with no actions (returned=%, actions=%)', __returned, __action_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected result (returned=%, actions=%)', __returned, __action_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 51: Source stored on created templates
-- ============================================================================
DO $$
DECLARE
    __source text;
BEGIN
    RAISE NOTICE 'TEST 51: ensure_invitation_templates - source stored on template';

    SELECT it.source INTO __source
    FROM auth.invitation_template it
    WHERE it.code = 'ef_invite_user' AND it.tenant_id = 1;

    IF __source = 'ef_test' THEN
        RAISE NOTICE '  PASS: Source stored correctly (source=%)', __source;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected source=ef_test, got %', __source;
    END IF;
END $$;
