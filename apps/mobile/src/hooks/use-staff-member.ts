import { useCallback, useEffect, useRef, useState } from 'react';

import {
  getOrganizationStaff,
  STAFF_ACCESS_DENIED,
  type OrganizationStaff,
  type StaffMember,
  type StaffResult,
} from '@/data/organization-staff';
import {
  getMyProfessionalClinics,
  type ProfessionalClinics,
  type ProfessionalClinicsResult,
} from '@/data/professional-clinics';
import {
  getMyProfessionalContext,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ProfessionalContext,
  type ProfessionalContextResult,
} from '@/data/professional-context';
import {
  getOrganizationVeterinarianWorkforce,
  type VeterinarianWorkforce,
  type WorkforceMember,
  type WorkforceResult,
} from '@/data/staff-workforce';
import type { TranslationKey } from '@/i18n/i18n';
import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';
import { workforceEntryFor } from '@/lib/staff-member-detail';
import {
  inviteClinicOptions,
  staffActionsFor,
  type InviteClinicOption,
  type StaffActions,
} from '@/lib/staff-invitation';

export type StaffMemberState =
  | { kind: 'loading' }
  /** Staff management lost for the route Organization (42501 or no advisory capability). */
  | { kind: 'unavailable' }
  /** The Membership is not in the Organization's current Staff (ended, unknown, other Organization). */
  | { kind: 'memberGone'; organizationDisplayName: string }
  | { kind: 'error'; messageKey: TranslationKey }
  | {
      kind: 'loaded';
      staff: OrganizationStaff;
      workforce: VeterinarianWorkforce;
      member: StaffMember;
      workforceMember: WorkforceMember | null;
      actions: StaffActions;
      clinics: InviteClinicOption[];
    };
export type StaffMemberRead = Exclude<StaffMemberState, { kind: 'loading' }>;

/** Combines the four parallel reads for one route Organization and Membership. */
export function staffMemberReadFrom(
  organizationId: string,
  membershipId: string,
  staff: StaffResult,
  workforce: WorkforceResult,
  context: ProfessionalContextResult<ProfessionalContext>,
  clinics: ProfessionalClinicsResult<ProfessionalClinics>,
): StaffMemberRead {
  if (staff.error === STAFF_ACCESS_DENIED || workforce.error === STAFF_ACCESS_DENIED)
    return { kind: 'unavailable' };
  if (
    [staff.error, workforce.error, context.error, clinics.error].includes(
      PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    )
  )
    return { kind: 'error', messageKey: 'errors.sessionExpired' };
  if (
    staff.error !== null ||
    workforce.error !== null ||
    context.error !== null ||
    clinics.error !== null
  )
    return { kind: 'error', messageKey: 'staffMember.loadError' };
  const actions = staffActionsFor(context.data, organizationId);
  if (!actions.manage) return { kind: 'unavailable' };
  const member = staff.data.members.find(
    (candidate) => candidate.membershipId.toLowerCase() === membershipId.toLowerCase(),
  );
  if (member === undefined)
    return { kind: 'memberGone', organizationDisplayName: staff.data.organizationDisplayName };
  return {
    kind: 'loaded',
    staff: staff.data,
    workforce: workforce.data,
    member,
    workforceMember: workforceEntryFor(workforce.data, membershipId),
    actions,
    clinics: inviteClinicOptions(clinics.data.clinics, organizationId),
  };
}

/** The Staff lifecycle discipline (lib/appointment-hours-lifecycle.ts) for one Member. */
export function useStaffMember(organizationId: string, membershipId: string) {
  const [state, setState] = useState<StaffMemberState>({ kind: 'loading' });
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  const hasLoaded = useRef(false);
  useEffect(() => {
    lifecycle.setMounted(true);
    return () => lifecycle.setMounted(false);
  }, [lifecycle]);
  const reload = useCallback(async (): Promise<StaffMemberRead | null> => {
    const token = lifecycle.beginLoad();
    const [staff, workforce, context, clinics] = await Promise.all([
      getOrganizationStaff(organizationId),
      getOrganizationVeterinarianWorkforce(organizationId),
      getMyProfessionalContext(),
      getMyProfessionalClinics(),
    ]);
    if (!lifecycle.isCurrentLoad(token)) return null;
    const read = staffMemberReadFrom(
      organizationId,
      membershipId,
      staff,
      workforce,
      context,
      clinics,
    );
    if (shouldApplyRead(read.kind === 'memberGone' ? 'loaded' : read.kind, hasLoaded.current)) {
      if (read.kind === 'loaded') hasLoaded.current = true;
      setState(read);
    }
    return read;
  }, [lifecycle, organizationId, membershipId]);
  const invalidate = useCallback(() => {
    lifecycle.beginLoad();
  }, [lifecycle]);
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);
  const isActive = useCallback(() => lifecycle.isActive(), [lifecycle]);
  return { state, reload, invalidate, leave, isActive };
}
