import { useCallback, useEffect, useRef, useState } from 'react';

import {
  getOrganizationStaff,
  STAFF_ACCESS_DENIED,
  type StaffResult,
} from '@/data/organization-staff';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import type { ProfessionalClinics, ProfessionalClinicsResult } from '@/data/professional-clinics';
import {
  getMyProfessionalContext,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ProfessionalContext,
  type ProfessionalContextResult,
} from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';
import {
  inviteClinicOptions,
  pendingInvitationIds,
  staffActionsFor,
  type InviteClinicOption,
} from '@/lib/staff-invitation';

export type StaffInviteState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** Not (or no longer) offered: Staff denied or no advisory invite capability. */
  | { kind: 'unavailable' }
  | {
      kind: 'loaded';
      organizationDisplayName: string;
      clinics: InviteClinicOption[];
      /** Pending Invitations known at this read: never mistaken for a new one. */
      pendingBefore: Set<string>;
    };
export type StaffInviteRead = Exclude<StaffInviteState, { kind: 'loading' }>;

/** Combines the three parallel reads (exported for unit testing). */
export function staffInviteReadFrom(
  organizationId: string,
  staff: StaffResult,
  context: ProfessionalContextResult<ProfessionalContext>,
  clinics: ProfessionalClinicsResult<ProfessionalClinics>,
): StaffInviteRead {
  if (staff.error === STAFF_ACCESS_DENIED) return { kind: 'unavailable' };
  const authenticationLost = [staff.error, context.error, clinics.error].includes(
    PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  );
  if (authenticationLost) return { kind: 'error', messageKey: 'errors.sessionExpired' };
  if (staff.error !== null || context.error !== null || clinics.error !== null)
    return { kind: 'error', messageKey: 'staffInvite.loadError' };
  if (!staffActionsFor(context.data, organizationId).invite) return { kind: 'unavailable' };
  return {
    kind: 'loaded',
    organizationDisplayName: staff.data.organizationDisplayName,
    clinics: inviteClinicOptions(clinics.data.clinics, organizationId),
    pendingBefore: pendingInvitationIds(staff.data),
  };
}

/** The Staff lifecycle discipline (lib/appointment-hours-lifecycle.ts) for the invite form. */
export function useStaffInvite(organizationId: string) {
  const [state, setState] = useState<StaffInviteState>({ kind: 'loading' });
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  const hasLoaded = useRef(false);
  useEffect(() => {
    lifecycle.setMounted(true);
    return () => lifecycle.setMounted(false);
  }, [lifecycle]);
  const reload = useCallback(async (): Promise<StaffInviteRead | null> => {
    const token = lifecycle.beginLoad();
    const [staff, context, clinics] = await Promise.all([
      getOrganizationStaff(organizationId),
      getMyProfessionalContext(),
      getMyProfessionalClinics(),
    ]);
    if (!lifecycle.isCurrentLoad(token)) return null;
    const read = staffInviteReadFrom(organizationId, staff, context, clinics);
    if (shouldApplyRead(read.kind, hasLoaded.current)) {
      if (read.kind === 'loaded') hasLoaded.current = true;
      setState(read);
    }
    return read;
  }, [lifecycle, organizationId]);
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);
  const isActive = useCallback(() => lifecycle.isActive(), [lifecycle]);
  return { state, reload, leave, isActive };
}
