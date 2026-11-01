-- Run only against an isolated database with all source-controlled migrations
-- applied. Synthetic fixtures and assertions are rolled back.
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_sqlstate(p_statement text, p_expected text)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected then return; end if;
        raise exception 'Expected SQLSTATE %, received %: %', p_expected, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected;
end;
$$;

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at) values
    ('14000000-0000-4000-8000-000000000001', 'owner@example.test', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000002', 'guardian@example.test', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000003', 'second@example.test', '2026-01-01Z');

insert into public.users (id, created_at) values
    ('14000000-0000-4000-8000-000000000011', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000012', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000013', '2026-01-01Z');

insert into public.user_authentication_identities (id, user_id, provider_subject) values
    ('14000000-0000-4000-8000-000000000021', '14000000-0000-4000-8000-000000000011', '14000000-0000-4000-8000-000000000001'),
    ('14000000-0000-4000-8000-000000000022', '14000000-0000-4000-8000-000000000012', '14000000-0000-4000-8000-000000000002'),
    ('14000000-0000-4000-8000-000000000023', '14000000-0000-4000-8000-000000000013', '14000000-0000-4000-8000-000000000003');

insert into auth.sessions (id, user_id, created_at, updated_at) values (
    '14000000-0000-4000-8000-000000000031',
    '14000000-0000-4000-8000-000000000002',
    '2026-09-01Z', '2026-09-01Z'
);

insert into public.veterinary_organizations (id, display_name)
values ('14000000-0000-4000-8000-000000000041', 'Slice 14 Organization');

insert into public.clinics (id, organization_id)
values ('14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000041');

insert into public.organization_memberships (
    id, organization_id, user_id, effective_start
) values (
    '14000000-0000-4000-8000-000000000043',
    '14000000-0000-4000-8000-000000000041',
    '14000000-0000-4000-8000-000000000011', '2026-01-01Z'
);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, effective_start,
    granted_by_user_id
) values (
    '14000000-0000-4000-8000-000000000044',
    '14000000-0000-4000-8000-000000000043', 'OWNER', 'ORGANIZATION',
    '2026-01-01Z', '14000000-0000-4000-8000-000000000011'
);

insert into public.pets (id, name, species, created_at)
values
    ('14000000-0000-4000-8000-000000000051', 'Luna', 'canine', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000052', 'Sol', 'feline', '2026-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start) values
    ('14000000-0000-4000-8000-000000000061', '14000000-0000-4000-8000-000000000012', '14000000-0000-4000-8000-000000000051', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000062', '14000000-0000-4000-8000-000000000013', '14000000-0000-4000-8000-000000000051', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000063', '14000000-0000-4000-8000-000000000012', '14000000-0000-4000-8000-000000000052', '2026-01-01Z');

-- Synthetic legacy pre-cutover record: no Communication is reconstructed.
insert into public.organization_invitations (
    id, organization_id, inviting_user_id, recipient_email, created_at,
    expires_at, acceptance_secret_digest
) values (
    '14000000-0000-4000-8000-000000000071',
    '14000000-0000-4000-8000-000000000041',
    '14000000-0000-4000-8000-000000000011', 'legacy@example.test',
    '2026-08-01Z', '2030-01-01Z', decode(repeat('11', 32), 'hex')
);
insert into public.organization_invitation_responsibilities (
    id, invitation_id, responsibility, scope_type
) values (
    '14000000-0000-4000-8000-000000000072',
    '14000000-0000-4000-8000-000000000071', 'ADMINISTRATOR', 'ORGANIZATION'
);

set local session_replication_role = origin;

select pg_temp.assert_true(
    not has_function_privilege(
        'service_role',
        'public.create_scoped_organization_invitation(uuid,uuid,uuid,text,jsonb,timestamptz,bytea)',
        'EXECUTE'
    ),
    'Legacy Organization Invitation creation must be disabled at cutover'
);
select pg_temp.assert_true(
    not has_function_privilege(
        'service_role',
        'public.create_guardianship_invitation(uuid,uuid,uuid,uuid,text,timestamptz,bytea)',
        'EXECUTE'
    ),
    'Legacy Guardianship Invitation creation must be disabled at cutover'
);
select pg_temp.assert_true(
    not exists (
        select 1 from public.transactional_communications
        where organization_invitation_id = '14000000-0000-4000-8000-000000000071'
    ),
    'Legacy pending Invitations must not be backfilled'
);

select pg_temp.assert_sqlstate(
    $statement$
    insert into public.transactional_communications (
        communication_type, recipient_email, organization_invitation_id,
        secret_envelope_version, secret_key_version, secret_algorithm,
        secret_aad_context, secret_nonce, secret_ciphertext
    ) values (
        'ORGANIZATION_INVITATION', 'different@example.test',
        '14000000-0000-4000-8000-000000000071', 1, 1,
        'AES-256-GCM', 'petcare.invitation.organization.v1',
        decode(repeat('12', 12), 'hex'), decode(repeat('34', 32), 'hex')
    )
    $statement$,
    '23514'
);

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        insert into public.organization_invitations (
            id, organization_id, inviting_user_id, recipient_email,
            created_at, expires_at, acceptance_secret_digest
        ) values (
            '14000000-0000-4000-8000-000000000073',
            '14000000-0000-4000-8000-000000000041',
            '14000000-0000-4000-8000-000000000011',
            'direct-org@example.test', clock_timestamp(),
            clock_timestamp() + interval '1 day',
            decode(repeat('18', 32), 'hex')
        );
        execute 'set constraints organization_invitations_require_communication immediate';
    exception when others then
        if sqlstate <> '23514' then raise; end if;
        rejected := true;
    end;
    perform pg_temp.assert_true(
        rejected,
        'A direct new Organization Invitation without Communication must fail at commit enforcement'
    );

    rejected := false;
    begin
        insert into public.guardianship_invitations (
            id, pet_id, inviting_guardianship_id, recipient_email,
            created_at, expires_at, acceptance_secret_digest
        ) values (
            '14000000-0000-4000-8000-000000000074',
            '14000000-0000-4000-8000-000000000051',
            '14000000-0000-4000-8000-000000000061',
            'direct-guardian@example.test', clock_timestamp(),
            clock_timestamp() + interval '1 day',
            decode(repeat('19', 32), 'hex')
        );
        execute 'set constraints guardianship_invitations_require_communication immediate';
    exception when others then
        if sqlstate <> '23514' then raise; end if;
        rejected := true;
    end;
    perform pg_temp.assert_true(
        rejected,
        'A direct new Guardianship Invitation without Communication must fail at commit enforcement'
    );
end;
$$;

select public.create_scoped_organization_invitation_with_communication(
    '14000000-0000-4000-8000-000000000001',
    '14000000-0000-4000-8000-000000000041', null,
    'new-org@example.test',
    '[{"responsibility":"ADMINISTRATOR","scope_type":"ORGANIZATION","clinic_id":null}]'::jsonb,
    '2030-01-01Z', decode(repeat('22', 32), 'hex'), 1,
    decode(repeat('33', 12), 'hex'), decode(repeat('44', 32), 'hex')
);

select public.create_guardianship_invitation_with_communication(
    '14000000-0000-4000-8000-000000000002',
    '14000000-0000-4000-8000-000000000051',
    '14000000-0000-4000-8000-000000000061', null,
    'new-guardian@example.test', '2030-01-01Z',
    decode(repeat('55', 32), 'hex'), 1,
    decode(repeat('66', 12), 'hex'), decode(repeat('77', 32), 'hex')
);

set constraints organization_invitations_require_communication immediate;
set constraints guardianship_invitations_require_communication immediate;

select pg_temp.assert_true(
    (select count(*) = 2 from public.transactional_communications
     where communication_type in ('ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION')),
    'Every supported new Invitation must atomically establish one Communication'
);
select pg_temp.assert_true(
    not exists (
        select 1 from public.transactional_communications
        where communication_type in ('ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION')
          and (secret_algorithm <> 'AES-256-GCM' or secret_envelope_version <> 1)
    ),
    'Invitation Communications must contain a versioned AES-GCM envelope'
);
select pg_temp.assert_true(
    not exists (
        select 1
        from public.transactional_communications as communication
        left join public.organization_invitations as organization_invitation
          on organization_invitation.id = communication.organization_invitation_id
        left join public.guardianship_invitations as guardianship_invitation
          on guardianship_invitation.id = communication.guardianship_invitation_id
        where communication.communication_type in (
            'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
        )
          and communication.secret_aad_context is distinct from case
              when communication.communication_type = 'ORGANIZATION_INVITATION'
                  then public.build_invitation_secret_aad(
                      'organization', organization_invitation.recipient_email,
                      organization_invitation.expires_at,
                      organization_invitation.acceptance_secret_digest
                  )
              else public.build_invitation_secret_aad(
                      'guardianship', guardianship_invitation.recipient_email,
                      guardianship_invitation.expires_at,
                      guardianship_invitation.acceptance_secret_digest
                  )
          end
    ),
    'Invitation AAD must be derived from DB-verifiable authorization context'
);
select pg_temp.assert_true(
    (select count(distinct secret_aad_context) = 2
     from public.transactional_communications
     where communication_type in (
         'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
     )),
    'Distinct valid Invitations must not share a transplantable AAD context'
);
select pg_temp.assert_true(
    exists (
        select 1 from public.transactional_communications
        where communication_type = 'ORGANIZATION_INVITATION'
          and secret_aad_context =
              'petcare.invitation.organization.v1|recipient_email_hex='
              || '6e65772d6f7267406578616d706c652e74657374'
              || '|expires_at_ms=1893456000000|acceptance_digest_hex='
              || repeat('22', 32)
    ),
    'Database and Edge must share the exact Invitation AAD serialization'
);

select public.upsert_session_push_registration(
    '14000000-0000-4000-8000-000000000002',
    '14000000-0000-4000-8000-000000000031',
    '14000000-0000-4000-8000-000000000081',
    'ExponentPushToken[slice14-test]', 'IOS', 'com.petcare.mobile'
);

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit,
    lifecycle_state, created_at
) values (
    '14000000-0000-4000-8000-000000000091',
    '14000000-0000-4000-8000-000000000051',
    '14000000-0000-4000-8000-000000000042',
    '14000000-0000-4000-8000-000000000012', 'Routine visit',
    'REQUESTED', '2026-09-01T10:00:00Z'
);

insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, created_at
) values (
    '14000000-0000-4000-8000-000000000092',
    '14000000-0000-4000-8000-000000000091', 1, 'REQUESTED',
    '2035-01-02T10:00:00Z', '2035-01-02T10:30:00Z', 'Europe/Madrid',
    '14000000-0000-4000-8000-000000000012', '2026-09-01T10:00:00Z'
);

select pg_temp.assert_true(
    (select count(*) = 2 from public.transactional_communications
     where communication_type = 'APPOINTMENT_REQUESTED'
       and appointment_id = '14000000-0000-4000-8000-000000000091'),
    'Initial Appointment request must notify all current Guardians exactly once'
);

insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, created_at
) values (
    '14000000-0000-4000-8000-000000000093',
    '14000000-0000-4000-8000-000000000091', 2, 'CONFIRMED',
    '2035-01-02T10:00:00Z', '2035-01-02T10:30:00Z', 'Europe/Madrid',
    '14000000-0000-4000-8000-000000000011', '2026-09-01T10:05:00Z'
);
insert into public.appointment_lifecycle_events (
    id, appointment_id, from_state, to_state, actor_user_id, actor_context,
    effective_at, recorded_at
) values (
    '14000000-0000-4000-8000-000000000094',
    '14000000-0000-4000-8000-000000000091', 'REQUESTED', 'CONFIRMED',
    '14000000-0000-4000-8000-000000000011', 'CLINIC',
    '2026-09-01T10:05:00Z', '2026-09-01T10:05:00Z'
);
update public.appointments set lifecycle_state = 'CONFIRMED'
where id = '14000000-0000-4000-8000-000000000091';

select pg_temp.assert_true(
    (select count(*) = 2 from public.transactional_communications
     where communication_type = 'APPOINTMENT_CONFIRMED'
       and appointment_lifecycle_event_id = '14000000-0000-4000-8000-000000000094'),
    'Lifecycle trigger must create one typed Communication per current Guardian'
);

select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-01-01T10:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 2,
    'The 24-hour reminder point must resolve current Guardians'
);
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-01-01T10:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 0,
    'Reminder establishment must be logically idempotent'
);

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit,
    lifecycle_state, created_at
) values (
    '14000000-0000-4000-8000-0000000000a1',
    '14000000-0000-4000-8000-000000000052',
    '14000000-0000-4000-8000-000000000042',
    '14000000-0000-4000-8000-000000000012', 'Routine visit',
    'CONFIRMED', '2026-09-01T11:00:00Z'
);
insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, created_at
) values (
    '14000000-0000-4000-8000-0000000000a2',
    '14000000-0000-4000-8000-0000000000a1', 1, 'CONFIRMED',
    '2035-02-02T10:00:00Z', '2035-02-02T10:30:00Z', 'Europe/Madrid',
    '14000000-0000-4000-8000-000000000011', '2026-09-01T11:00:00Z'
);
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-02-01T16:00:01Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 0,
    'A reminder missed by more than the six-hour catch-up window must not be created'
);

select public.materialize_communication_delivery_jobs();
select pg_temp.assert_true(
    exists (
        select 1 from public.communication_delivery_jobs
        where communication_id in (
            select id from public.transactional_communications
            where appointment_id = '14000000-0000-4000-8000-000000000091'
        ) and channel = 'EMAIL' and state = 'READY'
    ),
    'Appointment email baseline must materialize independently'
);
select pg_temp.assert_true(
    exists (
        select 1 from public.communication_delivery_jobs
        where communication_id in (
            select id from public.transactional_communications
            where appointment_id = '14000000-0000-4000-8000-000000000091'
              and recipient_user_id = '14000000-0000-4000-8000-000000000012'
        ) and channel = 'PUSH' and state = 'READY'
    ),
    'An eligible live session may independently materialize supplementary push'
);

do $$
declare
    initial_registration_id uuid;
    late_registration_id uuid;
    context_job_id uuid;
    context_lease_id uuid := '14000000-0000-4000-8000-000000000083';
    context jsonb;
    retry_job_id uuid;
    retry_communication_id uuid;
    retry_lease_id uuid := '14000000-0000-4000-8000-000000000084';
    frozen_at timestamptz;
    job_count integer;
begin
    select registration.id into initial_registration_id
    from public.push_registrations as registration
    where registration.device_installation_id =
        '14000000-0000-4000-8000-000000000081';

    perform pg_temp.assert_true(
        exists (
            select 1 from public.communication_delivery_jobs
            where push_registration_id = initial_registration_id
              and destination_snapshot ~ '^sha256:[0-9a-f]{64}$'
        ),
        'The initial Push Registration must receive digest-addressed Jobs'
    );
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.communication_delivery_jobs
            where destination_snapshot like '%ExponentPushToken[%'
        ),
        'Delivery Jobs must not retain raw Push provider tokens'
    );

    select job.id into context_job_id
    from public.communication_delivery_jobs as job
    where job.push_registration_id = initial_registration_id
      and job.state = 'READY'
    order by job.id
    limit 1;
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = context_lease_id,
        lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = context_job_id;
    context := public.get_communication_delivery_context(
        context_job_id, context_lease_id
    );
    perform pg_temp.assert_true(
        context ->> 'recipient' = 'ExponentPushToken[slice14-test]',
        'Trusted imminent Push context must load the raw token from its live Registration'
    );
    perform pg_temp.assert_true(
        context ->> 'pet_id' = '14000000-0000-4000-8000-000000000051',
        'Appointment delivery context must expose pet_id at zero extra cost (Milestone H push-navigation correction)'
    );
    perform public.mark_communication_delivery_submission_started(
        context_job_id, context_lease_id
    );
    perform public.complete_communication_delivery_job(
        context_job_id, context_lease_id, 'PERMANENT_FAILURE', null,
        'test_closed', 'TEST_CONTEXT_CLOSED', 60
    );
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.communication_delivery_attempts
            where delivery_job_id = context_job_id
              and destination_snapshot like '%ExponentPushToken[%'
        ) and exists (
            select 1 from public.communication_delivery_attempts
            where delivery_job_id = context_job_id
              and destination_snapshot ~ '^sha256:[0-9a-f]{64}$'
        ),
        'Delivery Attempt history must retain only the Push token digest reference'
    );

    select communication.id, communication.fanout_materialized_at
    into retry_communication_id, frozen_at
    from public.transactional_communications as communication
    where communication.communication_type = 'ORGANIZATION_INVITATION';
    select job.id into retry_job_id
    from public.communication_delivery_jobs as job
    where job.communication_id = retry_communication_id
      and job.channel = 'EMAIL' and job.state = 'READY';
    select count(*) into job_count from public.communication_delivery_jobs
    where communication_id = retry_communication_id;
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = retry_lease_id,
        lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = retry_job_id;
    perform public.mark_communication_delivery_submission_started(
        retry_job_id, retry_lease_id
    );
    perform public.complete_communication_delivery_job(
        retry_job_id, retry_lease_id, 'RETRYABLE', null, null,
        'SAFE_PRE_ACCEPTANCE_REJECTION', 86400
    );
    perform public.materialize_communication_delivery_jobs();
    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        (select count(*) = job_count from public.communication_delivery_jobs
         where communication_id = retry_communication_id)
        and (select fanout_materialized_at = frozen_at
             from public.transactional_communications
             where id = retry_communication_id),
        'Repeated materialization and retries must not rematerialize frozen fanout'
    );

    insert into auth.sessions (id, user_id, created_at, updated_at) values (
        '14000000-0000-4000-8000-000000000032',
        '14000000-0000-4000-8000-000000000002',
        clock_timestamp(), clock_timestamp()
    );
    late_registration_id := public.upsert_session_push_registration(
        '14000000-0000-4000-8000-000000000002',
        '14000000-0000-4000-8000-000000000032',
        '14000000-0000-4000-8000-000000000082',
        'ExponentPushToken[registered-after-fanout]', 'ANDROID',
        'com.petcare.mobile.after-fanout'
    );
    perform public.materialize_communication_delivery_jobs();
    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.communication_delivery_jobs
            where push_registration_id = late_registration_id
        ),
        'A Registration established after fanout must receive no historical Job'
    );

    update auth.users set email = 'after-fanout@example.test'
    where id = '14000000-0000-4000-8000-000000000002';
    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.communication_delivery_jobs
            where destination_snapshot = 'after-fanout@example.test'
        ),
        'An email address established after fanout must receive no historical Job'
    );
    update auth.users set email = 'guardian@example.test'
    where id = '14000000-0000-4000-8000-000000000002';
end;
$$;

delete from auth.sessions where id = '14000000-0000-4000-8000-000000000031';
select public.materialize_communication_delivery_jobs();
select pg_temp.assert_true(
    not exists (
        select 1 from public.communication_delivery_jobs
        where push_registration_id in (
            select id from public.push_registrations
            where auth_session_id = '14000000-0000-4000-8000-000000000031'
        ) and state in ('READY', 'CLAIMED', 'RETRYABLE')
    ),
    'A pre-recovery session row that no longer exists must fail push eligibility'
);

do $$
declare
    invitation_communication_id uuid;
    registration_id uuid;
    reclaimed_lease uuid;
    reclaimed_key text;
    start_state text;
    expo_started_at timestamptz := clock_timestamp() - interval '2 hours';
    pre_submit_job_id uuid := '14000000-0000-4000-8000-0000000000b3';
    resend_started_job_id uuid := '14000000-0000-4000-8000-0000000000b4';
    expo_started_job_id uuid := '14000000-0000-4000-8000-0000000000b5';
begin
    select communication.id into invitation_communication_id
    from public.transactional_communications as communication
    where communication.communication_type = 'GUARDIANSHIP_INVITATION';

    select registration.id into registration_id
    from public.push_registrations as registration
    where registration.device_installation_id =
        '14000000-0000-4000-8000-000000000081';

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, state, next_attempt_at, lease_token,
        lease_expires_at
    ) values (
        pre_submit_job_id, invitation_communication_id, 'EMAIL', 'RESEND',
        'PRE-SUBMIT-WORKER-LOSS', 'new-guardian@example.test', 'CLAIMED',
        '2000-01-01Z', '14000000-0000-4000-8000-0000000000b6',
        clock_timestamp() - interval '1 minute'
    );

    select claim.lease_token, claim.provider_idempotency_key
    into reclaimed_lease, reclaimed_key
    from public.claim_communication_delivery_jobs(1, 120) as claim
    where claim.delivery_job_id = pre_submit_job_id;

    perform pg_temp.assert_true(
        reclaimed_lease is not null
        and reclaimed_key = pre_submit_job_id::text
        and (select submission_count = 0
                    and active_submission_started_at is null
             from public.communication_delivery_jobs
             where id = pre_submit_job_id),
        'An expired pre-submission claim must be reclaimed without an Attempt'
    );
    start_state := public.mark_communication_delivery_submission_started(
        pre_submit_job_id, reclaimed_lease
    );
    perform pg_temp.assert_true(
        start_state = 'STARTED'
        and (select submission_count = 1
                    and active_submission_started_at is not null
             from public.communication_delivery_jobs
             where id = pre_submit_job_id),
        'Submission count and timestamps must advance only at provider start'
    );
    perform public.complete_communication_delivery_job(
        pre_submit_job_id, reclaimed_lease, 'RETRYABLE', null, null,
        'SAFE_PRE_ACCEPTANCE_REJECTION', 86400
    );

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, state, submission_count, next_attempt_at,
        lease_token, lease_expires_at, first_submitted_at, last_submitted_at,
        active_submission_started_at
    ) values (
        resend_started_job_id, invitation_communication_id, 'EMAIL', 'RESEND',
        'RESEND-POST-SUBMIT-WORKER-LOSS', 'new-guardian@example.test',
        'CLAIMED', 1, '2000-01-01Z',
        '14000000-0000-4000-8000-0000000000b7',
        clock_timestamp() - interval '1 minute',
        clock_timestamp() - interval '2 minutes',
        clock_timestamp() - interval '2 minutes',
        clock_timestamp() - interval '2 minutes'
    );

    select claim.lease_token, claim.provider_idempotency_key
    into reclaimed_lease, reclaimed_key
    from public.claim_communication_delivery_jobs(1, 120) as claim
    where claim.delivery_job_id = resend_started_job_id;
    perform pg_temp.assert_true(
        reclaimed_lease is not null
        and reclaimed_key = resend_started_job_id::text
        and (select submission_count = 1
                    and active_submission_started_at is null
             from public.communication_delivery_jobs
             where id = resend_started_job_id)
        and (select count(*) = 1
             from public.communication_delivery_attempts
             where delivery_job_id = resend_started_job_id
               and attempt_number = 1 and outcome = 'RETRYABLE'),
        'A post-start Resend lease must reuse its stable key inside the idempotency window'
    );
    perform public.mark_communication_delivery_submission_started(
        resend_started_job_id, reclaimed_lease
    );
    perform public.complete_communication_delivery_job(
        resend_started_job_id, reclaimed_lease, 'PERMANENT_FAILURE', null,
        'test_closed', 'TEST_END', 60
    );

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, push_registration_id, state, submission_count,
        next_attempt_at, lease_token, lease_expires_at, first_submitted_at,
        last_submitted_at, active_submission_started_at
    ) values (
        expo_started_job_id,
        (select communication.id
         from public.transactional_communications as communication
         where communication.appointment_id =
             '14000000-0000-4000-8000-000000000091'
           and communication.recipient_user_id =
             '14000000-0000-4000-8000-000000000012'
         limit 1),
        'PUSH', 'EXPO', 'EXPO-POST-SUBMIT-WORKER-LOSS',
        'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[slice14-test]', 'UTF8')),
            'hex'
        ), registration_id, 'CLAIMED', 1,
        '2000-01-01Z', '14000000-0000-4000-8000-0000000000b8',
        clock_timestamp() - interval '1 minute',
        expo_started_at, expo_started_at, expo_started_at
    );

    perform public.claim_communication_delivery_jobs(1, 120);
    perform pg_temp.assert_true(
        (select state = 'UNKNOWN' and resolved_at is not null
         from public.communication_delivery_jobs
         where id = expo_started_job_id)
        and (select count(*) = 1
             from public.communication_delivery_attempts
             where delivery_job_id = expo_started_job_id
               and outcome = 'UNKNOWN'
               and attempted_at = expo_started_at
               and attempted_at < clock_timestamp() - interval '1 hour'),
        'Expo reconciliation must close UNKNOWN at T2 while preserving provider-start T1 on its Attempt'
    );
end;
$$;

insert into public.communication_delivery_jobs (
    id, communication_id, channel, provider, destination_key,
    destination_snapshot, state, submission_count, lease_token,
    lease_expires_at, first_submitted_at, last_submitted_at
)
select '14000000-0000-4000-8000-0000000000c1', communication.id,
       'EMAIL', 'RESEND', 'EXHAUSTED-LEASE', 'new-org@example.test',
       'CLAIMED', 8, '14000000-0000-4000-8000-0000000000c2',
       clock_timestamp() - interval '1 minute',
       clock_timestamp() - interval '10 minutes',
       clock_timestamp() - interval '1 minute'
from public.transactional_communications as communication
where communication.communication_type = 'ORGANIZATION_INVITATION'
limit 1;

select count(*) from public.claim_communication_delivery_jobs(1, 120);
select pg_temp.assert_true(
    (select state = 'PERMANENT_FAILURE'
            and last_error_code = 'DELIVERY_ATTEMPTS_EXHAUSTED'
     from public.communication_delivery_jobs
     where id = '14000000-0000-4000-8000-0000000000c1'),
    'An expired final lease must not remain CLAIMED forever'
);

do $$
declare
    appointment_communication_id uuid;
    registration_id uuid;
    unknown_job_id uuid := '14000000-0000-4000-8000-0000000000d1';
    unknown_lease_id uuid := '14000000-0000-4000-8000-0000000000d2';
begin
    select communication.id into appointment_communication_id
    from public.transactional_communications as communication
    where communication.appointment_id = '14000000-0000-4000-8000-000000000091'
      and communication.recipient_user_id = '14000000-0000-4000-8000-000000000012'
    limit 1;

    select registration.id into registration_id
    from public.push_registrations as registration
    where registration.device_installation_id = '14000000-0000-4000-8000-000000000081';

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
         destination_snapshot, push_registration_id, state, submission_count,
         lease_token, lease_expires_at, first_submitted_at, last_submitted_at,
         active_submission_started_at
    ) values (
        unknown_job_id, appointment_communication_id, 'PUSH', 'EXPO',
        'EXPO-AMBIGUOUS', 'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[slice14-test]', 'UTF8')),
            'hex'
        ), registration_id,
         'CLAIMED', 1, unknown_lease_id,
         clock_timestamp() + interval '2 minutes', clock_timestamp(),
         clock_timestamp(), clock_timestamp()
    );

    perform public.complete_communication_delivery_job(
        unknown_job_id, unknown_lease_id, 'UNKNOWN', null, null,
        'AMBIGUOUS_PROVIDER_TIMEOUT', 60
    );

    perform pg_temp.assert_true(
        (select state = 'UNKNOWN' and resolved_at is not null
                and lease_token is null and submission_count = 1
         from public.communication_delivery_jobs where id = unknown_job_id),
        'An ambiguous Expo submission must close its Delivery Job as UNKNOWN'
    );
    perform pg_temp.assert_true(
        (select count(*) = 1
         from public.communication_delivery_attempts
         where delivery_job_id = unknown_job_id and outcome = 'UNKNOWN'),
        'An ambiguous Expo submission must append an UNKNOWN Attempt'
    );

    perform public.claim_communication_delivery_jobs(100, 120);
    perform pg_temp.assert_true(
        (select state = 'UNKNOWN' and submission_count = 1
         from public.communication_delivery_jobs where id = unknown_job_id),
        'UNKNOWN must not be reclaimed for ordinary provider submission'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_jobs set state = %L where id = %L',
            'RETRYABLE', unknown_job_id
        ),
        '23514'
    );
end;
$$;

do $$
declare
    appointment_communication_id uuid;
    affected_registration_id uuid;
    current_registration_id uuid;
    receipt_lease_id uuid;
    accepted_job_id uuid := '14000000-0000-4000-8000-0000000000e1';
    accepted_lease_id uuid := '14000000-0000-4000-8000-0000000000e2';
    rejected_job_id uuid := '14000000-0000-4000-8000-0000000000e3';
    rejected_lease_id uuid := '14000000-0000-4000-8000-0000000000e4';
    unaffected_registration_id uuid := '14000000-0000-4000-8000-0000000000e5';
    horizon_job_id uuid := '14000000-0000-4000-8000-0000000000e8';
    current_ticket_job_id uuid := '14000000-0000-4000-8000-0000000000e9';
    current_submission_lease_id uuid := '14000000-0000-4000-8000-0000000000ea';
    suppressed_job_id uuid;
begin
    select communication.id into appointment_communication_id
    from public.transactional_communications as communication
    where communication.appointment_id = '14000000-0000-4000-8000-000000000091'
      and communication.recipient_user_id = '14000000-0000-4000-8000-000000000012'
    limit 1;

    select registration.id into affected_registration_id
    from public.push_registrations as registration
    where registration.device_installation_id = '14000000-0000-4000-8000-000000000081';

    select registration.id into current_registration_id
    from public.push_registrations as registration
    where registration.device_installation_id =
        '14000000-0000-4000-8000-000000000082';

    insert into public.push_registrations (
        id, user_id, auth_session_id, device_installation_id, provider_token,
        platform, application_id
    ) values (
        unaffected_registration_id, '14000000-0000-4000-8000-000000000013',
        '14000000-0000-4000-8000-0000000000e6',
        '14000000-0000-4000-8000-0000000000e7',
        'ExponentPushToken[unaffected-test]', 'ANDROID',
        'com.petcare.mobile.unaffected'
    );

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
         destination_snapshot, push_registration_id, state, submission_count,
         lease_token, lease_expires_at, first_submitted_at, last_submitted_at,
         active_submission_started_at
    ) values (
        accepted_job_id, appointment_communication_id, 'PUSH', 'EXPO',
        'EXPO-RECEIPT-OK', 'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[slice14-test]', 'UTF8')),
            'hex'
        ),
         affected_registration_id, 'CLAIMED', 1, accepted_lease_id,
         clock_timestamp() + interval '2 minutes', clock_timestamp(),
         clock_timestamp(), clock_timestamp()
    );

    perform public.complete_communication_delivery_job(
        accepted_job_id, accepted_lease_id, 'ACCEPTED', 'expo-ticket-ok',
        'ticket_ok', null, 60
    );
    perform pg_temp.assert_true(
        (select state = 'ACCEPTED' from public.communication_delivery_jobs
         where id = accepted_job_id),
        'An Expo ticket with status ok must establish ACCEPTED'
    );

    update public.communication_delivery_jobs
    set next_attempt_at = clock_timestamp() - interval '1 second'
    where id = accepted_job_id;
    select receipt.lease_token into receipt_lease_id
    from public.claim_expo_push_receipts(100, 120) as receipt
    where receipt.delivery_job_id = accepted_job_id;
    perform public.complete_expo_push_receipt(
        accepted_job_id, receipt_lease_id, 'UPSTREAM_ACCEPTED',
        'receipt_ok', null, 300
    );
    perform pg_temp.assert_true(
        (select state = 'UPSTREAM_ACCEPTED' and state <> 'DELIVERED'
                and resolved_at is not null
         from public.communication_delivery_jobs where id = accepted_job_id),
        'An Expo ok receipt is UPSTREAM_ACCEPTED and never DELIVERED'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_jobs set state = %L, resolved_at = null where id = %L',
            'ACCEPTED', accepted_job_id
        ),
        '23514'
    );

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, push_registration_id, state, submission_count,
        provider_message_id, next_attempt_at, first_submitted_at,
        last_submitted_at
    ) values (
        current_ticket_job_id, appointment_communication_id, 'PUSH', 'EXPO',
        'EXPO-CURRENT-TICKET-HORIZON', 'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[registered-after-fanout]', 'UTF8')),
            'hex'
        ), current_registration_id, 'ACCEPTED', 2,
        'expo-ticket-current-1', clock_timestamp() - interval '1 second',
        clock_timestamp() - interval '24 hours', clock_timestamp()
    );
    select receipt.lease_token into receipt_lease_id
    from public.claim_expo_push_receipts(100, 120) as receipt
    where receipt.delivery_job_id = current_ticket_job_id;
    perform pg_temp.assert_true(
        receipt_lease_id is not null
        and (select state = 'ACCEPTED' and resolved_at is null
             from public.communication_delivery_jobs
             where id = current_ticket_job_id),
        'An old first submission must not expire a currently accepted recent Expo ticket'
    );
    perform public.complete_expo_push_receipt(
        current_ticket_job_id, receipt_lease_id, 'RETRYABLE',
        'receipt_rate_limited', 'MessageRateExceeded', 1
    );

    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = current_submission_lease_id,
        lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = current_ticket_job_id;
    perform public.mark_communication_delivery_submission_started(
        current_ticket_job_id, current_submission_lease_id
    );
    perform public.complete_communication_delivery_job(
        current_ticket_job_id, current_submission_lease_id, 'ACCEPTED',
        'expo-ticket-current-2', 'ticket_ok', null, 60
    );
    update public.communication_delivery_jobs
    set next_attempt_at = clock_timestamp() - interval '1 second'
    where id = current_ticket_job_id;
    receipt_lease_id := null;
    select receipt.lease_token into receipt_lease_id
    from public.claim_expo_push_receipts(100, 120) as receipt
    where receipt.delivery_job_id = current_ticket_job_id
      and receipt.ticket_id = 'expo-ticket-current-2';
    perform pg_temp.assert_true(
        receipt_lease_id is not null
        and (select first_submitted_at < last_submitted_at
                    and last_submitted_at > clock_timestamp() - interval '1 minute'
             from public.communication_delivery_jobs
             where id = current_ticket_job_id),
        'A later accepted ticket after a retryable receipt must get its own fresh horizon'
    );
    perform public.complete_expo_push_receipt(
        current_ticket_job_id, receipt_lease_id, 'PENDING',
        'receipt_pending', null, 300
    );

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, push_registration_id, state, submission_count,
        provider_message_id, next_attempt_at, first_submitted_at,
        last_submitted_at
    ) values (
        horizon_job_id, appointment_communication_id, 'PUSH', 'EXPO',
        'EXPO-RECEIPT-HORIZON', 'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[slice14-test]', 'UTF8')),
            'hex'
        ),
        affected_registration_id, 'ACCEPTED', 1, 'expo-ticket-horizon',
        clock_timestamp() - interval '1 minute',
        clock_timestamp() - interval '24 hours',
        clock_timestamp() - interval '24 hours'
    );
    perform public.claim_expo_push_receipts(100, 120);
    perform pg_temp.assert_true(
        (select state = 'UNKNOWN' and resolved_at is not null
                    and last_error_code = 'EXPO_RECEIPT_HORIZON_EXPIRED'
                    and lease_token is null
         from public.communication_delivery_jobs where id = horizon_job_id),
        'An unresolved Expo ticket must leave receipt polling as UNKNOWN at the horizon'
    );

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
         destination_snapshot, push_registration_id, state, submission_count,
         lease_token, lease_expires_at, first_submitted_at, last_submitted_at,
         active_submission_started_at
    ) values (
        rejected_job_id, appointment_communication_id, 'PUSH', 'EXPO',
        'EXPO-DEVICE-NOT-REGISTERED', 'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[slice14-test]', 'UTF8')),
            'hex'
        ),
         affected_registration_id, 'CLAIMED', 1, rejected_lease_id,
         clock_timestamp() + interval '2 minutes', clock_timestamp(),
         clock_timestamp(), clock_timestamp()
    );
    perform public.complete_communication_delivery_job(
        rejected_job_id, rejected_lease_id, 'ACCEPTED', 'expo-ticket-rejected',
        'ticket_ok', null, 60
    );
    update public.communication_delivery_jobs
    set next_attempt_at = clock_timestamp() - interval '1 second'
    where id = rejected_job_id;
    select receipt.lease_token into receipt_lease_id
    from public.claim_expo_push_receipts(100, 120) as receipt
    where receipt.delivery_job_id = rejected_job_id;
    perform public.complete_expo_push_receipt(
        rejected_job_id, receipt_lease_id, 'PERMANENT_FAILURE',
        'receipt_error', 'DeviceNotRegistered', 300
    );

    perform pg_temp.assert_true(
        (select state = 'PERMANENT_FAILURE'
         from public.communication_delivery_jobs where id = rejected_job_id),
        'DeviceNotRegistered must remain a permanent delivery failure'
    );
    perform pg_temp.assert_true(
        (select invalidated_at is not null
                and invalidation_reason = 'DEVICE_NOT_REGISTERED'
         from public.push_registrations where id = affected_registration_id),
        'DeviceNotRegistered must invalidate the affected registration'
    );
    perform pg_temp.assert_true(
        (select invalidated_at is null
         from public.push_registrations where id = unaffected_registration_id),
        'DeviceNotRegistered must not invalidate another registration'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_jobs set state = %L, resolved_at = null where id = %L',
            'RETRYABLE', rejected_job_id
        ),
        '23514'
    );

    select job.id into suppressed_job_id
    from public.communication_delivery_jobs as job
    where job.state = 'SUPPRESSED'
    limit 1;
    perform pg_temp.assert_true(
        suppressed_job_id is not null,
        'The session eligibility test must provide a suppressed terminal Job'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_jobs set state = %L, resolved_at = null where id = %L',
            'READY', suppressed_job_id
        ),
        '23514'
    );
end;
$$;

do $$
declare
    invitation_communication_id uuid;
    test_delivery_job_id uuid := '14000000-0000-4000-8000-0000000000b1';
    lease_id uuid := '14000000-0000-4000-8000-0000000000b2';
begin
    select id into invitation_communication_id
    from public.transactional_communications
    where communication_type = 'ORGANIZATION_INVITATION'
    limit 1;

    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
         destination_snapshot, state, submission_count, lease_token,
         lease_expires_at, first_submitted_at, last_submitted_at,
         active_submission_started_at
    ) values (
        test_delivery_job_id, invitation_communication_id, 'EMAIL', 'RESEND', 'TEST',
         'new-org@example.test', 'CLAIMED', 1, lease_id,
         clock_timestamp() + interval '2 minutes', clock_timestamp(),
         clock_timestamp(), clock_timestamp()
    );

    perform pg_temp.assert_true(
        public.record_resend_delivery_event(
            'event-early', 'email.delivered', 'resend-message-id',
            '2026-09-01T12:00:00Z'
        ) = 'UNMATCHED',
        'A valid early Resend event must remain unmatched until provider mapping exists'
    );

    perform public.complete_communication_delivery_job(
        test_delivery_job_id, lease_id, 'ACCEPTED', 'resend-message-id', 'accepted', null, 60
    );

    perform pg_temp.assert_true(
        (select count(*) = 1
         from public.communication_delivery_attempts
         where communication_delivery_attempts.delivery_job_id = test_delivery_job_id
           and attempt_number = 1
           and outcome = 'ACCEPTED'),
        'Provider submission must append one immutable Delivery Attempt'
    );

    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_attempts set outcome = %L where delivery_job_id = %L',
            'DELIVERED', test_delivery_job_id
        ),
        '23514'
    );

    perform pg_temp.assert_true(
        (select secret_consumed_at is not null and secret_nonce is null
                and secret_ciphertext is null
         from public.transactional_communications
         where id = invitation_communication_id),
        'Provider acceptance must erase the one-time encrypted handoff payload'
    );

    perform pg_temp.assert_true(
        public.record_resend_delivery_event(
            'event-early', 'email.delivered', 'resend-message-id',
            '2026-09-01T12:00:00Z'
        ) = 'DELIVERED',
        'Retrying the same signed event after mapping must apply it'
    );
    perform pg_temp.assert_true(
        public.record_resend_delivery_event(
            'event-early', 'email.delivered', 'resend-message-id',
            '2026-09-01T12:00:00Z'
        ) = 'DELIVERED',
        'A duplicate Resend event must be harmless and idempotent'
    );
    perform public.record_resend_delivery_event(
        'event-stale', 'email.bounced', 'resend-message-id', '2026-09-01T11:59:00Z'
    );
    perform pg_temp.assert_true(
        (select state = 'DELIVERED' from public.communication_delivery_jobs where id = test_delivery_job_id),
        'An out-of-order older callback must not regress delivery truth'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_jobs set state = %L, resolved_at = null where id = %L',
            'READY', test_delivery_job_id
        ),
        '23514'
    );
    perform public.record_resend_delivery_event(
        'event-failed-after-delivery', 'email.failed', 'resend-message-id',
        '2026-09-01T12:01:00Z'
    );
    perform pg_temp.assert_true(
        (select state = 'DELIVERED'
         from public.communication_delivery_jobs where id = test_delivery_job_id),
        'DELIVERED must not regress on a weaker or contradictory provider event'
    );
    perform public.record_resend_delivery_event(
        'event-complaint', 'email.complained', 'resend-message-id',
        '2026-09-01T12:02:00Z'
    );
    perform pg_temp.assert_true(
        (select state = 'PERMANENT_FAILURE'
         from public.communication_delivery_jobs where id = test_delivery_job_id),
        'A later Resend complaint may monotonically strengthen DELIVERED to permanent failure'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'update public.communication_delivery_jobs set state = %L, resolved_at = null where id = %L',
            'RETRYABLE', test_delivery_job_id
        ),
        '23514'
    );
end;
$$;

do $$
declare
    clinic_proposal_id uuid := '14000000-0000-4000-8000-0000000000f1';
    guardian_proposal_id uuid := '14000000-0000-4000-8000-0000000000f2';
begin
    -- Keep the Slice-14 enqueue trigger live while bypassing unrelated
    -- domain-operation guards for these already-valid synthetic rows.
    alter table public.appointment_reschedule_proposals
        disable trigger appointment_reschedule_proposals_enforce_integrity;
    alter table public.appointment_reschedule_proposals
        disable trigger appointment_reschedule_proposals_validate_base_revision;
    alter table public.appointment_reschedule_proposals
        disable trigger appointment_reschedule_proposals_enforce_acceptance;
    insert into public.appointment_reschedule_proposals (
        id, appointment_id, base_revision_id, base_revision_context, proposed_start_at,
        proposed_end_at, proposed_timezone_name, proposing_context,
        proposed_by_user_id, reason, created_at
    ) values
        (
            clinic_proposal_id, '14000000-0000-4000-8000-000000000091',
            '14000000-0000-4000-8000-000000000093', 'CONFIRMED',
            '2035-01-03T10:00:00Z', '2035-01-03T10:30:00Z',
            'Europe/Madrid', 'CLINIC',
            '14000000-0000-4000-8000-000000000011', 'Clinic proposal',
            '2026-09-01T13:00:00Z'
        ),
        (
            guardian_proposal_id, '14000000-0000-4000-8000-0000000000a1',
            '14000000-0000-4000-8000-0000000000a2', 'CONFIRMED',
            '2035-02-03T10:00:00Z', '2035-02-03T10:30:00Z',
            'Europe/Madrid', 'GUARDIAN',
            '14000000-0000-4000-8000-000000000012', null,
            '2026-09-01T13:01:00Z'
        );
    alter table public.appointment_reschedule_proposals
        enable trigger appointment_reschedule_proposals_enforce_integrity;
    alter table public.appointment_reschedule_proposals
        enable trigger appointment_reschedule_proposals_validate_base_revision;
    alter table public.appointment_reschedule_proposals
        enable trigger appointment_reschedule_proposals_enforce_acceptance;

    perform pg_temp.assert_true(
        (select count(*) = 2
         from public.transactional_communications
         where communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
           and appointment_reschedule_proposal_id = clinic_proposal_id),
        'A Clinic-originated Proposal must notify all current Guardians'
    );
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.transactional_communications
            where communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
              and appointment_reschedule_proposal_id = guardian_proposal_id
        ),
        'A Guardian-originated Proposal must not notify the Guardian audience'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'insert into public.transactional_communications (communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id) values (%L, %L, %L, %L)',
            'APPOINTMENT_RESCHEDULE_PROPOSED',
            '14000000-0000-4000-8000-000000000012',
            '14000000-0000-4000-8000-0000000000a1',
            guardian_proposal_id
        ),
        '23514'
    );

    -- Acceptance order: the Proposal becomes ACCEPTED, then its resulting
    -- revision is inserted, which enqueues the accepted notification. The
    -- enqueue trigger stays live; unrelated domain-operation guards are
    -- bypassed for these already-valid synthetic rows.
    alter table public.appointment_reschedule_proposals
        disable trigger appointment_reschedule_proposals_enforce_integrity;
    alter table public.appointment_reschedule_proposals
        disable trigger appointment_reschedule_proposals_enforce_acceptance;
    update public.appointment_reschedule_proposals
    set state = 'ACCEPTED'
    where id = clinic_proposal_id;
    alter table public.appointment_reschedule_proposals
        enable trigger appointment_reschedule_proposals_enforce_integrity;
    alter table public.appointment_reschedule_proposals
        enable trigger appointment_reschedule_proposals_enforce_acceptance;

    -- The revision's deferred provenance and conflict checks are never fired
    -- in this rolled-back suite.
    insert into public.appointment_schedule_revisions (
        id, appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    ) values (
        '14000000-0000-4000-8000-0000000000f3',
        '14000000-0000-4000-8000-000000000091', 3, 'CONFIRMED',
        '2035-01-03T10:00:00Z', '2035-01-03T10:30:00Z', 'Europe/Madrid',
        '14000000-0000-4000-8000-000000000012', clinic_proposal_id,
        '2026-09-01T13:03:00Z'
    );

    perform pg_temp.assert_true(
        (select count(*) = 2
         from public.transactional_communications
         where communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED'
           and appointment_reschedule_proposal_id = clinic_proposal_id),
        'Accepted reschedule notifications must remain unchanged'
    );
end;
$$;

do $$
declare
    job_id uuid;
    communication_id uuid;
    registration_id uuid;
    invitation_id uuid;
    lease_id uuid;
    context jsonb;
begin
    -- Current Guardianship ends after claim.
    select communication.id into communication_id
    from public.transactional_communications as communication
    where communication.appointment_id = '14000000-0000-4000-8000-000000000091'
      and communication.recipient_user_id = '14000000-0000-4000-8000-000000000013'
    limit 1;
    job_id := '14000000-0000-4000-8000-000000000110';
    lease_id := '14000000-0000-4000-8000-000000000101';
    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, state, lease_token, lease_expires_at
    ) values (
        job_id, communication_id, 'EMAIL', 'RESEND', 'GATE-GUARDIAN-ENDED',
        'second@example.test', 'CLAIMED', lease_id,
        clock_timestamp() + interval '5 minutes'
    );
    set local session_replication_role = replica;
    update public.guardianships set effective_end = clock_timestamp()
    where id = '14000000-0000-4000-8000-000000000062';
    set local session_replication_role = origin;
    context := public.get_communication_delivery_context(job_id, lease_id);
    perform pg_temp.assert_true(
        context is null
        and (select state = 'SUPPRESSED' and lease_token is null
             from public.communication_delivery_jobs where id = job_id),
        'A Guardian ending after claim must suppress before provider context returns'
    );

    -- Auth email changes after claim.
    select communication.id into communication_id
    from public.transactional_communications as communication
    where communication.appointment_id = '14000000-0000-4000-8000-000000000091'
      and communication.recipient_user_id = '14000000-0000-4000-8000-000000000012'
    limit 1;
    job_id := '14000000-0000-4000-8000-000000000111';
    lease_id := '14000000-0000-4000-8000-000000000102';
    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, state, lease_token, lease_expires_at
    ) values (
        job_id, communication_id, 'EMAIL', 'RESEND', 'GATE-EMAIL-CHANGED',
        'guardian@example.test', 'CLAIMED', lease_id,
        clock_timestamp() + interval '5 minutes'
    );
    update auth.users set email = 'changed@example.test'
    where id = '14000000-0000-4000-8000-000000000002';
    context := public.get_communication_delivery_context(job_id, lease_id);
    perform pg_temp.assert_true(
        context is null
        and (select state = 'SUPPRESSED'
             from public.communication_delivery_jobs where id = job_id),
        'An Auth email change after claim must suppress the stale destination'
    );

    -- Invitation terminates after claim.
    select communication.id, communication.guardianship_invitation_id
    into communication_id, invitation_id
    from public.transactional_communications as communication
    where communication.communication_type = 'GUARDIANSHIP_INVITATION';
    job_id := '14000000-0000-4000-8000-000000000112';
    lease_id := '14000000-0000-4000-8000-000000000103';
    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, state, lease_token, lease_expires_at
    ) values (
        job_id, communication_id, 'EMAIL', 'RESEND',
        'GATE-INVITATION-TERMINATED', 'new-guardian@example.test',
        'CLAIMED', lease_id, clock_timestamp() + interval '5 minutes'
    );
    set local session_replication_role = replica;
    update public.guardianship_invitations
    set revoked_at = clock_timestamp(),
        revoked_by_guardianship_id =
            '14000000-0000-4000-8000-000000000061'
    where id = invitation_id;
    set local session_replication_role = origin;
    context := public.get_communication_delivery_context(job_id, lease_id);
    perform pg_temp.assert_true(
        context is null
        and (select state = 'SUPPRESSED'
             from public.communication_delivery_jobs where id = job_id),
        'A terminated Invitation after claim must suppress before secret context returns'
    );

    -- A bound Auth Session disappears after claim.
    insert into auth.sessions (id, user_id, created_at, updated_at) values (
        '14000000-0000-4000-8000-000000000104',
        '14000000-0000-4000-8000-000000000002',
        clock_timestamp(), clock_timestamp()
    );
    registration_id := public.upsert_session_push_registration(
        '14000000-0000-4000-8000-000000000002',
        '14000000-0000-4000-8000-000000000104',
        '14000000-0000-4000-8000-000000000105',
        'ExponentPushToken[context-session-loss]', 'IOS',
        'com.petcare.context-session-loss'
    );
    job_id := '14000000-0000-4000-8000-000000000113';
    lease_id := '14000000-0000-4000-8000-000000000106';
    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, push_registration_id, state, lease_token,
        lease_expires_at
    ) values (
        job_id, communication_id, 'PUSH', 'EXPO', 'GATE-SESSION-ENDED',
        'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[context-session-loss]', 'UTF8')),
            'hex'
        ), registration_id, 'CLAIMED', lease_id,
        clock_timestamp() + interval '5 minutes'
    );
    delete from auth.sessions
    where id = '14000000-0000-4000-8000-000000000104';
    context := public.get_communication_delivery_context(job_id, lease_id);
    perform pg_temp.assert_true(
        context is null
        and (select state = 'SUPPRESSED'
             from public.communication_delivery_jobs where id = job_id),
        'A missing bound Auth Session after claim must suppress Push context'
    );

    -- A single Push Registration invalidates after claim.
    insert into auth.sessions (id, user_id, created_at, updated_at) values (
        '14000000-0000-4000-8000-000000000107',
        '14000000-0000-4000-8000-000000000002',
        clock_timestamp(), clock_timestamp()
    );
    registration_id := public.upsert_session_push_registration(
        '14000000-0000-4000-8000-000000000002',
        '14000000-0000-4000-8000-000000000107',
        '14000000-0000-4000-8000-000000000108',
        'ExponentPushToken[context-registration-loss]', 'ANDROID',
        'com.petcare.context-registration-loss'
    );
    job_id := '14000000-0000-4000-8000-000000000114';
    lease_id := '14000000-0000-4000-8000-000000000109';
    insert into public.communication_delivery_jobs (
        id, communication_id, channel, provider, destination_key,
        destination_snapshot, push_registration_id, state, lease_token,
        lease_expires_at
    ) values (
        job_id, communication_id, 'PUSH', 'EXPO',
        'GATE-REGISTRATION-INVALIDATED', 'sha256:' || encode(
            sha256(convert_to('ExponentPushToken[context-registration-loss]', 'UTF8')),
            'hex'
        ), registration_id, 'CLAIMED', lease_id,
        clock_timestamp() + interval '5 minutes'
    );
    update public.push_registrations
    set invalidated_at = clock_timestamp(), invalidation_reason = 'TEST_INVALIDATED'
    where id = registration_id;
    context := public.get_communication_delivery_context(job_id, lease_id);
    perform pg_temp.assert_true(
        context is null
        and (select state = 'SUPPRESSED'
             from public.communication_delivery_jobs where id = job_id),
        'An invalidated Push Registration after claim must suppress only that destination'
    );
end;
$$;

-- ===========================================================================
-- Closure-gate coverage: Appointment terminal-state notifications, reminder
-- policy edges, Push Registration lifecycle, and the Communications
-- authorization boundary. Deterministic and rollback-only. No provider,
-- scheduler, or remote state is touched.
-- ===========================================================================

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at) values
    ('14000000-0000-4000-8000-000000000201', 'gap-guardian-a@example.test', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000202', 'gap-guardian-b@example.test', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000203', 'gap-guardian-c@example.test', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000204', 'gap-push-one@example.test', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000205', 'gap-push-two@example.test', '2026-01-01Z');

insert into public.users (id, created_at) values
    ('14000000-0000-4000-8000-000000000211', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000212', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000213', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000214', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000215', '2026-01-01Z');

insert into public.user_authentication_identities (id, user_id, provider_subject) values
    ('14000000-0000-4000-8000-000000000221', '14000000-0000-4000-8000-000000000211', '14000000-0000-4000-8000-000000000201'),
    ('14000000-0000-4000-8000-000000000222', '14000000-0000-4000-8000-000000000212', '14000000-0000-4000-8000-000000000202'),
    ('14000000-0000-4000-8000-000000000223', '14000000-0000-4000-8000-000000000213', '14000000-0000-4000-8000-000000000203'),
    ('14000000-0000-4000-8000-000000000224', '14000000-0000-4000-8000-000000000214', '14000000-0000-4000-8000-000000000204'),
    ('14000000-0000-4000-8000-000000000225', '14000000-0000-4000-8000-000000000215', '14000000-0000-4000-8000-000000000205');

insert into auth.sessions (id, user_id, created_at, updated_at) values
    ('14000000-0000-4000-8000-000000000231', '14000000-0000-4000-8000-000000000204', '2026-09-01Z', '2026-09-01Z'),
    ('14000000-0000-4000-8000-000000000232', '14000000-0000-4000-8000-000000000204', '2026-09-01Z', '2026-09-01Z'),
    ('14000000-0000-4000-8000-000000000233', '14000000-0000-4000-8000-000000000205', '2026-09-01Z', '2026-09-01Z');

insert into public.pets (id, name, species, created_at) values
    ('14000000-0000-4000-8000-000000000241', 'GapPetOne', 'canine', '2026-01-01Z'),
    ('14000000-0000-4000-8000-000000000242', 'GapPetTwo', 'feline', '2026-01-01Z');

-- GapPetOne keeps two current Guardians throughout. GapPetTwo swaps Guardians
-- between Appointment confirmation and the reminder point.
insert into public.guardianships (
    id, user_id, pet_id, effective_start, effective_end
) values
    ('14000000-0000-4000-8000-000000000251', '14000000-0000-4000-8000-000000000211', '14000000-0000-4000-8000-000000000241', '2026-01-01Z', null),
    ('14000000-0000-4000-8000-000000000252', '14000000-0000-4000-8000-000000000212', '14000000-0000-4000-8000-000000000241', '2026-01-01Z', null),
    ('14000000-0000-4000-8000-000000000253', '14000000-0000-4000-8000-000000000211', '14000000-0000-4000-8000-000000000242', '2026-01-01Z', null),
    ('14000000-0000-4000-8000-000000000254', '14000000-0000-4000-8000-000000000213', '14000000-0000-4000-8000-000000000242', '2026-06-01Z', null);

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit,
    lifecycle_state, created_at
) values
    ('14000000-0000-4000-8000-000000000261', '14000000-0000-4000-8000-000000000241', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:00:00Z'),
    ('14000000-0000-4000-8000-000000000262', '14000000-0000-4000-8000-000000000241', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:01:00Z'),
    ('14000000-0000-4000-8000-000000000263', '14000000-0000-4000-8000-000000000241', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:02:00Z'),
    ('14000000-0000-4000-8000-000000000264', '14000000-0000-4000-8000-000000000241', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:03:00Z'),
    ('14000000-0000-4000-8000-000000000265', '14000000-0000-4000-8000-000000000241', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:04:00Z'),
    ('14000000-0000-4000-8000-000000000266', '14000000-0000-4000-8000-000000000242', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:05:00Z'),
    ('14000000-0000-4000-8000-000000000267', '14000000-0000-4000-8000-000000000241', '14000000-0000-4000-8000-000000000042', '14000000-0000-4000-8000-000000000211', 'Routine visit', 'CONFIRMED', '2026-09-01T09:06:00Z');

insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, created_at
) values
    ('14000000-0000-4000-8000-000000000271', '14000000-0000-4000-8000-000000000261', 1, 'CONFIRMED', '2036-01-02T10:00:00Z', '2036-01-02T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:00:00Z'),
    ('14000000-0000-4000-8000-000000000272', '14000000-0000-4000-8000-000000000262', 1, 'CONFIRMED', '2036-01-03T10:00:00Z', '2036-01-03T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:01:00Z'),
    ('14000000-0000-4000-8000-000000000273', '14000000-0000-4000-8000-000000000263', 1, 'CONFIRMED', '2035-08-02T10:00:00Z', '2035-08-02T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:02:00Z'),
    ('14000000-0000-4000-8000-000000000274', '14000000-0000-4000-8000-000000000264', 1, 'CONFIRMED', '2035-06-02T10:00:00Z', '2035-06-02T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:03:00Z'),
    ('14000000-0000-4000-8000-000000000275', '14000000-0000-4000-8000-000000000265', 1, 'CONFIRMED', '2035-07-02T10:00:00Z', '2035-07-02T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:04:00Z'),
    ('14000000-0000-4000-8000-000000000276', '14000000-0000-4000-8000-000000000266', 1, 'CONFIRMED', '2035-09-02T10:00:00Z', '2035-09-02T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:05:00Z'),
    ('14000000-0000-4000-8000-000000000278', '14000000-0000-4000-8000-000000000267', 1, 'CONFIRMED', '2035-10-02T10:00:00Z', '2035-10-02T10:30:00Z', 'Europe/Madrid', '14000000-0000-4000-8000-000000000011', '2026-09-01T09:06:00Z');

set local session_replication_role = origin;

-- --- Regression: a former-Guardian Communication must not wedge dispatch --
-- Earlier in this suite Guardianship 14...062 was ended while two Appointment
-- Communications for that now-former Guardian (14...013) on Appointment
-- 14...091 were still un-fanned-out. Before the corrective migration
-- (20260903120000), the next materialize/claim call raised SQLSTATE 23514
-- from the establishment-time current-Guardian assertion re-firing on the
-- fanout_materialized_at bookkeeping UPDATE, aborting the dispatcher.
do $$
declare
    poisoned_ids uuid[];
    drained integer;
begin
    select array_agg(communication.id)
    into poisoned_ids
    from public.transactional_communications as communication
    where communication.appointment_id = '14000000-0000-4000-8000-000000000091'
      and communication.recipient_user_id =
          '14000000-0000-4000-8000-000000000013'
      and communication.communication_type in (
          'APPOINTMENT_RESCHEDULE_PROPOSED', 'APPOINTMENT_RESCHEDULE_ACCEPTED'
      )
      and communication.fanout_materialized_at is null;

    perform pg_temp.assert_true(
        coalesce(array_length(poisoned_ids, 1), 0) = 2
        and not exists (
            select 1 from public.guardianships as guardianship
            where guardianship.pet_id = '14000000-0000-4000-8000-000000000051'
              and guardianship.user_id =
                  '14000000-0000-4000-8000-000000000013'
              and guardianship.effective_end is null
        ),
        'Precondition: pending fanout exists for a Communication whose Guardian has left'
    );

    -- The previously failing call. It must complete instead of raising.
    drained := public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        drained >= 0,
        'materialize_communication_delivery_jobs does not throw on a former-Guardian Communication'
    );
    perform pg_temp.assert_true(
        (select count(*) = 2 from public.transactional_communications
         where id = any (poisoned_ids)
           and fanout_materialized_at is not null),
        'The former-Guardian Communications remain valid and leave the fanout queue'
    );
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.communication_delivery_jobs as job
            where job.communication_id = any (poisoned_ids)
              and job.state <> 'SUPPRESSED'
        ),
        'A former-Guardian Communication produces no eligible delivery'
    );

    -- Drained rows never re-enter the loop, so the queue cannot be re-wedged.
    perform public.materialize_communication_delivery_jobs();
    perform public.claim_communication_delivery_jobs(50, 120);
    perform pg_temp.assert_true(
        (select count(*) = 2 from public.transactional_communications
         where id = any (poisoned_ids)
           and fanout_materialized_at is not null),
        'Repeated materialize and claim stay healthy with the historical Communication present'
    );
end;
$$;

-- --- APPOINTMENT_COMPLETED lifecycle notification -------------------------
-- SPEC-APT-009 BR-15: a completion Event carries no Clinical Encounter
-- reference, and none is needed for its Communication.
insert into public.appointment_lifecycle_events (
    id, appointment_id, from_state, to_state, actor_user_id, actor_context,
    effective_at, recorded_at
) values (
    '14000000-0000-4000-8000-000000000281',
    '14000000-0000-4000-8000-000000000261', 'CONFIRMED', 'COMPLETED',
    '14000000-0000-4000-8000-000000000011', 'CLINIC',
    '2026-09-02T10:00:00Z', '2026-09-02T10:00:00Z'
);
update public.appointments set lifecycle_state = 'COMPLETED'
where id = '14000000-0000-4000-8000-000000000261';

select pg_temp.assert_true(
    (select count(*) = 2 from public.transactional_communications
     where communication_type = 'APPOINTMENT_COMPLETED'
       and appointment_lifecycle_event_id =
           '14000000-0000-4000-8000-000000000281'),
    'Appointment completion notifies every current Guardian exactly once'
);
select pg_temp.assert_true(
    not exists (
        select 1 from public.transactional_communications
        where appointment_lifecycle_event_id =
              '14000000-0000-4000-8000-000000000281'
          and recipient_user_id not in (
              '14000000-0000-4000-8000-000000000211',
              '14000000-0000-4000-8000-000000000212'
          )
    ),
    'Completion Communications target only the two current Guardians'
);
select pg_temp.assert_sqlstate(
    $statement$
    insert into public.transactional_communications (
        communication_type, recipient_user_id, appointment_id,
        appointment_lifecycle_event_id
    ) values (
        'APPOINTMENT_NO_SHOW', '14000000-0000-4000-8000-000000000211',
        '14000000-0000-4000-8000-000000000261',
        '14000000-0000-4000-8000-000000000281'
    )
    $statement$,
    '23514'
);
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2036-01-01T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 0
    and not exists (
        select 1 from public.transactional_communications
        where communication_type = 'APPOINTMENT_REMINDER'
          and appointment_id = '14000000-0000-4000-8000-000000000261'
    ),
    'A COMPLETED Appointment inside a reminder window produces no reminder'
);

-- --- APPOINTMENT_NO_SHOW lifecycle notification --------------------------
insert into public.appointment_lifecycle_events (
    id, appointment_id, from_state, to_state, actor_user_id, actor_context,
    effective_at, recorded_at
) values (
    '14000000-0000-4000-8000-000000000282',
    '14000000-0000-4000-8000-000000000262', 'CONFIRMED', 'NO_SHOW',
    '14000000-0000-4000-8000-000000000011', 'CLINIC',
    '2026-09-02T10:10:00Z', '2026-09-02T10:10:00Z'
);
update public.appointments set lifecycle_state = 'NO_SHOW'
where id = '14000000-0000-4000-8000-000000000262';

select pg_temp.assert_true(
    (select count(*) = 2 from public.transactional_communications
     where communication_type = 'APPOINTMENT_NO_SHOW'
       and appointment_lifecycle_event_id =
           '14000000-0000-4000-8000-000000000282'),
    'A no-show outcome notifies every current Guardian exactly once'
);
select pg_temp.assert_sqlstate(
    $statement$
    insert into public.transactional_communications (
        communication_type, recipient_user_id, appointment_id,
        appointment_lifecycle_event_id
    ) values (
        'APPOINTMENT_COMPLETED', '14000000-0000-4000-8000-000000000211',
        '14000000-0000-4000-8000-000000000262',
        '14000000-0000-4000-8000-000000000282'
    )
    $statement$,
    '23514'
);
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2036-01-02T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 0
    and not exists (
        select 1 from public.transactional_communications
        where communication_type = 'APPOINTMENT_REMINDER'
          and appointment_id = '14000000-0000-4000-8000-000000000262'
    ),
    'A NO_SHOW Appointment inside a reminder window produces no reminder'
);

-- --- APPOINTMENT_CANCELLED notification and reminder suppression ---------
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-08-01T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 2,
    'A CONFIRMED Appointment inside the window establishes a reminder per Guardian'
);
select public.materialize_communication_delivery_jobs();

do $$
declare
    reminder_job_id uuid;
    reminder_communication_id uuid;
begin
    select communication.id, job.id
    into reminder_communication_id, reminder_job_id
    from public.communication_delivery_jobs as job
    join public.transactional_communications as communication
      on communication.id = job.communication_id
    where communication.communication_type = 'APPOINTMENT_REMINDER'
      and communication.appointment_id = '14000000-0000-4000-8000-000000000263'
      and job.channel = 'EMAIL'
      and job.state = 'READY'
    limit 1;

    perform pg_temp.assert_true(
        reminder_job_id is not null,
        'A CONFIRMED reminder materializes a deliverable email Job'
    );

    insert into public.appointment_lifecycle_events (
        id, appointment_id, from_state, to_state, actor_user_id,
        actor_context, reason, effective_at, recorded_at
    ) values (
        '14000000-0000-4000-8000-000000000283',
        '14000000-0000-4000-8000-000000000263', 'CONFIRMED', 'CANCELLED',
        '14000000-0000-4000-8000-000000000011', 'CLINIC',
        'Clinic scheduling change', '2026-09-02T11:00:00Z',
        '2026-09-02T11:00:00Z'
    );
    update public.appointments set lifecycle_state = 'CANCELLED'
    where id = '14000000-0000-4000-8000-000000000263';

    perform pg_temp.assert_true(
        (select count(*) = 2 from public.transactional_communications
         where communication_type = 'APPOINTMENT_CANCELLED'
           and appointment_lifecycle_event_id =
               '14000000-0000-4000-8000-000000000283'),
        'Appointment cancellation notifies every current Guardian exactly once'
    );

    perform pg_temp.assert_true(
        not public.communication_delivery_is_currently_eligible(
            reminder_communication_id, 'EMAIL', null,
            'gap-guardian-a@example.test'
        ),
        'Cancellation makes the pre-existing reminder Communication ineligible'
    );

    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        (select state = 'SUPPRESSED'
         from public.communication_delivery_jobs where id = reminder_job_id),
        'A pending reminder Job is suppressed once its Appointment is cancelled'
    );
    perform pg_temp.assert_true(
        exists (
            select 1 from public.transactional_communications
            where communication_type = 'APPOINTMENT_REMINDER'
              and appointment_id = '14000000-0000-4000-8000-000000000263'
        ),
        'Reminder Communication history survives the cancellation'
    );
end;
$$;

-- --- Positive reminder inside the catch-up window; failure does not
-- --- mutate the Appointment -------------------------------------------------
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-06-01T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 2,
    'A reference time strictly inside the catch-up window establishes reminders'
);
select pg_temp.assert_true(
    (select count(*) = 2 from public.transactional_communications
     where communication_type = 'APPOINTMENT_REMINDER'
       and appointment_id = '14000000-0000-4000-8000-000000000264'
       and appointment_schedule_revision_id =
           '14000000-0000-4000-8000-000000000274'),
    'In-window reminders bind to the current CONFIRMED Schedule Revision'
);

do $$
declare
    job_id uuid;
    lease_id uuid := '14000000-0000-4000-8000-000000000291';
begin
    perform public.materialize_communication_delivery_jobs();
    select job.id into job_id
    from public.communication_delivery_jobs as job
    join public.transactional_communications as communication
      on communication.id = job.communication_id
    where communication.communication_type = 'APPOINTMENT_REMINDER'
      and communication.appointment_id = '14000000-0000-4000-8000-000000000264'
      and job.channel = 'EMAIL' and job.state = 'READY'
    limit 1;
    perform pg_temp.assert_true(
        job_id is not null, 'A reminder email Job is READY before dispatch'
    );

    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = lease_id,
        lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = job_id;
    perform public.mark_communication_delivery_submission_started(
        job_id, lease_id
    );
    perform public.complete_communication_delivery_job(
        job_id, lease_id, 'PERMANENT_FAILURE', null, 'provider_down',
        'TEST_REMINDER_DELIVERY_FAILURE', 60
    );

    perform pg_temp.assert_true(
        (select state = 'PERMANENT_FAILURE'
         from public.communication_delivery_jobs where id = job_id),
        'The reminder Job records the provider failure'
    );
    perform pg_temp.assert_true(
        (select lifecycle_state = 'CONFIRMED'
         from public.appointments
         where id = '14000000-0000-4000-8000-000000000264'),
        'Reminder delivery failure does not change Appointment lifecycle state'
    );
    perform pg_temp.assert_true(
        (select scheduled_start_at = '2035-06-02T10:00:00Z'
         from public.appointment_schedule_revisions
         where id = '14000000-0000-4000-8000-000000000274'),
        'Reminder delivery failure does not change the confirmed Schedule Revision'
    );
end;
$$;

-- --- Reminder reselection after rescheduling ----------------------------
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-07-01T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 2,
    'The first CONFIRMED revision establishes a reminder inside its window'
);
select public.materialize_communication_delivery_jobs();

do $$
begin
    insert into public.appointment_schedule_revisions (
        id, appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, created_at
    ) values (
        '14000000-0000-4000-8000-000000000277',
        '14000000-0000-4000-8000-000000000265', 2, 'CONFIRMED',
        '2035-07-10T17:00:00Z', '2035-07-10T17:30:00Z', 'Europe/Madrid',
        '14000000-0000-4000-8000-000000000011', '2026-09-02T12:00:00Z'
    );

    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        (select bool_and(job.state = 'SUPPRESSED')
         from public.communication_delivery_jobs as job
         join public.transactional_communications as communication
           on communication.id = job.communication_id
         where communication.communication_type = 'APPOINTMENT_REMINDER'
           and communication.appointment_id =
               '14000000-0000-4000-8000-000000000265'
           and communication.appointment_schedule_revision_id =
               '14000000-0000-4000-8000-000000000275'),
        'Reminder Jobs bound to a superseded revision are suppressed after reschedule'
    );

    perform pg_temp.assert_true(
        public.establish_due_appointment_reminders(
            '2035-07-09T18:00:00Z', interval '24 hours', interval '6 hours',
            'es-ES'
        ) = 2,
        'Rescheduling moves reminder relevance to the new confirmed time'
    );
    perform pg_temp.assert_true(
        (select count(*) = 2 from public.transactional_communications
         where communication_type = 'APPOINTMENT_REMINDER'
           and appointment_id = '14000000-0000-4000-8000-000000000265'
           and appointment_schedule_revision_id =
               '14000000-0000-4000-8000-000000000277'),
        'Only the winning revision produces a reminder per current Guardian'
    );

    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        (select bool_and(job.state in ('READY', 'CLAIMED'))
         from public.communication_delivery_jobs as job
         join public.transactional_communications as communication
           on communication.id = job.communication_id
         where communication.communication_type = 'APPOINTMENT_REMINDER'
           and communication.appointment_id =
               '14000000-0000-4000-8000-000000000265'
           and communication.appointment_schedule_revision_id =
               '14000000-0000-4000-8000-000000000277'),
        'The winning revision reminder remains the only deliverable one'
    );
end;
$$;

-- --- Reminder recipients resolve from current Guardianship --------------
set local session_replication_role = replica;
update public.guardianships set effective_end = '2026-09-01T00:00:00Z'
where id = '14000000-0000-4000-8000-000000000253';
set local session_replication_role = origin;

select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-09-01T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 1,
    'Reminder recipients resolve from Guardianship current at materialization time'
);
select pg_temp.assert_true(
    (select recipient_user_id = '14000000-0000-4000-8000-000000000213'
     from public.transactional_communications
     where communication_type = 'APPOINTMENT_REMINDER'
       and appointment_id = '14000000-0000-4000-8000-000000000266'),
    'The Guardian who is current at the reminder point receives the reminder'
);
select pg_temp.assert_true(
    not exists (
        select 1 from public.transactional_communications
        where communication_type = 'APPOINTMENT_REMINDER'
          and appointment_id = '14000000-0000-4000-8000-000000000266'
          and recipient_user_id = '14000000-0000-4000-8000-000000000211'
    ),
    'A former Guardian receives no reminder for the same Appointment'
);

-- --- Regression (self-contained): former Guardian after establishment ----
-- A reminder is established for two current Guardians of GapPetOne; one
-- Guardianship then ends before the Communication is fanned out. The
-- previously failing path is materialize() freezing fanout for the row whose
-- recipient is no longer current.
select pg_temp.assert_true(
    public.establish_due_appointment_reminders(
        '2035-10-01T13:00:00Z', interval '24 hours', interval '6 hours', 'es-ES'
    ) = 2,
    'A reminder is established for both current Guardians before fanout'
);

set local session_replication_role = replica;
update public.guardianships set effective_end = '2026-09-01T00:00:00Z'
where id = '14000000-0000-4000-8000-000000000252';
set local session_replication_role = origin;

do $$
declare
    former_guardian_communication_id uuid;
    current_guardian_communication_id uuid;
    drained integer;
begin
    select id into former_guardian_communication_id
    from public.transactional_communications
    where communication_type = 'APPOINTMENT_REMINDER'
      and appointment_id = '14000000-0000-4000-8000-000000000267'
      and recipient_user_id = '14000000-0000-4000-8000-000000000212';
    select id into current_guardian_communication_id
    from public.transactional_communications
    where communication_type = 'APPOINTMENT_REMINDER'
      and appointment_id = '14000000-0000-4000-8000-000000000267'
      and recipient_user_id = '14000000-0000-4000-8000-000000000211';

    perform pg_temp.assert_true(
        former_guardian_communication_id is not null
        and current_guardian_communication_id is not null
        and (select fanout_materialized_at is null
             from public.transactional_communications
             where id = former_guardian_communication_id),
        'Precondition: the former-Guardian reminder is established but not yet fanned out'
    );

    drained := public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true(
        drained >= 0,
        'materialize_communication_delivery_jobs does not throw after the Guardianship ends'
    );
    perform pg_temp.assert_true(
        (select fanout_materialized_at is not null
         from public.transactional_communications
         where id = former_guardian_communication_id),
        'The former-Guardian reminder remains a valid historical Communication'
    );
    perform pg_temp.assert_true(
        not exists (
            select 1 from public.communication_delivery_jobs
            where communication_id = former_guardian_communication_id
              and state <> 'SUPPRESSED'
        ),
        'The former Guardian receives no eligible delivery'
    );
    perform pg_temp.assert_true(
        exists (
            select 1 from public.communication_delivery_jobs
            where communication_id = current_guardian_communication_id
              and channel = 'EMAIL' and state = 'READY'
        ),
        'The still-current Guardian reminder materializes an eligible delivery'
    );

    perform public.materialize_communication_delivery_jobs();
    perform public.claim_communication_delivery_jobs(50, 120);
    perform pg_temp.assert_true(
        (select fanout_materialized_at is not null
         from public.transactional_communications
         where id = former_guardian_communication_id)
        and not exists (
            select 1 from public.transactional_communications
            where fanout_materialized_at is null
              and appointment_id = '14000000-0000-4000-8000-000000000267'
        ),
        'The dispatcher queue cannot be wedged by the historical Communication'
    );
end;
$$;

-- --- Push Registration lifecycle --------------------------------------
do $$
declare
    reg_a1 uuid;
    reg_a1_repeat uuid;
    reg_rotated uuid;
    reg_reassociated uuid;
    reg_second_device uuid;
    reg_disabled uuid;
    disable_authorized boolean;
    disable_cross_session boolean;
    disable_cross_user boolean;
    subject_one constant uuid := '14000000-0000-4000-8000-000000000204';
    subject_two constant uuid := '14000000-0000-4000-8000-000000000205';
    session_one constant uuid := '14000000-0000-4000-8000-000000000231';
    session_two constant uuid := '14000000-0000-4000-8000-000000000232';
    session_three constant uuid := '14000000-0000-4000-8000-000000000233';
    installation_a constant uuid := '14000000-0000-4000-8000-0000000002d1';
    installation_b constant uuid := '14000000-0000-4000-8000-0000000002d2';
    installation_a_replacement constant uuid :=
        '14000000-0000-4000-8000-0000000002d3';
begin
    -- Exact idempotent repeat registration keeps the same Registration.
    reg_a1 := public.upsert_session_push_registration(
        subject_one, session_one, installation_a,
        'ExponentPushToken[gap-u1-a]', 'IOS', 'com.petcare.gap.a'
    );
    reg_a1_repeat := public.upsert_session_push_registration(
        subject_one, session_one, installation_a,
        'ExponentPushToken[gap-u1-a]', 'IOS', 'com.petcare.gap.a'
    );
    perform pg_temp.assert_true(
        reg_a1_repeat = reg_a1
        and (select count(*) = 1 from public.push_registrations
             where device_installation_id = installation_a)
        and (select invalidated_at is null
                    and last_registered_at >= created_at
             from public.push_registrations where id = reg_a1),
        'An identical repeat registration is idempotent on the same Registration'
    );

    -- Token rotation for the same session and installation replaces the row.
    reg_rotated := public.upsert_session_push_registration(
        subject_one, session_one, installation_a,
        'ExponentPushToken[gap-u1-a-rotated]', 'IOS', 'com.petcare.gap.a'
    );
    perform pg_temp.assert_true(
        reg_rotated <> reg_a1
        and (select invalidated_at is not null
                    and invalidation_reason = 'REBOUND'
             from public.push_registrations where id = reg_a1)
        and (select invalidated_at is null
                    and provider_token =
                        'ExponentPushToken[gap-u1-a-rotated]'
             from public.push_registrations where id = reg_rotated)
        and (select count(*) = 1 from public.push_registrations
             where device_installation_id = installation_a
               and application_id = 'com.petcare.gap.a'
               and invalidated_at is null),
        'Token rotation invalidates the prior Registration and establishes the replacement'
    );

    -- The same installation and token reassociated to another session and
    -- User invalidates the previous eligible Registration.
    reg_reassociated := public.upsert_session_push_registration(
        subject_two, session_three, installation_a,
        'ExponentPushToken[gap-u1-a-rotated]', 'ANDROID', 'com.petcare.gap.a'
    );
    perform pg_temp.assert_true(
        reg_reassociated <> reg_rotated
        and (select invalidated_at is not null
                    and invalidation_reason = 'REBOUND'
             from public.push_registrations where id = reg_rotated)
        and (select user_id = '14000000-0000-4000-8000-000000000215'
                    and auth_session_id = session_three
                    and invalidated_at is null
             from public.push_registrations where id = reg_reassociated),
        'Reassociating a destination to another session and User rebinds it safely'
    );

    -- A second device on an independent session survives the first session
    -- being disabled through the exact authorized context.
    reg_second_device := public.upsert_session_push_registration(
        subject_one, session_two, installation_b,
        'ExponentPushToken[gap-u1-b]', 'IOS', 'com.petcare.gap.b'
    );
    reg_disabled := public.upsert_session_push_registration(
        subject_one, session_one, installation_a_replacement,
        'ExponentPushToken[gap-u1-a2]', 'IOS', 'com.petcare.gap.a2'
    );
    disable_authorized := public.invalidate_session_push_registration(
        subject_one, session_one, reg_disabled
    );
    perform pg_temp.assert_true(
        disable_authorized is true
        and (select invalidated_at is not null
                    and invalidation_reason = 'CLIENT_DISABLED'
             from public.push_registrations where id = reg_disabled),
        'Exact-session disable succeeds for the authorized current context'
    );
    perform pg_temp.assert_true(
        (select invalidated_at is null
         from public.push_registrations where id = reg_second_device)
        and exists (select 1 from auth.sessions where id = session_two),
        'A second-device Registration survives the first session being disabled'
    );

    -- Cross-session and cross-User disable attempts are rejected and inert.
    disable_cross_session := public.invalidate_session_push_registration(
        subject_one, session_two, reg_reassociated
    );
    disable_cross_user := public.invalidate_session_push_registration(
        subject_two, session_three, reg_second_device
    );
    perform pg_temp.assert_true(
        disable_cross_session is false
        and disable_cross_user is false
        and (select invalidated_at is null
             from public.push_registrations where id = reg_second_device)
        and (select invalidated_at is null
             from public.push_registrations where id = reg_reassociated),
        'A disable from another session or User is rejected and changes nothing'
    );
end;
$$;

-- --- Communications authorization boundary ------------------------------
do $$
declare
    role_name text;
    relation_name text;
    function_signature text;
begin
    -- Neither anon nor authenticated may read or mutate Communications tables.
    foreach role_name in array array['anon', 'authenticated'] loop
        foreach relation_name in array array[
            'public.transactional_communications',
            'public.push_registrations',
            'public.communication_delivery_jobs',
            'public.communication_delivery_attempts'
        ] loop
            perform pg_temp.assert_true(
                (select bool_and(
                    not has_table_privilege(role_name, relation_name, p))
                 from unnest(
                     array['SELECT', 'INSERT', 'UPDATE', 'DELETE']
                 ) as p),
                format(
                    '%s holds no direct privilege on %s',
                    role_name, relation_name
                )
            );
        end loop;
    end loop;

    perform pg_temp.assert_true(
        (select bool_and(relrowsecurity)
         from pg_class
         where oid in (
             'public.transactional_communications'::regclass,
             'public.push_registrations'::regclass,
             'public.communication_delivery_jobs'::regclass,
             'public.communication_delivery_attempts'::regclass
         )),
        'Row level security stays enabled on every Communications table'
    );

    -- Service, maintenance, and authenticated-client database commands are
    -- unreachable from anon and authenticated, and remain callable by the
    -- trusted service role.
    foreach function_signature in array array[
        'public.upsert_session_push_registration(uuid,uuid,uuid,text,text,text)',
        'public.invalidate_session_push_registration(uuid,uuid,uuid)',
        'public.create_scoped_organization_invitation_with_communication(uuid,uuid,uuid,text,jsonb,timestamptz,bytea,integer,bytea,bytea)',
        'public.create_guardianship_invitation_with_communication(uuid,uuid,uuid,uuid,text,timestamptz,bytea,integer,bytea,bytea)',
        'public.establish_due_appointment_reminders(timestamptz,interval,interval,text)',
        'public.materialize_communication_delivery_jobs()',
        'public.claim_communication_delivery_jobs(integer,integer)',
        'public.get_communication_delivery_context(uuid,uuid)',
        'public.mark_communication_delivery_submission_started(uuid,uuid)',
        'public.complete_communication_delivery_job(uuid,uuid,text,text,text,text,integer)',
        'public.claim_expo_push_receipts(integer,integer)',
        'public.complete_expo_push_receipt(uuid,uuid,text,text,text,integer)',
        'public.record_resend_delivery_event(text,text,text,timestamptz)'
    ] loop
        perform pg_temp.assert_true(
            not has_function_privilege('anon', function_signature, 'EXECUTE')
            and not has_function_privilege(
                'authenticated', function_signature, 'EXECUTE'
            ),
            format(
                'anon and authenticated cannot execute %s', function_signature
            )
        );
        perform pg_temp.assert_true(
            has_function_privilege(
                'service_role', function_signature, 'EXECUTE'
            ),
            format(
                'service_role retains the trusted boundary for %s',
                function_signature
            )
        );
    end loop;

    -- Internal trigger and helper routines are not exposed to client roles.
    foreach function_signature in array array[
        'public.build_invitation_secret_aad(text,text,timestamptz,bytea)',
        'public.communication_delivery_is_currently_eligible(uuid,text,uuid,text)',
        'public.enqueue_appointment_communications()',
        'public.enforce_transactional_communication_integrity()',
        'public.enforce_push_registration_integrity()',
        'public.enforce_communication_delivery_job_integrity()',
        'public.enforce_new_invitation_communication_handoff()',
        'public.preserve_transactional_communication_history()',
        'public.preserve_communication_delivery_attempt_history()'
    ] loop
        perform pg_temp.assert_true(
            not has_function_privilege('anon', function_signature, 'EXECUTE')
            and not has_function_privilege(
                'authenticated', function_signature, 'EXECUTE'
            ),
            format(
                'anon and authenticated cannot execute internal %s',
                function_signature
            )
        );
    end loop;
end;
$$;

rollback;
