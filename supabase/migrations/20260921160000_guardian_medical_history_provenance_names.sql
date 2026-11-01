begin;

-- Guardian medical-history provenance names (Clinic + Veterinary
-- Organization display name).
--
-- Closes a gap found during the mobile Milestone G UI-contract audit:
-- SPEC-MED-005 BR-5 lists Clinic and Veterinary Organization identity among
-- the provenance a finalized clinical contribution must preserve/establish,
-- and BR-7 requires a record to "remain identifiable as an Animalia Madrid
-- Centro contribution" even years later. The only Guardian-reachable
-- Clinic-name surface before this migration
-- (public.published_clinic_public_profiles) is gated on
-- clinics.is_published, which contradicts BR-29 ("Unpublishing a Clinic must
-- not remove its historical clinical contributions... Public Clinic
-- Discovery and historical clinical provenance are separate concerns"), and
-- no Guardian-reachable Veterinary Organization-name surface existed at all.
--
-- This migration creates no new public lookup surface, no new grant, and no
-- new view/RPC reachable independently of an already-authorized read: the
-- two display names are embedded only inside the payload
-- public.view_guardian_pet_medical_history already returns after its own
-- unchanged current-Guardianship authorization succeeds, resolved from the
-- Clinic/Veterinary Organization already associated with each returned
-- Entry's Clinical Encounter (clinic_id/organization_id, already present in
-- that payload). No Veterinarian personal name or public.user_profiles data
-- is added or touched — that remains explicitly out of scope.
--
-- Slices 11-13 are not modified. The currently-deployed
-- public.view_guardian_pet_medical_history (the Slice 13 wrapper that adds
-- `attachments` over slice12_view_guardian_pet_medical_history via
-- decorate_clinical_attachment_read — see
-- supabase/migrations/20260831120000_clinical_attachments.sql) is renamed to
-- slice13_view_guardian_pet_medical_history and re-wrapped, unchanged, by a
-- new same-named public function that adds one further decoration step. This
-- mirrors that same migration's own renaming pattern for the Slice 12 base
-- function, one layer further out.

create function public.decorate_guardian_medical_history_provenance_names(
    p_result jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare decorated_entries jsonb;
begin
    if p_result ->> 'status' <> 'PERMITTED' then return p_result; end if;
    select coalesce(jsonb_agg(entry_value || jsonb_build_object(
               'clinic_display_name', (
                   select profile.display_name
                   from public.clinic_public_profiles as profile
                   where profile.clinic_id = (entry_value ->> 'clinic_id')::uuid
               ),
               'organization_display_name', (
                   select organization.display_name
                   from public.veterinary_organizations as organization
                   where organization.id = (entry_value ->> 'organization_id')::uuid
               )
           ) order by ordinal), '[]'::jsonb)
    into decorated_entries
    from jsonb_array_elements(p_result #> '{payload,entries}') with ordinality as item(entry_value, ordinal);
    return jsonb_set(p_result, '{payload,entries}', decorated_entries, false);
end;
$$;

revoke all privileges
on function public.decorate_guardian_medical_history_provenance_names(jsonb)
from public, anon, authenticated;

-- Preserve the exact deployed Slice 13 implementation (current-Guardianship
-- authorization, DENIED/audit behavior, pagination/cursor semantics,
-- finalized-only filtering, amendments, and attachment decoration) as a
-- private base; the same public signature adds only the two provenance-name
-- properties per entry, merged onto the entry object that already carries
-- `attachments` — no existing key is removed or overwritten.
alter function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
rename to slice13_view_guardian_pet_medical_history;
revoke all privileges
on function public.slice13_view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
from public, anon, authenticated;

create function public.view_guardian_pet_medical_history(
    p_pet_id uuid,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb language sql security definer set search_path = ''
as $$
    select public.decorate_guardian_medical_history_provenance_names(
        public.slice13_view_guardian_pet_medical_history(
            p_pet_id, p_limit, p_before_history_order_at, p_before_entry_id
        )
    );
$$;
revoke all privileges
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
from public, anon, authenticated;
grant execute
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
to authenticated;

commit;
