import type { ManagedClinicProfile } from '@/data/clinic-settings';
import { SCHEDULING_TIMEZONES } from '@/constants/scheduling-timezones';
import {
  canSaveTimezone,
  deviceTimezoneSuggestion,
  searchTimezones,
  timezoneLabel,
  timezoneSaveFailure,
  timezoneSelectionState,
} from '@/lib/clinic-timezone';

const managed = (schedulingTimezoneName: string | null): ManagedClinicProfile => ({
  clinicId: 'c-1',
  isPublished: false,
  schedulingTimezoneName,
  publicProfile: null,
  location: null,
});

describe('SCHEDULING_TIMEZONES', () => {
  it('contains only named, canonical region/city IANA timezones the runtime recognizes', () => {
    expect(SCHEDULING_TIMEZONES.length).toBeGreaterThan(300);
    for (const zone of SCHEDULING_TIMEZONES) {
      expect(zone).toMatch(
        /^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)\/[A-Za-z]/,
      );
      expect(() => new Intl.DateTimeFormat('en-US', { timeZone: zone }).format(0)).not.toThrow();
    }
    expect(new Set(SCHEDULING_TIMEZONES).size).toBe(SCHEDULING_TIMEZONES.length);
  });

  it('includes the zones Spanish clinics use and no fixed offsets or Etc zones', () => {
    expect(SCHEDULING_TIMEZONES).toEqual(
      expect.arrayContaining(['Europe/Madrid', 'Atlantic/Canary']),
    );
    expect(SCHEDULING_TIMEZONES.some((zone) => zone.startsWith('Etc/'))).toBe(false);
    expect(SCHEDULING_TIMEZONES).not.toContain('UTC');
  });
});

describe('timezoneLabel', () => {
  it('shows the city readably, the region, and the canonical name', () => {
    expect(timezoneLabel('Europe/Madrid')).toEqual({
      city: 'Madrid',
      region: 'Europe',
      name: 'Europe/Madrid',
    });
    expect(timezoneLabel('America/Argentina/Buenos_Aires')).toEqual({
      city: 'Buenos Aires',
      region: 'America / Argentina',
      name: 'America/Argentina/Buenos_Aires',
    });
  });
});

describe('searchTimezones', () => {
  it('matches nothing for an empty query (the list is searched, not scrolled)', () => {
    expect(searchTimezones('')).toEqual([]);
    expect(searchTimezones('   ')).toEqual([]);
  });

  it('finds a city case-insensitively, with spaces for underscores', () => {
    expect(searchTimezones('madrid')).toContain('Europe/Madrid');
    expect(searchTimezones('NEW YORK')).toContain('America/New_York');
  });

  it('ignores accents in the query', () => {
    expect(searchTimezones('são paulo')).toContain('America/Sao_Paulo');
    expect(searchTimezones('canary')).toEqual(['Atlantic/Canary']);
  });

  it('requires every word and also matches the region', () => {
    expect(searchTimezones('europe lisbon')).toEqual(['Europe/Lisbon']);
    expect(searchTimezones('europe madrid lisbon')).toEqual([]);
  });

  it('lists cities that start with the query first', () => {
    const results = searchTimezones('mad');
    expect(results.slice(0, 2)).toEqual(['Atlantic/Madeira', 'Europe/Madrid']);
  });
});

describe('deviceTimezoneSuggestion', () => {
  it('suggests the device timezone only when it is offered', () => {
    expect(deviceTimezoneSuggestion('Europe/Madrid')).toBe('Europe/Madrid');
    expect(deviceTimezoneSuggestion('Etc/GMT+3')).toBeNull();
    expect(deviceTimezoneSuggestion(null)).toBeNull();
    expect(deviceTimezoneSuggestion(undefined)).toBeNull();
  });
});

describe('timezoneSelectionState (selected-state feedback)', () => {
  const stored = 'Atlantic/Canary';

  it('nothing chosen yet: no pending selection, the device suggestion is offered', () => {
    expect(timezoneSelectionState({ selected: null, stored, suggestion: 'Europe/Madrid' })).toEqual(
      { pending: null, offerDeviceSuggestion: true },
    );
  });

  it('applying the device suggestion selects its canonical timezone as a visible, unsaved change', () => {
    const suggestion = deviceTimezoneSuggestion('Europe/Madrid');
    const state = timezoneSelectionState({ selected: suggestion, stored, suggestion });
    expect(state.pending).toEqual({ city: 'Madrid', region: 'Europe', name: 'Europe/Madrid' });
    expect(state.offerDeviceSuggestion).toBe(false);
    expect(canSaveTimezone({ selected: suggestion, stored, busy: false })).toBe(true);
  });

  it('a search result selects through the same model and presentation', () => {
    const fromSearch = searchTimezones('madrid').find((zone) => zone === 'Europe/Madrid') ?? null;
    expect(
      timezoneSelectionState({ selected: fromSearch, stored, suggestion: 'Europe/Madrid' }),
    ).toEqual(timezoneSelectionState({ selected: 'Europe/Madrid', stored, suggestion: null }));
  });

  it('choosing another timezone after the suggestion offers the suggestion again', () => {
    expect(
      timezoneSelectionState({
        selected: 'Europe/Lisbon',
        stored,
        suggestion: 'Europe/Madrid',
      }),
    ).toEqual({
      pending: { city: 'Lisbon', region: 'Europe', name: 'Europe/Lisbon' },
      offerDeviceSuggestion: true,
    });
  });

  it('re-selecting the stored timezone is not a false unsaved change', () => {
    expect(timezoneSelectionState({ selected: stored, stored, suggestion: stored })).toEqual({
      pending: null,
      offerDeviceSuggestion: false,
    });
    expect(canSaveTimezone({ selected: stored, stored, busy: false })).toBe(false);
  });

  it('a first timezone (none stored) is a pending change', () => {
    expect(
      timezoneSelectionState({ selected: 'Europe/Madrid', stored: null, suggestion: null }).pending
        ?.name,
    ).toBe('Europe/Madrid');
  });
});

describe('canSaveTimezone', () => {
  it('needs an explicit selection that differs from the stored timezone', () => {
    expect(canSaveTimezone({ selected: null, stored: 'Europe/Madrid', busy: false })).toBe(false);
    expect(
      canSaveTimezone({ selected: 'Europe/Madrid', stored: 'Europe/Madrid', busy: false }),
    ).toBe(false);
    expect(
      canSaveTimezone({ selected: 'Atlantic/Canary', stored: 'Europe/Madrid', busy: false }),
    ).toBe(true);
    expect(canSaveTimezone({ selected: 'Europe/Madrid', stored: null, busy: false })).toBe(true);
  });

  it('is disabled while saving', () => {
    expect(canSaveTimezone({ selected: 'Atlantic/Canary', stored: null, busy: true })).toBe(false);
  });
});

describe('timezoneSaveFailure (lost-response reconciliation)', () => {
  it('treats a re-read that already stores the submitted timezone as saved', () => {
    expect(
      timezoneSaveFailure(
        { kind: 'loaded', profile: managed('Atlantic/Canary') },
        'Atlantic/Canary',
      ),
    ).toBe('committed');
  });

  it('reports a failure (e.g. a BR-56 denial) when the timezone did not change', () => {
    expect(
      timezoneSaveFailure({ kind: 'loaded', profile: managed('Europe/Madrid') }, 'Atlantic/Canary'),
    ).toBe('failed');
    expect(timezoneSaveFailure({ kind: 'error' }, 'Atlantic/Canary')).toBe('failed');
    expect(timezoneSaveFailure(null, 'Atlantic/Canary')).toBe('failed');
  });

  it('reports lost access', () => {
    expect(timezoneSaveFailure({ kind: 'unavailable' }, 'Atlantic/Canary')).toBe('accessLost');
  });
});
