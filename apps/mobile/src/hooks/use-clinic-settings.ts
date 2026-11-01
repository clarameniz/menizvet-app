import { useCallback, useEffect, useRef, useState } from 'react';

import {
  getClinicAppointmentHours,
  type AppointmentHoursResult,
  type ClinicAppointmentHours,
} from '@/data/clinic-appointment-hours';
import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  getManagedClinicProfile,
  type ClinicSettingsResult,
  type ManagedClinicProfile,
} from '@/data/clinic-settings';
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
import { mapClinicSettingsLoadErrorToKey } from '@/i18n/clinic-settings-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { mapProfessionalClinicsErrorToKey } from '@/i18n/professional-context-error-messages';
import { appointmentHoursAccess } from '@/lib/appointment-hours';
import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';
import { findProfessionalClinic } from '@/lib/clinic-schedule-display';
import { offersOrganizationSubscription } from '@/lib/organization-subscription';
import { offersClinicSettings, type ClinicSettingsInput } from '@/lib/clinic-settings';

export type ClinicSettingsState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** Not (or no longer) a Clinic whose settings this User may see. */
  | { kind: 'unavailable' }
  | ({ kind: 'loaded' } & ClinicSettingsInput);

/** A fresh read's outcome, before deciding whether it replaces the screen. */
export type ClinicSettingsRead = Exclude<ClinicSettingsState, { kind: 'loading' }>;

/**
 * Combines the four parallel reads (exported for unit testing), treating them
 * differently (SPEC-CLI-007 BR-10, BR-11):
 *
 * - the Professional Clinic list decides whether Clinic settings is offered;
 * - the managed Clinic read is the core: if it fails, nothing is shown and
 *   no partial profile is invented (load error, or `unavailable` when denied);
 * - the Appointment hours read is secondary: if it fails, only the scheduling
 *   rows become unknown;
 * - the professional context only supplies APPOINTMENT_MANAGEMENT and the
 *   Appointment hours editability: unreadable, they become unknown /
 *   `unconfirmed`.
 *
 * An expired session in any read stops the screen.
 */
export function clinicSettingsReadFrom(
  clinicId: string,
  clinicsResult: ProfessionalClinicsResult<ProfessionalClinics>,
  contextResult: ProfessionalContextResult<ProfessionalContext>,
  profileResult: ClinicSettingsResult<ManagedClinicProfile>,
  hoursResult: AppointmentHoursResult<ClinicAppointmentHours>,
): ClinicSettingsRead {
  if (clinicsResult.error !== null) {
    return { kind: 'error', messageKey: mapProfessionalClinicsErrorToKey(clinicsResult.error) };
  }
  const clinic = findProfessionalClinic(clinicsResult.data, clinicId);
  if (clinic === null || !offersClinicSettings(clinic)) return { kind: 'unavailable' };
  if (profileResult.error === CLINIC_SETTINGS_ACCESS_DENIED) return { kind: 'unavailable' };
  if (profileResult.error !== null) {
    return { kind: 'error', messageKey: mapClinicSettingsLoadErrorToKey(profileResult.error) };
  }
  if (
    contextResult.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED ||
    hoursResult.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED
  ) {
    return {
      kind: 'error',
      messageKey: mapClinicSettingsLoadErrorToKey(PROFESSIONAL_CONTEXT_AUTH_REQUIRED),
    };
  }

  const context = contextResult.error === null ? contextResult.data : null;
  const organization =
    context?.organizations.find((entry) => entry.organizationId === clinic.organizationId) ?? null;

  return {
    kind: 'loaded',
    clinic,
    profile: profileResult.data,
    scheduling:
      hoursResult.error === null ? { kind: 'known', hours: hoursResult.data } : { kind: 'unknown' },
    appointmentManagement: organization?.entitlements.APPOINTMENT_MANAGEMENT ?? null,
    appointmentHoursAccess: appointmentHoursAccess(context, clinic.organizationId),
    subscriptionStatusAccess: organization !== null && offersOrganizationSubscription(organization),
  };
}

/**
 * Loads everything the Clinic settings overview shows, always fresh and never
 * from navigation. The four reads run in parallel; latest read wins. Only the
 * first load may replace the screen with an error: a failed refresh keeps
 * what is shown. Leaving is terminal and owned by `leave`, exactly as in
 * `useAppointmentHours` (lib/appointment-hours-lifecycle.ts), so no read in
 * flight updates a screen being popped.
 */
export function useClinicSettings(clinicId: string) {
  const [state, setState] = useState<ClinicSettingsState>({ kind: 'loading' });
  // One lifecycle per screen instance, created once and never replaced.
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  const hasLoadedRef = useRef(false);

  useEffect(() => {
    lifecycle.setMounted(true);
    return () => {
      lifecycle.setMounted(false);
    };
  }, [lifecycle]);

  const reload = useCallback(async (): Promise<ClinicSettingsRead | null> => {
    const token = lifecycle.beginLoad();
    const [clinicsResult, contextResult, profileResult, hoursResult] = await Promise.all([
      getMyProfessionalClinics(),
      getMyProfessionalContext(),
      getManagedClinicProfile(clinicId),
      getClinicAppointmentHours(clinicId),
    ]);
    if (!lifecycle.isCurrentLoad(token)) return null;

    const read = clinicSettingsReadFrom(
      clinicId,
      clinicsResult,
      contextResult,
      profileResult,
      hoursResult,
    );
    if (shouldApplyRead(read.kind, hasLoadedRef.current)) {
      if (read.kind === 'loaded') hasLoadedRef.current = true;
      setState(read);
    }
    return read;
  }, [clinicId, lifecycle]);

  /** The single owner of navigating away: runs `navigate` once, then the screen is inert. */
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);

  /** Whether an async continuation (a Publish/Unpublish reconciliation) may still update the screen. */
  const isActive = useCallback(() => lifecycle.isActive(), [lifecycle]);

  return { state, reload, leave, isActive };
}
