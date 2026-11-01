import type { MedicalAccessWithdrawal } from '@/data/appointments';
import {
  medicalAccessConsequenceKeys,
  medicalAccessView,
  medicalAccessWithdrawalNotice,
} from '@/lib/appointment-medical-access';

describe('medicalAccessConsequenceKeys (SPEC-ACC-002 §16)', () => {
  it('states what stays, that documentation of the care given continues, and the irreversibility', () => {
    expect(medicalAccessConsequenceKeys()).toEqual([
      'medicalAccess.consequenceStays',
      'medicalAccess.consequenceClinic',
      'medicalAccess.consequenceIrreversible',
    ]);
  });
});

describe('medicalAccessView (SPEC-APT-011 BR-35)', () => {
  it('offers the withdrawal only while medical access is ACTIVE', () => {
    expect(medicalAccessView('ACTIVE')).toBe('offerWithdrawal');
    expect(medicalAccessView('REVOKED')).toBe('withdrawn');
    expect(medicalAccessView('INACTIVE')).toBe('none');
  });
});

describe('medicalAccessWithdrawalNotice (SPEC-ACC-002 BR-59)', () => {
  const results: MedicalAccessWithdrawal[] = [
    { kind: 'withdrawn' },
    { kind: 'alreadyInactive' },
    { kind: 'unavailable' },
    { kind: 'authenticationRequired' },
    { kind: 'failed' },
  ];

  it.each(results)('a REVOKED re-read needs no notice after %p, never an error', (result) => {
    expect(medicalAccessWithdrawalNotice(result, 'REVOKED')).toBeNull();
  });

  it.each(results)(
    'an INACTIVE re-read is calm after %p (cancellation, no-show or expiry won)',
    (result) => {
      expect(medicalAccessWithdrawalNotice(result, 'INACTIVE')).toEqual({
        tone: 'info',
        messageKey: 'medicalAccess.noLongerActive',
      });
    },
  );

  it('falls back to the operation result when the re-read is unavailable', () => {
    expect(medicalAccessWithdrawalNotice({ kind: 'withdrawn' }, null)).toEqual({
      tone: 'info',
      messageKey: 'medicalAccess.withdrawn',
    });
    expect(medicalAccessWithdrawalNotice({ kind: 'alreadyInactive' }, null)).toEqual({
      tone: 'info',
      messageKey: 'medicalAccess.noLongerActive',
    });
    expect(medicalAccessWithdrawalNotice({ kind: 'unavailable' }, null)).toEqual({
      tone: 'error',
      messageKey: 'medicalAccess.unavailable',
    });
    expect(medicalAccessWithdrawalNotice({ kind: 'authenticationRequired' }, null)).toEqual({
      tone: 'error',
      messageKey: 'errors.sessionExpired',
    });
  });

  it('a failure with access still ACTIVE asks to try again', () => {
    expect(medicalAccessWithdrawalNotice({ kind: 'failed' }, 'ACTIVE')).toEqual({
      tone: 'error',
      messageKey: 'medicalAccess.failed',
    });
  });
});
