set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 2: Backend simulates creating invitation with on_create SMS action,
--          receives the action back, sends SMS, reports success
-- ============================================================================
DO $$
DECLARE
    __inviter_id bigint;
    __inv_id bigint;
    __inv_uuid uuid;
    __on_create jsonb;
    __action_id bigint;
    __action_payload jsonb;
    __count integer;
    __status text;
BEGIN
    RAISE NOTICE 'TEST 2: Backend action success flow — send_sms_invite';

    SELECT val FROM _inv_test_data WHERE key = 'inviter_id' INTO __inviter_id;

    -- Backend creates invitation with on_create SMS action
    SELECT __invitation_id, __uuid, __on_create_actions
    FROM auth.create_invitation(
        'svc_app', __inviter_id, 'inv-corr-sms-1', 1,
        '+420777123456',
        _actions := '[
            {"action_type_code": "send_sms_invite", "phase_code": "on_create", "sequence": 0}
        ]'::jsonb,
        _message := 'Join our team!'
    ) INTO __inv_id, __inv_uuid, __on_create;

    IF __inv_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Invitation created (id=%)', __inv_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Invitation creation returned null';
    END IF;

    -- Verify on_create returned the SMS action for backend to handle
    IF jsonb_array_length(__on_create) = 1 THEN
        RAISE NOTICE '  PASS: 1 on_create action returned to backend';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 on_create action, got %', jsonb_array_length(__on_create);
    END IF;

    -- Extract action details
    __action_id := (__on_create->0->>'invitation_action_id')::bigint;
    __action_payload := __on_create->0->'payload';

    -- Verify payload was resolved from schema
    IF __action_payload->>'mobile_phone' = '+420777123456' THEN
        RAISE NOTICE '  PASS: Payload mobile_phone resolved from target_email';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected mobile_phone=+420777123456, got %', __action_payload->>'mobile_phone';
    END IF;

    IF __action_payload->>'invitation_uuid' = __inv_uuid::text THEN
        RAISE NOTICE '  PASS: Payload invitation_uuid resolved';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected invitation_uuid=%, got %', __inv_uuid, __action_payload->>'invitation_uuid';
    END IF;

    IF __action_payload->>'message' = 'Join our team!' THEN
        RAISE NOTICE '  PASS: Payload message resolved';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected message=Join our team!, got %', __action_payload->>'message';
    END IF;

    -- Verify action is in processing state
    SELECT status_code FROM auth.invitation_action WHERE invitation_action_id = __action_id INTO __status;
    IF __status = 'processing' THEN
        RAISE NOTICE '  PASS: Action status is processing';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected processing, got %', __status;
    END IF;

    -- Backend "sends the SMS" ... then reports success
    PERFORM unsecure.complete_invitation_action('svc_app', __inviter_id, 'inv-corr-sms-2', __action_id,
        _result_data := '{"sms_provider_id": "msg-abc-123"}'::jsonb);

    -- Verify action is completed with result data
    SELECT status_code FROM auth.invitation_action WHERE invitation_action_id = __action_id INTO __status;
    IF __status = 'completed' THEN
        RAISE NOTICE '  PASS: Action status is completed after backend reports success';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected completed, got %', __status;
    END IF;

    -- Verify result_data was stored
    SELECT count(*) FROM auth.invitation_action
    WHERE invitation_action_id = __action_id
      AND result_data->>'sms_provider_id' = 'msg-abc-123'
    INTO __count;
    IF __count = 1 THEN
        RAISE NOTICE '  PASS: Result data stored correctly';
    ELSE
        RAISE EXCEPTION '  FAIL: Result data not found';
    END IF;

    -- Invitation should still be pending (no on_accept actions processed yet, invitation was never accepted)
    SELECT status_code FROM auth.invitation WHERE invitation_id = __inv_id INTO __status;
    IF __status = 'pending' THEN
        RAISE NOTICE '  PASS: Invitation still pending (waiting for accept)';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected pending, got %', __status;
    END IF;

    INSERT INTO _inv_test_data VALUES ('inv_id_sms', __inv_id) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    INSERT INTO _inv_test_data VALUES ('action_id_sms', __action_id) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;

    RAISE NOTICE 'TEST 2: Done';
    RAISE NOTICE '';
END $$;
