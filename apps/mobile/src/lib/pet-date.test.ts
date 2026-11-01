import {
  formatCalendarDateForDisplay,
  hasIncompleteOrInvalidBirthDate,
  normalizeBirthDate,
  parseCalendarDate,
  serializeCalendarDate,
  type BirthDateFormValue,
} from '@/lib/pet-date';

describe('serializeCalendarDate', () => {
  it('serializes a valid date to YYYY-MM-DD with zero-padding', () => {
    expect(serializeCalendarDate('2020', '3', '5')).toBe('2020-03-05');
    expect(serializeCalendarDate('2020', '03', '05')).toBe('2020-03-05');
  });

  it('accepts a leap-year February 29', () => {
    expect(serializeCalendarDate('2020', '2', '29')).toBe('2020-02-29');
  });

  it('rejects February 29 in a non-leap year', () => {
    expect(serializeCalendarDate('2021', '2', '29')).toBeNull();
  });

  it('rejects a century year that is not a leap year (2100)', () => {
    expect(serializeCalendarDate('2100', '2', '29')).toBeNull();
  });

  it('accepts a 400-divisible century year as a leap year (2000)', () => {
    expect(serializeCalendarDate('2000', '2', '29')).toBe('2000-02-29');
  });

  it('rejects an out-of-range month', () => {
    expect(serializeCalendarDate('2020', '13', '1')).toBeNull();
    expect(serializeCalendarDate('2020', '0', '1')).toBeNull();
  });

  it('rejects a day beyond the month length', () => {
    expect(serializeCalendarDate('2020', '4', '31')).toBeNull();
  });

  it('rejects malformed numeric input', () => {
    expect(serializeCalendarDate('20', '3', '5')).toBeNull();
    expect(serializeCalendarDate('2020', '', '5')).toBeNull();
    expect(serializeCalendarDate('2020', '3', '')).toBeNull();
    expect(serializeCalendarDate('abcd', '3', '5')).toBeNull();
  });
});

describe('parseCalendarDate', () => {
  it('splits a YYYY-MM-DD string into parts', () => {
    expect(parseCalendarDate('2020-03-05')).toEqual({ year: '2020', month: '03', day: '05' });
  });

  it('returns empty parts for null', () => {
    expect(parseCalendarDate(null)).toEqual({ year: '', month: '', day: '' });
  });
});

describe('formatCalendarDateForDisplay', () => {
  it('reformats YYYY-MM-DD to DD/MM/YYYY via plain string ops, never a Date', () => {
    expect(formatCalendarDateForDisplay('2020-03-05')).toBe('05/03/2020');
  });
});

describe('hasIncompleteOrInvalidBirthDate', () => {
  it('is always false for mode "unknown", regardless of leftover digits', () => {
    expect(hasIncompleteOrInvalidBirthDate({ mode: 'unknown', year: '', month: '', day: '' })).toBe(
      false,
    );
  });

  it('is false for a complete, valid exact date', () => {
    expect(
      hasIncompleteOrInvalidBirthDate({ mode: 'exact', year: '2020', month: '03', day: '05' }),
    ).toBe(false);
  });

  it('is true for an incomplete exact date', () => {
    expect(
      hasIncompleteOrInvalidBirthDate({ mode: 'exact', year: '2020', month: '', day: '' }),
    ).toBe(true);
  });

  it('is true for an invalid approximate date', () => {
    expect(
      hasIncompleteOrInvalidBirthDate({ mode: 'approximate', year: '2020', month: '2', day: '30' }),
    ).toBe(true);
  });
});

describe('normalizeBirthDate', () => {
  it('returns both fields null for "unknown"', () => {
    const value: BirthDateFormValue = { mode: 'unknown', year: '2020', month: '3', day: '5' };
    expect(normalizeBirthDate(value)).toEqual({ dateOfBirth: null, approximateDateOfBirth: null });
  });

  it('fills only dateOfBirth for "exact", leaving approximateDateOfBirth null', () => {
    const value: BirthDateFormValue = { mode: 'exact', year: '2020', month: '3', day: '5' };
    expect(normalizeBirthDate(value)).toEqual({
      dateOfBirth: '2020-03-05',
      approximateDateOfBirth: null,
    });
  });

  it('fills only approximateDateOfBirth for "approximate", leaving dateOfBirth null', () => {
    const value: BirthDateFormValue = { mode: 'approximate', year: '2020', month: '3', day: '5' };
    expect(normalizeBirthDate(value)).toEqual({
      dateOfBirth: null,
      approximateDateOfBirth: '2020-03-05',
    });
  });

  it('never produces both fields non-null, matching pets_birth_date_exclusivity_check', () => {
    const exact = normalizeBirthDate({ mode: 'exact', year: '2020', month: '3', day: '5' });
    const approximate = normalizeBirthDate({
      mode: 'approximate',
      year: '2020',
      month: '3',
      day: '5',
    });
    expect(exact.dateOfBirth === null || exact.approximateDateOfBirth === null).toBe(true);
    expect(approximate.dateOfBirth === null || approximate.approximateDateOfBirth === null).toBe(
      true,
    );
  });
});
