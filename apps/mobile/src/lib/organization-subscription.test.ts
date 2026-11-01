import type {
  OrganizationSubscription,
  OrganizationSubscriptionStatus,
} from '@/data/organization-subscription';
import type {
  OrganizationProfessionalContext,
  ProfessionalCapability,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import {
  offersOrganizationSubscription,
  organizationSubscriptionHref,
  subscriptionStatusView,
  type SubscriptionStatusView,
} from '@/lib/organization-subscription';

const NOW = new Date('2026-10-13T12:00:00Z');
const PAST = '2026-09-01T00:00:00+00:00';
const FUTURE = '2026-12-01T00:00:00+00:00';
const all = (value: boolean) => ({
  APPOINTMENT_MANAGEMENT: value,
  PROFESSIONAL_SCHEDULING: value,
  CLINICAL_CARE: value,
  CLINICAL_DOCUMENTATION: value,
});
const status = (
  subscription: Partial<OrganizationSubscription> | null,
  entitled = false,
): OrganizationSubscriptionStatus => ({
  organizationId: 'A',
  organizationDisplayName: 'Org A',
  subscription:
    subscription === null
      ? null
      : {
          state: 'ACTIVE',
          stateEffectiveAt: '2020-01-01T00:00:00+00:00',
          validFrom: null,
          validUntil: null,
          ...subscription,
        },
  entitlements: all(entitled),
});
const keys = (view: SubscriptionStatusView) => view.lines.map((line) => line.key);
const organization = (
  capabilities: { capability: ProfessionalCapability; clinic?: boolean }[],
): OrganizationProfessionalContext => ({
  organizationId: 'A',
  membershipId: 'm-A',
  organizationDisplayName: 'Org A',
  responsibilities: [],
  unknownCapabilities: [],
  clinicAssignments: [],
  entitlements: all(true),
  capabilities: capabilities.map(({ capability, clinic }) => ({
    capability,
    scope: clinic
      ? { type: 'CLINIC' as const, clinic: { clinicId: 'c', displayName: 'C' } }
      : { type: 'ORGANIZATION' as const },
  })),
});

describe('offersOrganizationSubscription', () => {
  it('offers the status only with Organization-scoped ORGANIZATION_MANAGE_SUBSCRIPTION', () => {
    expect(
      offersOrganizationSubscription(
        organization([{ capability: 'ORGANIZATION_MANAGE_SUBSCRIPTION' }]),
      ),
    ).toBe(true);
    expect(
      offersOrganizationSubscription(organization([{ capability: 'ORGANIZATION_INVITE_MEMBERS' }])),
    ).toBe(false);
    expect(
      offersOrganizationSubscription(
        organization([{ capability: 'APPOINTMENT_CONFIRM', clinic: true }]),
      ),
    ).toBe(false);
    expect(
      offersOrganizationSubscription(
        organization([{ capability: 'ORGANIZATION_MANAGE_SUBSCRIPTION', clinic: true }]),
      ),
    ).toBe(false);
    expect(offersOrganizationSubscription(organization([]))).toBe(false);
  });
  it('links to the explicit Organization route', () => {
    expect(organizationSubscriptionHref('A')).toEqual({
      pathname: '/professional/organizations/[organizationId]/subscription',
      params: { organizationId: 'A' },
    });
  });
});

describe('subscriptionStatusView', () => {
  it('shows an open-ended ACTIVE simply as Active, with no end or renewal date', () => {
    const view = subscriptionStatusView(status({}, true), NOW);
    expect(view.stateKey).toBe('subscription.stateActive');
    expect(view.tone).toBe('positive');
    expect(keys(view)).toEqual(['subscription.since']);
  });
  it('shows a finite current ACTIVE with its validity dates', () => {
    const view = subscriptionStatusView(status({ validFrom: PAST, validUntil: FUTURE }, true), NOW);
    expect(view.lines).toEqual([
      { key: 'subscription.since', date: '2020-01-01T00:00:00+00:00' },
      { key: 'subscription.validFrom', date: PAST },
      { key: 'subscription.validUntil', date: FUTURE },
    ]);
  });
  it('keeps a lapsed ACTIVE as Active and says its validity ended, never Expired', () => {
    const view = subscriptionStatusView(status({ validUntil: PAST }, false), NOW);
    expect(view.stateKey).toBe('subscription.stateActive');
    expect(view.stateKey).not.toBe('subscription.stateExpired');
    expect(view.lines).toContainEqual({ key: 'subscription.validityEnded', date: PAST });
    expect(view.tone).toBe('attention');
    expect(view.services.every((service) => !service.available)).toBe(true);
  });
  it('says when a future validity has not started yet', () => {
    expect(keys(subscriptionStatusView(status({ validFrom: FUTURE }), NOW))).toContain(
      'subscription.notStarted',
    );
  });
  it.each([
    ['PENDING', 'subscription.statePending', 'subscription.pendingNote'],
    ['PAST_DUE', 'subscription.statePastDue', 'subscription.pastDueNote'],
    ['EXPIRED', 'subscription.stateExpired', 'subscription.expiredNote'],
  ] as const)('labels %s calmly', (state, stateKey, note) => {
    const view = subscriptionStatusView(status({ state }), NOW);
    expect(view.stateKey).toBe(stateKey);
    expect(keys(view)).toEqual(['subscription.since', note]);
  });
  it('distinguishes CANCELLED within, after, and without validity', () => {
    expect(
      keys(subscriptionStatusView(status({ state: 'CANCELLED', validUntil: FUTURE }, true), NOW)),
    ).toContain('subscription.cancelledUntil');
    expect(
      keys(subscriptionStatusView(status({ state: 'CANCELLED', validUntil: PAST }), NOW)),
    ).toContain('subscription.cancelledEnded');
    expect(keys(subscriptionStatusView(status({ state: 'CANCELLED' }), NOW))).toContain(
      'subscription.cancelledNoCoverage',
    );
  });
  it('reports that the Organization never had a Subscription', () => {
    const view = subscriptionStatusView(status(null), NOW);
    expect(view.stateKey).toBeNull();
    expect(keys(view)).toEqual(['subscription.noSubscription']);
  });
  it('reports every service from the Entitlements, separately from the state', () => {
    const view = subscriptionStatusView(
      {
        ...status({ state: 'PAST_DUE' }),
        entitlements: { ...all(false), CLINICAL_CARE: true },
      },
      NOW,
    );
    expect(view.services).toEqual([
      { labelKey: 'subscription.serviceAppointments', available: false },
      { labelKey: 'subscription.serviceScheduling', available: false },
      { labelKey: 'subscription.serviceClinicalCare', available: true },
      { labelKey: 'subscription.serviceClinicalDocumentation', available: false },
    ]);
  });
});

describe('commercial copy (SPEC-SUB-003 §15)', () => {
  afterEach(() => {
    i18n.locale = 'es';
  });
  it.each(['es', 'en'])('never attributes unavailability to a plan (%s)', (locale) => {
    i18n.locale = locale;
    for (const key of [
      'clinicSettings.planNotice',
      'appointmentConfirmation.entitlementDenied',
      'appointmentErrors.entitlementDenied',
    ] as const) {
      expect(i18n.t(key)).not.toMatch(/\bplan\b/i);
    }
  });
  it.each([
    ['es', 'No hay citas en línea disponibles para este periodo.'],
    ['en', 'There are no online appointment times available for this period.'],
  ])('shows one generic, reason-agnostic empty availability message (%s)', (locale, text) => {
    i18n.locale = locale;
    const empty = i18n.t('appointmentRequest.noRequestableDatesError');
    expect(empty).toBe(text);
    expect(empty).not.toMatch(
      /suscripci|subscription|pago|payment|plan|factur|billing|past.due|caduc|expir|entitlement|servicio|service|no está aceptando|not .*accepting/i,
    );
  });
  it.each(['es', 'en'])('keeps the Guardian message non-commercial (%s)', (locale) => {
    i18n.locale = locale;
    const text = i18n.t('appointmentErrors.entitlementDenied');
    expect(text).toMatch(locale === 'es' ? /en línea/ : /online/);
    expect(text).not.toMatch(/suscripci|subscription|pago|payment|factur|billing|past.due/i);
  });
});
