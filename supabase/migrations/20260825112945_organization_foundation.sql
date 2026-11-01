begin;

create table public.veterinary_organizations (
    id uuid not null default gen_random_uuid(),
    display_name text not null,
    constraint veterinary_organizations_pkey primary key (id),
    constraint veterinary_organizations_display_name_check
        check (
            display_name = btrim(display_name, E' \t\n\r\f\013')
            and display_name <> ''
        )
);

create table public.organization_invitations (
    id uuid not null default gen_random_uuid(),
    organization_id uuid not null,
    inviting_user_id uuid not null,
    recipient_user_id uuid,
    recipient_email text not null,
    recipient_email_normalized text generated always as (
        lower(btrim(recipient_email, E' \t\n\r\f\013'))
    ) stored not null,
    created_at timestamptz not null,
    expires_at timestamptz not null,
    acceptance_secret_digest bytea,
    revoked_at timestamptz,
    revoked_by_user_id uuid,
    rejected_at timestamptz,
    rejected_by_user_id uuid,
    constraint organization_invitations_pkey primary key (id),
    constraint organization_invitations_organization_id_fkey
        foreign key (organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict,
    constraint organization_invitations_inviting_user_id_fkey
        foreign key (inviting_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_invitations_recipient_user_id_fkey
        foreign key (recipient_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_invitations_revoked_by_user_id_fkey
        foreign key (revoked_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_invitations_rejected_by_user_id_fkey
        foreign key (rejected_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_invitations_recipient_email_check
        check (
            recipient_email = btrim(recipient_email, E' \t\n\r\f\013')
            and recipient_email <> ''
        ),
    constraint organization_invitations_expiration_check
        check (expires_at > created_at),
    constraint organization_invitations_secret_digest_check
        check (
            acceptance_secret_digest is null
            or octet_length(acceptance_secret_digest) = 32
        ),
    constraint organization_invitations_revocation_pair_check
        check (
            (revoked_at is null) = (revoked_by_user_id is null)
        ),
    constraint organization_invitations_rejection_pair_check
        check (
            (rejected_at is null) = (rejected_by_user_id is null)
        ),
    constraint organization_invitations_terminal_exclusivity_check
        check (not (revoked_at is not null and rejected_at is not null)),
    constraint organization_invitations_revocation_time_check
        check (
            revoked_at is null
            or (revoked_at >= created_at and revoked_at < expires_at)
        ),
    constraint organization_invitations_rejection_time_check
        check (
            rejected_at is null
            or (rejected_at >= created_at and rejected_at < expires_at)
        )
);

create table public.organization_invitation_responsibilities (
    id uuid not null default gen_random_uuid(),
    invitation_id uuid not null,
    responsibility text not null,
    scope_type text not null,
    constraint organization_invitation_responsibilities_pkey primary key (id),
    constraint organization_invitation_responsibilities_invitation_id_fkey
        foreign key (invitation_id)
        references public.organization_invitations (id)
        on update no action
        on delete restrict,
    constraint organization_invitation_responsibilities_semantic_key
        unique (invitation_id, responsibility, scope_type),
    constraint organization_invitation_responsibilities_responsibility_check
        check (
            responsibility in (
                'ADMINISTRATOR',
                'RECEPTIONIST',
                'VETERINARIAN'
            )
        ),
    constraint organization_invitation_responsibilities_scope_type_check
        check (scope_type = 'ORGANIZATION')
);

create table public.organization_memberships (
    id uuid not null default gen_random_uuid(),
    organization_id uuid not null,
    user_id uuid not null,
    effective_start timestamptz not null,
    effective_end timestamptz,
    originating_invitation_id uuid,
    ended_by_user_id uuid,
    constraint organization_memberships_pkey primary key (id),
    constraint organization_memberships_organization_id_fkey
        foreign key (organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict,
    constraint organization_memberships_user_id_fkey
        foreign key (user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_memberships_originating_invitation_id_fkey
        foreign key (originating_invitation_id)
        references public.organization_invitations (id)
        on update no action
        on delete restrict,
    constraint organization_memberships_ended_by_user_id_fkey
        foreign key (ended_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_memberships_originating_invitation_id_key
        unique (originating_invitation_id),
    constraint organization_memberships_effective_period_check
        check (
            effective_end is null
            or effective_end >= effective_start
        ),
    constraint organization_memberships_end_pair_check
        check (
            (effective_end is null) = (ended_by_user_id is null)
        )
);

create table public.organization_responsibility_grants (
    id uuid not null default gen_random_uuid(),
    membership_id uuid not null,
    responsibility text not null,
    scope_type text not null,
    effective_start timestamptz not null,
    effective_end timestamptz,
    granted_by_user_id uuid not null,
    ended_by_user_id uuid,
    originating_invitation_responsibility_id uuid,
    constraint organization_responsibility_grants_pkey primary key (id),
    constraint organization_responsibility_grants_membership_id_fkey
        foreign key (membership_id)
        references public.organization_memberships (id)
        on update no action
        on delete restrict,
    constraint organization_responsibility_grants_granted_by_user_id_fkey
        foreign key (granted_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_responsibility_grants_ended_by_user_id_fkey
        foreign key (ended_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_responsibility_grants_origin_invitation_resp_fkey
        foreign key (originating_invitation_responsibility_id)
        references public.organization_invitation_responsibilities (id)
        on update no action
        on delete restrict,
    constraint organization_responsibility_grants_origin_invitation_resp_key
        unique (originating_invitation_responsibility_id),
    constraint organization_responsibility_grants_responsibility_check
        check (
            responsibility in (
                'OWNER',
                'ADMINISTRATOR',
                'RECEPTIONIST',
                'VETERINARIAN'
            )
        ),
    constraint organization_responsibility_grants_scope_type_check
        check (scope_type = 'ORGANIZATION'),
    constraint organization_responsibility_grants_effective_period_check
        check (
            effective_end is null
            or effective_end >= effective_start
        ),
    constraint organization_responsibility_grants_end_pair_check
        check (
            (effective_end is null) = (ended_by_user_id is null)
        )
);

create unique index organization_memberships_active_user_organization_key
on public.organization_memberships (user_id, organization_id)
where effective_end is null;

create index organization_memberships_user_organization_history_idx
on public.organization_memberships (
    user_id,
    organization_id,
    effective_start
);

create index organization_memberships_active_organization_idx
on public.organization_memberships (organization_id, id)
where effective_end is null;

create unique index organization_responsibility_grants_active_key
on public.organization_responsibility_grants (membership_id, responsibility)
where effective_end is null and scope_type = 'ORGANIZATION';

create index organization_responsibility_grants_membership_history_idx
on public.organization_responsibility_grants (membership_id, effective_start);

create index organization_invitations_organization_email_idx
on public.organization_invitations (
    organization_id,
    recipient_email_normalized
);

create index organization_invitations_organization_recipient_user_idx
on public.organization_invitations (organization_id, recipient_user_id)
where recipient_user_id is not null;

create function public.enforce_veterinary_organization_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Veterinary Organizations cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id then
        raise exception 'Veterinary Organization identity is immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_veterinary_organization_immutability()
from public, anon, authenticated;

create trigger veterinary_organizations_preserve_identity
before update or delete on public.veterinary_organizations
for each row
execute function public.enforce_veterinary_organization_immutability();

create function public.enforce_organization_invitation_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Organization Invitations cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.organization_id is distinct from new.organization_id
       or old.inviting_user_id is distinct from new.inviting_user_id
       or old.recipient_user_id is distinct from new.recipient_user_id
       or old.recipient_email is distinct from new.recipient_email
       or old.created_at is distinct from new.created_at
       or old.expires_at is distinct from new.expires_at then
        raise exception 'Organization Invitation identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.revoked_at is not null
       and (
           old.revoked_at is distinct from new.revoked_at
           or old.revoked_by_user_id is distinct from new.revoked_by_user_id
       ) then
        raise exception 'Organization Invitation revocation facts are immutable'
            using errcode = '23514';
    end if;

    if old.rejected_at is not null
       and (
           old.rejected_at is distinct from new.rejected_at
           or old.rejected_by_user_id is distinct from new.rejected_by_user_id
       ) then
        raise exception 'Organization Invitation rejection facts are immutable'
            using errcode = '23514';
    end if;

    if old.acceptance_secret_digest is null
       and new.acceptance_secret_digest is not null then
        raise exception 'Organization Invitation acceptance credential cannot be restored'
            using errcode = '23514';
    end if;

    if old.acceptance_secret_digest is not null
       and new.acceptance_secret_digest is not null
       and old.acceptance_secret_digest is distinct from new.acceptance_secret_digest then
        raise exception 'Organization Invitation acceptance credential cannot be replaced'
            using errcode = '23514';
    end if;

    if old.acceptance_secret_digest is not null
       and new.acceptance_secret_digest is null
       and new.revoked_at is null
       and new.rejected_at is null
       and not exists (
           select 1
           from public.organization_memberships as membership
           where membership.originating_invitation_id = old.id
       )
       and clock_timestamp() < old.expires_at then
        raise exception 'A pending Organization Invitation must retain its acceptance credential'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_organization_invitation_immutability()
from public, anon, authenticated;

create trigger organization_invitations_preserve_history
before update or delete on public.organization_invitations
for each row
execute function public.enforce_organization_invitation_immutability();

create function public.enforce_invitation_responsibility_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'Organization Invitation Responsibilities are immutable'
        using errcode = '23514';
end;
$$;

revoke all privileges
on function public.enforce_invitation_responsibility_immutability()
from public, anon, authenticated;

create trigger organization_invitation_responsibilities_preserve_history
before update or delete on public.organization_invitation_responsibilities
for each row
execute function public.enforce_invitation_responsibility_immutability();

create function public.enforce_organization_membership_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Organization Memberships cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.organization_id is distinct from new.organization_id
       or old.user_id is distinct from new.user_id
       or old.effective_start is distinct from new.effective_start
       or old.originating_invitation_id is distinct from new.originating_invitation_id then
        raise exception 'Organization Membership identity and historical origin are immutable'
            using errcode = '23514';
    end if;

    if old.effective_end is not null
       and (
           old.effective_end is distinct from new.effective_end
           or old.ended_by_user_id is distinct from new.ended_by_user_id
       ) then
        raise exception 'Ended Organization Membership facts are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_organization_membership_immutability()
from public, anon, authenticated;

create trigger organization_memberships_preserve_history
before update or delete on public.organization_memberships
for each row
execute function public.enforce_organization_membership_immutability();

create function public.enforce_organization_grant_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Organization Responsibility Grants cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.membership_id is distinct from new.membership_id
       or old.responsibility is distinct from new.responsibility
       or old.scope_type is distinct from new.scope_type
       or old.effective_start is distinct from new.effective_start
       or old.granted_by_user_id is distinct from new.granted_by_user_id
       or old.originating_invitation_responsibility_id is distinct from
           new.originating_invitation_responsibility_id then
        raise exception 'Organization Responsibility Grant historical facts are immutable'
            using errcode = '23514';
    end if;

    if old.effective_end is not null
       and (
           old.effective_end is distinct from new.effective_end
           or old.ended_by_user_id is distinct from new.ended_by_user_id
       ) then
        raise exception 'Ended Organization Responsibility Grant facts are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_organization_grant_immutability()
from public, anon, authenticated;

create trigger organization_responsibility_grants_preserve_history
before update or delete on public.organization_responsibility_grants
for each row
execute function public.enforce_organization_grant_immutability();

create function public.assert_organization_invitation_has_responsibility(
    p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        return;
    end if;

    if not exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
    ) then
        raise exception 'Organization Invitation % requires at least one intended responsibility',
            p_invitation_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_organization_invitation_has_responsibility(uuid)
from public, anon, authenticated;

create function public.enforce_organization_invitation_responsibility_minimum()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'organization_invitations' then
        perform public.assert_organization_invitation_has_responsibility(new.id);
    elsif tg_op = 'INSERT' then
        perform public.assert_organization_invitation_has_responsibility(new.invitation_id);
    elsif tg_op = 'DELETE' then
        perform public.assert_organization_invitation_has_responsibility(old.invitation_id);
    elsif tg_op = 'UPDATE' then
        perform public.assert_organization_invitation_has_responsibility(old.invitation_id);
        if old.invitation_id is distinct from new.invitation_id then
            perform public.assert_organization_invitation_has_responsibility(new.invitation_id);
        end if;
    else
        raise exception 'Unexpected Invitation responsibility cardinality trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_organization_invitation_responsibility_minimum()
from public, anon, authenticated;

create constraint trigger organization_invitations_require_responsibility
after insert on public.organization_invitations
deferrable initially deferred
for each row
execute function public.enforce_organization_invitation_responsibility_minimum();

create constraint trigger organization_invitation_responsibilities_preserve_minimum
after insert or update or delete
on public.organization_invitation_responsibilities
deferrable initially deferred
for each row
execute function public.enforce_organization_invitation_responsibility_minimum();

create function public.assert_organization_membership_has_responsibility_grant(
    p_membership_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.organization_memberships as membership
    where membership.id = p_membership_id
    for update;

    if not found then
        return;
    end if;

    if not exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
    ) then
        raise exception 'Organization Membership % requires at least one historical Responsibility Grant',
            p_membership_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_organization_membership_has_responsibility_grant(uuid)
from public, anon, authenticated;

create function public.enforce_organization_membership_grant_minimum()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'organization_memberships' then
        perform public.assert_organization_membership_has_responsibility_grant(new.id);
    elsif tg_op = 'INSERT' then
        perform public.assert_organization_membership_has_responsibility_grant(new.membership_id);
    elsif tg_op = 'DELETE' then
        perform public.assert_organization_membership_has_responsibility_grant(old.membership_id);
    elsif tg_op = 'UPDATE' then
        perform public.assert_organization_membership_has_responsibility_grant(old.membership_id);
        if old.membership_id is distinct from new.membership_id then
            perform public.assert_organization_membership_has_responsibility_grant(new.membership_id);
        end if;
    else
        raise exception 'Unexpected Membership Grant cardinality trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_organization_membership_grant_minimum()
from public, anon, authenticated;

create constraint trigger organization_memberships_require_grant
after insert on public.organization_memberships
deferrable initially deferred
for each row
execute function public.enforce_organization_membership_grant_minimum();

create constraint trigger organization_grants_preserve_membership_minimum
after insert or update or delete
on public.organization_responsibility_grants
deferrable initially deferred
for each row
execute function public.enforce_organization_membership_grant_minimum();

create function public.assert_organization_has_active_owner(
    p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found then
        return;
    end if;

    if not exists (
        select 1
        from public.organization_memberships as membership
        join public.organization_responsibility_grants as grant_record
          on grant_record.membership_id = membership.id
        where membership.organization_id = p_organization_id
          and membership.effective_end is null
          and grant_record.effective_end is null
          and grant_record.responsibility = 'OWNER'
          and grant_record.scope_type = 'ORGANIZATION'
    ) then
        raise exception 'Veterinary Organization % requires at least one active Owner',
            p_organization_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_organization_has_active_owner(uuid)
from public, anon, authenticated;

create function public.enforce_organization_active_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    old_organization_id uuid;
    new_organization_id uuid;
begin
    if tg_table_name = 'veterinary_organizations' then
        perform public.assert_organization_has_active_owner(new.id);
        return null;
    end if;

    if tg_table_name = 'organization_memberships' then
        if tg_op in ('UPDATE', 'DELETE') then
            old_organization_id := old.organization_id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            new_organization_id := new.organization_id;
        end if;
    elsif tg_table_name = 'organization_responsibility_grants' then
        if tg_op in ('UPDATE', 'DELETE') then
            select membership.organization_id
            into old_organization_id
            from public.organization_memberships as membership
            where membership.id = old.membership_id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            select membership.organization_id
            into new_organization_id
            from public.organization_memberships as membership
            where membership.id = new.membership_id;
        end if;
    else
        raise exception 'Unexpected Organization Owner trigger invocation'
            using errcode = '55000';
    end if;

    if old_organization_id is not null then
        perform public.assert_organization_has_active_owner(old_organization_id);
    end if;

    if new_organization_id is not null
       and new_organization_id is distinct from old_organization_id then
        perform public.assert_organization_has_active_owner(new_organization_id);
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_organization_active_owner()
from public, anon, authenticated;

create constraint trigger veterinary_organizations_require_active_owner
after insert on public.veterinary_organizations
deferrable initially deferred
for each row
execute function public.enforce_organization_active_owner();

create constraint trigger organization_memberships_preserve_active_owner
after insert or update or delete on public.organization_memberships
deferrable initially deferred
for each row
execute function public.enforce_organization_active_owner();

create constraint trigger organization_responsibility_grants_preserve_active_owner
after insert or update or delete
on public.organization_responsibility_grants
deferrable initially deferred
for each row
execute function public.enforce_organization_active_owner();

create function public.assert_membership_grant_temporal_integrity(
    p_membership_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    membership_record public.organization_memberships%rowtype;
begin
    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
    for update;

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
          and (
              grant_record.effective_start < membership_record.effective_start
              or (
                  membership_record.effective_end is not null
                  and (
                      grant_record.effective_end is null
                      or grant_record.effective_end > membership_record.effective_end
                  )
              )
          )
    ) then
        raise exception 'Organization Responsibility Grant period must remain within Membership %',
            p_membership_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_membership_grant_temporal_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_membership_grant_temporal_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'organization_memberships' then
        if tg_op in ('INSERT', 'UPDATE') then
            perform public.assert_membership_grant_temporal_integrity(new.id);
        end if;
        if tg_op = 'DELETE' then
            perform public.assert_membership_grant_temporal_integrity(old.id);
        end if;
    elsif tg_op = 'INSERT' then
        perform public.assert_membership_grant_temporal_integrity(new.membership_id);
    elsif tg_op = 'DELETE' then
        perform public.assert_membership_grant_temporal_integrity(old.membership_id);
    elsif tg_op = 'UPDATE' then
        perform public.assert_membership_grant_temporal_integrity(old.membership_id);
        if old.membership_id is distinct from new.membership_id then
            perform public.assert_membership_grant_temporal_integrity(new.membership_id);
        end if;
    else
        raise exception 'Unexpected Membership/Grant temporal trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_membership_grant_temporal_integrity()
from public, anon, authenticated;

create constraint trigger organization_memberships_enforce_grant_periods
after insert or update or delete on public.organization_memberships
deferrable initially deferred
for each row
execute function public.enforce_membership_grant_temporal_integrity();

create constraint trigger organization_responsibility_grants_enforce_membership_period
after insert or update or delete
on public.organization_responsibility_grants
deferrable initially deferred
for each row
execute function public.enforce_membership_grant_temporal_integrity();

create function public.assert_organization_invitation_acceptance_integrity(
    p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation_record public.organization_invitations%rowtype;
    membership_record public.organization_memberships%rowtype;
begin
    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        return;
    end if;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.originating_invitation_id = p_invitation_id;

    if not found then
        if exists (
            select 1
            from public.organization_responsibility_grants as grant_record
            join public.organization_invitation_responsibilities as intended
              on intended.id = grant_record.originating_invitation_responsibility_id
            where intended.invitation_id = p_invitation_id
        ) then
            raise exception 'Invitation-derived Grant requires the resulting Membership for Invitation %',
                p_invitation_id
                using errcode = '23514';
        end if;

        return;
    end if;

    if invitation_record.revoked_at is not null
       or invitation_record.rejected_at is not null then
        raise exception 'Accepted Organization Invitation % cannot also be revoked or rejected',
            p_invitation_id
            using errcode = '23514';
    end if;

    if invitation_record.acceptance_secret_digest is not null then
        raise exception 'Accepted Organization Invitation % must not retain its acceptance credential',
            p_invitation_id
            using errcode = '23514';
    end if;

    if membership_record.organization_id <> invitation_record.organization_id then
        raise exception 'Invitation-derived Membership must belong to the invited Organization'
            using errcode = '23514';
    end if;

    if invitation_record.recipient_user_id is not null
       and membership_record.user_id <> invitation_record.recipient_user_id then
        raise exception 'Invitation-derived Membership User must match the bound recipient User'
            using errcode = '23514';
    end if;

    if membership_record.effective_start < invitation_record.created_at
       or membership_record.effective_start >= invitation_record.expires_at then
        raise exception 'Organization Invitation acceptance must occur during its validity period'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
          and not exists (
              select 1
              from public.organization_responsibility_grants as grant_record
              where grant_record.originating_invitation_responsibility_id = intended.id
                and grant_record.membership_id = membership_record.id
                and grant_record.responsibility = intended.responsibility
                and grant_record.scope_type = intended.scope_type
                and grant_record.effective_start = membership_record.effective_start
                and grant_record.granted_by_user_id = invitation_record.inviting_user_id
          )
    ) then
        raise exception 'Accepted Organization Invitation % requires every intended Grant',
            p_invitation_id
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        join public.organization_invitation_responsibilities as intended
          on intended.id = grant_record.originating_invitation_responsibility_id
        where intended.invitation_id = p_invitation_id
          and (
              grant_record.membership_id <> membership_record.id
              or grant_record.responsibility <> intended.responsibility
              or grant_record.scope_type <> intended.scope_type
              or grant_record.effective_start <> membership_record.effective_start
              or grant_record.granted_by_user_id <> invitation_record.inviting_user_id
          )
    ) then
        raise exception 'Invitation-derived Grants must preserve their exact Invitation origin'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        join public.organization_invitation_responsibilities as intended
          on intended.id = grant_record.originating_invitation_responsibility_id
        where grant_record.membership_id = membership_record.id
          and intended.invitation_id <> p_invitation_id
    ) then
        raise exception 'Invitation-derived Membership cannot contain Grants from another Invitation'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_organization_invitation_acceptance_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_organization_invitation_acceptance_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    old_invitation_id uuid;
    new_invitation_id uuid;
begin
    if tg_table_name = 'organization_invitations' then
        if tg_op in ('INSERT', 'UPDATE') then
            new_invitation_id := new.id;
        end if;
        if tg_op = 'DELETE' then
            old_invitation_id := old.id;
        end if;
    elsif tg_table_name = 'organization_invitation_responsibilities' then
        if tg_op in ('UPDATE', 'DELETE') then
            old_invitation_id := old.invitation_id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            new_invitation_id := new.invitation_id;
        end if;
    elsif tg_table_name = 'organization_memberships' then
        if tg_op in ('UPDATE', 'DELETE') then
            old_invitation_id := old.originating_invitation_id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            new_invitation_id := new.originating_invitation_id;
        end if;
    elsif tg_table_name = 'organization_responsibility_grants' then
        if tg_op in ('UPDATE', 'DELETE')
           and old.originating_invitation_responsibility_id is not null then
            select intended.invitation_id
            into old_invitation_id
            from public.organization_invitation_responsibilities as intended
            where intended.id = old.originating_invitation_responsibility_id;
        end if;
        if tg_op in ('INSERT', 'UPDATE')
           and new.originating_invitation_responsibility_id is not null then
            select intended.invitation_id
            into new_invitation_id
            from public.organization_invitation_responsibilities as intended
            where intended.id = new.originating_invitation_responsibility_id;
        end if;
    else
        raise exception 'Unexpected Invitation acceptance integrity trigger invocation'
            using errcode = '55000';
    end if;

    if old_invitation_id is not null then
        perform public.assert_organization_invitation_acceptance_integrity(
            old_invitation_id
        );
    end if;

    if new_invitation_id is not null
       and new_invitation_id is distinct from old_invitation_id then
        perform public.assert_organization_invitation_acceptance_integrity(
            new_invitation_id
        );
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_organization_invitation_acceptance_integrity()
from public, anon, authenticated;

create constraint trigger organization_invitations_enforce_terminal_integrity
after insert or update or delete on public.organization_invitations
deferrable initially deferred
for each row
execute function public.enforce_organization_invitation_acceptance_integrity();

create constraint trigger organization_invitation_responsibilities_enforce_acceptance
after insert or update or delete
on public.organization_invitation_responsibilities
deferrable initially deferred
for each row
execute function public.enforce_organization_invitation_acceptance_integrity();

create constraint trigger organization_memberships_enforce_invitation_acceptance
after insert or update or delete on public.organization_memberships
deferrable initially deferred
for each row
execute function public.enforce_organization_invitation_acceptance_integrity();

create constraint trigger organization_responsibility_grants_enforce_invitation_origin
after insert or update or delete
on public.organization_responsibility_grants
deferrable initially deferred
for each row
execute function public.enforce_organization_invitation_acceptance_integrity();

create function public.user_has_organization_capability(
    p_user_id uuid,
    p_organization_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        coalesce(
            p_capability in (
                'ORGANIZATION_INVITE_MEMBERS',
                'ORGANIZATION_REVOKE_INVITATIONS',
                'ORGANIZATION_END_MEMBERSHIPS',
                'ORGANIZATION_GRANT_RESPONSIBILITIES'
            ),
            false
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as grant_record
              on grant_record.membership_id = membership.id
            where membership.user_id = p_user_id
              and membership.organization_id = p_organization_id
              and membership.effective_end is null
              and grant_record.effective_end is null
              and grant_record.scope_type = 'ORGANIZATION'
              and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
        )
$$;

revoke all privileges
on function public.user_has_organization_capability(uuid, uuid, text)
from public, anon, authenticated;

create function public.create_veterinary_organization(
    p_display_name text
)
returns table (
    organization_id uuid,
    membership_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    domain_user_id uuid;
    normalized_display_name text;
    operation_timestamp timestamptz;
    created_organization_id uuid;
    created_membership_id uuid;
begin
    authenticated_subject_id := auth.uid();

    if authenticated_subject_id is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    domain_user_id := public.current_domain_user_id();

    if domain_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from auth.users as auth_user
        where auth_user.id = authenticated_subject_id
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'A verified email address is required'
            using errcode = '42501';
    end if;

    normalized_display_name := btrim(p_display_name, E' \t\n\r\f\013');

    if normalized_display_name is null or normalized_display_name = '' then
        raise exception 'Veterinary Organization display name must not be blank'
            using errcode = '22023';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.veterinary_organizations (display_name)
    values (normalized_display_name)
    returning id into created_organization_id;

    insert into public.organization_memberships (
        organization_id,
        user_id,
        effective_start
    )
    values (
        created_organization_id,
        domain_user_id,
        operation_timestamp
    )
    returning id into created_membership_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        effective_start,
        granted_by_user_id
    )
    values (
        created_membership_id,
        'OWNER',
        'ORGANIZATION',
        operation_timestamp,
        domain_user_id
    );

    return query
    select created_organization_id, created_membership_id;
end;
$$;

revoke all privileges
on function public.create_veterinary_organization(text)
from public, anon, authenticated;

grant execute
on function public.create_veterinary_organization(text)
to authenticated;

create function public.create_organization_invitation(
    p_acting_user_id uuid,
    p_organization_id uuid,
    p_recipient_user_id uuid,
    p_recipient_email text,
    p_responsibilities text[],
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_recipient_email text;
    operation_timestamp timestamptz;
    created_invitation_id uuid;
begin
    if p_acting_user_id is null then
        raise exception 'A trusted acting domain User is required'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = p_acting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The acting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    normalized_recipient_email := btrim(
        p_recipient_email,
        E' \t\n\r\f\013'
    );

    if normalized_recipient_email is null
       or normalized_recipient_email = '' then
        raise exception 'Organization Invitation recipient email must not be blank'
            using errcode = '22023';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Organization Invitation acceptance digest must be 32 bytes'
            using errcode = '22023';
    end if;

    if coalesce(cardinality(p_responsibilities), 0) = 0 then
        raise exception 'At least one intended Organization responsibility is required'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from pg_catalog.unnest(p_responsibilities) as requested(responsibility)
        where requested.responsibility is null
           or requested.responsibility not in (
               'ADMINISTRATOR',
               'RECEPTIONIST',
               'VETERINARIAN'
           )
    ) then
        raise exception 'Invitation contains an unsupported Organization responsibility'
            using errcode = '22023';
    end if;

    if cardinality(p_responsibilities) <> (
        select count(distinct requested.responsibility)
        from pg_catalog.unnest(p_responsibilities) as requested(responsibility)
    ) then
        raise exception 'Invitation must not contain duplicate responsibilities'
            using errcode = '22023';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    operation_timestamp := clock_timestamp();

    if p_expires_at is null or p_expires_at <= operation_timestamp then
        raise exception 'Organization Invitation expiration must follow creation'
            using errcode = '22023';
    end if;

    if not public.user_has_organization_capability(
        p_acting_user_id,
        p_organization_id,
        'ORGANIZATION_INVITE_MEMBERS'
    ) then
        raise exception 'Organization Invitation capability is required'
            using errcode = '42501';
    end if;

    if p_recipient_user_id is not null
       and exists (
           select 1
           from public.organization_memberships as membership
           where membership.organization_id = p_organization_id
             and membership.user_id = p_recipient_user_id
             and membership.effective_end is null
       ) then
        raise exception 'Recipient already has an active Organization Membership'
            using errcode = '23505';
    end if;

    if exists (
        select 1
        from public.organization_invitations as invitation
        where invitation.organization_id = p_organization_id
          and invitation.revoked_at is null
          and invitation.rejected_at is null
          and invitation.expires_at > operation_timestamp
          and not exists (
              select 1
              from public.organization_memberships as resulting_membership
              where resulting_membership.originating_invitation_id = invitation.id
          )
          and (
              (
                  p_recipient_user_id is not null
                  and invitation.recipient_user_id = p_recipient_user_id
              )
              or invitation.recipient_email_normalized = lower(
                  btrim(normalized_recipient_email, E' \t\n\r\f\013')
              )
          )
    ) then
        raise exception 'An equivalent pending Organization Invitation already exists'
            using errcode = '23505';
    end if;

    insert into public.organization_invitations (
        organization_id,
        inviting_user_id,
        recipient_user_id,
        recipient_email,
        created_at,
        expires_at,
        acceptance_secret_digest
    )
    values (
        p_organization_id,
        p_acting_user_id,
        p_recipient_user_id,
        normalized_recipient_email,
        operation_timestamp,
        p_expires_at,
        p_acceptance_secret_digest
    )
    returning id into created_invitation_id;

    insert into public.organization_invitation_responsibilities (
        invitation_id,
        responsibility,
        scope_type
    )
    select
        created_invitation_id,
        requested.responsibility,
        'ORGANIZATION'
    from pg_catalog.unnest(p_responsibilities) as requested(responsibility);

    return created_invitation_id;
end;
$$;

revoke all privileges
on function public.create_organization_invitation(
    uuid,
    uuid,
    uuid,
    text,
    text[],
    timestamptz,
    bytea
)
from public, anon, authenticated;

grant execute
on function public.create_organization_invitation(
    uuid,
    uuid,
    uuid,
    text,
    text[],
    timestamptz,
    bytea
)
to service_role;

create function public.accept_organization_invitation(
    p_accepting_user_id uuid,
    p_invitation_id uuid,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation_organization_id uuid;
    invitation_record public.organization_invitations%rowtype;
    operation_timestamp timestamptz;
    created_membership_id uuid;
begin
    if p_accepting_user_id is null then
        raise exception 'A trusted accepting domain User is required'
            using errcode = '28000';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Organization Invitation acceptance digest must be 32 bytes'
            using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = p_accepting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The accepting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    select invitation.organization_id
    into invitation_organization_id
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id;

    if not found then
        raise exception 'Organization Invitation does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = invitation_organization_id
    for update;

    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        raise exception 'Organization Invitation does not exist'
            using errcode = '23503';
    end if;

    operation_timestamp := clock_timestamp();

    if operation_timestamp >= invitation_record.expires_at then
        raise exception 'Organization Invitation has expired'
            using errcode = '23514';
    end if;

    if invitation_record.revoked_at is not null
       or invitation_record.rejected_at is not null then
        raise exception 'Organization Invitation is no longer pending'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.originating_invitation_id = p_invitation_id
    ) then
        raise exception 'Organization Invitation has already been accepted'
            using errcode = '23505';
    end if;

    if invitation_record.acceptance_secret_digest is null
       or invitation_record.acceptance_secret_digest is distinct from
           p_acceptance_secret_digest then
        raise exception 'Organization Invitation recipient proof is invalid'
            using errcode = '42501';
    end if;

    if invitation_record.recipient_user_id is not null
       and invitation_record.recipient_user_id <> p_accepting_user_id then
        raise exception 'Organization Invitation is bound to another User'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.organization_id = invitation_record.organization_id
          and membership.user_id = p_accepting_user_id
          and membership.effective_end is null
    ) then
        raise exception 'User already has an active Organization Membership'
            using errcode = '23505';
    end if;

    if not exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
    ) or exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
          and (
              intended.responsibility not in (
                  'ADMINISTRATOR',
                  'RECEPTIONIST',
                  'VETERINARIAN'
              )
              or intended.scope_type <> 'ORGANIZATION'
          )
    ) then
        raise exception 'Organization Invitation contains invalid responsibilities'
            using errcode = '23514';
    end if;

    insert into public.organization_memberships (
        organization_id,
        user_id,
        effective_start,
        originating_invitation_id
    )
    values (
        invitation_record.organization_id,
        p_accepting_user_id,
        operation_timestamp,
        p_invitation_id
    )
    returning id into created_membership_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        effective_start,
        granted_by_user_id,
        originating_invitation_responsibility_id
    )
    select
        created_membership_id,
        intended.responsibility,
        intended.scope_type,
        operation_timestamp,
        invitation_record.inviting_user_id,
        intended.id
    from public.organization_invitation_responsibilities as intended
    where intended.invitation_id = p_invitation_id;

    update public.organization_invitations
    set acceptance_secret_digest = null
    where id = p_invitation_id;

    return created_membership_id;
end;
$$;

revoke all privileges
on function public.accept_organization_invitation(uuid, uuid, bytea)
from public, anon, authenticated;

grant execute
on function public.accept_organization_invitation(uuid, uuid, bytea)
to service_role;

create function public.end_organization_membership(
    p_membership_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    acting_user_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    operation_timestamp timestamptz;
begin
    authenticated_subject_id := auth.uid();

    if authenticated_subject_id is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_membership_id;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = target_organization_id
    for update;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
    end if;

    if membership_record.effective_end is not null then
        raise exception 'Organization Membership has already ended'
            using errcode = '23514';
    end if;

    if membership_record.user_id <> acting_user_id
       and not public.user_has_organization_capability(
           acting_user_id,
           target_organization_id,
           'ORGANIZATION_END_MEMBERSHIPS'
       ) then
        raise exception 'Organization Membership termination capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.organization_responsibility_grants as grant_record
    where grant_record.membership_id = p_membership_id
      and grant_record.effective_end is null
    order by grant_record.id
    for update;

    if exists (
        select 1
        from public.organization_responsibility_grants as target_owner
        where target_owner.membership_id = p_membership_id
          and target_owner.effective_end is null
          and target_owner.responsibility = 'OWNER'
          and target_owner.scope_type = 'ORGANIZATION'
    ) and not exists (
        select 1
        from public.organization_memberships as other_membership
        join public.organization_responsibility_grants as other_owner
          on other_owner.membership_id = other_membership.id
        where other_membership.organization_id = target_organization_id
          and other_membership.id <> p_membership_id
          and other_membership.effective_end is null
          and other_owner.effective_end is null
          and other_owner.responsibility = 'OWNER'
          and other_owner.scope_type = 'ORGANIZATION'
    ) then
        raise exception 'The sole active Organization Owner Membership cannot end'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    update public.organization_responsibility_grants
    set effective_end = operation_timestamp,
        ended_by_user_id = acting_user_id
    where membership_id = p_membership_id
      and effective_end is null;

    update public.organization_memberships
    set effective_end = operation_timestamp,
        ended_by_user_id = acting_user_id
    where id = p_membership_id;
end;
$$;

revoke all privileges
on function public.end_organization_membership(uuid)
from public, anon, authenticated;

grant execute
on function public.end_organization_membership(uuid)
to authenticated;

create function public.add_organization_responsibility(
    p_membership_id uuid,
    p_responsibility text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    operation_timestamp timestamptz;
    created_grant_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if p_responsibility is null
       or p_responsibility not in (
           'ADMINISTRATOR',
           'RECEPTIONIST',
           'VETERINARIAN'
       ) then
        raise exception 'Unsupported non-owner Organization responsibility'
            using errcode = '22023';
    end if;

    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_membership_id;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = target_organization_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
          and grant_record.responsibility = p_responsibility
          and grant_record.scope_type = 'ORGANIZATION'
          and grant_record.effective_end is null
    ) then
        raise exception 'Equivalent active Organization Responsibility Grant already exists'
            using errcode = '23505';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        effective_start,
        granted_by_user_id
    )
    values (
        p_membership_id,
        p_responsibility,
        'ORGANIZATION',
        operation_timestamp,
        acting_user_id
    )
    returning id into created_grant_id;

    return created_grant_id;
end;
$$;

revoke all privileges
on function public.add_organization_responsibility(uuid, text)
from public, anon, authenticated;

grant execute
on function public.add_organization_responsibility(uuid, text)
to authenticated;

create function public.end_organization_responsibility(
    p_grant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    grant_record public.organization_responsibility_grants%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select source_grant.membership_id, membership.organization_id
    into target_membership_id, target_organization_id
    from public.organization_responsibility_grants as source_grant
    join public.organization_memberships as membership
      on membership.id = source_grant.membership_id
    where source_grant.id = p_grant_id;

    if not found then
        raise exception 'Organization Responsibility Grant does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = target_organization_id
    for update;

    select current_grant.*
    into grant_record
    from public.organization_responsibility_grants as current_grant
    where current_grant.id = p_grant_id
      and current_grant.membership_id = target_membership_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if grant_record.effective_end is not null then
        raise exception 'Organization Responsibility Grant has already ended'
            using errcode = '23514';
    end if;

    if grant_record.responsibility = 'OWNER' then
        raise exception 'OWNER cannot be removed through ordinary responsibility management'
            using errcode = '42501';
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    operation_timestamp := clock_timestamp();

    update public.organization_responsibility_grants
    set effective_end = operation_timestamp,
        ended_by_user_id = acting_user_id
    where id = p_grant_id;
end;
$$;

revoke all privileges
on function public.end_organization_responsibility(uuid)
from public, anon, authenticated;

grant execute
on function public.end_organization_responsibility(uuid)
to authenticated;

create function public.replace_organization_responsibility(
    p_grant_id uuid,
    p_new_responsibility text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    grant_record public.organization_responsibility_grants%rowtype;
    operation_timestamp timestamptz;
    created_grant_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if p_new_responsibility is null
       or p_new_responsibility not in (
           'ADMINISTRATOR',
           'RECEPTIONIST',
           'VETERINARIAN'
       ) then
        raise exception 'Unsupported non-owner Organization responsibility'
            using errcode = '22023';
    end if;

    select source_grant.membership_id, membership.organization_id
    into target_membership_id, target_organization_id
    from public.organization_responsibility_grants as source_grant
    join public.organization_memberships as membership
      on membership.id = source_grant.membership_id
    where source_grant.id = p_grant_id;

    if not found then
        raise exception 'Organization Responsibility Grant does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = target_organization_id
    for update;

    select current_grant.*
    into grant_record
    from public.organization_responsibility_grants as current_grant
    where current_grant.id = p_grant_id
      and current_grant.membership_id = target_membership_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if grant_record.effective_end is not null then
        raise exception 'Organization Responsibility Grant has already ended'
            using errcode = '23514';
    end if;

    if grant_record.responsibility = 'OWNER' then
        raise exception 'OWNER cannot be replaced through ordinary responsibility management'
            using errcode = '42501';
    end if;

    if grant_record.responsibility = p_new_responsibility then
        raise exception 'No-op Organization responsibility replacement is not allowed'
            using errcode = '22023';
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as equivalent_grant
        where equivalent_grant.membership_id = target_membership_id
          and equivalent_grant.responsibility = p_new_responsibility
          and equivalent_grant.scope_type = 'ORGANIZATION'
          and equivalent_grant.effective_end is null
    ) then
        raise exception 'Equivalent active Organization Responsibility Grant already exists'
            using errcode = '23505';
    end if;

    operation_timestamp := clock_timestamp();

    update public.organization_responsibility_grants
    set effective_end = operation_timestamp,
        ended_by_user_id = acting_user_id
    where id = p_grant_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        effective_start,
        granted_by_user_id
    )
    values (
        target_membership_id,
        p_new_responsibility,
        'ORGANIZATION',
        operation_timestamp,
        acting_user_id
    )
    returning id into created_grant_id;

    return created_grant_id;
end;
$$;

revoke all privileges
on function public.replace_organization_responsibility(uuid, text)
from public, anon, authenticated;

grant execute
on function public.replace_organization_responsibility(uuid, text)
to authenticated;

alter table public.veterinary_organizations enable row level security;
alter table public.organization_invitations enable row level security;
alter table public.organization_invitation_responsibilities enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.organization_responsibility_grants enable row level security;

revoke all privileges on table public.veterinary_organizations
from public, anon, authenticated;
revoke all privileges on table public.organization_invitations
from public, anon, authenticated;
revoke all privileges on table public.organization_invitation_responsibilities
from public, anon, authenticated;
revoke all privileges on table public.organization_memberships
from public, anon, authenticated;
revoke all privileges on table public.organization_responsibility_grants
from public, anon, authenticated;

commit;
