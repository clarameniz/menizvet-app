import { Stack } from 'expo-router';

/**
 * Plain header-less Stack for the professional routes (`/professional`,
 * `/professional/clinics`, `/professional/clinics/[clinicId]`,
 * `/professional/clinics/[clinicId]/calendar` (the agenda: Calendar, Pending, History),
 * `/professional/clinics/[clinicId]/appointments/[appointmentId]`,
 * `/professional/clinics/[clinicId]/appointments/[appointmentId]/reschedule`,
 * `/professional/clinics/[clinicId]/appointments/[appointmentId]/alternative-time`,
 * `/professional/clinics/[clinicId]/appointment-hours`, and its
 * `/duration`, `/weekly`, and `/exception` editors,
 * `/professional/clinics/[clinicId]/settings`, and its `/profile`,
 * `/location`, and `/timezone` editors),
 * same as pets/_layout.tsx.
 * Registered under the authenticated guard in the root layout.
 */
export default function ProfessionalLayout() {
  return <Stack screenOptions={{ headerShown: false }} />;
}
