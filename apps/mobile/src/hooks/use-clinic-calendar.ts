import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  type ClinicScheduleAppointment,
  type ClinicScheduleResult,
} from '@/data/clinic-appointment-schedule';
import {
  getClinicAppointmentDay,
  getClinicAppointmentMonthCounts,
  getClinicCalendarContext,
  type ClinicCalendarContext,
  type ClinicMonthCounts,
} from '@/data/clinic-calendar';
import { getMyProfessionalClinics, type ProfessionalClinic } from '@/data/professional-clinics';
import type { TranslationKey } from '@/i18n/i18n';
import {
  mapClinicScheduleErrorToKey,
  mapProfessionalClinicsErrorToKey,
} from '@/i18n/professional-context-error-messages';
import {
  calendarFocusAfterContext,
  isSupportedMonth,
  monthKey,
  monthOfDate,
  type CalendarMonth,
} from '@/lib/clinic-calendar';
import { resolveClinicScheduleAvailability } from '@/lib/clinic-schedule-display';

/** What the whole screen shows. Only `ready` shows the calendar. */
export type ClinicCalendarScreenState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'clinicUnavailable' }
  | { kind: 'scheduleUnavailable'; clinic: ProfessionalClinic }
  | { kind: 'accessLost'; clinic: ProfessionalClinic }
  | { kind: 'ready'; clinic: ProfessionalClinic; context: ClinicCalendarContext };

/**
 * One cached read (a month's counts or a day's Appointments). The last good
 * `data` survives a reload or a failed refresh, so an error never erases data
 * already shown; `data === null` means never loaded. `fresh` data is not read
 * again until the screen regains focus.
 */
export type CachedRead<T> = {
  data: T | null;
  status: 'loading' | 'idle' | 'error';
  errorKey: TranslationKey | null;
  fresh: boolean;
};

type Cache<T> = Record<string, CachedRead<T>>;

const EMPTY_ENTRY = { data: null, status: 'idle', errorKey: null, fresh: false } as const;

function staled<T>(cache: Cache<T>): Cache<T> {
  return Object.fromEntries(
    Object.entries(cache).map(([key, entry]) => [key, { ...entry, fresh: false }]),
  );
}

/**
 * State and reads of the professional appointment calendar (SPEC-APT-012
 * §14). On every focus — and when the app returns to the foreground while the
 * calendar is focused — it re-reads the Professional Clinic list and the
 * calendar context (BR-60) in parallel, then the visible month's counts
 * (BR-54) and the selected day (BR-56), once each. In between, a month or day
 * already read in this focus is not read again; months the actor never opens
 * are never read. Every read is sequenced per key, so a late answer for an
 * older request is ignored. Losing schedule access replaces the calendar; any
 * other failure keeps what is shown.
 *
 * The calendar is one tab of the agenda. While another tab is shown
 * (`active` false) a focus or a return to the foreground reads nothing: it
 * only marks the calendar stale, and the focus refresh above runs when the
 * calendar is shown again. Whatever the tab, the calendar stays active while
 * the screen is not `ready`, since its reads are what decide (and re-check)
 * whether the agenda may be shown at all. `loseAccess` lets the other tabs
 * report a 42501.
 */
export function useClinicCalendar(clinicId: string, active = true) {
  const [screen, setScreen] = useState<ClinicCalendarScreenState>({ kind: 'loading' });
  const [visibleMonth, setVisibleMonth] = useState<CalendarMonth | null>(null);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [months, setMonths] = useState<Cache<ClinicMonthCounts>>({});
  const [days, setDays] = useState<Cache<ClinicScheduleAppointment[]>>({});

  const isMountedRef = useRef(true);
  const loadSeqRef = useRef(0);
  const requestSeqRef = useRef<Record<string, number>>({});
  // Mirrors of state read by callbacks, so they never act on a stale closure.
  const clinicRef = useRef<ProfessionalClinic | null>(null);
  const contextRef = useRef<ClinicCalendarContext | null>(null);
  const focusRef = useRef<{ visibleMonth: CalendarMonth; selectedDate: string | null } | null>(
    null,
  );
  const monthsRef = useRef<Cache<ClinicMonthCounts>>({});
  const daysRef = useRef<Cache<ClinicScheduleAppointment[]>>({});
  const activeRef = useRef(active);
  const staleRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const updateMonths = useCallback(
    (update: (cache: Cache<ClinicMonthCounts>) => Cache<ClinicMonthCounts>) => {
      monthsRef.current = update(monthsRef.current);
      setMonths(monthsRef.current);
    },
    [],
  );
  const updateDays = useCallback(
    (update: (cache: Cache<ClinicScheduleAppointment[]>) => Cache<ClinicScheduleAppointment[]>) => {
      daysRef.current = update(daysRef.current);
      setDays(daysRef.current);
    },
    [],
  );

  const loseAccess = useCallback(() => {
    if (clinicRef.current !== null) setScreen({ kind: 'accessLost', clinic: clinicRef.current });
  }, []);

  /** One sequenced, cached read; `force` ignores freshness (focus refresh, retry). */
  const runCachedRead = useCallback(
    async <T>(
      kind: 'month' | 'day',
      key: string,
      cacheRef: { current: Cache<T> },
      update: (change: (cache: Cache<T>) => Cache<T>) => void,
      request: () => Promise<ClinicScheduleResult<T>>,
      force: boolean,
    ) => {
      const current = cacheRef.current[key];
      if (!force && current !== undefined && (current.fresh || current.status === 'loading')) {
        return;
      }
      const seqKey = `${kind}:${key}`;
      const seq = (requestSeqRef.current[seqKey] ?? 0) + 1;
      requestSeqRef.current[seqKey] = seq;
      update((cache) => ({
        ...cache,
        [key]: { ...(cache[key] ?? EMPTY_ENTRY), status: 'loading', errorKey: null },
      }));

      const result = await request();
      if (!isMountedRef.current || requestSeqRef.current[seqKey] !== seq) return;
      if (result.error === CLINIC_SCHEDULE_ACCESS_DENIED) {
        loseAccess();
        return;
      }
      update((cache) => {
        const previous = cache[key] ?? EMPTY_ENTRY;
        return {
          ...cache,
          [key]:
            result.error === null
              ? { data: result.data, status: 'idle', errorKey: null, fresh: true }
              : {
                  ...previous,
                  status: 'error',
                  errorKey: mapClinicScheduleErrorToKey(result.error),
                  fresh: false,
                },
        };
      });
    },
    [loseAccess],
  );

  const requestMonth = useCallback(
    (month: CalendarMonth, force = false) => {
      if (!isSupportedMonth(month)) return;
      runCachedRead(
        'month',
        monthKey(month),
        monthsRef,
        updateMonths,
        () => getClinicAppointmentMonthCounts(clinicId, month.year, month.month),
        force,
      );
    },
    [clinicId, runCachedRead, updateMonths],
  );

  const requestDay = useCallback(
    (date: string, force = false) => {
      runCachedRead(
        'day',
        date,
        daysRef,
        updateDays,
        () => getClinicAppointmentDay(clinicId, date),
        force,
      );
    },
    [clinicId, runCachedRead, updateDays],
  );

  const setFocus = useCallback(
    (next: { visibleMonth: CalendarMonth; selectedDate: string | null }) => {
      focusRef.current = next;
      setVisibleMonth(next.visibleMonth);
      setSelectedDate(next.selectedDate);
    },
    [],
  );

  const load = useCallback(async () => {
    const seq = ++loadSeqRef.current;
    const isCurrent = () => isMountedRef.current && seq === loadSeqRef.current;
    const isFirstLoad = contextRef.current === null;

    const [clinicsResult, contextResult] = await Promise.all([
      getMyProfessionalClinics(),
      getClinicCalendarContext(clinicId),
    ]);
    if (!isCurrent()) return;

    if (clinicsResult.error !== null) {
      if (isFirstLoad) {
        setScreen({
          kind: 'error',
          messageKey: mapProfessionalClinicsErrorToKey(clinicsResult.error),
        });
      }
      return;
    }
    const availability = resolveClinicScheduleAvailability(clinicsResult.data, clinicId);
    if (availability.kind === 'clinicUnavailable') {
      clinicRef.current = null;
      setScreen({ kind: 'clinicUnavailable' });
      return;
    }
    if (availability.kind === 'scheduleUnavailable') {
      clinicRef.current = null;
      setScreen({ kind: 'scheduleUnavailable', clinic: availability.clinic });
      return;
    }
    const { clinic } = availability;
    clinicRef.current = clinic;

    if (contextResult.error === CLINIC_SCHEDULE_ACCESS_DENIED) {
      setScreen({ kind: 'accessLost', clinic });
      return;
    }
    if (contextResult.error !== null) {
      if (isFirstLoad) {
        setScreen({ kind: 'error', messageKey: mapClinicScheduleErrorToKey(contextResult.error) });
      }
      return;
    }

    const context = contextResult.data;
    const previous =
      focusRef.current === null || contextRef.current === null
        ? null
        : { ...focusRef.current, today: contextRef.current.clinicLocalToday };
    const focus = calendarFocusAfterContext(previous, context.clinicLocalToday);
    contextRef.current = context;
    setFocus(focus);
    setScreen({ kind: 'ready', clinic, context });

    // Everything read before this focus may be outdated (e.g. a mutation in
    // the Appointment detail): re-read what is visible now, the rest lazily.
    updateMonths(staled);
    updateDays(staled);
    requestMonth(focus.visibleMonth, true);
    if (focus.selectedDate !== null) requestDay(focus.selectedDate, true);
  }, [clinicId, requestDay, requestMonth, setFocus, updateDays, updateMonths]);

  // Shown: refresh now. Behind another tab: refresh when shown again.
  const loadIfActive = useCallback(() => {
    if (activeRef.current) load();
    else staleRef.current = true;
  }, [load]);

  useFocusEffect(
    useCallback(() => {
      loadIfActive();
      // Back from the background after a while: "today" may have changed.
      const subscription = AppState.addEventListener('change', (state) => {
        if (state === 'active') loadIfActive();
      });
      return () => subscription.remove();
    }, [loadIfActive]),
  );

  const shown = active || screen.kind !== 'ready';
  useEffect(() => {
    activeRef.current = shown;
    if (shown && staleRef.current) {
      staleRef.current = false;
      load();
    }
  }, [shown, load]);

  const retryScreen = useCallback(() => {
    setScreen({ kind: 'loading' });
    contextRef.current = null;
    focusRef.current = null;
    load();
  }, [load]);

  const showMonth = useCallback(
    (month: CalendarMonth) => {
      if (!isSupportedMonth(month)) return;
      // A new month shows its counts only; no day is read until one is chosen.
      setFocus({ visibleMonth: month, selectedDate: null });
      requestMonth(month);
    },
    [requestMonth, setFocus],
  );

  const selectDate = useCallback(
    (date: string) => {
      const current = focusRef.current;
      if (current === null) return;
      setFocus({ visibleMonth: current.visibleMonth, selectedDate: date });
      requestDay(date);
    },
    [requestDay, setFocus],
  );

  const showToday = useCallback(() => {
    const today = contextRef.current?.clinicLocalToday ?? null;
    if (today === null) return;
    const month = monthOfDate(today);
    setFocus({ visibleMonth: month, selectedDate: today });
    requestMonth(month);
    requestDay(today);
  }, [requestDay, requestMonth, setFocus]);

  const retryMonth = useCallback(() => {
    if (focusRef.current !== null) requestMonth(focusRef.current.visibleMonth, true);
  }, [requestMonth]);

  const retryDay = useCallback(() => {
    const date = focusRef.current?.selectedDate ?? null;
    if (date !== null) requestDay(date, true);
  }, [requestDay]);

  return {
    screen,
    visibleMonth,
    selectedDate,
    monthCounts: visibleMonth === null ? null : (months[monthKey(visibleMonth)] ?? null),
    dayAppointments: selectedDate === null ? null : (days[selectedDate] ?? null),
    showMonth,
    selectDate,
    showToday,
    retryScreen,
    retryMonth,
    retryDay,
    loseAccess,
  };
}
