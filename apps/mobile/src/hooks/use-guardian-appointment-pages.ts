import { getPublishedClinicProfilesByIds } from '@/data/clinics';
import {
  activeCursorOf,
  getGuardianActiveAppointments,
  getGuardianAppointmentHistory,
  historyCursorOf,
  type ActiveCursor,
  type GuardianActiveAppointment,
  type GuardianAppointment,
  type HistoryCursor,
} from '@/data/guardian-appointments';
import { usePagedList, type PageResult } from '@/hooks/use-paged-list';
import { mapGuardianAppointmentsErrorToKey } from '@/i18n/guardian-appointments-error-messages';
import { withClinicNames, type GuardianAppointmentListItem } from '@/lib/guardian-appointments';

/** Rows per page in both tabs (SPEC-APT-011 BR-40). */
export const GUARDIAN_APPOINTMENTS_PAGE_SIZE = 20;

function appointmentId(row: GuardianAppointment): string {
  return row.id;
}

// The Guardian reads have no denial (BR-36): no Guardianship is an empty page.
function neverAccessDenied(): boolean {
  return false;
}

function ignoreAccessLost(): void {}

/** One page with its Clinics' published names: one lookup per page, never per row. */
async function withNames<T extends GuardianAppointment>(
  result: { data: T[]; error: null } | { data: null; error: string },
): Promise<PageResult<GuardianAppointmentListItem<T>, never>> {
  if (result.error !== null) return result;
  const profiles = await getPublishedClinicProfilesByIds(result.data.map((row) => row.clinicId));
  return { data: { rows: withClinicNames(result.data, profiles.data), meta: null }, error: null };
}

// Module functions, so `readPage` is stable: usePagedList restarts a read only when it changes.
async function readActivePage(cursor: ActiveCursor | null) {
  return withNames(await getGuardianActiveAppointments(cursor, GUARDIAN_APPOINTMENTS_PAGE_SIZE));
}

async function readHistoryPage(cursor: HistoryCursor | null) {
  return withNames(await getGuardianAppointmentHistory(cursor, GUARDIAN_APPOINTMENTS_PAGE_SIZE));
}

/**
 * The Active tab of "My appointments" (SPEC-APT-011 BR-38, BR-40): keyset
 * pages (see `usePagedList`), read only once the tab is shown and restarted
 * on focus while it is on screen.
 */
export function useGuardianActiveAppointments(active: boolean) {
  return usePagedList<GuardianAppointmentListItem<GuardianActiveAppointment>, ActiveCursor, never>({
    active,
    pageSize: GUARDIAN_APPOINTMENTS_PAGE_SIZE,
    readPage: readActivePage,
    idOf: appointmentId,
    cursorOf: activeCursorOf,
    isAccessDenied: neverAccessDenied,
    errorKeyOf: mapGuardianAppointmentsErrorToKey,
    onAccessLost: ignoreAccessLost,
  });
}

/** The History tab of "My appointments" (SPEC-APT-011 BR-39, BR-40): terminal Appointments, newest first. */
export function useGuardianAppointmentHistory(active: boolean) {
  return usePagedList<GuardianAppointmentListItem, HistoryCursor, never>({
    active,
    pageSize: GUARDIAN_APPOINTMENTS_PAGE_SIZE,
    readPage: readHistoryPage,
    idOf: appointmentId,
    cursorOf: historyCursorOf,
    isAccessDenied: neverAccessDenied,
    errorKeyOf: mapGuardianAppointmentsErrorToKey,
    onAccessLost: ignoreAccessLost,
  });
}
