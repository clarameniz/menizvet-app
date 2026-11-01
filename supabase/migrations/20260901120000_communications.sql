begin;

-- Slice 14: provider-independent durable Communications handoff. Provider
-- credentials and pricing remain deployment configuration, never schema.

create function public.build_invitation_secret_aad(
    p_invitation_kind text,
    p_recipient_email text,
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea
)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
    kind_prefix text;
begin
    if p_invitation_kind not in ('organization', 'guardianship')
       or p_recipient_email <> btrim(p_recipient_email, E' \t\n\r\f\013')
       or p_recipient_email = ''
       or not isfinite(p_expires_at)
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Invitation AAD inputs are invalid' using errcode = '22023';
    end if;

    kind_prefix := 'petcare.invitation.' || p_invitation_kind || '.v1';
    return kind_prefix
        || '|recipient_email_hex='
        || encode(convert_to(lower(p_recipient_email), 'UTF8'), 'hex')
        || '|expires_at_ms='
        || ((extract(epoch from p_expires_at) * 1000)::bigint)::text
        || '|acceptance_digest_hex='
        || encode(p_acceptance_secret_digest, 'hex');
end;
$$;

revoke all privileges on function public.build_invitation_secret_aad(
    text, text, timestamptz, bytea
) from public, anon, authenticated;

create table public.transactional_communications (
    id uuid not null default gen_random_uuid(),
    communication_type text not null,
    recipient_user_id uuid,
    recipient_email text,
    locale text not null default 'es-ES',
    organization_invitation_id uuid,
    guardianship_invitation_id uuid,
    appointment_id uuid,
    appointment_lifecycle_event_id uuid,
    appointment_reschedule_proposal_id uuid,
    appointment_schedule_revision_id uuid,
    secret_envelope_version smallint,
    secret_key_version integer,
    secret_algorithm text,
    secret_aad_context text,
    secret_nonce bytea,
    secret_ciphertext bytea,
    secret_consumed_at timestamptz,
    fanout_materialized_at timestamptz,
    created_at timestamptz not null default transaction_timestamp(),
    constraint transactional_communications_pkey primary key (id),
    constraint transactional_communications_recipient_user_id_fkey
        foreign key (recipient_user_id) references public.users (id)
        on update no action on delete restrict,
    constraint transactional_communications_organization_invitation_id_fkey
        foreign key (organization_invitation_id)
        references public.organization_invitations (id)
        on update no action on delete restrict,
    constraint transactional_communications_guardianship_invitation_id_fkey
        foreign key (guardianship_invitation_id)
        references public.guardianship_invitations (id)
        on update no action on delete restrict,
    constraint transactional_communications_appointment_id_fkey
        foreign key (appointment_id) references public.appointments (id)
        on update no action on delete restrict,
    constraint transactional_communications_lifecycle_event_id_fkey
        foreign key (appointment_lifecycle_event_id)
        references public.appointment_lifecycle_events (id)
        on update no action on delete restrict,
    constraint transactional_communications_reschedule_proposal_id_fkey
        foreign key (appointment_reschedule_proposal_id)
        references public.appointment_reschedule_proposals (id)
        on update no action on delete restrict,
    constraint transactional_communications_schedule_revision_id_fkey
        foreign key (appointment_schedule_revision_id)
        references public.appointment_schedule_revisions (id)
        on update no action on delete restrict,
    constraint transactional_communications_type_check check (
        communication_type in (
            'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION',
            'APPOINTMENT_REQUESTED', 'APPOINTMENT_CONFIRMED',
            'APPOINTMENT_CANCELLED', 'APPOINTMENT_RESCHEDULE_PROPOSED',
            'APPOINTMENT_RESCHEDULE_ACCEPTED', 'APPOINTMENT_COMPLETED',
            'APPOINTMENT_NO_SHOW', 'APPOINTMENT_REMINDER'
        )
    ),
    constraint transactional_communications_recipient_check check (
        recipient_user_id is not null
        or (
            recipient_email is not null
            and recipient_email = btrim(recipient_email, E' \t\n\r\f\013')
            and recipient_email <> ''
        )
    ),
    constraint transactional_communications_recipient_shape_check check (
        (
            communication_type in (
                'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
            )
            and recipient_email is not null
        )
        or (
            communication_type not in (
                'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
            )
            and recipient_user_id is not null
            and recipient_email is null
        )
    ),
    constraint transactional_communications_locale_check check (
        locale = btrim(locale, E' \t\n\r\f\013') and locale <> ''
    ),
    constraint transactional_communications_created_at_check
        check (isfinite(created_at)),
    constraint transactional_communications_fanout_time_check check (
        fanout_materialized_at is null
        or isfinite(fanout_materialized_at)
    ),
    constraint transactional_communications_secret_shape_check check (
        (
            communication_type in (
                'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
            )
            and (
                (
                    secret_consumed_at is null
                    and secret_envelope_version = 1
                    and secret_key_version > 0
                    and secret_algorithm = 'AES-256-GCM'
                    and secret_aad_context ~ case communication_type
                        when 'ORGANIZATION_INVITATION' then
                            '^petcare\.invitation\.organization\.v1\|recipient_email_hex=[0-9a-f]+\|expires_at_ms=-?[0-9]+\|acceptance_digest_hex=[0-9a-f]{64}$'
                        when 'GUARDIANSHIP_INVITATION' then
                            '^petcare\.invitation\.guardianship\.v1\|recipient_email_hex=[0-9a-f]+\|expires_at_ms=-?[0-9]+\|acceptance_digest_hex=[0-9a-f]{64}$'
                    end
                    and octet_length(secret_nonce) = 12
                    and octet_length(secret_ciphertext) >= 16
                )
                or (
                    secret_consumed_at is not null
                    and isfinite(secret_consumed_at)
                    and secret_envelope_version = 1
                    and secret_key_version > 0
                    and secret_algorithm = 'AES-256-GCM'
                    and secret_aad_context ~ case communication_type
                        when 'ORGANIZATION_INVITATION' then
                            '^petcare\.invitation\.organization\.v1\|recipient_email_hex=[0-9a-f]+\|expires_at_ms=-?[0-9]+\|acceptance_digest_hex=[0-9a-f]{64}$'
                        when 'GUARDIANSHIP_INVITATION' then
                            '^petcare\.invitation\.guardianship\.v1\|recipient_email_hex=[0-9a-f]+\|expires_at_ms=-?[0-9]+\|acceptance_digest_hex=[0-9a-f]{64}$'
                    end
                    and secret_nonce is null
                    and secret_ciphertext is null
                    and secret_consumed_at >= created_at
                )
            )
        )
        or (
            communication_type not in (
                'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
            )
            and secret_envelope_version is null
            and secret_key_version is null
            and secret_algorithm is null
            and secret_aad_context is null
            and secret_nonce is null
            and secret_ciphertext is null
            and secret_consumed_at is null
        )
    ),
    constraint transactional_communications_origin_shape_check check (
        (
            communication_type = 'ORGANIZATION_INVITATION'
            and organization_invitation_id is not null
            and guardianship_invitation_id is null
            and appointment_id is null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'GUARDIANSHIP_INVITATION'
            and organization_invitation_id is null
            and guardianship_invitation_id is not null
            and appointment_id is null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'APPOINTMENT_REQUESTED'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is not null
        )
        or (
            communication_type in (
                'APPOINTMENT_CONFIRMED', 'APPOINTMENT_CANCELLED',
                'APPOINTMENT_COMPLETED', 'APPOINTMENT_NO_SHOW'
            )
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is not null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is not null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is not null
            and appointment_schedule_revision_id is not null
        )
        or (
            communication_type = 'APPOINTMENT_REMINDER'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is not null
        )
    )
);

create table public.push_registrations (
    id uuid not null default gen_random_uuid(),
    user_id uuid not null,
    auth_session_id uuid not null,
    device_installation_id uuid not null,
    provider text not null default 'EXPO',
    provider_token text not null,
    provider_token_digest bytea generated always as (
        sha256(provider_token::bytea)
    ) stored,
    platform text not null,
    application_id text not null,
    created_at timestamptz not null default transaction_timestamp(),
    last_registered_at timestamptz not null default transaction_timestamp(),
    invalidated_at timestamptz,
    invalidation_reason text,
    constraint push_registrations_pkey primary key (id),
    constraint push_registrations_user_id_fkey
        foreign key (user_id) references public.users (id)
        on update no action on delete restrict,
    constraint push_registrations_provider_check check (
        provider ~ '^[A-Z][A-Z0-9_]{1,31}$'
    ),
    constraint push_registrations_token_check check (
        provider_token = btrim(provider_token, E' \t\n\r\f\013')
        and provider_token <> ''
    ),
    constraint push_registrations_token_digest_check check (
        octet_length(provider_token_digest) = 32
    ),
    constraint push_registrations_platform_check
        check (platform in ('IOS', 'ANDROID')),
    constraint push_registrations_application_id_check check (
        application_id = btrim(application_id, E' \t\n\r\f\013')
        and application_id <> ''
    ),
    constraint push_registrations_time_check check (
        isfinite(created_at) and isfinite(last_registered_at)
        and last_registered_at >= created_at
        and (invalidated_at is null or isfinite(invalidated_at))
    ),
    constraint push_registrations_invalidation_pair_check check (
        (invalidated_at is null) = (invalidation_reason is null)
    )
);

create unique index push_registrations_active_token_key
on public.push_registrations (provider, provider_token_digest)
where invalidated_at is null;

create unique index push_registrations_active_installation_key
on public.push_registrations (device_installation_id, application_id)
where invalidated_at is null;

create index push_registrations_session_eligibility_idx
on public.push_registrations (auth_session_id, user_id)
where invalidated_at is null;

create function public.enforce_push_registration_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Push Registrations cannot be deleted through ordinary operations'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.user_id is distinct from new.user_id
       or old.auth_session_id is distinct from new.auth_session_id
       or old.device_installation_id is distinct from new.device_installation_id
       or old.provider is distinct from new.provider
       or old.provider_token is distinct from new.provider_token
       or old.application_id is distinct from new.application_id
       or old.created_at is distinct from new.created_at
       or new.last_registered_at < old.last_registered_at then
        raise exception 'Push Registration identity, session, and destination history are immutable'
            using errcode = '23514';
    end if;

    if old.invalidated_at is not null
       and (
           new.invalidated_at is distinct from old.invalidated_at
           or new.invalidation_reason is distinct from old.invalidation_reason
       ) then
        raise exception 'Push Registration invalidation is terminal'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_push_registration_integrity()
from public, anon, authenticated;

create trigger push_registrations_enforce_integrity
before update or delete on public.push_registrations
for each row execute function public.enforce_push_registration_integrity();

create table public.communication_delivery_jobs (
    id uuid not null default gen_random_uuid(),
    communication_id uuid not null,
    channel text not null,
    provider text not null,
    destination_key text not null,
    destination_snapshot text,
    push_registration_id uuid,
    state text not null default 'READY',
    submission_count integer not null default 0,
    provider_message_id text,
    provider_status text,
    last_error_code text,
    next_attempt_at timestamptz not null default transaction_timestamp(),
    lease_token uuid,
    lease_expires_at timestamptz,
    provider_event_id text,
    provider_event_occurred_at timestamptz,
    receipt_checked_at timestamptz,
    created_at timestamptz not null default transaction_timestamp(),
    first_submitted_at timestamptz,
    last_submitted_at timestamptz,
    active_submission_started_at timestamptz,
    resolved_at timestamptz,
    constraint communication_delivery_jobs_pkey primary key (id),
    constraint communication_delivery_jobs_communication_id_fkey
        foreign key (communication_id)
        references public.transactional_communications (id)
        on update no action on delete restrict,
    constraint communication_delivery_jobs_push_registration_id_fkey
        foreign key (push_registration_id)
        references public.push_registrations (id)
        on update no action on delete restrict,
    constraint communication_delivery_jobs_channel_shape_check check (
        (channel = 'EMAIL' and push_registration_id is null)
        or (channel = 'PUSH' and push_registration_id is not null)
    ),
    constraint communication_delivery_jobs_provider_check check (
        provider ~ '^[A-Z][A-Z0-9_]{1,31}$'
    ),
    constraint communication_delivery_jobs_provider_state_check check (
        (state <> 'UPSTREAM_ACCEPTED' or provider = 'EXPO')
        and not (provider = 'EXPO' and state = 'DELIVERED')
    ),
    constraint communication_delivery_jobs_destination_key_check check (
        destination_key = btrim(destination_key, E' \t\n\r\f\013')
        and destination_key <> ''
    ),
    constraint communication_delivery_jobs_state_check check (
        state in (
            'READY', 'CLAIMED', 'RETRYABLE', 'ACCEPTED', 'DELIVERED',
            'UPSTREAM_ACCEPTED', 'UNKNOWN', 'PERMANENT_FAILURE',
            'SUPPRESSED'
        )
    ),
    constraint communication_delivery_jobs_submission_count_check
        check (submission_count >= 0),
    constraint communication_delivery_jobs_submission_time_shape_check check (
        (
            submission_count = 0
            and first_submitted_at is null
            and last_submitted_at is null
        )
        or (
            submission_count > 0
            and first_submitted_at is not null
            and last_submitted_at is not null
        )
    ),
    constraint communication_delivery_jobs_lease_pair_check check (
        (lease_token is null) = (lease_expires_at is null)
    ),
    constraint communication_delivery_jobs_lease_state_check check (
        (state = 'CLAIMED' and lease_token is not null)
        or (state = 'ACCEPTED')
        or (state not in ('CLAIMED', 'ACCEPTED') and lease_token is null)
    ),
    constraint communication_delivery_jobs_active_submission_shape_check check (
        active_submission_started_at is null
        or (
            state = 'CLAIMED'
            and lease_token is not null
            and submission_count > 0
        )
    ),
    constraint communication_delivery_jobs_resolution_shape_check check (
        (state in (
            'DELIVERED', 'UPSTREAM_ACCEPTED', 'UNKNOWN',
            'PERMANENT_FAILURE', 'SUPPRESSED'
        ))
        = (resolved_at is not null)
    ),
    constraint communication_delivery_jobs_time_check check (
        isfinite(next_attempt_at) and isfinite(created_at)
        and (lease_expires_at is null or isfinite(lease_expires_at))
        and (first_submitted_at is null or isfinite(first_submitted_at))
        and (last_submitted_at is null or isfinite(last_submitted_at))
        and (active_submission_started_at is null or isfinite(active_submission_started_at))
        and (
            first_submitted_at is null
            or last_submitted_at is null
            or first_submitted_at <= last_submitted_at
        )
        and (resolved_at is null or isfinite(resolved_at))
        and (provider_event_occurred_at is null or isfinite(provider_event_occurred_at))
        and (receipt_checked_at is null or isfinite(receipt_checked_at))
    ),
    constraint communication_delivery_jobs_destination_shape_check check (
        state in ('PERMANENT_FAILURE', 'SUPPRESSED')
        or destination_snapshot is not null
    ),
    constraint communication_delivery_jobs_destination_privacy_check check (
        channel = 'EMAIL'
        or destination_snapshot ~ '^sha256:[0-9a-f]{64}$'
    ),
    constraint communication_delivery_jobs_communication_destination_key
        unique (communication_id, channel, destination_key)
);

create unique index communication_delivery_jobs_provider_message_key
on public.communication_delivery_jobs (provider, provider_message_id)
where provider_message_id is not null;

create index communication_delivery_jobs_dispatch_idx
on public.communication_delivery_jobs (state, next_attempt_at, created_at);

create index communication_delivery_jobs_receipt_idx
on public.communication_delivery_jobs (provider, state, next_attempt_at)
where provider = 'EXPO' and state = 'ACCEPTED';

create table public.communication_delivery_attempts (
    id uuid not null default gen_random_uuid(),
    delivery_job_id uuid not null,
    communication_id uuid not null,
    attempt_number integer not null,
    channel text not null,
    provider text not null,
    destination_snapshot text not null,
    push_registration_id uuid,
    outcome text not null,
    provider_message_id text,
    provider_status text,
    error_code text,
    attempted_at timestamptz not null default clock_timestamp(),
    constraint communication_delivery_attempts_pkey primary key (id),
    constraint communication_delivery_attempts_delivery_job_id_fkey
        foreign key (delivery_job_id)
        references public.communication_delivery_jobs (id)
        on update no action on delete restrict,
    constraint communication_delivery_attempts_communication_id_fkey
        foreign key (communication_id)
        references public.transactional_communications (id)
        on update no action on delete restrict,
    constraint communication_delivery_attempts_push_registration_id_fkey
        foreign key (push_registration_id)
        references public.push_registrations (id)
        on update no action on delete restrict,
    constraint communication_delivery_attempts_number_check
        check (attempt_number > 0),
    constraint communication_delivery_attempts_channel_shape_check check (
        (channel = 'EMAIL' and push_registration_id is null)
        or (channel = 'PUSH' and push_registration_id is not null)
    ),
    constraint communication_delivery_attempts_provider_check check (
        provider ~ '^[A-Z][A-Z0-9_]{1,31}$'
    ),
    constraint communication_delivery_attempts_provider_outcome_check check (
        not (provider = 'EXPO' and outcome = 'DELIVERED')
    ),
    constraint communication_delivery_attempts_destination_check check (
        destination_snapshot = btrim(destination_snapshot, E' \t\n\r\f\013')
        and destination_snapshot <> ''
    ),
    constraint communication_delivery_attempts_destination_privacy_check check (
        channel = 'EMAIL'
        or destination_snapshot ~ '^sha256:[0-9a-f]{64}$'
    ),
    constraint communication_delivery_attempts_outcome_check check (
        outcome in (
            'ACCEPTED', 'DELIVERED', 'RETRYABLE', 'UNKNOWN',
            'PERMANENT_FAILURE'
        )
    ),
    constraint communication_delivery_attempts_provider_identity_check check (
        outcome not in ('ACCEPTED', 'DELIVERED')
        or (
            provider_message_id is not null
            and btrim(provider_message_id, E' \t\n\r\f\013') <> ''
        )
    ),
    constraint communication_delivery_attempts_attempted_at_check
        check (isfinite(attempted_at)),
    constraint communication_delivery_attempts_job_number_key
        unique (delivery_job_id, attempt_number)
);

create index communication_delivery_attempts_history_idx
on public.communication_delivery_attempts (
    communication_id, attempted_at, id
);

alter table public.transactional_communications enable row level security;
alter table public.push_registrations enable row level security;
alter table public.communication_delivery_jobs enable row level security;
alter table public.communication_delivery_attempts enable row level security;

revoke all privileges on table public.transactional_communications
from public, anon, authenticated;
revoke all privileges on table public.push_registrations
from public, anon, authenticated;
revoke all privileges on table public.communication_delivery_jobs
from public, anon, authenticated;
revoke all privileges on table public.communication_delivery_attempts
from public, anon, authenticated;

-- One logical Communication per authoritative origin and recipient.
create unique index transactional_communications_org_invitation_key
on public.transactional_communications (organization_invitation_id)
where communication_type = 'ORGANIZATION_INVITATION';

create unique index transactional_communications_guardianship_invitation_key
on public.transactional_communications (guardianship_invitation_id)
where communication_type = 'GUARDIANSHIP_INVITATION';

create unique index transactional_communications_appointment_created_key
on public.transactional_communications (appointment_id, recipient_user_id)
where communication_type = 'APPOINTMENT_REQUESTED';

create unique index transactional_communications_lifecycle_event_key
on public.transactional_communications (
    appointment_lifecycle_event_id, recipient_user_id
)
where appointment_lifecycle_event_id is not null;

create unique index transactional_communications_proposal_created_key
on public.transactional_communications (
    appointment_reschedule_proposal_id, recipient_user_id
)
where communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED';

create unique index transactional_communications_proposal_accepted_key
on public.transactional_communications (
    appointment_reschedule_proposal_id, recipient_user_id
)
where communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED';

create unique index transactional_communications_reminder_key
on public.transactional_communications (
    appointment_schedule_revision_id, recipient_user_id
)
where communication_type = 'APPOINTMENT_REMINDER';

create function public.enforce_transactional_communication_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.organization_invitation_id is not null
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = new.organization_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'organization', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Organization Invitation'
            using errcode = '23514';
    end if;

    if new.guardianship_invitation_id is not null
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = new.guardianship_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'guardianship', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Guardianship Invitation'
            using errcode = '23514';
    end if;

    if new.appointment_lifecycle_event_id is not null
       and not exists (
           select 1 from public.appointment_lifecycle_events as event_record
           where event_record.id = new.appointment_lifecycle_event_id
             and event_record.appointment_id = new.appointment_id
             and (
                 (new.communication_type = 'APPOINTMENT_CONFIRMED' and event_record.to_state = 'CONFIRMED')
                 or (new.communication_type = 'APPOINTMENT_CANCELLED' and event_record.to_state = 'CANCELLED')
                 or (new.communication_type = 'APPOINTMENT_COMPLETED' and event_record.to_state = 'COMPLETED')
                 or (new.communication_type = 'APPOINTMENT_NO_SHOW' and event_record.to_state = 'NO_SHOW')
             )
       ) then
        raise exception 'Communication lifecycle origin does not match its Appointment and type'
            using errcode = '23514';
    end if;

    if new.appointment_reschedule_proposal_id is not null
       and not exists (
           select 1 from public.appointment_reschedule_proposals as proposal
           where proposal.id = new.appointment_reschedule_proposal_id
             and proposal.appointment_id = new.appointment_id
              and (
                  new.appointment_schedule_revision_id is null
                  or proposal.resulting_confirmed_revision_id = new.appointment_schedule_revision_id
              )
              and (
                  new.communication_type <> 'APPOINTMENT_RESCHEDULE_PROPOSED'
                  or proposal.proposing_context = 'CLINIC'
              )
       ) then
        raise exception 'Communication Proposal origin does not match its Appointment or revision'
            using errcode = '23514';
    end if;

    if new.appointment_schedule_revision_id is not null
       and not exists (
           select 1 from public.appointment_schedule_revisions as revision
           where revision.id = new.appointment_schedule_revision_id
             and revision.appointment_id = new.appointment_id
             and revision.revision_context = case
                 when new.communication_type = 'APPOINTMENT_REQUESTED'
                     then 'REQUESTED'
                 else 'CONFIRMED'
             end
       ) then
        raise exception 'Communication Schedule Revision origin does not match its Appointment'
            using errcode = '23514';
    end if;

    if new.recipient_user_id is not null
       and new.appointment_id is not null
       and not exists (
           select 1
           from public.appointments as appointment
           join public.guardianships as guardianship
             on guardianship.pet_id = appointment.pet_id
           where appointment.id = new.appointment_id
             and guardianship.user_id = new.recipient_user_id
             and guardianship.effective_start <= new.created_at
             and guardianship.effective_end is null
       ) then
        raise exception 'Appointment Communication recipient must be a current Guardian'
            using errcode = '23514';
    end if;

    if tg_op = 'UPDATE' then
        if old.id is distinct from new.id
           or old.communication_type is distinct from new.communication_type
           or old.recipient_user_id is distinct from new.recipient_user_id
           or old.recipient_email is distinct from new.recipient_email
           or old.locale is distinct from new.locale
           or old.organization_invitation_id is distinct from new.organization_invitation_id
           or old.guardianship_invitation_id is distinct from new.guardianship_invitation_id
           or old.appointment_id is distinct from new.appointment_id
           or old.appointment_lifecycle_event_id is distinct from new.appointment_lifecycle_event_id
           or old.appointment_reschedule_proposal_id is distinct from new.appointment_reschedule_proposal_id
           or old.appointment_schedule_revision_id is distinct from new.appointment_schedule_revision_id
           or old.secret_envelope_version is distinct from new.secret_envelope_version
           or old.secret_key_version is distinct from new.secret_key_version
           or old.secret_algorithm is distinct from new.secret_algorithm
           or old.secret_aad_context is distinct from new.secret_aad_context
           or old.created_at is distinct from new.created_at
           or (
               old.fanout_materialized_at is not null
               and new.fanout_materialized_at is distinct from
                   old.fanout_materialized_at
           )
           or (old.secret_consumed_at is not null and new.secret_consumed_at is distinct from old.secret_consumed_at)
           or (old.secret_consumed_at is null and new.secret_consumed_at is null and (
               old.secret_nonce is distinct from new.secret_nonce
               or old.secret_ciphertext is distinct from new.secret_ciphertext
           )) then
            raise exception 'Communication identity, origin, recipient, and encrypted handoff are immutable'
                using errcode = '23514';
        end if;

        if old.secret_consumed_at is null and new.secret_consumed_at is not null
           and (new.secret_nonce is not null or new.secret_ciphertext is not null) then
            raise exception 'Consuming an Invitation secret must erase its encrypted payload'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_transactional_communication_integrity()
from public, anon, authenticated;

create trigger transactional_communications_enforce_integrity
before insert or update on public.transactional_communications
for each row execute function public.enforce_transactional_communication_integrity();

create function public.preserve_transactional_communication_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'Transactional Communications cannot be deleted through ordinary operations'
        using errcode = '23514';
end;
$$;

revoke all privileges on function public.preserve_transactional_communication_history()
from public, anon, authenticated;

create trigger transactional_communications_preserve_history
before delete on public.transactional_communications
for each row execute function public.preserve_transactional_communication_history();

create function public.enforce_new_invitation_communication_handoff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'organization_invitations' and not exists (
        select 1
        from public.transactional_communications as communication
        where communication.communication_type = 'ORGANIZATION_INVITATION'
          and communication.organization_invitation_id = new.id
          and communication.recipient_user_id is not distinct from
              new.recipient_user_id
          and communication.recipient_email = new.recipient_email
    ) then
        raise exception 'A new Organization Invitation requires its exact Communication at commit'
            using errcode = '23514';
    elsif tg_table_name = 'guardianship_invitations' and not exists (
        select 1
        from public.transactional_communications as communication
        where communication.communication_type = 'GUARDIANSHIP_INVITATION'
          and communication.guardianship_invitation_id = new.id
          and communication.recipient_user_id is not distinct from
              new.recipient_user_id
          and communication.recipient_email = new.recipient_email
    ) then
        raise exception 'A new Guardianship Invitation requires its exact Communication at commit'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_new_invitation_communication_handoff()
from public, anon, authenticated;

create constraint trigger organization_invitations_require_communication
after insert on public.organization_invitations
deferrable initially deferred
for each row execute function public.enforce_new_invitation_communication_handoff();

create constraint trigger guardianship_invitations_require_communication
after insert on public.guardianship_invitations
deferrable initially deferred
for each row execute function public.enforce_new_invitation_communication_handoff();

create function public.upsert_session_push_registration(
    p_auth_subject uuid,
    p_auth_session_id uuid,
    p_device_installation_id uuid,
    p_provider_token text,
    p_platform text,
    p_application_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    domain_user_id uuid;
    operation_timestamp timestamptz := clock_timestamp();
    normalized_token text;
    normalized_token_digest bytea;
    normalized_application_id text;
    existing_registration_id uuid;
begin
    select identity_record.user_id
    into domain_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth'
      and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;

    if domain_user_id is null or not exists (
        select 1 from auth.sessions as auth_session
        where auth_session.id = p_auth_session_id
          and auth_session.user_id = p_auth_subject
    ) then
        raise exception 'A live matching authentication session is required'
            using errcode = '28000';
    end if;

    normalized_token := btrim(p_provider_token, E' \t\n\r\f\013');
    normalized_application_id := btrim(p_application_id, E' \t\n\r\f\013');

    if p_device_installation_id is null
       or normalized_token is null
       or normalized_token = ''
       or normalized_application_id is null
       or normalized_application_id = ''
       or p_platform is null
       or upper(p_platform) not in ('IOS', 'ANDROID')
       or normalized_token !~ E'^ExponentPushToken\\[[A-Za-z0-9_-]+\\]$|^ExpoPushToken\\[[A-Za-z0-9_-]+\\]$' then
        raise exception 'A valid Push Registration contract is required'
            using errcode = '22023';
    end if;

    normalized_token_digest := sha256(convert_to(normalized_token, 'UTF8'));

    perform 1
    from public.push_registrations as registration
    where registration.invalidated_at is null
      and (
          (
              registration.provider = 'EXPO'
              and registration.provider_token_digest = normalized_token_digest
          )
          or (
              registration.device_installation_id = p_device_installation_id
              and registration.application_id = normalized_application_id
          )
      )
    order by registration.id
    for update;

    select registration.id
    into existing_registration_id
    from public.push_registrations as registration
    where registration.invalidated_at is null
      and registration.user_id = domain_user_id
      and registration.auth_session_id = p_auth_session_id
      and registration.device_installation_id = p_device_installation_id
      and registration.application_id = normalized_application_id
      and registration.provider_token_digest = normalized_token_digest;

    if existing_registration_id is not null then
        update public.push_registrations
        set last_registered_at = operation_timestamp,
            platform = upper(p_platform)
        where id = existing_registration_id;
        return existing_registration_id;
    end if;

    update public.push_registrations
    set invalidated_at = operation_timestamp,
        invalidation_reason = 'REBOUND'
    where invalidated_at is null
      and (
          (
              provider = 'EXPO'
              and provider_token_digest = normalized_token_digest
          )
          or (
              device_installation_id = p_device_installation_id
              and application_id = normalized_application_id
          )
      );

    insert into public.push_registrations (
        user_id, auth_session_id, device_installation_id, provider,
        provider_token, platform, application_id, created_at,
        last_registered_at
    ) values (
        domain_user_id, p_auth_session_id, p_device_installation_id, 'EXPO',
        normalized_token, upper(p_platform), normalized_application_id,
        operation_timestamp, operation_timestamp
    ) returning id into existing_registration_id;

    return existing_registration_id;
end;
$$;

revoke all privileges on function public.upsert_session_push_registration(
    uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_session_push_registration(
    uuid, uuid, uuid, text, text, text
) to service_role;

create function public.invalidate_session_push_registration(
    p_auth_subject uuid,
    p_auth_session_id uuid,
    p_registration_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    domain_user_id uuid;
begin
    select identity_record.user_id into domain_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth'
      and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;

    if domain_user_id is null then
        raise exception 'A coherent domain User is required' using errcode = '28000';
    end if;

    update public.push_registrations
    set invalidated_at = clock_timestamp(), invalidation_reason = 'CLIENT_DISABLED'
    where id = p_registration_id
      and user_id = domain_user_id
      and auth_session_id = p_auth_session_id
      and invalidated_at is null;

    return found;
end;
$$;

revoke all privileges on function public.invalidate_session_push_registration(
    uuid, uuid, uuid
) from public, anon, authenticated;
grant execute on function public.invalidate_session_push_registration(
    uuid, uuid, uuid
) to service_role;

-- Cut over Invitation creation without touching any pre-cutover row. The old
-- service-only commands remain present for historical acceptance compatibility
-- but can no longer create a new Invitation without its Communication.
revoke execute on function public.create_scoped_organization_invitation(
    uuid, uuid, uuid, text, jsonb, timestamptz, bytea
) from service_role;
revoke execute on function public.create_organization_invitation(
    uuid, uuid, uuid, text, text[], timestamptz, bytea
) from service_role;
revoke execute on function public.create_guardianship_invitation(
    uuid, uuid, uuid, uuid, text, timestamptz, bytea
) from service_role;

create function public.create_scoped_organization_invitation_with_communication(
    p_auth_subject uuid,
    p_organization_id uuid,
    p_recipient_user_id uuid,
    p_recipient_email text,
    p_intended_responsibilities jsonb,
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea,
    p_secret_key_version integer,
    p_secret_nonce bytea,
    p_secret_ciphertext bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    invitation_id uuid;
begin
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth'
      and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;

    if acting_user_id is null then
        raise exception 'A coherent acting domain User is required'
            using errcode = '28000';
    end if;

    invitation_id := public.create_scoped_organization_invitation(
        acting_user_id, p_organization_id, p_recipient_user_id,
        p_recipient_email, p_intended_responsibilities, p_expires_at,
        p_acceptance_secret_digest
    );

    insert into public.transactional_communications (
        communication_type, recipient_user_id, recipient_email, locale,
        organization_invitation_id, secret_envelope_version,
        secret_key_version, secret_algorithm, secret_aad_context,
        secret_nonce, secret_ciphertext
    ) values (
        'ORGANIZATION_INVITATION', p_recipient_user_id,
        btrim(p_recipient_email, E' \t\n\r\f\013'), 'es-ES', invitation_id,
        1, p_secret_key_version, 'AES-256-GCM',
        public.build_invitation_secret_aad(
            'organization', btrim(p_recipient_email, E' \t\n\r\f\013'),
            p_expires_at, p_acceptance_secret_digest
        ), p_secret_nonce,
        p_secret_ciphertext
    );

    return invitation_id;
end;
$$;

revoke all privileges on function public.create_scoped_organization_invitation_with_communication(
    uuid, uuid, uuid, text, jsonb, timestamptz, bytea, integer, bytea, bytea
) from public, anon, authenticated;
grant execute on function public.create_scoped_organization_invitation_with_communication(
    uuid, uuid, uuid, text, jsonb, timestamptz, bytea, integer, bytea, bytea
) to service_role;

create function public.create_guardianship_invitation_with_communication(
    p_auth_subject uuid,
    p_pet_id uuid,
    p_inviting_guardianship_id uuid,
    p_recipient_user_id uuid,
    p_recipient_email text,
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea,
    p_secret_key_version integer,
    p_secret_nonce bytea,
    p_secret_ciphertext bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    invitation_id uuid;
begin
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth'
      and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;

    if acting_user_id is null then
        raise exception 'A coherent acting domain User is required'
            using errcode = '28000';
    end if;

    invitation_id := public.create_guardianship_invitation(
        acting_user_id, p_pet_id, p_inviting_guardianship_id,
        p_recipient_user_id, p_recipient_email, p_expires_at,
        p_acceptance_secret_digest
    );

    insert into public.transactional_communications (
        communication_type, recipient_user_id, recipient_email, locale,
        guardianship_invitation_id, secret_envelope_version,
        secret_key_version, secret_algorithm, secret_aad_context,
        secret_nonce, secret_ciphertext
    ) values (
        'GUARDIANSHIP_INVITATION', p_recipient_user_id,
        btrim(p_recipient_email, E' \t\n\r\f\013'), 'es-ES', invitation_id,
        1, p_secret_key_version, 'AES-256-GCM',
        public.build_invitation_secret_aad(
            'guardianship', btrim(p_recipient_email, E' \t\n\r\f\013'),
            p_expires_at, p_acceptance_secret_digest
        ), p_secret_nonce,
        p_secret_ciphertext
    );

    return invitation_id;
end;
$$;

revoke all privileges on function public.create_guardianship_invitation_with_communication(
    uuid, uuid, uuid, uuid, text, timestamptz, bytea, integer, bytea, bytea
) from public, anon, authenticated;
grant execute on function public.create_guardianship_invitation_with_communication(
    uuid, uuid, uuid, uuid, text, timestamptz, bytea, integer, bytea, bytea
) to service_role;

create function public.enqueue_appointment_communications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_type text;
begin
    if tg_table_name = 'appointment_schedule_revisions' then
        if new.revision_context = 'REQUESTED'
           and new.revision_sequence = 1 then
            resolved_type := 'APPOINTMENT_REQUESTED';

            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_schedule_revision_id, locale, created_at
            )
            select resolved_type, guardianship.user_id, appointment.id,
                   new.id, 'es-ES', new.created_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.created_at
              and guardianship.effective_end is null
            on conflict do nothing;
        end if;

    elsif tg_table_name = 'appointment_lifecycle_events' then
        resolved_type := case new.to_state
            when 'CONFIRMED' then 'APPOINTMENT_CONFIRMED'
            when 'CANCELLED' then 'APPOINTMENT_CANCELLED'
            when 'COMPLETED' then 'APPOINTMENT_COMPLETED'
            when 'NO_SHOW' then 'APPOINTMENT_NO_SHOW'
            else null
        end;

        if resolved_type is not null then
            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_lifecycle_event_id, locale, created_at
            )
            select resolved_type, guardianship.user_id, appointment.id,
                   new.id, 'es-ES', new.recorded_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.recorded_at
              and guardianship.effective_end is null
            on conflict do nothing;
        end if;

    elsif tg_table_name = 'appointment_reschedule_proposals' then
        if tg_op = 'INSERT' then
            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_reschedule_proposal_id, locale, created_at
            )
            select 'APPOINTMENT_RESCHEDULE_PROPOSED', guardianship.user_id,
                   appointment.id, new.id, 'es-ES', new.created_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and new.state = 'PENDING'
              and new.proposing_context = 'CLINIC'
              and new.non_actionable_at is null
              and guardianship.effective_start <= new.created_at
              and guardianship.effective_end is null
            on conflict do nothing;

        elsif tg_op = 'UPDATE' then
            if old.state = 'PENDING' and new.state = 'ACCEPTED' then
                insert into public.transactional_communications (
                    communication_type, recipient_user_id, appointment_id,
                    appointment_reschedule_proposal_id,
                    appointment_schedule_revision_id, locale, created_at
                )
                select 'APPOINTMENT_RESCHEDULE_ACCEPTED', guardianship.user_id,
                       appointment.id, new.id,
                       new.resulting_confirmed_revision_id,
                       'es-ES', new.accepted_at
                from public.appointments as appointment
                join public.guardianships as guardianship
                  on guardianship.pet_id = appointment.pet_id
                where appointment.id = new.appointment_id
                  and guardianship.effective_start <= new.accepted_at
                  and guardianship.effective_end is null
                on conflict do nothing;
            end if;
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enqueue_appointment_communications()
from public, anon, authenticated;

create trigger appointment_initial_schedule_enqueue_communication
after insert on public.appointment_schedule_revisions
for each row execute function public.enqueue_appointment_communications();

create trigger appointment_lifecycle_events_enqueue_communication
after insert on public.appointment_lifecycle_events
for each row execute function public.enqueue_appointment_communications();

create trigger appointment_reschedule_proposals_enqueue_communication
after insert or update of state on public.appointment_reschedule_proposals
for each row execute function public.enqueue_appointment_communications();

create function public.establish_due_appointment_reminders(
    p_reference_time timestamptz default clock_timestamp(),
    p_advance interval default interval '24 hours',
    p_catchup interval default interval '6 hours',
    p_locale text default 'es-ES'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    inserted_count integer;
begin
    if p_reference_time is null or not isfinite(p_reference_time)
       or p_advance is null or p_advance <= interval '0 seconds'
       or p_catchup is null or p_catchup < interval '0 seconds'
       or p_locale is null
       or btrim(p_locale, E' \t\n\r\f\013') = '' then
        raise exception 'Valid reminder policy inputs are required'
            using errcode = '22023';
    end if;

    with latest_confirmed_revision as (
        select distinct on (revision.appointment_id)
            revision.id, revision.appointment_id, revision.scheduled_start_at
        from public.appointment_schedule_revisions as revision
        where revision.revision_context = 'CONFIRMED'
        order by revision.appointment_id, revision.revision_sequence desc
    )
    insert into public.transactional_communications (
        communication_type, recipient_user_id, appointment_id,
        appointment_schedule_revision_id, locale, created_at
    )
    select 'APPOINTMENT_REMINDER', guardianship.user_id, appointment.id,
           revision.id, btrim(p_locale, E' \t\n\r\f\013'), p_reference_time
    from public.appointments as appointment
    join latest_confirmed_revision as revision
      on revision.appointment_id = appointment.id
    join public.guardianships as guardianship
      on guardianship.pet_id = appointment.pet_id
    where appointment.lifecycle_state = 'CONFIRMED'
      and revision.scheduled_start_at > p_reference_time
      and p_reference_time >= revision.scheduled_start_at - p_advance
      and p_reference_time <= revision.scheduled_start_at - p_advance + p_catchup
      and guardianship.effective_start <= p_reference_time
      and guardianship.effective_end is null
    on conflict do nothing;

    get diagnostics inserted_count = row_count;
    return inserted_count;
end;
$$;

revoke all privileges on function public.establish_due_appointment_reminders(
    timestamptz, interval, interval, text
) from public, anon, authenticated;
grant execute on function public.establish_due_appointment_reminders(
    timestamptz, interval, interval, text
) to service_role;

create function public.communication_delivery_is_currently_eligible(
    p_communication_id uuid,
    p_channel text,
    p_push_registration_id uuid default null,
    p_destination_snapshot text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    communication_record public.transactional_communications%rowtype;
begin
    select communication.* into communication_record
    from public.transactional_communications as communication
    where communication.id = p_communication_id;

    if not found or p_channel is null or p_channel not in ('EMAIL', 'PUSH') then
        return false;
    end if;

    if communication_record.communication_type in (
        'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
    ) and p_channel <> 'EMAIL' then
        return false;
    end if;

    if communication_record.communication_type = 'ORGANIZATION_INVITATION'
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = communication_record.organization_invitation_id
             and invitation.revoked_at is null
             and invitation.rejected_at is null
             and invitation.expires_at > clock_timestamp()
             and invitation.acceptance_secret_digest is not null
             and not exists (
                 select 1 from public.organization_memberships as membership
                 where membership.originating_invitation_id = invitation.id
             )
       ) then return false;
    end if;

    if communication_record.communication_type = 'GUARDIANSHIP_INVITATION'
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = communication_record.guardianship_invitation_id
             and invitation.revoked_at is null
             and invitation.expires_at > clock_timestamp()
             and invitation.acceptance_secret_digest is not null
             and not exists (
                 select 1 from public.guardianships as guardianship
                 where guardianship.originating_invitation_id = invitation.id
             )
       ) then return false;
    end if;

    if communication_record.appointment_id is not null then
        if not exists (
            select 1
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = communication_record.appointment_id
              and guardianship.user_id = communication_record.recipient_user_id
              and guardianship.effective_start <= clock_timestamp()
              and guardianship.effective_end is null
        ) then return false; end if;

        if communication_record.communication_type = 'APPOINTMENT_REMINDER'
           and not exists (
               select 1
               from public.appointments as appointment
               join public.appointment_schedule_revisions as revision
                 on revision.id = communication_record.appointment_schedule_revision_id
                and revision.appointment_id = appointment.id
               where appointment.id = communication_record.appointment_id
                 and appointment.lifecycle_state = 'CONFIRMED'
                 and revision.revision_context = 'CONFIRMED'
                 and revision.scheduled_start_at > clock_timestamp()
                 and revision.id = (
                     select latest.id
                     from public.appointment_schedule_revisions as latest
                     where latest.appointment_id = appointment.id
                       and latest.revision_context = 'CONFIRMED'
                     order by latest.revision_sequence desc
                     limit 1
                 )
           ) then return false; end if;

        if communication_record.communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
           and not exists (
               select 1 from public.appointment_reschedule_proposals as proposal
                where proposal.id = communication_record.appointment_reschedule_proposal_id
                  and proposal.proposing_context = 'CLINIC'
                  and proposal.state = 'PENDING'
                 and proposal.non_actionable_at is null
                 and proposal.proposed_start_at > clock_timestamp()
           ) then return false; end if;
    end if;

    if p_channel = 'EMAIL'
       and communication_record.recipient_email is not null
       and p_destination_snapshot is distinct from
           communication_record.recipient_email then
        return false;
    end if;

    if p_channel = 'EMAIL'
       and communication_record.recipient_email is null
       and not exists (
           select 1
           from public.user_authentication_identities as identity_record
           join auth.users as auth_user
             on auth_user.id = identity_record.provider_subject
           where identity_record.user_id = communication_record.recipient_user_id
             and identity_record.provider = 'supabase_auth'
             and identity_record.issuer = 'primary'
             and auth_user.email_confirmed_at is not null
             and auth_user.email is not null
             and (
                 p_destination_snapshot is null
                 or auth_user.email = p_destination_snapshot
             )
       ) then return false; end if;

    if p_channel = 'PUSH' and not exists (
        select 1
        from public.push_registrations as registration
        join public.user_authentication_identities as identity_record
          on identity_record.user_id = registration.user_id
         and identity_record.provider = 'supabase_auth'
         and identity_record.issuer = 'primary'
        join auth.sessions as auth_session
          on auth_session.id = registration.auth_session_id
         and auth_session.user_id = identity_record.provider_subject
        where registration.id = p_push_registration_id
          and registration.user_id = communication_record.recipient_user_id
          and registration.invalidated_at is null
          and p_destination_snapshot = 'sha256:' ||
              encode(registration.provider_token_digest, 'hex')
    ) then return false; end if;

    return true;
end;
$$;

revoke all privileges on function public.communication_delivery_is_currently_eligible(
    uuid, text, uuid, text
) from public, anon, authenticated;

create function public.materialize_communication_delivery_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    inserted_count integer := 0;
    affected_count integer;
    communication_record public.transactional_communications%rowtype;
    resolved_email text;
begin
    update public.communication_delivery_jobs as attempt
    set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
        last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
        lease_token = null, lease_expires_at = null
    where attempt.state in ('READY', 'RETRYABLE')
      and not public.communication_delivery_is_currently_eligible(
          attempt.communication_id, attempt.channel,
          attempt.push_registration_id, attempt.destination_snapshot
      );

    -- A Communication's destination set is a one-time operational fact. The
    -- row lock prevents concurrent dispatchers from observing or recording
    -- different fanout sets; SKIP LOCKED lets another worker make progress.
    for communication_record in
        select communication.*
        from public.transactional_communications as communication
        where communication.fanout_materialized_at is null
        order by communication.created_at, communication.id
        for update skip locked
    loop
        resolved_email := communication_record.recipient_email;
        if resolved_email is null then
            select auth_user.email into resolved_email
            from public.user_authentication_identities as identity_record
            join auth.users as auth_user
              on auth_user.id = identity_record.provider_subject
             and auth_user.email_confirmed_at is not null
             and auth_user.email is not null
            where identity_record.user_id = communication_record.recipient_user_id
              and identity_record.provider = 'supabase_auth'
              and identity_record.issuer = 'primary';
        end if;

        if resolved_email is not null and
           public.communication_delivery_is_currently_eligible(
               communication_record.id, 'EMAIL', null, resolved_email
           ) then
            insert into public.communication_delivery_jobs (
                communication_id, channel, provider, destination_key,
                destination_snapshot
            ) values (
                communication_record.id, 'EMAIL', 'RESEND',
                'EMAIL:' || lower(resolved_email), resolved_email
            )
            on conflict do nothing;
            get diagnostics affected_count = row_count;
            inserted_count := inserted_count + affected_count;
        end if;

        if communication_record.appointment_id is not null then
            insert into public.communication_delivery_jobs (
                communication_id, channel, provider, destination_key,
                destination_snapshot, push_registration_id
            )
            select communication_record.id, 'PUSH', 'EXPO',
                   registration.id::text,
                   'sha256:' || encode(registration.provider_token_digest, 'hex'),
                   registration.id
            from public.push_registrations as registration
            join public.user_authentication_identities as identity_record
              on identity_record.user_id = registration.user_id
             and identity_record.provider = 'supabase_auth'
             and identity_record.issuer = 'primary'
            join auth.sessions as auth_session
              on auth_session.id = registration.auth_session_id
             and auth_session.user_id = identity_record.provider_subject
            where registration.user_id = communication_record.recipient_user_id
              and registration.invalidated_at is null
              and public.communication_delivery_is_currently_eligible(
                  communication_record.id, 'PUSH', registration.id,
                  'sha256:' || encode(registration.provider_token_digest, 'hex')
              )
            on conflict do nothing;
            get diagnostics affected_count = row_count;
            inserted_count := inserted_count + affected_count;
        end if;

        update public.transactional_communications
        set fanout_materialized_at = clock_timestamp()
        where id = communication_record.id;
    end loop;

    return inserted_count;
end;
$$;

revoke all privileges on function public.materialize_communication_delivery_jobs()
from public, anon, authenticated;
grant execute on function public.materialize_communication_delivery_jobs()
to service_role;

create function public.claim_communication_delivery_jobs(
    p_limit integer default 50,
    p_lease_seconds integer default 120
)
returns table (
    delivery_job_id uuid,
    lease_token uuid,
    communication_id uuid,
    communication_type text,
    channel text,
    provider text,
    provider_idempotency_key text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_limit is null or p_lease_seconds is null
       or p_limit < 1 or p_limit > 100
       or p_lease_seconds < 30 or p_lease_seconds > 600 then
        raise exception 'Dispatch claim limits are invalid' using errcode = '22023';
    end if;

    perform public.materialize_communication_delivery_jobs();

    -- Only an expired Expo claim whose provider submission was explicitly
    -- marked as started is ambiguous. A pre-submission lease is safe to reclaim.
    insert into public.communication_delivery_attempts (
        delivery_job_id, communication_id, attempt_number, channel,
        provider, destination_snapshot, push_registration_id, outcome,
        provider_status, error_code, attempted_at
    )
    select attempt.id, attempt.communication_id, attempt.submission_count,
           attempt.channel, attempt.provider, attempt.destination_snapshot,
           attempt.push_registration_id, 'UNKNOWN', 'lease_expired',
           'AMBIGUOUS_WORKER_COMPLETION',
           attempt.active_submission_started_at
    from public.communication_delivery_jobs as attempt
    where attempt.provider = 'EXPO'
      and attempt.state = 'CLAIMED'
      and attempt.active_submission_started_at is not null
      and attempt.lease_expires_at <= clock_timestamp()
    for update skip locked
    on conflict on constraint communication_delivery_attempts_job_number_key
    do nothing;

    update public.communication_delivery_jobs as attempt
    set state = 'UNKNOWN', resolved_at = clock_timestamp(),
        last_error_code = 'AMBIGUOUS_WORKER_COMPLETION',
        provider_status = 'lease_expired',
        lease_token = null, lease_expires_at = null,
        active_submission_started_at = null
    where attempt.provider = 'EXPO'
      and attempt.state = 'CLAIMED'
      and attempt.active_submission_started_at is not null
      and attempt.lease_expires_at <= clock_timestamp();

    update public.communication_delivery_jobs as attempt
    set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
        last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
        lease_token = null, lease_expires_at = null,
        active_submission_started_at = null
    where (
          attempt.state in ('READY', 'RETRYABLE')
          or (
              attempt.state = 'CLAIMED'
              and attempt.lease_expires_at <= clock_timestamp()
          )
      )
      and not public.communication_delivery_is_currently_eligible(
          attempt.communication_id, attempt.channel,
          attempt.push_registration_id, attempt.destination_snapshot
      );

    -- A lost Resend worker is an ambiguous provider call, but the stable Job
    -- key makes it safe to retry inside the provider idempotency window. Record
    -- the actual start before reclaiming the lease.
    insert into public.communication_delivery_attempts (
        delivery_job_id, communication_id, attempt_number, channel,
        provider, destination_snapshot, push_registration_id, outcome,
        provider_status, error_code, attempted_at
    )
    select attempt.id, attempt.communication_id, attempt.submission_count,
           attempt.channel, attempt.provider, attempt.destination_snapshot,
           attempt.push_registration_id, 'RETRYABLE', 'lease_expired',
           'AMBIGUOUS_WORKER_COMPLETION',
           attempt.active_submission_started_at
    from public.communication_delivery_jobs as attempt
    where attempt.provider = 'RESEND'
      and attempt.state = 'CLAIMED'
      and attempt.active_submission_started_at is not null
      and attempt.lease_expires_at <= clock_timestamp()
      and attempt.first_submitted_at > clock_timestamp() - interval '23 hours'
    for update skip locked
    on conflict on constraint communication_delivery_attempts_job_number_key
    do nothing;

    insert into public.communication_delivery_attempts (
        delivery_job_id, communication_id, attempt_number, channel,
        provider, destination_snapshot, push_registration_id, outcome,
        provider_status, error_code, attempted_at
    )
    select attempt.id, attempt.communication_id, attempt.submission_count,
           attempt.channel, attempt.provider, attempt.destination_snapshot,
           attempt.push_registration_id, 'UNKNOWN', 'idempotency_window_expired',
           'RESEND_IDEMPOTENCY_WINDOW_EXPIRED',
           attempt.active_submission_started_at
    from public.communication_delivery_jobs as attempt
    where attempt.provider = 'RESEND'
      and attempt.state = 'CLAIMED'
      and attempt.active_submission_started_at is not null
      and attempt.first_submitted_at <= clock_timestamp() - interval '23 hours'
    for update skip locked
    on conflict on constraint communication_delivery_attempts_job_number_key
    do nothing;

    -- Resend's provider idempotency guarantee is time-bounded. Do not turn an
    -- ambiguous attempt into a duplicate after the supported window.
    update public.communication_delivery_jobs as attempt
    set state = 'UNKNOWN', resolved_at = clock_timestamp(),
        last_error_code = 'RESEND_IDEMPOTENCY_WINDOW_EXPIRED',
        lease_token = null, lease_expires_at = null,
        active_submission_started_at = null
    where attempt.provider = 'RESEND'
      and attempt.state in ('READY', 'CLAIMED', 'RETRYABLE')
      and attempt.first_submitted_at is not null
      and attempt.first_submitted_at <= clock_timestamp() - interval '23 hours';

    -- A worker may disappear after taking its final lease. Expired work must
    -- become terminal instead of remaining CLAIMED forever.
    update public.communication_delivery_jobs as attempt
    set state = 'PERMANENT_FAILURE', resolved_at = clock_timestamp(),
        last_error_code = 'DELIVERY_ATTEMPTS_EXHAUSTED',
        lease_token = null, lease_expires_at = null,
        active_submission_started_at = null
    where attempt.submission_count >= 8
      and (
          attempt.state in ('READY', 'RETRYABLE')
          or (
              attempt.state = 'CLAIMED'
              and attempt.lease_expires_at <= clock_timestamp()
          )
      );

    return query
    with candidates as (
        select attempt.id
        from public.communication_delivery_jobs as attempt
        where (
                attempt.state in ('READY', 'RETRYABLE')
                or (
                    attempt.state = 'CLAIMED'
                    and attempt.lease_expires_at <= clock_timestamp()
                )
              )
          and attempt.next_attempt_at <= clock_timestamp()
          and attempt.submission_count < 8
        order by attempt.next_attempt_at, attempt.created_at, attempt.id
        limit p_limit
        for update skip locked
    ), claimed as (
        update public.communication_delivery_jobs as attempt
        set state = 'CLAIMED', lease_token = gen_random_uuid(),
            lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
            active_submission_started_at = null
        from candidates
        where attempt.id = candidates.id
        returning attempt.*
    )
    select claimed.id, claimed.lease_token, communication.id,
           communication.communication_type, claimed.channel,
           claimed.provider, claimed.id::text
    from claimed
    join public.transactional_communications as communication
      on communication.id = claimed.communication_id;
end;
$$;

revoke all privileges on function public.claim_communication_delivery_jobs(
    integer, integer
) from public, anon, authenticated;
grant execute on function public.claim_communication_delivery_jobs(
    integer, integer
) to service_role;

create function public.get_communication_delivery_context(
    p_delivery_job_id uuid,
    p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    communication_record public.transactional_communications%rowtype;
    resolved_destination text;
    result jsonb;
begin
    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.state = 'CLAIMED'
      and attempt.lease_token = p_lease_token
      and attempt.lease_expires_at > clock_timestamp()
      and attempt.active_submission_started_at is null
    for update;

    if not found then
        raise exception 'A live delivery claim is required' using errcode = '55000';
    end if;

    if not public.communication_delivery_is_currently_eligible(
        attempt_record.communication_id, attempt_record.channel,
        attempt_record.push_registration_id,
        attempt_record.destination_snapshot
    ) then
        update public.communication_delivery_jobs
        set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
            last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
            lease_token = null, lease_expires_at = null,
            active_submission_started_at = null
        where id = attempt_record.id;
        return null;
    end if;

    select communication.* into communication_record
    from public.transactional_communications as communication
    where communication.id = attempt_record.communication_id;

    resolved_destination := attempt_record.destination_snapshot;
    if attempt_record.channel = 'PUSH' then
        -- The raw provider token lives only on the private Registration. Load
        -- it after final registration/session revalidation and lock both rows
        -- for the remainder of this imminent trusted provider operation.
        select registration.provider_token into resolved_destination
        from public.push_registrations as registration
        join public.user_authentication_identities as identity_record
          on identity_record.user_id = registration.user_id
         and identity_record.provider = 'supabase_auth'
         and identity_record.issuer = 'primary'
        join auth.sessions as auth_session
          on auth_session.id = registration.auth_session_id
         and auth_session.user_id = identity_record.provider_subject
        where registration.id = attempt_record.push_registration_id
          and registration.user_id = communication_record.recipient_user_id
          and registration.invalidated_at is null
          and attempt_record.destination_snapshot = 'sha256:' ||
              encode(registration.provider_token_digest, 'hex')
        for key share of registration, auth_session;

        if not found then
            update public.communication_delivery_jobs
            set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
                last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
                lease_token = null, lease_expires_at = null,
                active_submission_started_at = null
            where id = attempt_record.id;
            return null;
        end if;
    end if;

    result := jsonb_build_object(
        'communication_id', communication_record.id,
        'communication_type', communication_record.communication_type,
        'locale', communication_record.locale,
        'recipient', resolved_destination,
        'channel', attempt_record.channel,
        'appointment_id', communication_record.appointment_id,
        'organization_invitation_id', communication_record.organization_invitation_id,
        'guardianship_invitation_id', communication_record.guardianship_invitation_id,
        'secret_envelope_version', communication_record.secret_envelope_version,
        'secret_key_version', communication_record.secret_key_version,
        'secret_algorithm', communication_record.secret_algorithm,
        'secret_aad_context', communication_record.secret_aad_context,
        'secret_nonce', communication_record.secret_nonce,
        'secret_ciphertext', communication_record.secret_ciphertext
    );

    if communication_record.organization_invitation_id is not null then
        select result || jsonb_build_object(
            'organization_name', organization.display_name,
            'invitation_expires_at', invitation.expires_at
        ) into result
        from public.organization_invitations as invitation
        join public.veterinary_organizations as organization
          on organization.id = invitation.organization_id
        where invitation.id = communication_record.organization_invitation_id;
    elsif communication_record.guardianship_invitation_id is not null then
        select result || jsonb_build_object(
            'pet_name', pet.name,
            'invitation_expires_at', invitation.expires_at
        ) into result
        from public.guardianship_invitations as invitation
        join public.pets as pet on pet.id = invitation.pet_id
        where invitation.id = communication_record.guardianship_invitation_id;
    elsif communication_record.appointment_id is not null then
        select result || jsonb_build_object(
            'pet_name', pet.name,
            'clinic_name', coalesce(profile.display_name, organization.display_name),
            'appointment_state', appointment.lifecycle_state,
            'scheduled_start_at', coalesce(
                selected_revision.scheduled_start_at,
                proposal.proposed_start_at,
                latest_revision.scheduled_start_at
            ),
            'scheduled_end_at', coalesce(
                selected_revision.scheduled_end_at,
                proposal.proposed_end_at,
                latest_revision.scheduled_end_at
            ),
            'timezone_name', coalesce(
                selected_revision.establishment_timezone_name,
                proposal.proposed_timezone_name,
                latest_revision.establishment_timezone_name
            ),
            'reschedule_proposal_id', communication_record.appointment_reschedule_proposal_id
        ) into result
        from public.appointments as appointment
        join public.pets as pet on pet.id = appointment.pet_id
        join public.clinics as clinic on clinic.id = appointment.clinic_id
        join public.veterinary_organizations as organization
          on organization.id = clinic.organization_id
        left join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        left join public.appointment_schedule_revisions as selected_revision
          on selected_revision.id = communication_record.appointment_schedule_revision_id
        left join public.appointment_reschedule_proposals as proposal
          on proposal.id = communication_record.appointment_reschedule_proposal_id
         and communication_record.communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
        left join lateral (
            select revision.*
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
              and (
                  (communication_record.communication_type = 'APPOINTMENT_REQUESTED'
                   and revision.revision_context = 'REQUESTED')
                  or
                  (communication_record.communication_type <> 'APPOINTMENT_REQUESTED'
                   and revision.revision_context = 'CONFIRMED')
              )
            order by revision.revision_sequence desc
            limit 1
        ) as latest_revision on true
        where appointment.id = communication_record.appointment_id;
    end if;

    return result;
end;
$$;

revoke all privileges on function public.get_communication_delivery_context(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_communication_delivery_context(uuid, uuid)
to service_role;

create function public.mark_communication_delivery_submission_started(
    p_delivery_job_id uuid,
    p_lease_token uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    operation_timestamp timestamptz := clock_timestamp();
begin
    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.state = 'CLAIMED'
      and attempt.lease_token = p_lease_token
      and attempt.lease_expires_at > operation_timestamp
      and attempt.active_submission_started_at is null
    for update;

    if not found then
        raise exception 'A live pre-submission delivery claim is required'
            using errcode = '55000';
    end if;

    if not public.communication_delivery_is_currently_eligible(
        attempt_record.communication_id, attempt_record.channel,
        attempt_record.push_registration_id,
        attempt_record.destination_snapshot
    ) then
        update public.communication_delivery_jobs
        set state = 'SUPPRESSED', resolved_at = operation_timestamp,
            last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
            lease_token = null, lease_expires_at = null,
            active_submission_started_at = null
        where id = attempt_record.id;
        return 'SUPPRESSED';
    end if;

    update public.communication_delivery_jobs
    set submission_count = submission_count + 1,
        first_submitted_at = coalesce(first_submitted_at, operation_timestamp),
        last_submitted_at = operation_timestamp,
        active_submission_started_at = operation_timestamp
    where id = attempt_record.id;

    return 'STARTED';
end;
$$;

revoke all privileges on function public.mark_communication_delivery_submission_started(
    uuid, uuid
) from public, anon, authenticated;
grant execute on function public.mark_communication_delivery_submission_started(
    uuid, uuid
) to service_role;

create function public.complete_communication_delivery_job(
    p_delivery_job_id uuid,
    p_lease_token uuid,
    p_outcome text,
    p_provider_message_id text default null,
    p_provider_status text default null,
    p_error_code text default null,
    p_retry_after_seconds integer default 60
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    final_state text;
begin
    if p_outcome is null
       or p_outcome not in (
           'ACCEPTED', 'DELIVERED', 'RETRYABLE', 'UNKNOWN',
           'PERMANENT_FAILURE'
       )
       or p_retry_after_seconds is null
       or p_retry_after_seconds < 1 or p_retry_after_seconds > 86400
       or (
           p_outcome in ('ACCEPTED', 'DELIVERED')
           and (
               p_provider_message_id is null
               or btrim(p_provider_message_id) = ''
           )
       ) then
        raise exception 'Delivery completion inputs are invalid' using errcode = '22023';
    end if;

    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.state = 'CLAIMED'
      and attempt.lease_token = p_lease_token
      and attempt.active_submission_started_at is not null
    for update;

    if not found then
        raise exception 'Delivery claim does not exist or is no longer current'
            using errcode = '55000';
    end if;

    final_state := case
        when p_outcome = 'RETRYABLE' and attempt_record.submission_count >= 8
            then 'PERMANENT_FAILURE'
        else p_outcome
    end;

    insert into public.communication_delivery_attempts (
        delivery_job_id, communication_id, attempt_number, channel,
        provider, destination_snapshot, push_registration_id, outcome,
        provider_message_id, provider_status, error_code, attempted_at
    ) values (
        attempt_record.id, attempt_record.communication_id,
        attempt_record.submission_count, attempt_record.channel,
        attempt_record.provider, attempt_record.destination_snapshot,
        attempt_record.push_registration_id, p_outcome,
        p_provider_message_id, p_provider_status, p_error_code,
        attempt_record.active_submission_started_at
    );

    update public.communication_delivery_jobs
    set state = final_state,
        provider_message_id = coalesce(p_provider_message_id, provider_message_id),
        provider_status = p_provider_status,
        last_error_code = p_error_code,
        next_attempt_at = case
            when final_state = 'RETRYABLE'
                then clock_timestamp() + make_interval(secs => p_retry_after_seconds)
            when final_state = 'ACCEPTED' and attempt_record.provider = 'EXPO'
                then clock_timestamp() + interval '15 minutes'
            else next_attempt_at end,
        lease_token = null,
        lease_expires_at = null,
        active_submission_started_at = null,
        resolved_at = case when final_state in (
            'DELIVERED', 'UNKNOWN', 'PERMANENT_FAILURE'
        )
            then clock_timestamp() else null end
    where id = p_delivery_job_id;

    if attempt_record.channel = 'EMAIL'
       and final_state in ('ACCEPTED', 'DELIVERED') then
        update public.transactional_communications
        set secret_nonce = null,
            secret_ciphertext = null,
            secret_consumed_at = clock_timestamp()
        where id = attempt_record.communication_id
          and communication_type in (
              'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
          )
          and secret_consumed_at is null;
    end if;

    if attempt_record.provider = 'EXPO'
       and final_state = 'PERMANENT_FAILURE'
       and p_error_code = 'DeviceNotRegistered' then
        update public.push_registrations
        set invalidated_at = coalesce(invalidated_at, clock_timestamp()),
            invalidation_reason = coalesce(invalidation_reason, 'DEVICE_NOT_REGISTERED')
        where id = attempt_record.push_registration_id;
    end if;

    return final_state;
end;
$$;

revoke all privileges on function public.complete_communication_delivery_job(
    uuid, uuid, text, text, text, text, integer
) from public, anon, authenticated;
grant execute on function public.complete_communication_delivery_job(
    uuid, uuid, text, text, text, text, integer
) to service_role;

create function public.claim_expo_push_receipts(
    p_limit integer default 100,
    p_lease_seconds integer default 120
)
returns table (delivery_job_id uuid, lease_token uuid, ticket_id text)
language plpgsql
security definer
set search_path = ''
as $$
declare
    expo_receipt_retention_horizon constant interval := interval '23 hours';
begin
    if p_limit is null or p_lease_seconds is null
       or p_limit < 1 or p_limit > 300
       or p_lease_seconds < 30 or p_lease_seconds > 600 then
        raise exception 'Receipt claim limits are invalid' using errcode = '22023';
    end if;

    -- Expo documents receipts as available for at least a day. Stop polling
    -- inside that retention boundary so unresolved infrastructure evidence
    -- cannot remain queued forever.
    update public.communication_delivery_jobs as attempt
    set state = 'UNKNOWN', resolved_at = clock_timestamp(),
        provider_status = 'receipt_horizon_expired',
        last_error_code = 'EXPO_RECEIPT_HORIZON_EXPIRED',
        lease_token = null, lease_expires_at = null
    where attempt.provider = 'EXPO'
      and attempt.state = 'ACCEPTED'
      and attempt.last_submitted_at <=
          clock_timestamp() - expo_receipt_retention_horizon
      and (
          attempt.lease_expires_at is null
          or attempt.lease_expires_at <= clock_timestamp()
      );

    return query
    with candidates as (
        select attempt.id
        from public.communication_delivery_jobs as attempt
        where attempt.provider = 'EXPO'
          and attempt.state = 'ACCEPTED'
          and attempt.provider_message_id is not null
          and attempt.next_attempt_at <= clock_timestamp()
          and (attempt.lease_expires_at is null or attempt.lease_expires_at <= clock_timestamp())
        order by attempt.next_attempt_at, attempt.id
        limit p_limit
        for update skip locked
    ), claimed as (
        update public.communication_delivery_jobs as attempt
        set lease_token = gen_random_uuid(),
            lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds)
        from candidates
        where attempt.id = candidates.id
        returning attempt.*
    )
    select claimed.id, claimed.lease_token, claimed.provider_message_id
    from claimed;
end;
$$;

revoke all privileges on function public.claim_expo_push_receipts(integer, integer)
from public, anon, authenticated;
grant execute on function public.claim_expo_push_receipts(integer, integer)
to service_role;

create function public.complete_expo_push_receipt(
    p_delivery_job_id uuid,
    p_lease_token uuid,
    p_outcome text,
    p_provider_status text,
    p_error_code text default null,
    p_retry_after_seconds integer default 300
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    registration_id uuid;
    final_state text;
begin
    if p_outcome is null
       or p_outcome not in (
           'UPSTREAM_ACCEPTED', 'PERMANENT_FAILURE', 'RETRYABLE',
           'PENDING'
       )
       or (
           p_outcome = 'UPSTREAM_ACCEPTED'
           and (
               p_provider_status is null
               or btrim(p_provider_status) = ''
           )
       )
       or p_retry_after_seconds is null
       or p_retry_after_seconds < 1 or p_retry_after_seconds > 86400 then
        raise exception 'Expo receipt outcome is invalid' using errcode = '22023';
    end if;

    select attempt.push_registration_id into registration_id
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.provider = 'EXPO'
      and attempt.state = 'ACCEPTED'
      and attempt.lease_token = p_lease_token
    for update;

    if not found then
        raise exception 'Expo receipt claim does not exist or is no longer current'
            using errcode = '55000';
    end if;

    final_state := case when p_outcome = 'PENDING' then 'ACCEPTED' else p_outcome end;

    update public.communication_delivery_jobs
    set state = final_state,
        provider_status = p_provider_status,
        last_error_code = p_error_code,
        receipt_checked_at = clock_timestamp(),
        next_attempt_at = case when p_outcome in ('PENDING', 'RETRYABLE')
            then clock_timestamp() + make_interval(secs => p_retry_after_seconds)
            else next_attempt_at end,
        lease_token = null, lease_expires_at = null,
        resolved_at = case when p_outcome in (
            'UPSTREAM_ACCEPTED', 'PERMANENT_FAILURE'
        )
            then clock_timestamp() else null end
    where id = p_delivery_job_id;

    if p_outcome = 'PERMANENT_FAILURE'
       and p_error_code = 'DeviceNotRegistered' then
        update public.push_registrations
        set invalidated_at = coalesce(invalidated_at, clock_timestamp()),
            invalidation_reason = coalesce(invalidation_reason, 'DEVICE_NOT_REGISTERED')
        where id = registration_id;
    end if;

    return final_state;
end;
$$;

revoke all privileges on function public.complete_expo_push_receipt(
    uuid, uuid, text, text, text, integer
) from public, anon, authenticated;
grant execute on function public.complete_expo_push_receipt(
    uuid, uuid, text, text, text, integer
) to service_role;

create function public.record_resend_delivery_event(
    p_provider_event_id text,
    p_event_type text,
    p_provider_message_id text,
    p_occurred_at timestamptz
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    event_state text;
    resulting_state text;
begin
    if p_provider_event_id is null or btrim(p_provider_event_id) = ''
       or p_provider_message_id is null or btrim(p_provider_message_id) = ''
       or p_occurred_at is null or not isfinite(p_occurred_at) then
        raise exception 'A complete Resend event identity is required'
            using errcode = '22023';
    end if;

    event_state := case p_event_type
        when 'email.sent' then 'ACCEPTED'
        when 'email.delivered' then 'DELIVERED'
        when 'email.delivery_delayed' then 'ACCEPTED'
        when 'email.bounced' then 'PERMANENT_FAILURE'
        when 'email.complained' then 'PERMANENT_FAILURE'
        when 'email.failed' then 'PERMANENT_FAILURE'
        when 'email.suppressed' then 'PERMANENT_FAILURE'
        else null
    end;

    if event_state is null then return 'IGNORED'; end if;

    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.provider = 'RESEND'
      and attempt.provider_message_id = p_provider_message_id
    for update;

    if not found then return 'UNMATCHED'; end if;

    if attempt_record.provider_event_id = p_provider_event_id then
        return attempt_record.state;
    end if;

    if attempt_record.state in ('UNKNOWN', 'UPSTREAM_ACCEPTED') then
        return attempt_record.state;
    end if;

    if attempt_record.provider_event_occurred_at is not null
       and p_occurred_at < attempt_record.provider_event_occurred_at then
        return attempt_record.state;
    end if;

    if attempt_record.state = 'PERMANENT_FAILURE'
       and event_state <> 'PERMANENT_FAILURE' then
        return attempt_record.state;
    end if;

    if attempt_record.state = 'DELIVERED'
       and (
           event_state = 'ACCEPTED'
           or (
               event_state = 'PERMANENT_FAILURE'
               and p_event_type not in (
                   'email.bounced', 'email.complained', 'email.suppressed'
               )
           )
       ) then
        return attempt_record.state;
    end if;

    resulting_state := event_state;

    update public.communication_delivery_jobs
    set state = resulting_state,
        provider_status = p_event_type,
        provider_event_id = p_provider_event_id,
        provider_event_occurred_at = p_occurred_at,
        last_error_code = case when event_state = 'PERMANENT_FAILURE'
            then replace(p_event_type, 'email.', '') else last_error_code end,
        resolved_at = case when resulting_state in ('DELIVERED', 'PERMANENT_FAILURE')
            then coalesce(resolved_at, clock_timestamp()) else resolved_at end
    where id = attempt_record.id;

    if resulting_state in ('ACCEPTED', 'DELIVERED') then
        update public.transactional_communications
        set secret_nonce = null, secret_ciphertext = null,
            secret_consumed_at = clock_timestamp()
        where id = attempt_record.communication_id
          and communication_type in (
              'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
          )
          and secret_consumed_at is null;
    end if;

    return resulting_state;
end;
$$;

revoke all privileges on function public.record_resend_delivery_event(
    text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.record_resend_delivery_event(
    text, text, text, timestamptz
) to service_role;

create function public.enforce_communication_delivery_job_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Communication Delivery Jobs cannot be deleted through ordinary operations'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.communication_id is distinct from new.communication_id
       or old.channel is distinct from new.channel
       or old.provider is distinct from new.provider
       or old.destination_key is distinct from new.destination_key
       or old.destination_snapshot is distinct from new.destination_snapshot
       or old.push_registration_id is distinct from new.push_registration_id
       or old.created_at is distinct from new.created_at
       or new.submission_count < old.submission_count then
        raise exception 'Delivery Job identity and destination are immutable'
            using errcode = '23514';
    end if;

    if old.first_submitted_at is not null
       and new.first_submitted_at is distinct from old.first_submitted_at then
        raise exception 'Delivery Job first submission time is immutable'
            using errcode = '23514';
    end if;

    if new.submission_count <> old.submission_count then
        if new.submission_count <> old.submission_count + 1
           or old.state <> 'CLAIMED' or new.state <> 'CLAIMED'
           or old.active_submission_started_at is not null
           or new.active_submission_started_at is null
           or new.last_submitted_at is distinct from new.active_submission_started_at
           or (
               old.submission_count = 0
               and new.first_submitted_at is distinct from new.active_submission_started_at
           ) then
            raise exception 'Submission count advances only at the explicit provider-start boundary'
                using errcode = '23514';
        end if;
    elsif new.last_submitted_at is distinct from old.last_submitted_at
       or new.first_submitted_at is distinct from old.first_submitted_at
       or (
           old.active_submission_started_at is null
           and new.active_submission_started_at is not null
       ) then
        raise exception 'Submission timestamps require a new provider start'
            using errcode = '23514';
    end if;

    if old.state in ('UNKNOWN', 'UPSTREAM_ACCEPTED') then
        raise exception 'Closed Delivery Job evidence is immutable'
            using errcode = '23514';
    end if;

    if old.state is distinct from new.state and not (
        (old.state = 'READY' and new.state in (
            'CLAIMED', 'UNKNOWN', 'PERMANENT_FAILURE', 'SUPPRESSED'
        ))
        or (old.state = 'CLAIMED' and new.state in (
            'RETRYABLE', 'ACCEPTED', 'DELIVERED', 'UNKNOWN',
            'PERMANENT_FAILURE', 'SUPPRESSED'
        ))
        or (old.state = 'RETRYABLE' and new.state in (
            'CLAIMED', 'UNKNOWN', 'PERMANENT_FAILURE', 'SUPPRESSED'
        ))
        or (
            old.state = 'ACCEPTED'
            and (
                (new.state = 'DELIVERED' and new.provider = 'RESEND')
                or (new.state = 'UPSTREAM_ACCEPTED' and new.provider = 'EXPO')
                or (new.state = 'RETRYABLE' and new.provider = 'EXPO')
                or new.state = 'PERMANENT_FAILURE'
                or (new.state = 'UNKNOWN' and new.provider = 'EXPO')
            )
        )
        or (
            old.state = 'DELIVERED'
            and new.state = 'PERMANENT_FAILURE'
            and new.provider = 'RESEND'
            and new.provider_status in (
                'email.bounced', 'email.complained', 'email.suppressed'
            )
        )
    ) then
        raise exception 'Delivery Job state transition is not monotonic or supported'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_communication_delivery_job_integrity()
from public, anon, authenticated;

create trigger communication_delivery_jobs_enforce_integrity
before update or delete on public.communication_delivery_jobs
for each row execute function public.enforce_communication_delivery_job_integrity();

create function public.preserve_communication_delivery_attempt_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'Communication Delivery Attempts are append-only while retained'
        using errcode = '23514';
end;
$$;

revoke all privileges on function public.preserve_communication_delivery_attempt_history()
from public, anon, authenticated;

create trigger communication_delivery_attempts_preserve_history
before update or delete on public.communication_delivery_attempts
for each row execute function public.preserve_communication_delivery_attempt_history();

commit;
