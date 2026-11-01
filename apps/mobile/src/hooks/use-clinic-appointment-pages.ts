import { useCallback } from 'react';

import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import {
  getClinicAppointmentHistory,
  getClinicAppointmentPending,
  historyCursorOf,
  pendingCursorOf,
  type ClinicPendingAppointment,
  type HistoryCursor,
  type PendingCursor,
  type PendingTotals,
} from '@/data/clinic-calendar';
import { usePagedList, type PageResult } from '@/hooks/use-paged-list';
import { mapClinicScheduleErrorToKey } from '@/i18n/professional-context-error-messages';

export type { PagedListState } from '@/hooks/use-paged-list';

/** Pending page size: within BR-57's 1–100, its default; every page classifies the whole set anyway. */
export const PENDING_PAGE_SIZE = 50;

/** History page size: BR-59's default (1–50). */
export const HISTORY_PAGE_SIZE = 30;

function pendingId(row: ClinicPendingAppointment): string {
  return row.appointment.id;
}

function appointmentId(appointment: ClinicScheduleAppointment): string {
  return appointment.id;
}

function isScheduleAccessDenied(error: string): boolean {
  return error === CLINIC_SCHEDULE_ACCESS_DENIED;
}

/**
 * The agenda's Pending tab (SPEC-APT-012 BR-57): keyset pages (see
 * `usePagedList`) with the whole classification's totals; a 42501 replaces
 * the whole agenda.
 */
export function useClinicPendingAppointments(
  clinicId: string,
  active: boolean,
  onAccessLost: () => void,
) {
  const readPage = useCallback(
    async (
      cursor: PendingCursor | null,
    ): Promise<PageResult<ClinicPendingAppointment, PendingTotals>> => {
      const result = await getClinicAppointmentPending(clinicId, cursor, PENDING_PAGE_SIZE);
      return result.error !== null
        ? result
        : { data: { rows: result.data.rows, meta: result.data.totals }, error: null };
    },
    [clinicId],
  );
  return usePagedList({
    active,
    pageSize: PENDING_PAGE_SIZE,
    readPage,
    idOf: pendingId,
    cursorOf: pendingCursorOf,
    isAccessDenied: isScheduleAccessDenied,
    errorKeyOf: mapClinicScheduleErrorToKey,
    onAccessLost,
  });
}

/** The agenda's History tab (SPEC-APT-012 BR-59): terminal Appointments, newest first. */
export function useClinicAppointmentHistory(
  clinicId: string,
  active: boolean,
  onAccessLost: () => void,
) {
  const readPage = useCallback(
    async (cursor: HistoryCursor | null): Promise<PageResult<ClinicScheduleAppointment, never>> => {
      const result = await getClinicAppointmentHistory(clinicId, cursor, HISTORY_PAGE_SIZE);
      return result.error !== null
        ? result
        : { data: { rows: result.data, meta: null }, error: null };
    },
    [clinicId],
  );
  return usePagedList({
    active,
    pageSize: HISTORY_PAGE_SIZE,
    readPage,
    idOf: appointmentId,
    cursorOf: historyCursorOf,
    isAccessDenied: isScheduleAccessDenied,
    errorKeyOf: mapClinicScheduleErrorToKey,
    onAccessLost,
  });
}
