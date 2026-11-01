import { useCallback, useEffect, useRef, useState } from 'react';

import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  getManagedClinicProfile,
  type ClinicSettingsResult,
  type ManagedClinicProfile,
} from '@/data/clinic-settings';
import {
  getMyProfessionalClinics,
  type ProfessionalClinic,
  type ProfessionalClinics,
  type ProfessionalClinicsResult,
} from '@/data/professional-clinics';
import { mapClinicSettingsLoadErrorToKey } from '@/i18n/clinic-settings-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { mapProfessionalClinicsErrorToKey } from '@/i18n/professional-context-error-messages';
import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';
import { findProfessionalClinic } from '@/lib/clinic-schedule-display';
import { offersClinicSettingsEditor, type ClinicSettingsEditor } from '@/lib/clinic-settings';

export type ClinicSettingsEditorState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** Not (or no longer) an editor this User may use for this Clinic. */
  | { kind: 'unavailable' }
  | { kind: 'loaded'; clinic: ProfessionalClinic; profile: ManagedClinicProfile };

/** A fresh read's outcome, before deciding whether it replaces the screen. */
export type ClinicSettingsEditorRead = Exclude<ClinicSettingsEditorState, { kind: 'loading' }>;

/**
 * Combines the two parallel reads (exported for unit testing). The editor is
 * offered only while the Professional Clinic list still holds the editor's
 * own capability (advisory) AND the managed Clinic read itself succeeds — the
 * backend authorized it on that call. A denied read means `unavailable`, the
 * same for an unknown Clinic as for an inaccessible one.
 */
export function clinicSettingsEditorReadFrom(
  clinicId: string,
  editor: ClinicSettingsEditor,
  clinicsResult: ProfessionalClinicsResult<ProfessionalClinics>,
  profileResult: ClinicSettingsResult<ManagedClinicProfile>,
): ClinicSettingsEditorRead {
  if (clinicsResult.error !== null) {
    return { kind: 'error', messageKey: mapProfessionalClinicsErrorToKey(clinicsResult.error) };
  }
  const clinic = findProfessionalClinic(clinicsResult.data, clinicId);
  if (clinic === null || !offersClinicSettingsEditor(clinic, editor))
    return { kind: 'unavailable' };
  if (profileResult.error === CLINIC_SETTINGS_ACCESS_DENIED) return { kind: 'unavailable' };
  if (profileResult.error !== null) {
    return { kind: 'error', messageKey: mapClinicSettingsLoadErrorToKey(profileResult.error) };
  }
  return { kind: 'loaded', clinic, profile: profileResult.data };
}

/**
 * Loads one Clinic settings editor's state, always fresh and never from
 * navigation, with the Appointment hours lifecycle discipline
 * (lib/appointment-hours-lifecycle.ts): latest read wins; only the first load
 * may replace the screen with an error; `leave` navigates once and then no
 * read, initialization, reconciliation, or `finally` updates the screen; after
 * leaving (or unmount) `reload` resolves to `null` and `isActive()` is false.
 * A later `unavailable` read replaces an editable form, so a User who lost
 * access is never left editing a stale one.
 */
export function useClinicSettingsEditor(clinicId: string, editor: ClinicSettingsEditor) {
  const [state, setState] = useState<ClinicSettingsEditorState>({ kind: 'loading' });
  // One lifecycle per screen instance, created once and never replaced.
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  const hasLoadedRef = useRef(false);

  useEffect(() => {
    lifecycle.setMounted(true);
    return () => {
      lifecycle.setMounted(false);
    };
  }, [lifecycle]);

  const reload = useCallback(async (): Promise<ClinicSettingsEditorRead | null> => {
    const token = lifecycle.beginLoad();
    const [clinicsResult, profileResult] = await Promise.all([
      getMyProfessionalClinics(),
      getManagedClinicProfile(clinicId),
    ]);
    if (!lifecycle.isCurrentLoad(token)) return null;

    const read = clinicSettingsEditorReadFrom(clinicId, editor, clinicsResult, profileResult);
    if (shouldApplyRead(read.kind, hasLoadedRef.current)) {
      if (read.kind === 'loaded') hasLoadedRef.current = true;
      setState(read);
    }
    return read;
  }, [clinicId, editor, lifecycle]);

  /** The single owner of navigating away: runs `navigate` once, then the screen is inert. */
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);

  /** Whether an async continuation may still update the screen. */
  const isActive = useCallback(() => lifecycle.isActive(), [lifecycle]);

  return { state, reload, leave, isActive };
}
