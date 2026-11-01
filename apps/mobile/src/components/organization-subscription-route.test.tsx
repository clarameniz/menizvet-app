import { createElement } from 'react';
import { Alert, Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import OrganizationSubscriptionRoute from '@/app/professional/organizations/[organizationId]/subscription';
import {
  getOrganizationSubscriptionStatus,
  SUBSCRIPTION_STATUS_ACCESS_DENIED,
  type OrganizationSubscription,
  type SubscriptionStatusResult,
} from '@/data/organization-subscription';
import { i18n } from '@/i18n/i18n';

const ORG_A = 'd0310000-0000-4000-8000-00000000a001';
const ORG_B = 'd0310000-0000-4000-8000-00000000b002';
let mockOrganizationId = ORG_A;
let mockFocus: (() => void | (() => void)) | null = null;
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ organizationId: mockOrganizationId }),
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => {
      mockFocus = callback;
      return callback();
    }, [callback]);
  },
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    replace: jest.fn(),
  },
}));
jest.mock('@/components/design-system/app-top-bar', () => {
  const React = jest.requireActual('react');
  const { Pressable } = jest.requireActual('react-native');
  return {
    AppTopBar: ({ onBack }: { onBack: () => void }) =>
      React.createElement(Pressable, { onPress: onBack, testID: 'back' }),
  };
});
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
});
jest.mock('@/data/organization-subscription', () => ({
  ...jest.requireActual('@/data/organization-subscription'),
  getOrganizationSubscriptionStatus: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const read = getOrganizationSubscriptionStatus as jest.Mock;
const all = (value: boolean) => ({
  APPOINTMENT_MANAGEMENT: value,
  PROFESSIONAL_SCHEDULING: value,
  CLINICAL_CARE: value,
  CLINICAL_DOCUMENTATION: value,
});
const ok = (
  id: string,
  subscription: Partial<OrganizationSubscription> | null = {},
  entitled = true,
): SubscriptionStatusResult => ({
  data: {
    organizationId: id,
    organizationDisplayName: `Organization ${id === ORG_A ? 'A' : 'B'}`,
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
  },
  error: null,
});
let tree: ReactTestRenderer;
const content = () =>
  tree.root
    .findAllByType(Text)
    .map((node) => node.props.children)
    .flat()
    .join(' | ');
const t = (key: Parameters<typeof i18n.t>[0]) => i18n.t(key);
async function render(result: SubscriptionStatusResult) {
  read.mockResolvedValueOnce(result);
  await act(async () => {
    tree = create(createElement(OrganizationSubscriptionRoute));
  });
}
beforeEach(() => {
  i18n.locale = 'es';
  mockOrganizationId = ORG_A;
  read.mockReset();
  jest.clearAllMocks();
});
afterEach(() => {
  act(() => tree.unmount());
});

it('shows an open-ended ACTIVE as Active with no end date, and every service available', async () => {
  await render(ok(ORG_A));
  expect(read).toHaveBeenCalledWith(ORG_A);
  expect(content()).toContain('Organization A');
  expect(content()).toContain(t('subscription.stateActive'));
  expect(content()).not.toContain('Válida hasta');
  expect(content()).not.toContain(t('subscription.stateExpired'));
  expect(content().split(t('subscription.serviceAvailable')).length - 1).toBe(4);
});

it('shows a finite current ACTIVE with its end date', async () => {
  await render(ok(ORG_A, { validUntil: '2099-01-01T00:00:00+00:00' }));
  expect(content()).toContain('Válida hasta el');
});

it('shows a lapsed ACTIVE as Active whose validity ended, never as Expired', async () => {
  await render(ok(ORG_A, { validUntil: '2021-01-01T00:00:00+00:00' }, false));
  expect(content()).toContain(t('subscription.stateActive'));
  expect(content()).toContain('Su periodo de validez terminó el');
  expect(content()).not.toContain(t('subscription.stateExpired'));
  expect(content().split(t('subscription.serviceUnavailable')).length - 1).toBe(4);
});

it.each([
  ['PENDING', 'subscription.statePending'],
  ['PAST_DUE', 'subscription.statePastDue'],
  ['CANCELLED', 'subscription.stateCancelled'],
  ['EXPIRED', 'subscription.stateExpired'],
] as const)('shows %s with its calm label', async (state, key) => {
  await render(ok(ORG_A, { state }, false));
  expect(content()).toContain(t(key));
});

it('shows that the Organization has no Subscription', async () => {
  await render(ok(ORG_A, null, false));
  expect(content()).toContain(t('subscription.noSubscription'));
});

it('renders no identifiers, provider data, or plan wording', async () => {
  await render(ok(ORG_A, { state: 'CANCELLED', validUntil: '2099-01-01T00:00:00+00:00' }));
  const text = content();
  expect(text).not.toContain(ORG_A);
  expect(text).not.toMatch(/\bplan\b|cus_|evt|provider|proveedor/i);
});

it('changes Organization A to B without retaining A, ignoring a late A response', async () => {
  let settle!: (value: SubscriptionStatusResult) => void;
  read
    .mockReturnValueOnce(
      new Promise<SubscriptionStatusResult>((resolve) => {
        settle = resolve;
      }),
    )
    .mockResolvedValueOnce(ok(ORG_B, { state: 'PAST_DUE' }, false));
  await act(async () => {
    tree = create(createElement(OrganizationSubscriptionRoute));
  });
  mockOrganizationId = ORG_B;
  await act(async () => {
    tree.update(createElement(OrganizationSubscriptionRoute));
  });
  await act(async () => {
    settle(ok(ORG_A));
  });
  expect(content()).toContain('Organization B');
  expect(content()).toContain(t('subscription.statePastDue'));
  expect(content()).not.toContain('Organization A');
});

it('reflects a recovered Subscription on the next focus without leaving the screen', async () => {
  await render(ok(ORG_A, { state: 'PAST_DUE' }, false));
  read.mockResolvedValueOnce(ok(ORG_A, {}, true));
  await act(async () => {
    mockFocus?.();
  });
  expect(content()).toContain(t('subscription.stateActive'));
  expect(content()).not.toContain(t('subscription.statePastDue'));
});

it('clears commercial content and returns calmly to Professional after losing access', async () => {
  const announcement = jest.spyOn(Alert, 'alert').mockImplementation(() => undefined);
  await render(ok(ORG_A, { state: 'PAST_DUE' }, false));
  read.mockResolvedValueOnce({ data: null, error: SUBSCRIPTION_STATUS_ACCESS_DENIED });
  await act(async () => {
    mockFocus?.();
  });
  expect(content()).not.toContain(t('subscription.statePastDue'));
  expect(content()).not.toContain('Organization A');
  expect(router.dismissTo).toHaveBeenCalledWith('/professional');
  expect(announcement).toHaveBeenCalledWith(t('subscription.title'), t('subscription.unavailable'));
  announcement.mockRestore();
});

it('shows a calm unavailable state for an Organization it may not read', async () => {
  await render({ data: null, error: SUBSCRIPTION_STATUS_ACCESS_DENIED });
  expect(content()).toContain(t('subscription.unavailable'));
  expect(content()).not.toContain(t('subscription.stateActive'));
  expect(router.dismissTo).not.toHaveBeenCalled();
});
