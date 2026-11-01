import { useCallback, useEffect, useRef, useState } from 'react';

import {
  APPOINTMENT_HOURS_ACCESS_DENIED,
  getClinicAppointmentHours,
  type AppointmentHoursResult,
  type ClinicAppointmentHours,
} from '@/data/clinic-appointment-hours';
import {
  getMyProfessionalClinics,
  type ProfessionalClinic,
  type ProfessionalClinics,
  type ProfessionalClinicsResult,
} from '@/data/professional-clinics';
import {
  getMyProfessionalContext,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ProfessionalContext,
  type ProfessionalContextResult,
} from '@/data/professional-context';
import { mapAppointmentHoursLoadErrorToKey } from '@/i18n/appointment-hours-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { mapProfessionalClinicsErrorToKey } from '@/i18n/professional-context-error-messages';
import { findProfessionalClinic } from '@/lib/clinic-schedule-display';
import {
  appointmentHoursAccess,
  offersAppointmentHours,
  type AppointmentHoursAccess,
} from '@/lib/appointment-hours';
import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';

export type AppointmentHoursState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** Not (or no longer) an Appointment-hours Clinic for this User. */
  | { kind: 'unavailable' }
  | {
      kind: 'loaded';
      clinic: ProfessionalClinic;
      access: AppointmentHoursAccess;
      config: ClinicAppointmentHours;
    };

/** A fresh read's outcome, before deciding whether it replaces the screen. */
export type AppointmentHoursRead = Exclude<AppointmentHoursState, { kind: 'loading' }>;

/**
 * Combines the three parallel reads (exported for unit testing). The
 * configuration is shown only when the management read itself succeeded —
 * the backend authorized it for this User and Clinic on that call. The
 * professional context only decides editability, so its failure degrades to
 * `unconfirmed` (shown, not editable) instead of hiding authorized
 * configuration; an expired session still stops the screen.
 */
export function appointmentHoursReadFrom(
  clinicId: string,
  clinicsResult: ProfessionalClinicsResult<ProfessionalClinics>,
  contextResult: ProfessionalContextResult<ProfessionalContext>,
  hoursResult: AppointmentHoursResult<ClinicAppointmentHours>,
): AppointmentHoursRead {
  if (clinicsResult.error !== null) {
    return { kind: 'error', messageKey: mapProfessionalClinicsErrorToKey(clinicsResult.error) };
  }
  const clinic = findProfessionalClinic(clinicsResult.data, clinicId);
  if (clinic === null || !offersAppointmentHours(clinic)) return { kind: 'unavailable' };
  if (hoursResult.error === APPOINTMENT_HOURS_ACCESS_DENIED) return { kind: 'unavailable' };
  if (hoursResult.error !== null) {
    return { kind: 'error', messageKey: mapAppointmentHoursLoadErrorToKey(hoursResult.error) };
  }
  if (contextResult.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) {
    return {
      kind: 'error',
      messageKey: mapAppointmentHoursLoadErrorToKey(PROFESSIONAL_CONTEXT_AUTH_REQUIRED),
    };
  }
  return {
    kind: 'loaded',
    clinic,
    access: appointmentHoursAccess(
      contextResult.error === null ? contextResult.data : null,
      clinic.organizationId,
    ),
    config: hoursResult.data,
  };
}

/**
 * Loads everything the Appointment hours screens show for one Clinic, always
 * fresh and never from navigation: the Professional Clinic (the advisory
 * APPOINTMENT_MANAGE_AVAILABILITY capability decides whether the surface is
 * offered), the professional context (the Organization's
 * PROFESSIONAL_SCHEDULING decides editable vs read-only; unreadable, it only
 * withholds editing), and the Clinic's management read (SPEC-APT-013 BR-74).
 * The three reads run in parallel.
 *
 * Shared by the main screen (re-read on every focus) and the three editors
 * (read on mount, re-read after a failed save to reconcile with the
 * authoritative state). Latest read wins. Only the first load may replace the
 * screen with an error: a failed refresh keeps what is shown, but `reload`
 * still resolves to that outcome so a caller can decide.
 *
 * The hook also owns the screen's terminal leaving (lib/appointment-hours-lifecycle.ts):
 * every in-app navigation away goes through `leave`, which navigates once
 * and invalidates any read in flight. From then on — or after unmount —
 * `reload` resolves to `null` without touching state, and `isActive()` is
 * false, so callers skip every later state update (initialization,
 * reconciliation, `finally`).
 */
export function useAppointmentHours(clinicId: string) {
  const [state, setState] = useState<AppointmentHoursState>({ kind: 'loading' });
  // One lifecycle per screen instance, created once and never replaced.
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  const hasLoadedRef = useRef(false);

  useEffect(() => {
    lifecycle.setMounted(true);
    return () => {
      lifecycle.setMounted(false);
    };
  }, [lifecycle]);

  const reload = useCallback(async (): Promise<AppointmentHoursRead | null> => {
    const token = lifecycle.beginLoad();
    const [clinicsResult, contextResult, hoursResult] = await Promise.all([
      getMyProfessionalClinics(),
      getMyProfessionalContext(),
      getClinicAppointmentHours(clinicId),
    ]);
    if (!lifecycle.isCurrentLoad(token)) return null;

    const read = appointmentHoursReadFrom(clinicId, clinicsResult, contextResult, hoursResult);
    if (shouldApplyRead(read.kind, hasLoadedRef.current)) {
      if (read.kind === 'loaded') hasLoadedRef.current = true;
      setState(read);
    }
    return read;
  }, [clinicId, lifecycle]);

  /** The single owner of navigating away: runs `navigate` once, then the screen is inert. */
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);

  /** Whether an async continuation may still update the screen. */
  const isActive = useCallback(() => lifecycle.isActive(), [lifecycle]);

  return { state, reload, leave, isActive };
}
