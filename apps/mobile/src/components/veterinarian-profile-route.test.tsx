import { createElement } from 'react';
import { Text, TextInput } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import VeterinarianProfileScreen from '@/app/professional/veterinarian-profile';
import { getMyProfessionalContext, type ProfessionalContext } from '@/data/professional-context';
import { createMyVeterinarianProfessionalProfile } from '@/data/veterinarian-profile';
import { i18n } from '@/i18n/i18n';

jest.mock('expo-router', () => ({
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    push: jest.fn(),
  },
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
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
});
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/data/veterinarian-profile', () => ({
  ...jest.requireActual('@/data/veterinarian-profile'),
  createMyVeterinarianProfessionalProfile: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const contextRead = getMyProfessionalContext as jest.Mock;
const createProfile = createMyVeterinarianProfessionalProfile as jest.Mock;

const context = (
  hasProfile: boolean,
  role = 'VETERINARIAN',
): { data: ProfessionalContext; error: null } => ({
  data: {
    hasVeterinarianProfessionalProfile: hasProfile,
    organizations: [
      {
        membershipId: 'm',
        organizationId: 'A',
        organizationDisplayName: 'A',
        responsibilities: [
          { responsibility: role as 'VETERINARIAN', scope: { type: 'ORGANIZATION' } },
        ],
        capabilities: [],
        unknownCapabilities: [],
        clinicAssignments: [],
        entitlements: {
          APPOINTMENT_MANAGEMENT: false,
          PROFESSIONAL_SCHEDULING: false,
          CLINICAL_CARE: false,
          CLINICAL_DOCUMENTATION: false,
        },
      },
    ],
  },
  error: null,
});

let tree: ReactTestRenderer;
const t = (key: string) => i18n.t(key);
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const button = (label: string) =>
  tree.root.find(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityLabel === label &&
      typeof node.props.onPress === 'function',
  );
async function press(label: string) {
  await act(async () => {
    button(label).props.onPress();
  });
}
async function fill(identifier: string, issuing: string) {
  const [first, second] = tree.root.findAllByType(TextInput);
  await act(async () => {
    first.props.onChangeText(identifier);
  });
  await act(async () => {
    second.props.onChangeText(issuing);
  });
}
async function render() {
  await act(async () => {
    tree = create(createElement(VeterinarianProfileScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  contextRead.mockReset().mockResolvedValue(context(false));
  createProfile.mockReset();
});
afterEach(() => act(() => tree.unmount()));

it('collects exactly the two credential facts and reviews them before creating', async () => {
  await render();
  expect(tree.root.findAllByType(TextInput)).toHaveLength(2);
  expect(button(t('veterinarianProfile.reviewAction')).props.accessibilityState.disabled).toBe(
    true,
  );
  await fill('  COL-28/1234 ', 'Colegio de Madrid');
  await press(t('veterinarianProfile.reviewAction'));
  expect(texts()).toEqual(expect.arrayContaining(['COL-28/1234', 'Colegio de Madrid']));
  expect(texts()).toContain(t('veterinarianProfile.notEditableNote'));
  expect(texts()).toContain(t('veterinarianProfile.notVerifiedNote'));
  expect(texts().join(' ')).not.toMatch(/verificad[oa] por MenizVet/i);
  expect(createProfile).not.toHaveBeenCalled();
});

it('creates the Profile, re-reads the context and returns to Professional', async () => {
  createProfile.mockResolvedValue({ kind: 'outcome', outcome: 'CREATED' });
  await render();
  await fill('COL-1', 'Colegio de Madrid');
  await press(t('veterinarianProfile.reviewAction'));
  contextRead.mockResolvedValue(context(true));
  await press(t('veterinarianProfile.submit'));
  expect(createProfile).toHaveBeenCalledTimes(1);
  expect(createProfile).toHaveBeenCalledWith({
    registrationIdentifier: 'COL-1',
    issuingContext: 'Colegio de Madrid',
  });
  expect(contextRead).toHaveBeenCalledTimes(2);
  expect(router.dismissTo).toHaveBeenCalledWith('/professional');
});

it('reconciles a lost response through the re-read instead of retrying', async () => {
  createProfile.mockResolvedValue({ kind: 'uncertain' });
  await render();
  await fill('COL-1', 'Colegio de Madrid');
  await press(t('veterinarianProfile.reviewAction'));
  contextRead.mockResolvedValue(context(true));
  await press(t('veterinarianProfile.submit'));
  expect(createProfile).toHaveBeenCalledTimes(1);
  expect(router.dismissTo).toHaveBeenCalledWith('/professional');
});

it('reports a different existing Profile calmly and stops offering creation', async () => {
  createProfile.mockResolvedValue({ kind: 'rejected', reason: 'PROFILE_CREDENTIAL_MISMATCH' });
  await render();
  await fill('COL-2', 'Colegio de Madrid');
  await press(t('veterinarianProfile.reviewAction'));
  contextRead.mockResolvedValue(context(true));
  await press(t('veterinarianProfile.submit'));
  expect(texts()).toContain(t('veterinarianProfile.mismatch'));
  expect(texts()).toContain(t('veterinarianProfile.completed'));
  expect(tree.root.findAllByType(TextInput)).toHaveLength(0);
});

it('does not offer creation once a Profile exists, nor to non-Veterinarians', async () => {
  contextRead.mockResolvedValue(context(true));
  await render();
  expect(texts()).toContain(t('veterinarianProfile.completed'));
  expect(tree.root.findAllByType(TextInput)).toHaveLength(0);
  act(() => tree.unmount());
  contextRead.mockResolvedValue(context(false, 'RECEPTIONIST'));
  await render();
  expect(texts()).toContain(t('veterinarianProfile.notOffered'));
  expect(texts()).not.toContain(t('veterinarianProfile.completedAssignmentNote'));
  expect(texts()).not.toContain(t('veterinarianProfile.assignmentNote'));
});

it('explains that the Profile comes before Clinic assignment while it is pending', async () => {
  await render();
  expect(texts()).toContain(t('veterinarianProfile.assignmentNote'));
  expect(texts()).not.toContain(t('veterinarianProfile.completedAssignmentNote'));
});

it('does not present a completed Profile as a Clinic assignment', async () => {
  contextRead.mockResolvedValue(context(true));
  await render();
  expect(texts()).toContain(t('veterinarianProfile.completedAssignmentNote'));
  expect(texts()).not.toContain(t('veterinarianProfile.assignmentNote'));
});
