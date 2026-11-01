import type {
  ManagedClinicLocation,
  ManagedClinicProfile,
  ManagedClinicPublicProfile,
} from '@/data/clinic-settings';
import {
  NEUTRAL_MAP_REGION,
  backendTrim,
  canSaveLocation,
  canSaveProfile,
  formatCoordinate,
  locationDraftFrom,
  locationDraftIssues,
  locationMatches,
  locationPayload,
  locationSaveFailure,
  profileDraftFrom,
  profileDraftIssue,
  profileMatches,
  profilePayload,
  profileSaveFailure,
  roundCoordinate,
  storedValueOf,
  withPin,
  type ProfileDraft,
} from '@/lib/clinic-settings-editors';

const FULL_PROFILE: ManagedClinicPublicProfile = {
  displayName: 'Animalia Madrid Centro',
  description: 'Línea uno\nLínea  dos',
  publicPhone: '+34 910 000 001',
  publicEmail: 'centro@example.test',
  website: 'https://centro.example.test',
};

const LOCATION: ManagedClinicLocation = {
  addressText: 'Calle Mayor 1, 28013 Madrid',
  latitude: 40.4168,
  longitude: -3.7038,
};

function managed(overrides: Partial<ManagedClinicProfile> = {}): ManagedClinicProfile {
  return {
    clinicId: 'c-1',
    isPublished: false,
    schedulingTimezoneName: null,
    publicProfile: FULL_PROFILE,
    location: LOCATION,
    ...overrides,
  };
}

describe('backendTrim / storedValueOf', () => {
  it('trims exactly the backend whitespace set: space, tab, LF, CR, FF, VT', () => {
    expect(backendTrim(' \t\n\r\f\u000BAnimalia \t\n\r\f\u000B')).toBe('Animalia');
  });

  it('keeps inner whitespace and line breaks', () => {
    expect(backendTrim('  Línea uno\n\nLínea  dos  ')).toBe('Línea uno\n\nLínea  dos');
  });

  it('keeps Unicode spaces the backend keeps, unlike String.prototype.trim', () => {
    const text = ' Animalia ';
    expect(text.trim()).toBe('Animalia');
    expect(backendTrim(text)).toBe(text);
  });

  it('stores blank as absent (null), and anything else trimmed', () => {
    expect(storedValueOf('')).toBeNull();
    expect(storedValueOf(' \t\n ')).toBeNull();
    expect(storedValueOf(' x ')).toBe('x');
    expect(storedValueOf(' ')).toBe(' ');
  });
});

describe('profile draft', () => {
  it('starts empty for a Clinic without a profile', () => {
    expect(profileDraftFrom(null)).toEqual({
      displayName: '',
      description: '',
      publicPhone: '',
      publicEmail: '',
      website: '',
    });
  });

  it('starts from the stored values, keeping multi-line text exactly', () => {
    expect(profileDraftFrom(FULL_PROFILE)).toEqual({
      displayName: 'Animalia Madrid Centro',
      description: 'Línea uno\nLínea  dos',
      publicPhone: '+34 910 000 001',
      publicEmail: 'centro@example.test',
      website: 'https://centro.example.test',
    });
  });

  it('starts absent values of a partial profile empty', () => {
    expect(profileDraftFrom({ ...FULL_PROFILE, displayName: null, website: null })).toMatchObject({
      displayName: '',
      website: '',
    });
  });

  it('always sends all five values, blank ones as null, so a cleared field is removed', () => {
    const draft: ProfileDraft = {
      ...profileDraftFrom(FULL_PROFILE),
      description: '   ',
      website: '',
    };
    expect(profilePayload(draft)).toEqual({
      displayName: 'Animalia Madrid Centro',
      description: null,
      publicPhone: '+34 910 000 001',
      publicEmail: 'centro@example.test',
      website: null,
    });
  });

  it('applies no format rules: any text is sent as typed, only trimmed', () => {
    expect(
      profilePayload({
        displayName: ' x ',
        description: '',
        publicPhone: 'call us',
        publicEmail: 'not-an-email',
        website: 'example',
      }),
    ).toEqual({
      displayName: 'x',
      description: null,
      publicPhone: 'call us',
      publicEmail: 'not-an-email',
      website: 'example',
    });
  });

  it('treats an absent profile as equal to an all-absent payload', () => {
    expect(profileMatches(null, profilePayload(profileDraftFrom(null)))).toBe(true);
    expect(profileMatches(null, { ...profilePayload(profileDraftFrom(null)), website: 'x' })).toBe(
      false,
    );
  });

  it('compares with backend normalization: surrounding whitespace is not a change', () => {
    const draft = { ...profileDraftFrom(FULL_PROFILE), displayName: '  Animalia Madrid Centro\t' };
    expect(profileMatches(FULL_PROFILE, profilePayload(draft))).toBe(true);
  });
});

describe('profileDraftIssue / canSaveProfile', () => {
  it('lets an unpublished Clinic save without a name', () => {
    const draft = { ...profileDraftFrom(FULL_PROFILE), displayName: '' };
    expect(profileDraftIssue(draft, false)).toBeNull();
    expect(canSaveProfile({ draft, profile: managed(), busy: false })).toBe(true);
  });

  it('requires a name while published, blank-only included', () => {
    const draft = { ...profileDraftFrom(FULL_PROFILE), displayName: ' \t ' };
    expect(profileDraftIssue(draft, true)).toBe('nameRequiredWhilePublished');
    expect(canSaveProfile({ draft, profile: managed({ isPublished: true }), busy: false })).toBe(
      false,
    );
  });

  it('lets a published Clinic clear optional values', () => {
    const draft = { ...profileDraftFrom(FULL_PROFILE), description: '', publicPhone: '' };
    expect(canSaveProfile({ draft, profile: managed({ isPublished: true }), busy: false })).toBe(
      true,
    );
  });

  it('keeps Save disabled while unchanged or saving', () => {
    const draft = profileDraftFrom(FULL_PROFILE);
    expect(canSaveProfile({ draft, profile: managed(), busy: false })).toBe(false);
    const changed = { ...draft, publicPhone: '+34 600 000 000' };
    expect(canSaveProfile({ draft: changed, profile: managed(), busy: true })).toBe(false);
    expect(canSaveProfile({ draft: changed, profile: managed(), busy: false })).toBe(true);
  });

  it('allows clearing every value of an unpublished Clinic (the profile is then removed)', () => {
    const draft = profileDraftFrom(null);
    expect(canSaveProfile({ draft, profile: managed(), busy: false })).toBe(true);
    expect(canSaveProfile({ draft, profile: managed({ publicProfile: null }), busy: false })).toBe(
      false,
    );
  });
});

describe('profileSaveFailure (lost-response reconciliation)', () => {
  const submitted = profilePayload({ ...profileDraftFrom(FULL_PROFILE), publicPhone: '' });

  it('treats a re-read that already stores exactly what was sent as saved', () => {
    expect(
      profileSaveFailure(
        {
          kind: 'loaded',
          profile: managed({ publicProfile: { ...FULL_PROFILE, publicPhone: null } }),
        },
        submitted,
      ),
    ).toBe('committed');
  });

  it('treats an all-absent save whose profile is now gone as saved', () => {
    expect(
      profileSaveFailure(
        { kind: 'loaded', profile: managed({ publicProfile: null }) },
        profilePayload(profileDraftFrom(null)),
      ),
    ).toBe('committed');
  });

  it('reports a failure when the stored values differ — including one stale field', () => {
    expect(profileSaveFailure({ kind: 'loaded', profile: managed() }, submitted)).toBe('failed');
  });

  it('reports lost access when the editor is no longer available', () => {
    expect(profileSaveFailure({ kind: 'unavailable' }, submitted)).toBe('accessLost');
  });

  it('reports a failure, never success, when the re-read fails too', () => {
    expect(profileSaveFailure({ kind: 'error' }, submitted)).toBe('failed');
    expect(profileSaveFailure(null, submitted)).toBe('failed');
  });
});

describe('coordinates', () => {
  it.each([
    [40.41683749, 40.416837],
    [-3.70379851, -3.703799],
    [0, 0],
    [-0.0000001, 0],
    [90, 90],
    [-90, -90],
    [180, 180],
    [-180, -180],
  ])('rounds %p to %p', (value, expected) => {
    expect(roundCoordinate(value)).toBe(expected);
    expect(Object.is(roundCoordinate(value), -0)).toBe(false);
  });

  it('round-trips: a rounded value rounds to itself', () => {
    for (const value of [40.416837, -3.703799, 0.000001, -89.999999, 179.999999]) {
      expect(roundCoordinate(roundCoordinate(value))).toBe(roundCoordinate(value));
    }
  });

  it('formats the position for display and screen readers', () => {
    expect(formatCoordinate({ latitude: 40.4168, longitude: -3.7038 })).toBe(
      '40.416800, -3.703800',
    );
    expect(formatCoordinate({ latitude: 0, longitude: 0 })).toBe('0.000000, 0.000000');
  });
});

describe('location draft', () => {
  it('starts without a pin for a Clinic without a location; the neutral map centre is not a pin', () => {
    const draft = locationDraftFrom(null);
    expect(draft).toEqual({ addressText: '', pin: null });
    expect(locationDraftIssues({ ...draft, addressText: 'Calle 1' })).toEqual(['pinRequired']);
    expect(locationPayload({ ...draft, addressText: 'Calle 1' })).toBeNull();
    expect(
      canSaveLocation({ draft: { ...draft, addressText: 'Calle 1' }, stored: null, busy: false }),
    ).toBe(false);
    // Only an explicit action places a pin — even at the neutral centre.
    const placed = withPin(
      { ...draft, addressText: 'Calle 1' },
      { latitude: NEUTRAL_MAP_REGION.latitude, longitude: NEUTRAL_MAP_REGION.longitude },
    );
    expect(canSaveLocation({ draft: placed, stored: null, busy: false })).toBe(true);
  });

  it('requires both an address and a pin for a new location', () => {
    expect(locationDraftIssues(locationDraftFrom(null))).toEqual([
      'addressRequired',
      'pinRequired',
    ]);
    const pinOnly = withPin(locationDraftFrom(null), { latitude: 40, longitude: -3 });
    expect(locationDraftIssues(pinOnly)).toEqual(['addressRequired']);
    expect(locationDraftIssues({ ...pinOnly, addressText: ' \t ' })).toEqual(['addressRequired']);
  });

  it('starts from a stored location with its pin already confirmed', () => {
    const draft = locationDraftFrom(LOCATION);
    expect(draft).toEqual({
      addressText: 'Calle Mayor 1, 28013 Madrid',
      pin: { latitude: 40.4168, longitude: -3.7038 },
    });
    expect(locationDraftIssues(draft)).toEqual([]);
  });

  it('is unchanged until the address or the pin changes', () => {
    const draft = locationDraftFrom(LOCATION);
    expect(canSaveLocation({ draft, stored: LOCATION, busy: false })).toBe(false);
    expect(
      canSaveLocation({
        draft: { ...draft, addressText: ' Calle Mayor 1, 28013 Madrid\n' },
        stored: LOCATION,
        busy: false,
      }),
    ).toBe(false);
  });

  it('saves an address-only change with the stored pin, without reselecting it', () => {
    const draft = { ...locationDraftFrom(LOCATION), addressText: 'Calle Mayor 3, 28013 Madrid' };
    expect(canSaveLocation({ draft, stored: LOCATION, busy: false })).toBe(true);
    expect(locationPayload(draft)).toEqual({
      addressText: 'Calle Mayor 3, 28013 Madrid',
      latitude: 40.4168,
      longitude: -3.7038,
    });
  });

  it('saves a pin-only change, rounded', () => {
    const draft = withPin(locationDraftFrom(LOCATION), {
      latitude: 40.41712345678,
      longitude: -3.70456789123,
    });
    expect(canSaveLocation({ draft, stored: LOCATION, busy: false })).toBe(true);
    expect(locationPayload(draft)).toEqual({
      addressText: 'Calle Mayor 1, 28013 Madrid',
      latitude: 40.417123,
      longitude: -3.704568,
    });
  });

  it('does not count a sub-precision pin movement as a change', () => {
    const draft = withPin(locationDraftFrom(LOCATION), {
      latitude: 40.41680000004,
      longitude: -3.70380000004,
    });
    expect(canSaveLocation({ draft, stored: LOCATION, busy: false })).toBe(false);
  });

  it('treats a stored location with more precision as unchanged when only re-confirmed', () => {
    const precise = { ...LOCATION, latitude: 40.416837492, longitude: -3.703798512 };
    expect(
      canSaveLocation({ draft: locationDraftFrom(precise), stored: precise, busy: false }),
    ).toBe(false);
  });

  it('allows 0,0 and the range boundaries (no plausibility rule)', () => {
    for (const pin of [
      { latitude: 0, longitude: 0 },
      { latitude: 90, longitude: 180 },
      { latitude: -90, longitude: -180 },
    ]) {
      expect(locationDraftIssues(withPin({ addressText: 'X', pin: null }, pin))).toEqual([]);
    }
  });

  it('refuses a pin outside the valid ranges', () => {
    expect(
      locationDraftIssues(withPin({ addressText: 'X', pin: null }, { latitude: 91, longitude: 0 })),
    ).toEqual(['pinOutOfRange']);
    expect(
      locationPayload(
        withPin({ addressText: 'X', pin: null }, { latitude: 0, longitude: Number.NaN }),
      ),
    ).toBeNull();
  });

  it('keeps Save disabled while saving', () => {
    const draft = { ...locationDraftFrom(LOCATION), addressText: 'Otra' };
    expect(canSaveLocation({ draft, stored: LOCATION, busy: true })).toBe(false);
  });
});

describe('locationMatches / locationSaveFailure (lost-response reconciliation)', () => {
  const draft = withPin(
    { addressText: ' Calle Nueva 2 ', pin: null },
    {
      latitude: 40.12345678,
      longitude: -3.87654321,
    },
  );
  const submitted = locationPayload(draft) as ManagedClinicLocation;

  it('matches the stored location after the save, despite float representation', () => {
    // What the database returns for the rounded values that were sent.
    const stored = { addressText: 'Calle Nueva 2', latitude: 40.123457, longitude: -3.876543 };
    expect(locationMatches(stored, submitted)).toBe(true);
    expect(
      locationSaveFailure({ kind: 'loaded', profile: managed({ location: stored }) }, submitted),
    ).toBe('committed');
  });

  it('reports a failure when nothing or something else is stored', () => {
    expect(locationMatches(null, submitted)).toBe(false);
    expect(
      locationSaveFailure({ kind: 'loaded', profile: managed({ location: null }) }, submitted),
    ).toBe('failed');
    expect(locationSaveFailure({ kind: 'loaded', profile: managed() }, submitted)).toBe('failed');
  });

  it('reports lost access, and never success when the re-read fails', () => {
    expect(locationSaveFailure({ kind: 'unavailable' }, submitted)).toBe('accessLost');
    expect(locationSaveFailure({ kind: 'error' }, submitted)).toBe('failed');
    expect(locationSaveFailure(null, submitted)).toBe('failed');
  });
});

describe('a Clinic with no stored location, step by step', () => {
  it('never saves without both an address and an explicitly placed pin', () => {
    // Opening the editor: no pin is fabricated; the neutral map region is presentation only.
    let draft = locationDraftFrom(null);
    expect(draft.pin).toBeNull();
    expect(canSaveLocation({ draft, stored: null, busy: false })).toBe(false);

    // Address alone is not enough.
    draft = { ...draft, addressText: 'Calle Mayor 1, Madrid' };
    expect(locationDraftIssues(draft)).toEqual(['pinRequired']);
    expect(canSaveLocation({ draft, stored: null, busy: false })).toBe(false);

    // A pin alone is not enough either.
    const pinOnly = withPin(locationDraftFrom(null), { latitude: 40.4168, longitude: -3.7038 });
    expect(canSaveLocation({ draft: pinOnly, stored: null, busy: false })).toBe(false);

    // An explicit pin (map tap, drag, or "place at the centre") with an address enables Save.
    draft = withPin(draft, { latitude: 40.41683749, longitude: -3.70379851 });
    expect(canSaveLocation({ draft, stored: null, busy: false })).toBe(true);
    const submitted = locationPayload(draft) as ManagedClinicLocation;
    expect(submitted).toEqual({
      addressText: 'Calle Mayor 1, Madrid',
      latitude: 40.416837,
      longitude: -3.703799,
    });

    // After saving and reopening, the stored location is a confirmed pin with nothing to save.
    const reopened = locationDraftFrom(submitted);
    expect(reopened).toEqual({
      addressText: 'Calle Mayor 1, Madrid',
      pin: { latitude: 40.416837, longitude: -3.703799 },
    });
    expect(canSaveLocation({ draft: reopened, stored: submitted, busy: false })).toBe(false);
  });

  it('keeps the neutral map region independent from the draft', () => {
    expect(NEUTRAL_MAP_REGION).toEqual({
      latitude: 0,
      longitude: 0,
      latitudeDelta: 80,
      longitudeDelta: 80,
    });
    expect(locationDraftFrom(null)).toEqual({ addressText: '', pin: null });
  });
});
