import {
  getOrganizationSubscriptionStatus,
  parseOrganizationSubscriptionStatus,
  SUBSCRIPTION_STATUS_ACCESS_DENIED,
  SUBSCRIPTION_STATUS_MALFORMED,
} from '@/data/organization-subscription';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;
const A = 'd0310000-0000-4000-8000-000000003001';
const B = 'd0310000-0000-4000-8000-000000003002';
const entitlements = (value: boolean) => ({
  APPOINTMENT_MANAGEMENT: value,
  PROFESSIONAL_SCHEDULING: value,
  CLINICAL_CARE: value,
  CLINICAL_DOCUMENTATION: value,
});
const payload = (
  subscription: unknown = {
    state: 'ACTIVE',
    state_effective_at: '2020-01-01T00:00:00+00:00',
    valid_from: null,
    valid_until: null,
  },
): Record<string, unknown> => ({
  organization_id: A,
  organization_display_name: 'Org A',
  subscription,
  entitlements: entitlements(true),
});
beforeEach(() => rpc.mockReset());

it('parses an open-ended ACTIVE status with its Entitlements', () => {
  expect(parseOrganizationSubscriptionStatus(payload(), A)).toEqual({
    organizationId: A,
    organizationDisplayName: 'Org A',
    subscription: {
      state: 'ACTIVE',
      stateEffectiveAt: '2020-01-01T00:00:00+00:00',
      validFrom: null,
      validUntil: null,
    },
    entitlements: entitlements(true),
  });
});

it.each(['PENDING', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED'])(
  'accepts the stored state %s with finite validity',
  (state) => {
    const parsed = parseOrganizationSubscriptionStatus(
      payload({
        state,
        state_effective_at: '2021-01-01T00:00:00+00:00',
        valid_from: '2020-01-01T00:00:00+00:00',
        valid_until: '2030-01-01T00:00:00+00:00',
      }),
      A,
    );
    expect(parsed?.subscription?.state).toBe(state);
    expect(parsed?.subscription?.validUntil).toBe('2030-01-01T00:00:00+00:00');
  },
);

it('accepts an Organization that never had a Subscription', () => {
  expect(parseOrganizationSubscriptionStatus(payload(null), A)?.subscription).toBeNull();
});

it.each([
  [
    'an unknown state',
    {
      ...payload(),
      subscription: {
        state: 'GRACE',
        state_effective_at: '2020-01-01T00:00:00Z',
        valid_from: null,
        valid_until: null,
      },
    },
  ],
  ['a provider reference member', { ...payload(), provider_references: ['cus_123'] }],
  [
    'a source event member inside the subscription',
    payload({
      state: 'ACTIVE',
      state_effective_at: '2020-01-01T00:00:00Z',
      valid_from: null,
      valid_until: null,
      source_event_key: 'evt',
    }),
  ],
  [
    'a subscription id',
    payload({
      id: B,
      state: 'ACTIVE',
      state_effective_at: '2020-01-01T00:00:00Z',
      valid_from: null,
      valid_until: null,
    }),
  ],
  ['a missing Entitlement', { ...payload(), entitlements: { APPOINTMENT_MANAGEMENT: true } }],
  [
    'a non-boolean Entitlement',
    { ...payload(), entitlements: { ...entitlements(true), CLINICAL_CARE: 'yes' } },
  ],
  [
    'an extra Entitlement',
    { ...payload(), entitlements: { ...entitlements(true), BILLING: true } },
  ],
  [
    'an invalid validity instant',
    payload({
      state: 'ACTIVE',
      state_effective_at: '2020-01-01T00:00:00Z',
      valid_from: null,
      valid_until: 'soon',
    }),
  ],
  ['a blank Organization name', { ...payload(), organization_display_name: ' ' }],
])('rejects %s', (_label, raw) => {
  expect(parseOrganizationSubscriptionStatus(raw, A)).toBeNull();
});

it('rejects a payload describing another Organization', () => {
  expect(parseOrganizationSubscriptionStatus(payload(), B)).toBeNull();
});

it('reads only the explicit route Organization through the status RPC', async () => {
  rpc.mockResolvedValueOnce({ data: payload(), error: null });
  const result = await getOrganizationSubscriptionStatus(A);
  expect(rpc).toHaveBeenCalledWith('get_organization_subscription_status', {
    p_organization_id: A,
  });
  expect(result.error).toBeNull();
});

it('maps 42501 to access denied, 28000 to session expiry, and malformed payloads', async () => {
  rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'denied' } });
  expect((await getOrganizationSubscriptionStatus(A)).error).toBe(
    SUBSCRIPTION_STATUS_ACCESS_DENIED,
  );
  rpc.mockResolvedValueOnce({ data: null, error: { code: '28000', message: 'auth' } });
  expect((await getOrganizationSubscriptionStatus(A)).error).toBe(
    PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  );
  rpc.mockResolvedValueOnce({ data: { ...payload(), extra: 1 }, error: null });
  expect((await getOrganizationSubscriptionStatus(A)).error).toBe(SUBSCRIPTION_STATUS_MALFORMED);
});

it('never calls the RPC for a malformed Organization id', async () => {
  expect((await getOrganizationSubscriptionStatus('not-an-id')).error).toBe(
    SUBSCRIPTION_STATUS_ACCESS_DENIED,
  );
  expect(rpc).not.toHaveBeenCalled();
});
