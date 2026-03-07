set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 7: Template-based invitation — create template, invite from template
-- ============================================================================
DO $$
DECLARE
    __inviter_id bigint;
    __target_id bigint;
    __group_id integer;
    __tmpl_id integer;
    __inv_id bigint;
    __inv_uuid uuid;
    __on_create jsonb;
    __sms_action_id bigint;
    __sms_payload jsonb;
    __count integer;
    __status text;
BEGIN
    RAISE NOTICE 'TEST 7: Template-based invitation flow';

    SELECT val FROM _inv_test_data WHERE key = 'inviter_id' INTO __inviter_id;
    SELECT val FROM _inv_test_data WHERE key = 'target_id' INTO __target_id;
    SELECT val FROM _inv_test_data WHERE key = 'group_id' INTO __group_id;

    -- Create a reusable template
    SELECT __template_id
    FROM auth.create_invitation_template(
        'test_inv', __inviter_id, 'inv-corr-tmpl-1', 1,
        'sms_group_invite',
        'SMS Group Invitation',
        _description := 'Invite user to a group via SMS',
        _default_message := 'You have been invited!',
        _actions := ('[
            {"action_type_code": "send_sms_invite",  "phase_code": "on_create", "sequence": 0, "is_required": false},
            {"action_type_code": "add_tenant_user",   "phase_code": "on_accept", "sequence": 0,
             "condition_code": "user_not_in_tenant"},
            {"action_type_code": "add_group_member",  "phase_code": "on_accept", "sequence": 1,
             "condition_code": "user_not_in_group", "payload_template": {}},
            {"action_type_code": "notify_inviter",    "phase_code": "on_reject", "sequence": 0}
        ]')::jsonb
    ) INTO __tmpl_id;

    IF __tmpl_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Template created (id=%)', __tmpl_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Template creation returned null';
    END IF;

    -- Verify template actions were created
    SELECT count(*) FROM auth.invitation_template_action WHERE template_id = __tmpl_id INTO __count;
    IF __count = 4 THEN
        RAISE NOTICE '  PASS: 4 template actions created';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 4 template actions, got %', __count;
    END IF;

    -- Create invitation from template with dynamic payload (group_id)
    SELECT __invitation_id, __uuid, __on_create_actions
    FROM auth.create_invitation_from_template(
        'svc_app', __inviter_id, 'inv-corr-tmpl-2', 1,
        'sms_group_invite',
        '+420555666777',
        _message := 'Custom message overrides default',
        _payload_overrides := ('{"user_group_id": ' || __group_id || '}')::jsonb
    ) INTO __inv_id, __inv_uuid, __on_create;

    IF __inv_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Invitation created from template (id=%)', __inv_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Template invitation creation returned null';
    END IF;

    -- Verify template_code was stored
    SELECT count(*) FROM auth.invitation WHERE invitation_id = __inv_id AND template_code = 'sms_group_invite' INTO __count;
    IF __count = 1 THEN
        RAISE NOTICE '  PASS: template_code stored on invitation';
    ELSE
        RAISE EXCEPTION '  FAIL: template_code not stored';
    END IF;

    -- Verify the custom message overrode the template default
    SELECT count(*) FROM auth.invitation WHERE invitation_id = __inv_id AND message = 'Custom message overrides default' INTO __count;
    IF __count = 1 THEN
        RAISE NOTICE '  PASS: Custom message overrode template default';
    ELSE
        RAISE EXCEPTION '  FAIL: Message not overridden';
    END IF;

    -- Verify on_create returned the SMS action with resolved payload
    IF jsonb_array_length(__on_create) = 1 THEN
        __sms_action_id := (__on_create->0->>'invitation_action_id')::bigint;
        __sms_payload := __on_create->0->'payload';

        IF __sms_payload->>'mobile_phone' = '+420555666777' THEN
            RAISE NOTICE '  PASS: SMS payload mobile_phone resolved from template';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected mobile_phone=+420555666777, got %', __sms_payload->>'mobile_phone';
        END IF;

        IF __sms_payload->>'message' = 'Custom message overrides default' THEN
            RAISE NOTICE '  PASS: SMS payload message = custom override';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected custom message, got %', __sms_payload->>'message';
        END IF;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 on_create action, got %', jsonb_array_length(__on_create);
    END IF;

    -- Complete the SMS action
    PERFORM unsecure.complete_invitation_action('svc_app', __inviter_id, 'inv-corr-tmpl-3', __sms_action_id);

    -- Verify the group_id was merged into the add_group_member action payload
    SELECT count(*) FROM auth.invitation_action
    WHERE invitation_id = __inv_id
      AND action_type_code = 'add_group_member'
      AND (payload->>'user_group_id')::integer = __group_id
    INTO __count;
    IF __count = 1 THEN
        RAISE NOTICE '  PASS: user_group_id merged into add_group_member payload from overrides';
    ELSE
        RAISE EXCEPTION '  FAIL: user_group_id not found in add_group_member payload';
    END IF;

    INSERT INTO _inv_test_data VALUES ('tmpl_inv_id', __inv_id) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    INSERT INTO _inv_test_data VALUES ('tmpl_id', __tmpl_id) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;

    RAISE NOTICE 'TEST 7: Done';
    RAISE NOTICE '';
END $$;
