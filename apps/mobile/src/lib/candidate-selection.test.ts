import type { RequestableCandidate } from '@/data/appointments';
import type { RescheduleCandidate } from '@/data/professional-appointment-reschedule';
import {
  candidateAfterDateChange,
  candidateKey,
  candidatesForDate,
  distinctSortedCandidateDates,
  formatCandidateTime,
  isSameCandidate,
  preferredCandidateDate,
  rematchSelectedCandidate,
} from '@/lib/candidate-selection';

const SLOT_A: RequestableCandidate = {
  localDate: '2026-09-22',
  localTime: '16:30:00',
  utcOffsetSeconds: 7200,
};

// A Professional candidate also carries its server-authored end.
const NINE_AM: RescheduleCandidate = {
  localDate: '2035-03-06',
  localTime: '09:00:00',
  utcOffsetSeconds: 3600,
  endAt: '2035-03-06T08:30:00Z',
};
const TEN_AM: RescheduleCandidate = {
  ...NINE_AM,
  localTime: '10:00:00',
  endAt: '2035-03-06T09:30:00Z',
};
const NEXT_DAY: RescheduleCandidate = {
  ...NINE_AM,
  localDate: '2035-03-08',
  endAt: '2035-03-08T08:30:00Z',
};

describe('isSameCandidate', () => {
  it('matches only when date, time and offset are all equal', () => {
    expect(isSameCandidate(SLOT_A, { ...SLOT_A })).toBe(true);
    expect(isSameCandidate(SLOT_A, { ...SLOT_A, localTime: '16:45:00' })).toBe(false);
    expect(isSameCandidate(SLOT_A, { ...SLOT_A, localDate: '2026-09-23' })).toBe(false);
    // Same wall-clock time across a DST change is a different slot.
    expect(isSameCandidate(SLOT_A, { ...SLOT_A, utcOffsetSeconds: 3600 })).toBe(false);
  });

  it('ignores fields beyond the identity, such as a Professional candidate end', () => {
    const otherEnd: RescheduleCandidate = { ...NINE_AM, endAt: 'other' };
    expect(isSameCandidate(NINE_AM, otherEnd)).toBe(true);
    expect(isSameCandidate(NINE_AM, { ...NINE_AM, utcOffsetSeconds: 7200 })).toBe(false);
  });
});

describe('candidateKey', () => {
  it('is equal exactly for the same slot', () => {
    expect(candidateKey(SLOT_A)).toBe(candidateKey({ ...SLOT_A }));
    expect(candidateKey(SLOT_A)).not.toBe(candidateKey({ ...SLOT_A, utcOffsetSeconds: 3600 }));
    const otherEnd: RescheduleCandidate = { ...NINE_AM, endAt: 'other' };
    expect(candidateKey(NINE_AM)).toBe(candidateKey(otherEnd));
  });
});

describe('formatCandidateTime', () => {
  it('drops the seconds', () => {
    expect(formatCandidateTime('09:05:00')).toBe('09:05');
  });
});

describe('distinctSortedCandidateDates', () => {
  it('returns an empty array for no candidates', () => {
    expect(distinctSortedCandidateDates([])).toEqual([]);
  });

  it('deduplicates repeated dates and sorts ascending', () => {
    const candidates: RequestableCandidate[] = [
      { localDate: '2026-02-03', localTime: '09:00:00', utcOffsetSeconds: 3600 },
      { localDate: '2026-02-01', localTime: '10:00:00', utcOffsetSeconds: 3600 },
      { localDate: '2026-02-01', localTime: '10:30:00', utcOffsetSeconds: 3600 },
      { localDate: '2026-02-02', localTime: '09:00:00', utcOffsetSeconds: 3600 },
    ];

    expect(distinctSortedCandidateDates(candidates)).toEqual([
      '2026-02-01',
      '2026-02-02',
      '2026-02-03',
    ]);
    expect(distinctSortedCandidateDates([NEXT_DAY, TEN_AM, NINE_AM])).toEqual([
      '2035-03-06',
      '2035-03-08',
    ]);
  });
});

describe('candidatesForDate', () => {
  const candidates: RequestableCandidate[] = [
    { localDate: '2026-02-01', localTime: '09:00:00', utcOffsetSeconds: 3600 },
    { localDate: '2026-02-01', localTime: '09:30:00', utcOffsetSeconds: 3600 },
    { localDate: '2026-02-02', localTime: '10:00:00', utcOffsetSeconds: 3600 },
  ];

  it('filters an already-loaded candidate array down to one Clinic-local date, in backend order', () => {
    expect(candidatesForDate(candidates, '2026-02-01')).toEqual([
      { localDate: '2026-02-01', localTime: '09:00:00', utcOffsetSeconds: 3600 },
      { localDate: '2026-02-01', localTime: '09:30:00', utcOffsetSeconds: 3600 },
    ]);
  });

  it('returns an empty array for a date with no loaded candidates, or no candidates', () => {
    expect(candidatesForDate(candidates, '2026-02-28')).toEqual([]);
    expect(candidatesForDate([], '2026-02-01')).toEqual([]);
  });

  it('preserves every candidate object exactly, never mutating or re-deriving it', () => {
    const [firstMatch] = candidatesForDate(candidates, '2026-02-02');
    expect(firstMatch).toBe(candidates[2]);
    const professional = candidatesForDate([NINE_AM, TEN_AM, NEXT_DAY], '2035-03-06');
    expect(professional).toEqual([NINE_AM, TEN_AM]);
    expect(professional[1]).toBe(TEN_AM);
    expect(professional[1].endAt).toBe('2035-03-06T09:30:00Z');
  });
});

describe('candidateAfterDateChange', () => {
  it('keeps the selected slot when re-selecting its own date', () => {
    expect(candidateAfterDateChange(SLOT_A, '2026-09-22')).toBe(SLOT_A);
    expect(candidateAfterDateChange(TEN_AM, '2035-03-06')).toBe(TEN_AM);
  });

  it('clears the selected slot when switching to another date', () => {
    expect(candidateAfterDateChange(SLOT_A, '2026-09-23')).toBeNull();
    expect(candidateAfterDateChange(TEN_AM, '2035-03-08')).toBeNull();
  });

  it('stays empty when nothing was selected', () => {
    expect(candidateAfterDateChange(null, '2026-09-22')).toBeNull();
  });
});

describe('preferredCandidateDate (date after a candidate read)', () => {
  it('selects the first date that has times when there is no preference (Guardian request)', () => {
    expect(preferredCandidateDate([NEXT_DAY, NINE_AM], null)).toBe('2035-03-06');
  });

  it('preselects the preferred date when the read offers it (current date, or the date already shown)', () => {
    expect(preferredCandidateDate([NINE_AM, NEXT_DAY], '2035-03-08')).toBe('2035-03-08');
  });

  it('never selects a date without times; the first date of the read is offered instead', () => {
    // The preferred date (e.g. today, 2035-03-05) has no candidates; a later date does.
    expect(preferredCandidateDate([NEXT_DAY], '2035-03-05')).toBe('2035-03-08');
  });

  it('selects nothing only when the read has no candidates at all', () => {
    expect(preferredCandidateDate([], '2035-03-06')).toBeNull();
    expect(preferredCandidateDate([], null)).toBeNull();
  });
});

describe('rematchSelectedCandidate (selection after a candidate read)', () => {
  it('keeps the selected time as the complete fresh object, with its latest server-authored end', () => {
    const refreshedTenAm: RescheduleCandidate = { ...TEN_AM, endAt: '2035-03-06T09:45:00Z' };
    const rematched = rematchSelectedCandidate([NINE_AM, refreshedTenAm], TEN_AM);
    expect(rematched).toBe(refreshedTenAm);
    expect(rematched?.endAt).toBe('2035-03-06T09:45:00Z');
  });

  it('clears the selection when the fresh read no longer offers the slot', () => {
    expect(rematchSelectedCandidate([NINE_AM], TEN_AM)).toBeNull();
    // Same wall-clock time, different offset: a different slot.
    expect(rematchSelectedCandidate([{ ...TEN_AM, utcOffsetSeconds: 7200 }], TEN_AM)).toBeNull();
  });

  it('stays empty when nothing was selected or nothing was read', () => {
    expect(rematchSelectedCandidate([NINE_AM], null)).toBeNull();
    expect(rematchSelectedCandidate([], TEN_AM)).toBeNull();
  });

  it('works for Guardian candidates too, returning the fresh object', () => {
    const fresh: RequestableCandidate = { ...SLOT_A };
    expect(rematchSelectedCandidate([fresh], SLOT_A)).toBe(fresh);
  });
});
