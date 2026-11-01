import { appointmentDetailHref, appointmentsListHref } from '@/lib/appointments-navigation';

describe('appointmentDetailHref', () => {
  it('keeps both the appointment id and the petId (post-reschedule target)', () => {
    expect(appointmentDetailHref('apt-1', 'pet-dana')).toBe('/appointments/apt-1?petId=pet-dana');
  });

  it('encodes both values', () => {
    expect(appointmentDetailHref('a/b', 'c&d')).toBe('/appointments/a%2Fb?petId=c%26d');
  });
});

describe('appointmentsListHref', () => {
  it('carries the current petId back to the list', () => {
    expect(appointmentsListHref('pet-dana')).toBe('/appointments?petId=pet-dana');
  });

  it('encodes the petId as a query value', () => {
    expect(appointmentsListHref('a b&c')).toBe('/appointments?petId=a%20b%26c');
  });

  it('is plain /appointments without a petId', () => {
    expect(appointmentsListHref(undefined)).toBe('/appointments');
    expect(appointmentsListHref('')).toBe('/appointments');
  });
});
