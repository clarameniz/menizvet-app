import type { ClinicAppointmentHours } from '@/data/clinic-appointment-hours';
import type { ManagedClinicProfile } from '@/data/clinic-settings';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { ProfessionalCapability } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import type { AppointmentHoursAccess } from '@/lib/appointment-hours';
import { clinicLocalToday } from '@/lib/appointment-time';

/**
 * Pure logic for the professional Clinic settings overview (SPEC-CLI-007
 * BR-7–BR-12). It derives three separate statuses — ready to publish,
 * published, and online Appointment setup complete — from current reads and
 * persists nothing. Everything here is ADVISORY presentation: it never
 * authorizes, blocks, or filters an operation, and online Appointment setup
 * complete never claims that candidate times exist (BR-9).
 */

// ---------------------------------------------------------------------------
// Entry gating (BR-12)
// ---------------------------------------------------------------------------

/** The Clinic self-service capabilities: any one shows Clinic settings (BR-2). */
export const CLINIC_SETTINGS_CAPABILITIES = [
  'CLINIC_MANAGE_PUBLIC_PROFILE',
  'CLINIC_MANAGE_LOCATION',
  'CLINIC_MANAGE_PUBLICATION',
  'CLINIC_MANAGE_OPENING_HOURS',
] as const satisfies readonly ProfessionalCapability[];

/** Offer "Clinic settings" only with a KNOWN Clinic self-service capability (advisory, SPEC-ORG-008 BR-13). */
export function offersClinicSettings(clinic: ProfessionalClinic): boolean {
  return CLINIC_SETTINGS_CAPABILITIES.some((capability) =>
    clinic.capabilities.includes(capability),
  );
}

/** The Clinic settings overview of a Professional Clinic. */
export function clinicSettingsHref(clinicId: string) {
  return {
    pathname: '/professional/clinics/[clinicId]/settings',
    params: { clinicId },
  } as const;
}

/** The Clinic settings editors of this version and the capability each requires (BR-12). */
export type ClinicSettingsEditor = 'profile' | 'location' | 'timezone';

export const CLINIC_SETTINGS_EDITOR_CAPABILITIES: Record<
  ClinicSettingsEditor,
  ProfessionalCapability
> = {
  profile: 'CLINIC_MANAGE_PUBLIC_PROFILE',
  location: 'CLINIC_MANAGE_LOCATION',
  timezone: 'CLINIC_MANAGE_OPENING_HOURS',
};

/** Offer an editor only with its own KNOWN capability (advisory; the write re-authorizes). */
export function offersClinicSettingsEditor(
  clinic: ProfessionalClinic,
  editor: ClinicSettingsEditor,
): boolean {
  return clinic.capabilities.includes(CLINIC_SETTINGS_EDITOR_CAPABILITIES[editor]);
}

export function clinicSettingsEditorHref(clinicId: string, editor: ClinicSettingsEditor) {
  if (editor === 'profile') {
    return {
      pathname: '/professional/clinics/[clinicId]/settings/profile',
      params: { clinicId },
    } as const;
  }
  if (editor === 'location') {
    return {
      pathname: '/professional/clinics/[clinicId]/settings/location',
      params: { clinicId },
    } as const;
  }
  return {
    pathname: '/professional/clinics/[clinicId]/settings/timezone',
    params: { clinicId },
  } as const;
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/** The Appointment hours read (SPEC-APT-013 BR-74), or `unknown` when it could not be read. */
export type SchedulingConfiguration =
  { kind: 'known'; hours: ClinicAppointmentHours } | { kind: 'unknown' };

export type ClinicSettingsInput = {
  clinic: ProfessionalClinic;
  profile: ManagedClinicProfile;
  scheduling: SchedulingConfiguration;
  /** The Organization's APPOINTMENT_MANAGEMENT (SPEC-ORG-007); `null` when the context is unreadable. */
  appointmentManagement: boolean | null;
  /** Whether the Appointment hours editors are editable for this User (advisory). */
  appointmentHoursAccess: AppointmentHoursAccess;
  /**
   * Whether this User may open the Organization's Subscription status
   * (advisory ORGANIZATION_MANAGE_SUBSCRIPTION, SPEC-SUB-002 §15). Never
   * decides Appointment readiness, publication, or Entitlement.
   */
  subscriptionStatusAccess: boolean;
};

// ---------------------------------------------------------------------------
// Timezone and Availability
// ---------------------------------------------------------------------------

/** Whether a stored timezone name is one this device can apply. */
export function isValidTimeZoneName(name: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: name }).format(0);
    return true;
  } catch {
    return false;
  }
}

/**
 * BR-9 condition 4: at least one recurring Appointment availability period,
 * or an OPEN exception dated on or after the Clinic-local `today`. CLOSED
 * exceptions never count; neither do past OPEN exceptions. Without a
 * Clinic-local today (`null`: no valid timezone) no exception counts.
 * Configuration presence only — candidate generation is not reproduced.
 */
export function hasCurrentOrFutureAppointmentAvailability(
  hours: ClinicAppointmentHours,
  today: string | null,
): boolean {
  if (hours.recurringPeriods.length > 0) return true;
  if (today === null) return false;
  return hours.exceptions.some(
    (exception) => exception.kind === 'OPEN' && exception.localDate >= today,
  );
}

// ---------------------------------------------------------------------------
// Derived statuses (BR-7–BR-10)
// ---------------------------------------------------------------------------

/** BR-7 — exactly the backend publication prerequisites. */
export function isReadyToPublish(profile: ManagedClinicProfile): boolean {
  return profile.publicProfile?.displayName != null && profile.location !== null;
}

/** BR-8 — the persisted publication state. */
export function isPublished(profile: ManagedClinicProfile): boolean {
  return profile.isPublished;
}

/** `unknown` only when a definite answer depends on a read that failed. */
export type OnlineAppointmentSetup = 'complete' | 'incomplete' | 'unknown';

type Condition = boolean | null;

/**
 * BR-9 — online Appointment setup complete: published, valid timezone,
 * standard duration, current/future Availability, and APPOINTMENT_MANAGEMENT.
 * A condition known to fail makes it `incomplete`; otherwise any unknown
 * condition (failed scheduling or context read) makes it `unknown`. Never
 * named "bookable", and never used to allow or block anything.
 */
export function onlineAppointmentSetup(conditions: readonly Condition[]): OnlineAppointmentSetup {
  if (conditions.some((condition) => condition === false)) return 'incomplete';
  if (conditions.some((condition) => condition === null)) return 'unknown';
  return 'complete';
}

// ---------------------------------------------------------------------------
// Overview rows (BR-11)
// ---------------------------------------------------------------------------

export type SettingsItemStatus =
  | 'complete'
  | 'missing'
  /** Stored, but not usable (a timezone this device does not recognize). */
  | 'needsAttention'
  /** Depends on a read that failed. */
  | 'unknown'
  | 'published'
  | 'notPublished';

export type SettingsItemKey =
  'profile' | 'location' | 'timezone' | 'duration' | 'appointmentHours' | 'publication';

/**
 * Each row's label, and a short subtitle where the destination covers more
 * than the label alone says: the Profile row opens the whole public profile
 * (name, description, contact details), and the Location row covers both the
 * public address and the map position.
 */
export const SETTINGS_ITEM_COPY: Record<
  SettingsItemKey,
  { labelKey: TranslationKey; supportKey: TranslationKey | null }
> = {
  profile: {
    labelKey: 'clinicSettings.itemProfile',
    supportKey: 'clinicSettings.itemProfileSupport',
  },
  location: {
    labelKey: 'clinicSettings.itemLocation',
    supportKey: 'clinicSettings.itemLocationSupport',
  },
  timezone: { labelKey: 'clinicSettings.itemTimezone', supportKey: null },
  duration: { labelKey: 'clinicSettings.itemDuration', supportKey: null },
  appointmentHours: { labelKey: 'clinicSettings.itemAppointmentHours', supportKey: null },
  publication: { labelKey: 'clinicSettings.itemPublication', supportKey: null },
};

/** Where a row navigates: its editor or the existing Appointment hours screens. */
export type SettingsItemTarget =
  | 'profileEditor'
  | 'locationEditor'
  | 'timezoneEditor'
  | 'appointmentHours'
  | 'durationEditor'
  | null;

export type SettingsItem = {
  key: SettingsItemKey;
  status: SettingsItemStatus;
  /** Whether this User holds the capability that manages this item (advisory). */
  canManage: boolean;
  /** Incomplete and not manageable by this User: suggest asking a Clinic administrator. */
  askAdministrator: boolean;
  target: SettingsItemTarget;
};

export type ClinicSettingsOverview = {
  readyToPublish: boolean;
  published: boolean;
  onlineAppointmentSetup: OnlineAppointmentSetup;
  /** The Organization's plan does not include online Appointment requests. */
  showPlanNotice: boolean;
  /** A secondary read failed: scheduling rows are unknown and a Retry is offered. */
  schedulingUnknown: boolean;
  items: SettingsItem[];
};

const INCOMPLETE_STATUSES: readonly SettingsItemStatus[] = ['missing', 'needsAttention'];

function item(
  key: SettingsItemKey,
  status: SettingsItemStatus,
  canManage: boolean,
  target: SettingsItemTarget = null,
): SettingsItem {
  return {
    key,
    status,
    canManage,
    askAdministrator: !canManage && INCOMPLETE_STATUSES.includes(status),
    target: canManage ? target : null,
  };
}

/**
 * The whole overview for one Clinic at `referenceInstant` (defaults to now;
 * the Clinic-local date decides which exceptions are current or future).
 */
export function clinicSettingsOverview(
  input: ClinicSettingsInput,
  referenceInstant: Date = new Date(),
): ClinicSettingsOverview {
  const { clinic, profile, scheduling, appointmentManagement } = input;
  const can = (capability: ProfessionalCapability) => clinic.capabilities.includes(capability);

  const timezoneName = profile.schedulingTimezoneName;
  const timezoneValid = timezoneName !== null && isValidTimeZoneName(timezoneName);
  const today = timezoneValid ? clinicLocalToday(timezoneName, referenceInstant) : null;

  const hours = scheduling.kind === 'known' ? scheduling.hours : null;
  const hasDuration = hours === null ? null : hours.standardAppointmentDurationMinutes !== null;
  const hasAvailability =
    hours === null ? null : hasCurrentOrFutureAppointmentAvailability(hours, today);

  const manageHours = can('APPOINTMENT_MANAGE_AVAILABILITY');
  const statusOf = (known: boolean | null): SettingsItemStatus =>
    known === null ? 'unknown' : known ? 'complete' : 'missing';

  const items: SettingsItem[] = [
    item(
      'profile',
      statusOf(profile.publicProfile?.displayName != null),
      can('CLINIC_MANAGE_PUBLIC_PROFILE'),
      'profileEditor',
    ),
    item(
      'location',
      statusOf(profile.location !== null),
      can('CLINIC_MANAGE_LOCATION'),
      'locationEditor',
    ),
    item(
      'timezone',
      timezoneName === null ? 'missing' : timezoneValid ? 'complete' : 'needsAttention',
      can('CLINIC_MANAGE_OPENING_HOURS'),
      'timezoneEditor',
    ),
    item(
      'duration',
      statusOf(hasDuration),
      manageHours,
      input.appointmentHoursAccess === 'editable' ? 'durationEditor' : 'appointmentHours',
    ),
    item('appointmentHours', statusOf(hasAvailability), manageHours, 'appointmentHours'),
    item(
      'publication',
      profile.isPublished ? 'published' : 'notPublished',
      can('CLINIC_MANAGE_PUBLICATION'),
    ),
  ];

  return {
    readyToPublish: isReadyToPublish(profile),
    published: isPublished(profile),
    onlineAppointmentSetup: onlineAppointmentSetup([
      profile.isPublished,
      timezoneValid,
      hasDuration,
      hasAvailability,
      appointmentManagement,
    ]),
    showPlanNotice: appointmentManagement === false,
    schedulingUnknown: scheduling.kind === 'unknown',
    items,
  };
}

// ---------------------------------------------------------------------------
// Presentation: status summary and row structure
// ---------------------------------------------------------------------------

/**
 * The two status cards at the top of the overview. They stay separate on
 * purpose (SPEC-CLI-007): whether the public can find the Clinic is not
 * whether the known setup for online Appointment requests is complete, and
 * neither is ever presented as "bookable".
 */
export type ClinicSettingsStatusSummary = {
  visibility: 'published' | 'notPublished';
  onlineAppointments: OnlineAppointmentSetup;
  /** A calm plan notice inside the online card, never a visibility fact. */
  planNotice: boolean;
};

export function clinicSettingsStatusSummary(
  overview: ClinicSettingsOverview,
): ClinicSettingsStatusSummary {
  return {
    visibility: overview.published ? 'published' : 'notPublished',
    onlineAppointments: overview.onlineAppointmentSetup,
    planNotice: overview.showPlanNotice,
  };
}

/** How a row's status reads at a glance; always shown with an icon and a label, not color alone. */
export type SettingsStatusTone = 'positive' | 'attention' | 'neutral';

export const SETTINGS_STATUS_TONE: Record<SettingsItemStatus, SettingsStatusTone> = {
  complete: 'positive',
  missing: 'attention',
  needsAttention: 'attention',
  unknown: 'neutral',
  published: 'positive',
  notPublished: 'neutral',
};

/**
 * Whether a row opens something: only when it has a destination this User
 * may manage. A read-only row shows no chevron and is not a button.
 */
export function isSettingsItemActionable(item: SettingsItem): boolean {
  return item.target !== null;
}

// ---------------------------------------------------------------------------
// Publication action (SPEC-CLI-003 BR-15, BR-16, BR-21)
// ---------------------------------------------------------------------------

/** What publication requires that the Clinic lacks (exactly SPEC-CLI-003 BR-15). */
export type PublicationRequirement = 'profile' | 'location';

/**
 * The publication control the overview offers, from the managed read and the
 * User's advisory CLINIC_MANAGE_PUBLICATION:
 * - `publish` — unpublished and ready to publish;
 * - `publishBlocked` — unpublished but missing a display name and/or a
 *   location; no active Publish, only what to complete. A scheduling timezone
 *   is NOT a requirement (BR-15);
 * - `unpublish` — published;
 * - `none` — the User cannot manage publication; the state is shown read-only.
 * Advisory: the backend re-checks every requirement and capability.
 */
export type PublicationAction =
  | { kind: 'publish' }
  | { kind: 'publishBlocked'; missing: PublicationRequirement[] }
  | { kind: 'unpublish' }
  | { kind: 'none' };

export function publicationAction(input: ClinicSettingsInput): PublicationAction {
  if (!input.clinic.capabilities.includes('CLINIC_MANAGE_PUBLICATION')) return { kind: 'none' };
  const { profile } = input;
  if (profile.isPublished) return { kind: 'unpublish' };
  const missing: PublicationRequirement[] = [];
  if (profile.publicProfile?.displayName == null) missing.push('profile');
  if (profile.location === null) missing.push('location');
  return missing.length === 0 ? { kind: 'publish' } : { kind: 'publishBlocked', missing };
}

/**
 * What a failed Publish or Unpublish means, decided from the fresh overview
 * read that follows it: the publication state already equal to the requested
 * one (a lost response) is success; lost access is reported as such;
 * anything else failed.
 */
export function publicationSaveFailure(
  read:
    | { kind: 'loaded'; profile: ManagedClinicProfile }
    | { kind: 'unavailable' }
    | { kind: 'error' }
    | null,
  requestedPublished: boolean,
): 'committed' | 'accessLost' | 'failed' {
  if (read?.kind === 'unavailable') return 'accessLost';
  if (read?.kind === 'loaded' && read.profile.isPublished === requestedPublished)
    return 'committed';
  return 'failed';
}
