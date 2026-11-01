import {
  addCivilDays,
  civilDateString,
  civilDateTimeInTimeZone,
  clinicLocalToday,
  formatCandidateDateLabel,
  formatCandidateDateParts,
  formatCandidateWindowDate,
  formatInstantInTimeZone,
  formatScheduledInterval,
  initialRequestableCandidateWindow,
  nextRequestableCandidateWindow,
  previousRequestableCandidateWindow,
  REQUESTABLE_DATE_RANGE_DAYS,
  REQUESTABLE_HORIZON_DAYS,
  requestableCandidateWindow,
  shiftLocalDate,
} from '@/lib/appointment-time';

describe('civilDateString', () => {
  it('formats the calendar-date portion as YYYY-MM-DD', () => {
    expect(civilDateString({ year: 2026, month: 2, day: 5 })).toBe('2026-02-05');
  });

  it('pads single-digit month and day', () => {
    expect(civilDateString({ year: 2026, month: 1, day: 9 })).toBe('2026-01-09');
  });
});

describe('civilDateTimeInTimeZone', () => {
  it('reads the civil digits of a stored instant in the given Clinic timezone', () => {
    expect(civilDateTimeInTimeZone('2026-06-15T08:00:00Z', 'Europe/Madrid')).toEqual({
      year: 2026,
      month: 6,
      day: 15,
      hour: 10,
      minute: 0,
    });
  });
});

describe('formatInstantInTimeZone', () => {
  it('formats using the given Clinic timezone, not the test runner timezone', () => {
    expect(formatInstantInTimeZone('2026-06-15T08:00:00Z', 'Europe/Madrid')).toBe(
      '15/06/2026 10:00',
    );
    expect(formatInstantInTimeZone('2026-06-15T08:00:00Z', 'America/New_York')).toBe(
      '15/06/2026 04:00',
    );
  });
});

describe('formatScheduledInterval', () => {
  it('formats date and time range in the Clinic timezone, Spanish', () => {
    expect(
      formatScheduledInterval(
        '2035-02-06T17:00:00+00:00',
        '2035-02-06T17:45:00+00:00',
        'Atlantic/Canary',
        'es',
      ),
    ).toEqual({ date: 'mar, 6 feb 2035', time: '17:00 – 17:45' });
  });

  it('formats date and time range in the Clinic timezone, English', () => {
    const result = formatScheduledInterval(
      '2035-02-06T17:00:00+00:00',
      '2035-02-06T17:45:00+00:00',
      'Atlantic/Canary',
      'en',
    );
    expect(result.date).toBe('Tue, Feb 6, 2035');
    // ICU may separate "PM" with a narrow no-break space.
    expect(result.time).toMatch(/^5:00\sPM – 5:45\sPM$/u);
  });

  it('uses the supplied timezone, never the device timezone', () => {
    const start = '2035-06-15T08:00:00Z';
    const end = '2035-06-15T08:30:00Z';
    expect(formatScheduledInterval(start, end, 'Europe/Madrid', 'es').time).toBe('10:00 – 10:30');
    expect(formatScheduledInterval(start, end, 'America/New_York', 'es').time).toBe('4:00 – 4:30');
  });

  it('handles a DST transition by resolving each instant in the zone', () => {
    // Europe/Madrid springs forward at 02:00 local on 2026-03-29: 00:30Z is
    // 01:30 CET and 01:30Z is 03:30 CEST — one real hour, two wall hours.
    expect(
      formatScheduledInterval(
        '2026-03-29T00:30:00Z',
        '2026-03-29T01:30:00Z',
        'Europe/Madrid',
        'es',
      ),
    ).toEqual({ date: 'dom, 29 mar 2026', time: '1:30 – 3:30' });
  });

  it('shows the end date when the interval ends on a later Clinic-local day', () => {
    expect(
      formatScheduledInterval(
        '2035-02-06T22:30:00Z',
        '2035-02-07T00:30:00Z',
        'Europe/Madrid',
        'es',
      ),
    ).toEqual({ date: 'mar, 6 feb 2035', time: '23:30 – mié, 7 feb 2035 1:30' });
  });
});

describe('addCivilDays', () => {
  it('adds days within a month', () => {
    expect(addCivilDays({ year: 2026, month: 6, day: 15 }, 5)).toEqual({
      year: 2026,
      month: 6,
      day: 20,
    });
  });

  it('rolls over a month boundary', () => {
    expect(addCivilDays({ year: 2026, month: 6, day: 25 }, 10)).toEqual({
      year: 2026,
      month: 7,
      day: 5,
    });
  });

  it('rolls over a year boundary', () => {
    expect(addCivilDays({ year: 2026, month: 12, day: 28 }, 10)).toEqual({
      year: 2027,
      month: 1,
      day: 7,
    });
  });

  it('supports negative days', () => {
    expect(addCivilDays({ year: 2026, month: 3, day: 2 }, -5)).toEqual({
      year: 2026,
      month: 2,
      day: 25,
    });
  });
});

describe('clinicLocalToday and shiftLocalDate', () => {
  it('reads today in the Clinic timezone, never the device/test-runner timezone', () => {
    // 23:30 UTC on 15 June is already 16 June in Auckland.
    expect(clinicLocalToday('Pacific/Auckland', new Date('2026-06-15T23:30:00Z'))).toBe(
      '2026-06-16',
    );
    // Same instant, two Clinic timezones straddling a UTC-day boundary.
    const instant = new Date('2026-06-15T02:00:00Z');
    expect(clinicLocalToday('America/New_York', instant)).toBe('2026-06-14');
    expect(clinicLocalToday('Pacific/Auckland', instant)).toBe('2026-06-15');
  });

  it('shifts plain calendar dates across month, year and leap-day boundaries', () => {
    expect(shiftLocalDate('2026-01-31', 1)).toBe('2026-02-01');
    expect(shiftLocalDate('2026-12-31', 1)).toBe('2027-01-01');
    expect(shiftLocalDate('2028-02-28', 1)).toBe('2028-02-29');
    expect(shiftLocalDate('2026-03-01', -1)).toBe('2026-02-28');
  });
});

describe('formatCandidateWindowDate', () => {
  it('labels window dates with their year', () => {
    expect(formatCandidateWindowDate('2037-07-04', 'en-US')).toContain('2037');
    expect(formatCandidateWindowDate('2037-07-04', 'es-ES')).toContain('2037');
  });
});

describe('Guardian candidate windows (SPEC-APT-014 BR-11: today … today + 60)', () => {
  // Days from `a` to `b` ("YYYY-MM-DD"), computed independently.
  const daysBetween = (a: string, b: string) =>
    (Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000;
  const MADRID_MORNING = new Date('2026-06-15T08:00:00Z');
  const TODAY = '2026-06-15';

  // Every window reachable from the first one through "Later dates".
  function allWindows(instant: Date = MADRID_MORNING) {
    const windows = [initialRequestableCandidateWindow('Europe/Madrid', instant)];
    for (;;) {
      const next = nextRequestableCandidateWindow(
        windows[windows.length - 1],
        'Europe/Madrid',
        instant,
      );
      if (next === null) return windows;
      windows.push(next);
    }
  }

  it('starts with the first 30 dates, anchored to the Clinic-local date (unchanged initial window)', () => {
    expect(initialRequestableCandidateWindow('Europe/Madrid', MADRID_MORNING)).toEqual({
      index: 0,
      startDate: '2026-06-15',
      endDate: '2026-07-14',
    });
    // 23:30 UTC in Pacific/Auckland (UTC+12) is already the next Clinic-local day.
    expect(
      initialRequestableCandidateWindow('Pacific/Auckland', new Date('2026-06-15T23:30:00Z')),
    ).toEqual({ index: 0, startDate: '2026-06-16', endDate: '2026-07-15' });
    expect(REQUESTABLE_DATE_RANGE_DAYS).toBe(30);
  });

  it('offers the remaining dates through today + 60 as the later window', () => {
    const [first, later] = allWindows();
    expect(nextRequestableCandidateWindow(first, 'Europe/Madrid', MADRID_MORNING)).toEqual({
      index: 1,
      startDate: '2026-07-15',
      endDate: '2026-08-14',
    });
    expect(later.endDate).toBe('2026-08-14');
  });

  it('reaches day + 60 exactly and never day + 61', () => {
    const windows = allWindows();
    const last = windows[windows.length - 1];
    expect(REQUESTABLE_HORIZON_DAYS).toBe(60);
    expect(daysBetween(TODAY, last.endDate)).toBe(60);
    for (const window of windows) {
      expect(daysBetween(TODAY, window.endDate)).toBeLessThanOrEqual(60);
    }
    // No window after the last one.
    expect(nextRequestableCandidateWindow(last, 'Europe/Madrid', MADRID_MORNING)).toBeNull();
    expect(requestableCandidateWindow(windows.length, TODAY)).toBeNull();
  });

  it('partitions the 61 allowed dates with no gap and no duplicate boundary day', () => {
    const windows = allWindows();
    expect(windows).toHaveLength(2);
    expect(windows[0].startDate).toBe(TODAY);
    for (let i = 1; i < windows.length; i++) {
      expect(daysBetween(windows[i - 1].endDate, windows[i].startDate)).toBe(1);
    }
    const covered = windows.reduce(
      (total, window) => total + daysBetween(window.startDate, window.endDate) + 1,
      0,
    );
    expect(covered).toBe(61);
  });

  it('keeps every window within the backend span and never before Clinic-local today', () => {
    for (const window of allWindows()) {
      expect(daysBetween(window.startDate, window.endDate)).toBeLessThanOrEqual(60);
      expect(window.startDate >= TODAY).toBe(true);
    }
  });

  it('goes back to the earlier window, and never before the first one (clamped at today)', () => {
    const [first, later] = allWindows();
    expect(previousRequestableCandidateWindow(later, 'Europe/Madrid', MADRID_MORNING)).toEqual(
      first,
    );
    expect(previousRequestableCandidateWindow(first, 'Europe/Madrid', MADRID_MORNING)).toBeNull();
  });

  it('re-anchors on the current Clinic-local today when moving, so it never exceeds today + 60', () => {
    const [, later] = allWindows();
    // The Clinic-local date moved on by a day while the later window was shown.
    const tomorrow = new Date('2026-06-16T08:00:00Z');
    const back = previousRequestableCandidateWindow(later, 'Europe/Madrid', tomorrow);
    expect(back).toEqual({ index: 0, startDate: '2026-06-16', endDate: '2026-07-15' });
    const forward = back && nextRequestableCandidateWindow(back, 'Europe/Madrid', tomorrow);
    expect(forward).toEqual({ index: 1, startDate: '2026-07-16', endDate: '2026-08-15' });
  });
});

describe('formatCandidateDateLabel', () => {
  it('formats a Clinic-local date via Intl in English, never a hardcoded weekday/month string', () => {
    expect(formatCandidateDateLabel('2026-01-05', 'en')).toBe('Mon, Jan 5');
  });

  it('formats the same date via Intl in Spanish', () => {
    expect(formatCandidateDateLabel('2026-01-05', 'es')).toBe('lun, 5 ene');
  });

  it('is not shifted by the device timezone (parses as a UTC-anchored calendar date)', () => {
    expect(formatCandidateDateLabel('2026-01-01', 'en')).toBe('Thu, Jan 1');
    expect(formatCandidateDateLabel('2026-12-31', 'en')).toBe('Thu, Dec 31');
  });
});

describe('formatCandidateDateParts', () => {
  it('splits the English label into weekday and month + day', () => {
    expect(formatCandidateDateParts('2026-01-05', 'en')).toEqual({
      weekday: 'Mon',
      dayMonth: 'Jan 5',
    });
  });

  it('splits the Spanish label into weekday and day + month', () => {
    expect(formatCandidateDateParts('2026-01-05', 'es')).toEqual({
      weekday: 'lun',
      dayMonth: '5 ene',
    });
  });

  it('is not shifted by the device timezone (UTC-anchored, like the one-line label)', () => {
    expect(formatCandidateDateParts('2026-01-01', 'en')).toEqual({
      weekday: 'Thu',
      dayMonth: 'Jan 1',
    });
    expect(formatCandidateDateParts('2026-12-31', 'en')).toEqual({
      weekday: 'Thu',
      dayMonth: 'Dec 31',
    });
  });
});
