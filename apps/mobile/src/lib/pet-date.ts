/**
 * Pet date-of-birth handling as plain calendar dates, never JavaScript Date
 * objects. Constructing a `Date` from a 'YYYY-MM-DD' string and formatting
 * it back interprets it through a timezone (UTC parse, local display or
 * vice versa), which can shift the displayed day by one — exactly what
 * PostgreSQL `date` semantics must not be subjected to. Every function here
 * works on the string/number parts directly instead.
 */

export type BirthDateMode = 'unknown' | 'exact' | 'approximate';

export type BirthDateFormValue = {
  mode: BirthDateMode;
  year: string;
  month: string;
  day: string;
};

export type BirthDateFields = {
  dateOfBirth: string | null;
  approximateDateOfBirth: string | null;
};

function isLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

function daysInMonth(year: number, month: number): number {
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month === 2 && isLeapYear(year)) return 29;
  return lengths[month - 1];
}

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

/**
 * Validates a Y/M/D triple as a real calendar date and serializes it to the
 * plain 'YYYY-MM-DD' string PostgreSQL's `date` type expects, or returns
 * null if the triple isn't a valid calendar date. Deliberately checks only
 * calendar validity (real month, real day-of-month including leap years) —
 * no "not in the future" or other business rule the backend doesn't itself
 * enforce (supabase/migrations/20260825170004_pet_and_guardianship.sql has
 * no such constraint on date_of_birth/approximate_date_of_birth).
 */
export function serializeCalendarDate(year: string, month: string, day: string): string | null {
  if (!/^\d{4}$/.test(year) || !/^\d{1,2}$/.test(month) || !/^\d{1,2}$/.test(day)) {
    return null;
  }

  const yearNum = Number(year);
  const monthNum = Number(month);
  const dayNum = Number(day);

  if (monthNum < 1 || monthNum > 12) return null;
  if (dayNum < 1 || dayNum > daysInMonth(yearNum, monthNum)) return null;

  return `${year}-${pad2(monthNum)}-${pad2(dayNum)}`;
}

/** Splits a 'YYYY-MM-DD' string back into editable Y/M/D form parts. */
export function parseCalendarDate(value: string | null): {
  year: string;
  month: string;
  day: string;
} {
  if (!value) return { year: '', month: '', day: '' };
  const [year, month, day] = value.split('-');
  return { year: year ?? '', month: month ?? '', day: day ?? '' };
}

/** Plain string reformatting for display — never constructs a Date. */
export function formatCalendarDateForDisplay(value: string): string {
  const [year, month, day] = value.split('-');
  return `${day}/${month}/${year}`;
}

/**
 * True when the user selected "exact" or "approximate" but the digits they
 * entered don't form a real calendar date — distinct from "unknown", which
 * is always valid. The caller should block submission and show an error in
 * this case rather than silently sending null.
 */
export function hasIncompleteOrInvalidBirthDate(value: BirthDateFormValue): boolean {
  if (value.mode === 'unknown') return false;
  return serializeCalendarDate(value.year, value.month, value.day) === null;
}

/**
 * Normalizes a BirthDateFormValue into the two mutually-exclusive backend
 * columns (pets_birth_date_exclusivity_check: at most one of
 * date_of_birth/approximate_date_of_birth may be non-null). The caller must
 * check hasIncompleteOrInvalidBirthDate first — this never sends a
 * half-entered date, only a valid one or null.
 */
export function normalizeBirthDate(value: BirthDateFormValue): BirthDateFields {
  if (value.mode === 'unknown') {
    return { dateOfBirth: null, approximateDateOfBirth: null };
  }

  const serialized = serializeCalendarDate(value.year, value.month, value.day);

  if (value.mode === 'exact') {
    return { dateOfBirth: serialized, approximateDateOfBirth: null };
  }

  return { dateOfBirth: null, approximateDateOfBirth: serialized };
}
