-- Clinic creation self-service Phase 1 (SPEC-CLI-001 §10 BR-12–BR-16;
-- SPEC-ORG-005, SPEC-ORG-008 BR-3; REQ-CLI-001, REQ-ORG-005, REQ-ORG-006).
--
-- The earlier create_clinic(p_organization_id uuid) was not idempotent: a
-- response lost after commit could only be retried by creating another Clinic,
-- and Clinics cannot be deleted (BR-16). It also reported an unknown
-- Organization (23503) before evaluating capability.
--
-- clinics.creation_idempotency_key
--   Durable, immutable operational metadata recorded in the same insert as the
--   Clinic, so no key exists without its Clinic and no client-created Clinic
--   exists without its key. Unique per Organization when present (rows created
--   before this migration, and direct trusted fixtures, have none). Never
--   returned by any Clinic read; clients have no table privileges on clinics.
--
-- create_clinic(p_organization_id uuid, p_idempotency_key uuid) returns jsonb
--   authenticated only. Order (BR-13):
--     1. authentication + coherent domain User (28000);
--     2. ORGANIZATION_CREATE_CLINICS before any Organization fact is disclosed:
--        an unknown Organization and one the caller may not create Clinics in
--        fail identically (42501); nothing is locked for that caller;
--     3. the target Organization's lock, then the capability again;
--     4. creation key required (22023);
--     5. lookup by (Organization, key): an existing Clinic is returned as
--        ALREADY_CREATED and nothing is written;
--     6. one unpublished Clinic with no configuration rows (BR-15).
--   No Subscription or Entitlement is evaluated (SPEC-SUB-003 BR-41). Lock
--   order Organization -> Clinic, the order of every Clinic configuration
--   write, so concurrent creations in one Organization serialize and same-key
--   requests resolve to one Clinic.
--
-- The withdrawn one-argument form is dropped rather than kept for trusted
-- use: its only callers were rollback-only suites and the operator
-- provisioning script, which now use the idempotent form.
begin;

alter table public.clinics
    add column creation_idempotency_key uuid;

alter table public.clinics
    add constraint clinics_organization_creation_idempotency_key
        unique (organization_id, creation_idempotency_key);

-- The creation key is part of the Clinic's creation facts.
create or replace function public.enforce_clinic_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Clinics cannot be deleted through ordinary operations'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.organization_id is distinct from new.organization_id
       or old.created_at is distinct from new.created_at
       or old.creation_idempotency_key is distinct from new.creation_idempotency_key then
        raise exception 'Clinic identity, Organization, creation time, and creation key are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

drop function public.create_clinic(uuid);

create function public.create_clinic(
    p_organization_id uuid,
    p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    created_clinic_id uuid;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Capability before any Organization fact; an unknown Organization has
    -- no capability holder, so it fails exactly like an inaccessible one.
    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_CREATE_CLINICS'
    ) then
        raise exception 'Clinic-creation capability is required'
            using errcode = '42501';
    end if;

    -- 3. Serialize creations per Organization, then decide again under the lock.
    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found or not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_CREATE_CLINICS'
    ) then
        raise exception 'Clinic-creation capability is required'
            using errcode = '42501';
    end if;

    -- 4. The creation key identifies the intent.
    if p_idempotency_key is null then
        raise exception 'Clinic creation key is required'
            using errcode = '22023';
    end if;

    -- 5. The same intent in this Organization resolves to its Clinic.
    select clinic.id
    into created_clinic_id
    from public.clinics as clinic
    where clinic.organization_id = p_organization_id
      and clinic.creation_idempotency_key = p_idempotency_key;

    if found then
        return jsonb_build_object(
            'clinic_id', created_clinic_id,
            'organization_id', p_organization_id,
            'outcome', 'ALREADY_CREATED'
        );
    end if;

    -- 6. One unpublished Clinic and nothing else (BR-15).
    insert into public.clinics (
        organization_id,
        created_at,
        creation_idempotency_key
    )
    values (
        p_organization_id,
        clock_timestamp(),
        p_idempotency_key
    )
    returning id into created_clinic_id;

    return jsonb_build_object(
        'clinic_id', created_clinic_id,
        'organization_id', p_organization_id,
        'outcome', 'CREATED'
    );
end;
$$;

revoke all privileges
on function public.create_clinic(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute
on function public.create_clinic(uuid, uuid)
to authenticated;

commit;
