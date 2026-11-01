import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import ProfessionalScreen from '@/app/professional';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import {
  getMyProfessionalContext,
  type OrganizationResponsibility,
  type ProfessionalContext,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import { setProfessionalOrganizationSelection } from '@/lib/professional-organization-selection';

/**
 * Professional Home — Veterinarian Profile prompt (SPEC-VET-001 §13): shown,
 * with why it matters for Clinic assignment, only while the User holds a
 * current VETERINARIAN Responsibility and has no Profile; a completed Profile
 * removes it whether or not any Clinic is assigned yet.
 */

jest.mock('expo-router', () => ({
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => callback(), [callback]);
  },
  router: { push: jest.fn(), back: jest.fn(), canGoBack: jest.fn(() => true), replace: jest.fn() },
}));
jest.mock('@/components/design-system/app-top-bar', () => ({ AppTopBar: () => null }));
jest.mock('react-native-safe-area-context', () => {
  const { View } = jest.requireActual('react-native');
  return {
    SafeAreaView: View,
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
  };
});
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: mockI18n.locale, t: mockTranslate }) };
});
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/data/professional-clinics', () => ({
  ...jest.requireActual('@/data/professional-clinics'),
  getMyProfessionalClinics: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const contextRead = getMyProfessionalContext as jest.Mock;
const clinicsRead = getMyProfessionalClinics as jest.Mock;

const context = (
  hasProfile: boolean,
  roles: OrganizationResponsibility[] = ['VETERINARIAN'],
  assignedClinicIds: string[] = [],
): { data: ProfessionalContext; error: null } => ({
  data: {
    hasVeterinarianProfessionalProfile: hasProfile,
    organizations: [
      {
        membershipId: 'm',
        organizationId: 'A',
        organizationDisplayName: 'Animalia',
        responsibilities: roles.map((responsibility) => ({
          responsibility,
          scope: { type: 'ORGANIZATION' },
        })),
        capabilities: [],
        unknownCapabilities: [],
        clinicAssignments: assignedClinicIds.map((clinicId) => ({
          veterinarianClinicAssignmentId: `a-${clinicId}`,
          clinic: { clinicId, displayName: `Clinic ${clinicId}` },
        })),
        entitlements: {
          APPOINTMENT_MANAGEMENT: true,
          PROFESSIONAL_SCHEDULING: true,
          CLINICAL_CARE: true,
          CLINICAL_DOCUMENTATION: true,
        },
      },
    ],
  },
  error: null,
});

let tree: ReactTestRenderer;
const t = (key: string) => i18n.t(key);
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const promptLabel = () =>
  `${t('veterinarianProfile.homeAction')}. ${t('veterinarianProfile.homeActionSupport')}`;
const prompts = () =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityLabel === promptLabel() &&
      typeof node.props.onPress === 'function',
  );
async function render() {
  await act(async () => {
    tree = create(createElement(ProfessionalScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  i18n.locale = 'es';
  setProfessionalOrganizationSelection(null);
  contextRead.mockReset().mockResolvedValue(context(false));
  clinicsRead.mockReset().mockResolvedValue({ data: { clinics: [] }, error: null });
});
afterEach(() => {
  act(() => tree.unmount());
  i18n.locale = 'es';
});

it('prompts a Veterinarian without a Profile, explaining it is needed for Clinic assignment', async () => {
  await render();
  expect(texts()).toContain(t('veterinarianProfile.homeAction'));
  expect(texts()).toContain('Tu colegiación: necesaria para que puedan asignarte a clínicas');
  expect(prompts().length).toBeGreaterThan(0);
  await act(async () => {
    prompts()[0].props.onPress();
  });
  expect(router.push).toHaveBeenCalledWith('/professional/veterinarian-profile');
});

it('removes the prompt once the Profile exists, even with no Clinic assigned yet', async () => {
  contextRead.mockResolvedValue(context(true));
  await render();
  expect(texts()).not.toContain(t('veterinarianProfile.homeAction'));
  expect(texts()).not.toContain(t('veterinarianProfile.homeActionSupport'));
});

it('does not prompt an assigned Veterinarian', async () => {
  contextRead.mockResolvedValue(context(true, ['VETERINARIAN'], ['c1']));
  await render();
  expect(texts()).not.toContain(t('veterinarianProfile.homeAction'));
});

it('never prompts a User without the VETERINARIAN Responsibility', async () => {
  contextRead.mockResolvedValue(context(false, ['OWNER', 'ADMINISTRATOR', 'RECEPTIONIST']));
  await render();
  expect(texts()).not.toContain(t('veterinarianProfile.homeAction'));
  expect(texts()).not.toContain(t('veterinarianProfile.homeActionSupport'));
});

it('explains the prompt in English', async () => {
  i18n.locale = 'en';
  await render();
  expect(texts()).toEqual(
    expect.arrayContaining([
      'Complete veterinarian profile',
      'Your professional registration — needed before you can be assigned to clinics',
    ]),
  );
});
