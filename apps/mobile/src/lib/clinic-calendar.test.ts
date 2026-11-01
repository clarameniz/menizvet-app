import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import {
  appointmentLocalDate,
  calendarFocusAfterContext,
  compactAppointmentDate,
  compactAppointmentTimes,
  daysInMonth,
  deviceMonth,
  firstDateOfMonth,
  formatDayHeading,
  formatMonthTitle,
  isCalendarDate,
  isDateInMonth,
  isSupportedMonth,
  monthKey,
  monthOfDate,
  mondayFirstWeekdays,
  shiftMonth,
  showsAppointmentTimezone,
  weekRowsInMonth,
} from '@/lib/clinic-calendar';

function appointment(
  start: string,
  end: string,
  timezone = 'Europe/Madrid',
): ClinicScheduleAppointment {
  return {
    id: 'appt-1',
    petId: 'pet-1',
    petName: 'Luna',
    requestingUserId: 'user-1',
    requesterDisplayName: 'Marta Ruiz',
    reasonForVisit: 'Revisión',
    guardianNotes: null,
    lifecycleState: 'CONFIRMED',
    createdAt: '2026-01-01T00:00:00Z',
    currentScheduledStartAt: start,
    currentScheduledEndAt: end,
    currentSchedulingTimezoneName: timezone,
    currentScheduleRevisionSequence: 1,
    currentVeterinarianClinicAssignmentId: null,
    pendingReschedule: null,
    currentScheduleSource: null,
    cancellationReason: null,
    hasClinicalRecord: false,
  };
}

describe('calendar dates and months', () => {
  it('accepts only real YYYY-MM-DD dates', () => {
    expect(isCalendarDate('2026-11-03')).toBe(true);
    expect(isCalendarDate('2028-02-29')).toBe(true);
    for (const value of [
      '2026-02-29',
      '2026-13-01',
      '2026-11-3',
      '2026-11-03T00:00',
      '',
      null,
      3,
    ]) {
      expect(isCalendarDate(value)).toBe(false);
    }
  });

  it('moves across year boundaries in both directions', () => {
    expect(shiftMonth({ year: 2026, month: 12 }, 1)).toEqual({ year: 2027, month: 1 });
    expect(shiftMonth({ year: 2027, month: 1 }, -1)).toEqual({ year: 2026, month: 12 });
    expect(shiftMonth({ year: 2026, month: 11 }, 14)).toEqual({ year: 2028, month: 1 });
    expect(monthKey({ year: 2026, month: 3 })).toBe('2026-03');
    expect(firstDateOfMonth({ year: 2026, month: 3 })).toBe('2026-03-01');
    expect(monthOfDate('2026-11-30')).toEqual({ year: 2026, month: 11 });
    expect(isDateInMonth('2026-11-30', { year: 2026, month: 11 })).toBe(true);
    expect(isDateInMonth('2026-12-01', { year: 2026, month: 11 })).toBe(false);
  });

  it('knows month lengths, including leap Februaries', () => {
    expect(daysInMonth({ year: 2026, month: 2 })).toBe(28);
    expect(daysInMonth({ year: 2028, month: 2 })).toBe(29);
    expect(daysInMonth({ year: 2026, month: 4 })).toBe(30);
    expect(daysInMonth({ year: 2026, month: 12 })).toBe(31);
  });

  it('counts Monday-first week rows: four, five and six', () => {
    // February 2027 starts on a Monday and has 28 days.
    expect(weekRowsInMonth({ year: 2027, month: 2 })).toBe(4);
    // October 2026 starts on a Thursday: 3 + 31 days.
    expect(weekRowsInMonth({ year: 2026, month: 10 })).toBe(5);
    // March 2026 and November 2026 start on a Sunday: the last column first.
    expect(weekRowsInMonth({ year: 2026, month: 3 })).toBe(6);
    expect(weekRowsInMonth({ year: 2026, month: 11 })).toBe(6);
  });

  it('accepts only the months the backend reads (2000–2999)', () => {
    expect(isSupportedMonth({ year: 2000, month: 1 })).toBe(true);
    expect(isSupportedMonth({ year: 2999, month: 12 })).toBe(true);
    expect(isSupportedMonth({ year: 1999, month: 12 })).toBe(false);
    expect(isSupportedMonth({ year: 3000, month: 1 })).toBe(false);
  });

  it('takes the device month only as a provisional month', () => {
    expect(deviceMonth(new Date(2026, 10, 30, 23, 59))).toEqual({ year: 2026, month: 11 });
  });
});

describe('localized labels', () => {
  it('starts the week on Monday in Spanish and English', () => {
    const es = mondayFirstWeekdays('es');
    const en = mondayFirstWeekdays('en');
    expect(es.map((day) => day.long)).toEqual([
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ]);
    expect(en[0]).toEqual({ short: 'Mon', long: 'Monday' });
    expect(en[6].long).toBe('Sunday');
    expect(es[0].short).toMatch(/^Lun/);
  });

  it('titles the month and the day in each language, never shifted by the device timezone', () => {
    expect(formatMonthTitle({ year: 2026, month: 11 }, 'es')).toBe('Noviembre de 2026');
    expect(formatMonthTitle({ year: 2026, month: 11 }, 'en')).toBe('November 2026');
    expect(formatDayHeading('2026-11-03', 'es')).toBe('Martes, 3 de noviembre de 2026');
    expect(formatDayHeading('2026-11-03', 'en')).toBe('Tuesday, November 3, 2026');
    expect(formatDayHeading('2027-01-01', 'es')).toBe('Viernes, 1 de enero de 2027');
  });
});

describe('calendar focus after a calendar context read', () => {
  const now = new Date(2026, 10, 20, 12, 0);

  it("opens on the Clinic's today, selected", () => {
    expect(calendarFocusAfterContext(null, '2026-11-03', now)).toEqual({
      visibleMonth: { year: 2026, month: 11 },
      selectedDate: '2026-11-03',
    });
  });

  it('without a Clinic today opens the device month provisionally and selects nothing', () => {
    expect(calendarFocusAfterContext(null, null, now)).toEqual({
      visibleMonth: { year: 2026, month: 11 },
      selectedDate: null,
    });
  });

  it('keeps the actor’s own choice while today is unchanged', () => {
    const previous = {
      visibleMonth: { year: 2027, month: 2 },
      selectedDate: '2027-02-10',
      today: '2026-11-03',
    };
    expect(calendarFocusAfterContext(previous, '2026-11-03', now)).toEqual({
      visibleMonth: { year: 2027, month: 2 },
      selectedDate: '2027-02-10',
    });
  });

  it('follows midnight when the actor was still on today, also into a new month and year', () => {
    expect(
      calendarFocusAfterContext(
        {
          visibleMonth: { year: 2026, month: 11 },
          selectedDate: '2026-11-03',
          today: '2026-11-03',
        },
        '2026-11-04',
        now,
      ),
    ).toEqual({ visibleMonth: { year: 2026, month: 11 }, selectedDate: '2026-11-04' });
    expect(
      calendarFocusAfterContext(
        {
          visibleMonth: { year: 2026, month: 12 },
          selectedDate: '2026-12-31',
          today: '2026-12-31',
        },
        '2027-01-01',
        now,
      ),
    ).toEqual({ visibleMonth: { year: 2027, month: 1 }, selectedDate: '2027-01-01' });
  });

  it('does not move another selected day when midnight passes', () => {
    expect(
      calendarFocusAfterContext(
        {
          visibleMonth: { year: 2026, month: 11 },
          selectedDate: '2026-11-20',
          today: '2026-11-03',
        },
        '2026-11-04',
        now,
      ),
    ).toEqual({ visibleMonth: { year: 2026, month: 11 }, selectedDate: '2026-11-20' });
  });

  it('keeps the selection when the Clinic loses its timezone, and selects today when it gains one', () => {
    expect(
      calendarFocusAfterContext(
        {
          visibleMonth: { year: 2026, month: 11 },
          selectedDate: '2026-11-03',
          today: '2026-11-03',
        },
        null,
        now,
      ),
    ).toEqual({ visibleMonth: { year: 2026, month: 11 }, selectedDate: '2026-11-03' });
    expect(
      calendarFocusAfterContext(
        { visibleMonth: { year: 2026, month: 11 }, selectedDate: null, today: null },
        '2026-11-21',
        now,
      ),
    ).toEqual({ visibleMonth: { year: 2026, month: 11 }, selectedDate: '2026-11-21' });
  });
});

describe('compact appointment times', () => {
  it("shows the interval in its own timezone, not the device's", () => {
    // 23:30–00:15 in Madrid (UTC+1): ends on the next local date.
    const late = compactAppointmentTimes(
      appointment('2026-11-03T22:30:00Z', '2026-11-03T23:15:00Z'),
      'es',
    );
    expect(late).toEqual({ start: '23:30', end: '0:15', endsLater: true });
    const morning = compactAppointmentTimes(
      appointment('2026-11-03T08:00:00Z', '2026-11-03T08:30:00Z'),
      'en',
    );
    expect(morning).toEqual({ start: '9:00 AM', end: '9:30 AM', endsLater: false });
  });

  it('follows daylight saving: the same UTC hour is another local hour in summer', () => {
    expect(
      compactAppointmentTimes(appointment('2026-07-03T08:00:00Z', '2026-07-03T08:30:00Z'), 'es')
        .start,
    ).toBe('10:00');
    expect(
      compactAppointmentTimes(appointment('2026-12-03T08:00:00Z', '2026-12-03T08:30:00Z'), 'es')
        .start,
    ).toBe('9:00');
  });

  it('names the timezone only when it differs from the Clinic’s current one, or there is none', () => {
    const madrid = appointment('2026-11-03T08:00:00Z', '2026-11-03T08:30:00Z');
    const newYork = appointment('2026-11-03T14:00:00Z', '2026-11-03T14:30:00Z', 'America/New_York');
    expect(showsAppointmentTimezone(madrid, 'Europe/Madrid')).toBe(false);
    expect(showsAppointmentTimezone(newYork, 'Europe/Madrid')).toBe(true);
    expect(showsAppointmentTimezone(madrid, null)).toBe(true);
  });
});

describe('compactAppointmentDate (list rows)', () => {
  const NOW = new Date('2026-10-22T10:00:00Z');

  it('omits the year in the current year and shows it otherwise', () => {
    const thisYear = appointment('2026-10-15T08:00:00Z', '2026-10-15T08:30:00Z');
    const lastYear = appointment('2025-10-15T08:00:00Z', '2025-10-15T08:30:00Z');
    expect(compactAppointmentDate(thisYear, 'es', NOW)).toBe('15 oct');
    expect(compactAppointmentDate(lastYear, 'es', NOW)).toBe('15 oct 2025');
    expect(compactAppointmentDate(thisYear, 'en', NOW)).toBe('Oct 15');
    expect(compactAppointmentDate(lastYear, 'en', NOW)).toBe('Oct 15, 2025');
  });

  it("dates the Appointment in its own timezone, never UTC's or the device's", () => {
    // 00:30 on 1 January 2027 in Madrid is still 31 December 2026 in UTC.
    const newYear = appointment('2026-12-31T23:30:00Z', '2027-01-01T00:00:00Z');
    expect(appointmentLocalDate(newYear)).toBe('2027-01-01');
    expect(compactAppointmentDate(newYear, 'es', NOW)).toBe('1 ene 2027');
    // 20:00 on 15 October in New York is 16 October in UTC.
    const evening = appointment('2026-10-16T00:00:00Z', '2026-10-16T00:30:00Z', 'America/New_York');
    expect(compactAppointmentDate(evening, 'es', NOW)).toBe('15 oct');
  });
});
