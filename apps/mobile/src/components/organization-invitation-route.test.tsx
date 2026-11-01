import { createElement } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';
import * as SecureStore from 'expo-secure-store';

import OrganizationInvitationAcceptRoute from '@/app/invitations/organization/accept';
import {
  acceptOrganizationInvitation,
  previewOrganizationInvitation,
  type InvitationAcceptanceResult,
  type InvitationPreview,
  type InvitationPreviewResult,
} from '@/data/organization-invitations';
import { getMyProfessionalContext, type ProfessionalContext } from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import {
  isOrganizationInvitationScreenMounted,
  routeIncomingSystemPath,
  takeStagedOrganizationInvitationLink,
} from '@/lib/organization-invitation-intake';
import {
  clearPendingOrganizationInvitation,
  hasPendingOrganizationInvitation,
  readPendingOrganizationInvitation,
} from '@/lib/pending-organization-invitation';
import { getProfessionalOrganizationSelection } from '@/lib/professional-organization-selection';

// No useLocalSearchParams: the route must never read the link from params.
jest.mock('expo-router', () => ({ router: { push: jest.fn(), replace: jest.fn() } }));
jest.mock('expo-secure-store', () => {
  const values = new Map<string, string>();
  return {
    __values: values,
    getItemAsync: jest.fn(async (key: string) => values.get(key) ?? null),
    setItemAsync: jest.fn(async (key: string, value: string) => {
      values.set(key, value);
    }),
    deleteItemAsync: jest.fn(async (key: string) => {
      values.delete(key);
    }),
  };
});
type MockSession = {
  session: object | null;
  user: { id: string; email_confirmed_at: string | null } | null;
  isLoading: boolean;
  isPasswordRecovery: boolean;
};
let mockSession: MockSession;
jest.mock('@/lib/session-provider', () => ({ useSession: () => mockSession }));
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
});
jest.mock('@/components/design-system/brand-mark', () => ({ BrandMark: () => null }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
jest.mock('@/data/organization-invitations', () => ({
  ...jest.requireActual('@/data/organization-invitations'),
  previewOrganizationInvitation: jest.fn(),
  acceptOrganizationInvitation: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));

const preview = previewOrganizationInvitation as jest.Mock;
const accept = acceptOrganizationInvitation as jest.Mock;
const context = getMyProfessionalContext as jest.Mock;
const storeValues = (SecureStore as unknown as { __values: Map<string, string> }).__values;
const KEY = 'menizvet.pendingOrganizationInvitation.v1';

const ID = '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f';
const SECRET = 'U2VjcmV0VGhhdE11c3ROZXZlckxlYWstMDEyMzQ1Njc4OQ';
const NEW_ID = '9b8a7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
const NEW_SECRET = 'QW5vdGhlclNlY3JldFRoYXRNdXN0TmV2ZXJMZWFr';
const ORG = '11111111-2222-4333-8444-555555555555';
const MEMBERSHIP = '66666666-7777-4888-8999-aaaaaaaaaaaa';
const link = (id = ID, secret = SECRET) =>
  `https://app.menizvet.com/invitations/organization/accept?invitation=${id}#secret=${secret}`;

const t = (key: string, options?: Record<string, string>) => i18n.t(key, options);
const SIGNED_IN: MockSession = {
  session: {},
  user: { id: 'user-1', email_confirmed_at: '2020-01-01T00:00:00Z' },
  isLoading: false,
  isPasswordRecovery: false,
};
const SIGNED_OUT: MockSession = {
  session: null,
  user: null,
  isLoading: false,
  isPasswordRecovery: false,
};

const pendingPreview = (overrides: Partial<InvitationPreview> = {}): InvitationPreviewResult => ({
  kind: 'preview',
  preview: {
    invitationId: ID,
    state: 'PENDING',
    organizationDisplayName: 'Animalia Group',
    responsibilities: [
      {
        responsibility: 'ADMINISTRATOR',
        scope: { type: 'CLINIC', clinic: { clinicId: 'c1', displayName: 'Animalia Centro' } },
      },
    ],
    maskedRecipientEmail: 'c***@example.com',
    invitedEmailMatchesCurrentAccount: true,
    expiresAt: '2030-01-08T10:00:00Z',
    ...overrides,
  },
});
const accepted = (
  outcome: 'ACCEPTED' | 'ALREADY_ACCEPTED' = 'ACCEPTED',
): InvitationAcceptanceResult => ({
  kind: 'accepted',
  outcome,
  organizationId: ORG,
  membershipId: MEMBERSHIP,
});
const contextWithMembership = (): { data: ProfessionalContext; error: null } => ({
  data: {
    hasVeterinarianProfessionalProfile: false,
    organizations: [
      {
        membershipId: MEMBERSHIP,
        organizationId: ORG,
        organizationDisplayName: 'Animalia Group',
        responsibilities: [],
        capabilities: [],
        unknownCapabilities: [],
        clinicAssignments: [],
        entitlements: {
          APPOINTMENT_MANAGEMENT: true,
          PROFESSIONAL_SCHEDULING: true,
          CLINICAL_CARE: false,
          CLINICAL_DOCUMENTATION: false,
        },
      },
    ],
  },
  error: null,
});

let tree: ReactTestRenderer | null;
let consoleSpies: jest.SpyInstance[];
const rendered = () => JSON.stringify(tree?.toJSON() ?? null);
const hasText = (text: string) => rendered().includes(JSON.stringify(text).slice(1, -1));
const buttonsLabelled = (label: string) =>
  tree!.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityLabel === label &&
      typeof node.props.onPress === 'function',
  );
const press = async (label: string) => {
  const [button] = buttonsLabelled(label);
  if (!button) throw new Error(`No button ${label}`);
  await act(async () => {
    button.props.onPress();
  });
  await settle();
};
const isDisabled = (label: string) => buttonsLabelled(label)[0]?.props.accessibilityState?.disabled;
async function settle() {
  for (let i = 0; i < 12; i += 1) {
    await act(async () => {
      await Promise.resolve();
    });
  }
}
async function render() {
  await act(async () => {
    tree = create(createElement(OrganizationInvitationAcceptRoute));
  });
  await settle();
}
async function rerender() {
  await act(async () => {
    tree!.update(createElement(OrganizationInvitationAcceptRoute));
  });
  await settle();
}
const storedProof = () => {
  const raw = storeValues.get(KEY);
  return raw === undefined ? null : JSON.parse(raw);
};

beforeEach(async () => {
  tree = null;
  mockSession = SIGNED_IN;
  takeStagedOrganizationInvitationLink();
  await clearPendingOrganizationInvitation();
  storeValues.clear();
  jest.clearAllMocks();
  preview.mockResolvedValue(pendingPreview());
  accept.mockResolvedValue(accepted());
  context.mockResolvedValue(contextWithMembership());
  consoleSpies = (['log', 'info', 'warn', 'error', 'debug'] as const).map((method) =>
    jest.spyOn(console, method),
  );
});

afterEach(async () => {
  // Security (SPEC-ORG-003 Note 33): the secret never reaches navigation,
  // logs, or anything rendered.
  for (const secret of [SECRET, NEW_SECRET]) {
    expect(JSON.stringify((router.push as jest.Mock).mock.calls)).not.toContain(secret);
    expect(JSON.stringify((router.replace as jest.Mock).mock.calls)).not.toContain(secret);
    expect(JSON.stringify(consoleSpies.map((spy) => spy.mock.calls))).not.toContain(secret);
    expect(rendered()).not.toContain(secret);
  }
  consoleSpies.forEach((spy) => spy.mockRestore());
  if (tree) {
    await act(async () => {
      tree!.unmount();
    });
  }
  expect(isOrganizationInvitationScreenMounted()).toBe(false);
});

describe('signed out', () => {
  it('stores only the proof, shows generic copy and no Invitation detail, and never previews', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();

    expect(storedProof()).toEqual({ version: 1, invitationId: ID, secret: SECRET });
    expect(hasText(t('organizationInvitation.signedOutBody'))).toBe(true);
    expect(rendered()).not.toContain('Animalia');
    expect(preview).not.toHaveBeenCalled();
    expect(buttonsLabelled(t('organizationInvitation.signIn'))).toHaveLength(1);
    expect(buttonsLabelled(t('organizationInvitation.createAccount'))).toHaveLength(1);
    expect(buttonsLabelled(t('organizationInvitation.notNow'))).toHaveLength(1);
  });

  it('opens sign-in and registration without clearing the proof, then resumes once signed in', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();

    await press(t('organizationInvitation.signIn'));
    expect(router.push).toHaveBeenLastCalledWith('/sign-in');
    await press(t('organizationInvitation.createAccount'));
    expect(router.push).toHaveBeenLastCalledWith('/register');
    expect(storedProof()).toEqual({ version: 1, invitationId: ID, secret: SECRET });

    mockSession = SIGNED_IN;
    await rerender();

    expect(preview).toHaveBeenCalledWith({ invitationId: ID, secret: SECRET });
    expect(
      hasText(t('organizationInvitation.reviewTitle', { organization: 'Animalia Group' })),
    ).toBe(true);
    expect(accept).not.toHaveBeenCalled();
  });

  it('survives the screen unmounting (app restart) and resumes from the secure store', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();
    await act(async () => {
      tree!.unmount();
    });
    tree = null;
    expect(storedProof()).not.toBeNull();

    mockSession = SIGNED_IN;
    await render();

    expect(preview).toHaveBeenCalledWith({ invitationId: ID, secret: SECRET });
    expect(hasText(t('organizationInvitation.accept'))).toBe(true);
  });

  it('"Not now" clears the keystore proof, leaves to the signed-out landing and calls no RPC', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();

    await press(t('organizationInvitation.notNow'));

    expect(storedProof()).toBeNull();
    expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith(KEY);
    expect(router.replace).toHaveBeenCalledTimes(1);
    expect(router.replace).toHaveBeenCalledWith('/(auth)');
    expect(router.replace).not.toHaveBeenCalledWith('/');
    expect(preview).not.toHaveBeenCalled();
    expect(accept).not.toHaveBeenCalled();
  });

  it('"Not now" also clears an in-process proof kept after a failed keystore write', async () => {
    mockSession = SIGNED_OUT;
    (SecureStore.setItemAsync as jest.Mock).mockRejectedValueOnce(new Error('write failed'));
    const warn = consoleSpies[2];
    warn.mockImplementation(() => {});
    routeIncomingSystemPath(link());
    await render();
    expect(storedProof()).toBeNull();
    await expect(readPendingOrganizationInvitation()).resolves.toEqual({
      invitationId: ID,
      secret: SECRET,
    });

    await press(t('organizationInvitation.notNow'));

    await expect(readPendingOrganizationInvitation()).resolves.toBeNull();
    expect(router.replace).toHaveBeenCalledWith('/(auth)');
  });

  it('"Not now" twice navigates once and cannot error', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();
    const [button] = buttonsLabelled(t('organizationInvitation.notNow'));

    await act(async () => {
      button.props.onPress();
      button.props.onPress();
    });
    await settle();

    expect(router.replace).toHaveBeenCalledTimes(1);
    expect(storedProof()).toBeNull();
  });

  it('"Not now" while signed in leaves to the signed-in landing', async () => {
    routeIncomingSystemPath(link());
    await render();

    await press(t('organizationInvitation.notNow'));

    expect(router.replace).toHaveBeenCalledWith('/(app)');
    expect(storedProof()).toBeNull();
    expect(accept).not.toHaveBeenCalled();
  });

  it('after "Not now" a reopened app and a later sign-in do not restore the Invitation', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.notNow'));
    await act(async () => {
      tree!.unmount();
    });
    tree = null;

    await expect(hasPendingOrganizationInvitation()).resolves.toBe(false);
    mockSession = SIGNED_IN;
    await render();

    expect(preview).not.toHaveBeenCalled();
    expect(hasText(t('organizationInvitation.unavailableBody'))).toBe(true);
  });

  it('after "Not now" the same email link is captured and stored again normally', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.notNow'));
    await act(async () => {
      tree!.unmount();
    });
    tree = null;

    routeIncomingSystemPath(link());
    await render();

    expect(storedProof()).toEqual({ version: 1, invitationId: ID, secret: SECRET });
    expect(hasText(t('organizationInvitation.signedOutBody'))).toBe(true);
    expect(buttonsLabelled(t('organizationInvitation.notNow'))).toHaveLength(1);
  });

  it('closing a terminal state while signed out goes to the signed-out landing', async () => {
    mockSession = SIGNED_OUT;
    routeIncomingSystemPath(
      `https://app.menizvet.com/invitations/organization/accept?invitation=nope#secret=${SECRET}`,
    );
    await render();

    await press(t('organizationInvitation.close'));

    expect(router.replace).toHaveBeenCalledWith('/(auth)');
  });
});

describe('links', () => {
  it('shows a malformed link as unavailable and stores nothing', async () => {
    routeIncomingSystemPath(
      `https://app.menizvet.com/invitations/organization/accept?invitation=nope#secret=${SECRET}`,
    );
    await render();

    expect(hasText(t('organizationInvitation.unavailableBody'))).toBe(true);
    expect(storedProof()).toBeNull();
    expect(preview).not.toHaveBeenCalled();
  });

  it('a newer link received while the screen is open replaces the older proof', async () => {
    routeIncomingSystemPath(link());
    await render();
    expect(preview).toHaveBeenLastCalledWith({ invitationId: ID, secret: SECRET });

    preview.mockResolvedValue(pendingPreview({ invitationId: NEW_ID }));
    await act(async () => {
      routeIncomingSystemPath(link(NEW_ID, NEW_SECRET));
    });
    await settle();

    expect(preview).toHaveBeenLastCalledWith({ invitationId: NEW_ID, secret: NEW_SECRET });
    expect(storedProof()).toEqual({ version: 1, invitationId: NEW_ID, secret: NEW_SECRET });
  });

  it('with nothing pending shows the generic unavailable state', async () => {
    await render();
    expect(hasText(t('organizationInvitation.unavailableBody'))).toBe(true);
    expect(preview).not.toHaveBeenCalled();
  });
});

describe('preview', () => {
  it('shows Organization, role and Clinic scope, masked address and expiry; offers Accept and Not now, no Decline', async () => {
    routeIncomingSystemPath(link());
    await render();

    expect(
      hasText(t('organizationInvitation.reviewTitle', { organization: 'Animalia Group' })),
    ).toBe(true);
    expect(hasText('Administrador · Clínica: Animalia Centro')).toBe(true);
    expect(hasText(t('organizationInvitation.invitedAddress', { email: 'c***@example.com' }))).toBe(
      true,
    );
    expect(rendered()).toContain('Válida hasta el');
    expect(rendered()).not.toContain('ADMINISTRATOR');
    expect(buttonsLabelled(t('organizationInvitation.accept'))).toHaveLength(1);
    expect(buttonsLabelled(t('organizationInvitation.notNow'))).toHaveLength(1);
    expect(rendered().toLowerCase()).not.toMatch(/rechazar|decline/);
    expect(storedProof()).not.toBeNull();
  });

  it.each([
    ['EXPIRED', 'organizationInvitation.expiredBody', false],
    ['REVOKED', 'organizationInvitation.revokedBody', false],
    ['ALREADY_MEMBER', 'organizationInvitation.alreadyMemberBody', true],
    ['ACCEPTED_BY_YOU', 'organizationInvitation.acceptedByYouBody', true],
    ['UNAVAILABLE', 'organizationInvitation.unavailableBody', false],
  ] as const)(
    '%s is a calm terminal state that clears the proof',
    async (state, body, toProfessional) => {
      preview.mockResolvedValue(
        pendingPreview({
          state,
          organizationDisplayName: state === 'UNAVAILABLE' ? null : 'Animalia Group',
        }),
      );
      routeIncomingSystemPath(link());
      await render();

      expect(hasText(t(body, { organization: 'Animalia Group' }))).toBe(true);
      expect(storedProof()).toBeNull();
      expect(buttonsLabelled(t('organizationInvitation.accept'))).toHaveLength(0);
      expect(buttonsLabelled(t('organizationInvitation.retry'))).toHaveLength(0);
      expect(buttonsLabelled(t('organizationInvitation.goToProfessional'))).toHaveLength(
        toProfessional ? 1 : 0,
      );
      if (toProfessional) {
        await press(t('organizationInvitation.goToProfessional'));
        expect(router.replace).toHaveBeenCalledWith('/professional');
      }
    },
  );

  it('the uniform failure reveals nothing and clears the proof', async () => {
    preview.mockResolvedValue({ kind: 'unavailable' });
    routeIncomingSystemPath(link());
    await render();

    expect(hasText(t('organizationInvitation.unavailableBody'))).toBe(true);
    expect(rendered()).not.toContain('Animalia');
    expect(storedProof()).toBeNull();
  });

  it('a failed read keeps the proof and can be retried', async () => {
    preview.mockResolvedValueOnce({ kind: 'failed' });
    routeIncomingSystemPath(link());
    await render();

    expect(hasText(t('organizationInvitation.loadError'))).toBe(true);
    expect(storedProof()).not.toBeNull();
    await press(t('organizationInvitation.retry'));
    expect(preview).toHaveBeenCalledTimes(2);
    expect(hasText(t('organizationInvitation.accept'))).toBe(true);
  });

  it('an unconfirmed account sees the preview but cannot accept', async () => {
    mockSession = { ...SIGNED_IN, user: { id: 'user-1', email_confirmed_at: null } };
    routeIncomingSystemPath(link());
    await render();

    expect(hasText(t('organizationInvitation.verificationRequired'))).toBe(true);
    expect(isDisabled(t('organizationInvitation.accept'))).toBe(true);
    await press(t('organizationInvitation.accept'));
    expect(accept).not.toHaveBeenCalled();
  });
});

describe('different signed-in address', () => {
  beforeEach(() => {
    preview.mockResolvedValue(pendingPreview({ invitedEmailMatchesCurrentAccount: false }));
  });

  it('warns with the masked address and requires a second explicit confirmation', async () => {
    routeIncomingSystemPath(link());
    await render();

    expect(
      hasText(t('organizationInvitation.mismatchWarning', { email: 'c***@example.com' })),
    ).toBe(true);
    await press(t('organizationInvitation.accept'));

    expect(accept).not.toHaveBeenCalled();
    expect(
      hasText(
        t('organizationInvitation.mismatchConfirmBody', {
          organization: 'Animalia Group',
          email: 'c***@example.com',
        }),
      ),
    ).toBe(true);
  });

  it('Cancel returns to the preview without accepting', async () => {
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.accept'));
    await press(t('organizationInvitation.mismatchCancel'));

    expect(accept).not.toHaveBeenCalled();
    expect(buttonsLabelled(t('organizationInvitation.accept'))).toHaveLength(1);
    expect(storedProof()).not.toBeNull();
  });

  it('Confirm accepts into the signed-in account', async () => {
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.accept'));
    await press(t('organizationInvitation.mismatchConfirm'));

    expect(accept).toHaveBeenCalledTimes(1);
    expect(accept).toHaveBeenCalledWith({ invitationId: ID, secret: SECRET });
    expect(router.replace).toHaveBeenCalledWith('/professional');
  });
});

describe('acceptance', () => {
  it('clears the proof, re-reads professional context, selects the new Organization and enters Professional', async () => {
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.accept'));

    expect(accept).toHaveBeenCalledTimes(1);
    expect(storedProof()).toBeNull();
    expect(context).toHaveBeenCalledTimes(1);
    expect(getProfessionalOrganizationSelection()).toEqual({
      membershipId: MEMBERSHIP,
      organizationId: ORG,
    });
    expect(router.replace).toHaveBeenCalledWith('/professional');
  });

  it('does not enter Professional on authority the context read does not confirm', async () => {
    context.mockResolvedValueOnce({
      data: { hasVeterinarianProfessionalProfile: false, organizations: [] },
      error: null,
    });
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.accept'));

    expect(hasText(t('organizationInvitation.contextFailedBody'))).toBe(true);
    expect(router.replace).not.toHaveBeenCalledWith('/professional');

    await press(t('organizationInvitation.reloadAccess'));
    expect(accept).toHaveBeenCalledTimes(1);
    expect(context).toHaveBeenCalledTimes(2);
    expect(router.replace).toHaveBeenCalledWith('/professional');
  });

  it('a lost response is reconciled through the preview, then the idempotent acceptance', async () => {
    accept
      .mockResolvedValueOnce({ kind: 'previewAgain' })
      .mockResolvedValueOnce(accepted('ALREADY_ACCEPTED'));
    routeIncomingSystemPath(link());
    await render();
    preview.mockResolvedValue(pendingPreview({ state: 'ACCEPTED_BY_YOU' }));
    await press(t('organizationInvitation.accept'));

    expect(preview).toHaveBeenCalledTimes(2);
    expect(accept).toHaveBeenCalledTimes(2);
    expect(storedProof()).toBeNull();
    expect(router.replace).toHaveBeenCalledWith('/professional');
  });

  it('a failed acceptance that is still pending is shown calmly, never retried blindly', async () => {
    accept.mockResolvedValue({ kind: 'previewAgain' });
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.accept'));

    expect(accept).toHaveBeenCalledTimes(1);
    expect(hasText(t('organizationInvitation.notAccepted'))).toBe(true);
    expect(storedProof()).not.toBeNull();
  });

  it('a failure that the preview shows as revoked ends there and clears the proof', async () => {
    accept.mockResolvedValue({ kind: 'previewAgain' });
    routeIncomingSystemPath(link());
    await render();
    preview.mockResolvedValue(pendingPreview({ state: 'REVOKED' }));
    await press(t('organizationInvitation.accept'));

    expect(hasText(t('organizationInvitation.revokedBody'))).toBe(true);
    expect(storedProof()).toBeNull();
    expect(accept).toHaveBeenCalledTimes(1);
  });

  it('a backend confirmation requirement keeps the proof and explains it', async () => {
    accept.mockResolvedValue({ kind: 'verificationRequired' });
    routeIncomingSystemPath(link());
    await render();
    await press(t('organizationInvitation.accept'));

    expect(hasText(t('organizationInvitation.verificationRequired'))).toBe(true);
    expect(storedProof()).not.toBeNull();
  });
});
