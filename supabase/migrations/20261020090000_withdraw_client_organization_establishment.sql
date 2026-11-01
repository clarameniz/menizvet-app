-- Withdraw client-role Organization establishment (ADR-009, SPEC-ORG-001 BR-10).
--
-- `create_veterinary_organization(text)` was granted to `authenticated` by
-- 20260825112945_organization_foundation.sql, when SPEC-ORG-001 still allowed
-- self-service Organization creation. ADR-009 replaced that rule: a Veterinary
-- Organization is established only through trusted Commercial Onboarding, and
-- authentication or email verification never suffice (SPEC-ORG-001 BR-10).
-- With the grant in place, any verified User could establish an Organization,
-- become its OWNER, and create and publish Clinics with no Subscription
-- (contradicting BR-12 as well).
--
-- This migration only withdraws the client-role grant. It is not the atomic,
-- idempotent Commercial Onboarding operation ADR-009 describes (Organization +
-- OWNER + initial Subscription in one operation); that remains future work.
-- Until it exists, the trusted path is the operator database session that
-- impersonates the designated initial Owner and then establishes the initial
-- Subscription with `establish_organization_subscription`, as
-- supabase/provisioning/production_validation_data.sql does.
--
-- Unchanged: the function body, signature, SECURITY DEFINER, empty
-- search_path, and every existing Organization, Membership, and
-- responsibility row.

revoke all privileges
on function public.create_veterinary_organization(text)
from public, anon, authenticated;

-- Trusted service context only. The function still derives the initial Owner
-- from auth.uid(), so a trusted caller must establish the designated Owner's
-- subject first; a service_role request without a subject is rejected (28000).
grant execute
on function public.create_veterinary_organization(text)
to service_role;
