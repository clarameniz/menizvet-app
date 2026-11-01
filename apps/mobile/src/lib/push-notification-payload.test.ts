import { parsePushNavigationTarget } from '@/lib/push-notification-payload';

const VALID_APPOINTMENT_ID = '11111111-2222-3333-4444-555555555555';
const VALID_PET_ID = '66666666-7777-8888-9999-aaaaaaaaaaaa';

describe('parsePushNavigationTarget', () => {
  it('accepts a valid appointment payload', () => {
    expect(
      parsePushNavigationTarget({
        route: 'appointment',
        appointment_id: VALID_APPOINTMENT_ID,
        pet_id: VALID_PET_ID,
      }),
    ).toEqual({
      screen: 'appointment',
      appointmentId: VALID_APPOINTMENT_ID,
      petId: VALID_PET_ID,
    });
  });

  it('trims surrounding whitespace from valid ids', () => {
    expect(
      parsePushNavigationTarget({
        route: 'appointment',
        appointment_id: `  ${VALID_APPOINTMENT_ID}  `,
        pet_id: `  ${VALID_PET_ID}  `,
      }),
    ).toEqual({
      screen: 'appointment',
      appointmentId: VALID_APPOINTMENT_ID,
      petId: VALID_PET_ID,
    });
  });

  it('ignores an unknown or future route', () => {
    expect(
      parsePushNavigationTarget({
        route: 'clinic',
        appointment_id: VALID_APPOINTMENT_ID,
        pet_id: VALID_PET_ID,
      }),
    ).toBeNull();
  });

  it('rejects a missing appointment_id', () => {
    expect(parsePushNavigationTarget({ route: 'appointment', pet_id: VALID_PET_ID })).toBeNull();
  });

  it('rejects a missing pet_id', () => {
    expect(
      parsePushNavigationTarget({ route: 'appointment', appointment_id: VALID_APPOINTMENT_ID }),
    ).toBeNull();
  });

  it('rejects a blank pet_id', () => {
    expect(
      parsePushNavigationTarget({
        route: 'appointment',
        appointment_id: VALID_APPOINTMENT_ID,
        pet_id: '   ',
      }),
    ).toBeNull();
  });

  it('rejects a malformed pet_id', () => {
    expect(
      parsePushNavigationTarget({
        route: 'appointment',
        appointment_id: VALID_APPOINTMENT_ID,
        pet_id: 'not-a-uuid',
      }),
    ).toBeNull();
  });

  it('rejects a non-string pet_id', () => {
    expect(
      parsePushNavigationTarget({
        route: 'appointment',
        appointment_id: VALID_APPOINTMENT_ID,
        pet_id: 12345,
      }),
    ).toBeNull();
  });

  it('never builds a path from an arbitrary payload string', () => {
    expect(
      parsePushNavigationTarget({
        route: 'appointment',
        appointment_id: VALID_APPOINTMENT_ID,
        pet_id: '../../etc/passwd',
      }),
    ).toBeNull();
  });

  it('rejects null, undefined, and non-object payloads', () => {
    expect(parsePushNavigationTarget(null)).toBeNull();
    expect(parsePushNavigationTarget(undefined)).toBeNull();
    expect(parsePushNavigationTarget('appointment')).toBeNull();
    expect(parsePushNavigationTarget(42)).toBeNull();
  });
});
