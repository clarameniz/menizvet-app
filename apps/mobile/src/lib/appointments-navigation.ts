import type { Href } from 'expo-router';

/**
 * One Appointment's detail — opened from a "My appointments" row, and
 * where Reschedule returns (after a successful save, via its back control,
 * or from its error state). Always carries the petId the detail needs for
 * its Guardian-scoped re-read.
 */
export function appointmentDetailHref(appointmentId: string, petId: string): Href {
  return `/appointments/${encodeURIComponent(appointmentId)}?petId=${encodeURIComponent(petId)}`;
}

/**
 * Where Appointment detail's back action returns: /appointments, which lists
 * every Pet's Appointments. The `petId` it still carries is ignored by the
 * list (SPEC-APT-011 BR-40).
 */
export function appointmentsListHref(petId: string | null | undefined): Href {
  return petId ? `/appointments?petId=${encodeURIComponent(petId)}` : '/appointments';
}
