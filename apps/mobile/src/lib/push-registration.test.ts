import {
  ensurePushRegistered,
  resolveApplicationId,
  resolveEasProjectId,
  resolvePushPlatform,
} from '@/lib/push-registration';
// Deliberately NOT mocked: @/lib/push-registration-state is a simple
// in-memory module with no side effects, and push-registration-lifecycle.test.ts
// specifically exercises it for real to verify the Milestone H
// logout-race/concurrency fix. Using the real module here too (reset between
// tests below) keeps both files consistent and avoids maintaining a second,
// growing fake state machine.
import {
  getCurrentPushRegistrationId,
  setCurrentPushRegistrationId,
} from '@/lib/push-registration-state';

const mockGetPermissionsAsync = jest.fn();
const mockRequestPermissionsAsync = jest.fn();
const mockGetExpoPushTokenAsync = jest.fn();
jest.mock('expo-notifications', () => ({
  getPermissionsAsync: (...args: unknown[]) => mockGetPermissionsAsync(...args),
  requestPermissionsAsync: (...args: unknown[]) => mockRequestPermissionsAsync(...args),
  getExpoPushTokenAsync: (...args: unknown[]) => mockGetExpoPushTokenAsync(...args),
}));

const mockRegisterPushToken = jest.fn();
jest.mock('@/data/push', () => ({
  registerPushToken: (...args: unknown[]) => mockRegisterPushToken(...args),
  // Not exercised by this file's tests (see push-registration-lifecycle.test.ts
  // for disableCurrentPushRegistrations), but @/lib/push-registration imports
  // it, so the mock module must still provide it.
  disablePushRegistration: jest.fn(),
}));

const mockGetInstallationId = jest.fn();
jest.mock('@/lib/installation-id', () => ({
  getInstallationId: (...args: unknown[]) => mockGetInstallationId(...args),
}));

// android.package is configured; ios.bundleIdentifier deliberately is not,
// mirroring apps/mobile/app.config.ts's current real state (iOS push
// provisioning is an explicit Milestone H follow-up, not this pass).
jest.mock('expo-constants', () => ({
  __esModule: true,
  default: {
    expoConfig: {
      android: { package: 'com.menizvet.dev' },
      extra: { eas: { projectId: 'proj-1' } },
    },
    easConfig: null,
  },
}));

const notStale = () => false;

beforeEach(() => {
  mockGetPermissionsAsync.mockReset();
  mockRequestPermissionsAsync.mockReset();
  mockGetExpoPushTokenAsync.mockReset();
  mockRegisterPushToken.mockReset();
  mockGetInstallationId.mockReset();
  setCurrentPushRegistrationId(null);
});

describe('resolvePushPlatform', () => {
  it('maps ios and android to the backend platform enum', () => {
    expect(resolvePushPlatform('ios')).toBe('IOS');
    expect(resolvePushPlatform('android')).toBe('ANDROID');
  });

  it('returns null for an unsupported platform', () => {
    expect(resolvePushPlatform('web')).toBeNull();
  });
});

describe('resolveApplicationId', () => {
  it('reads the configured Android package', () => {
    expect(resolveApplicationId('android')).toBe('com.menizvet.dev');
  });

  it('returns null on iOS while no bundleIdentifier is configured', () => {
    expect(resolveApplicationId('ios')).toBeNull();
  });
});

describe('resolveEasProjectId', () => {
  it('reads the configured EAS project id', () => {
    expect(resolveEasProjectId()).toBe('proj-1');
  });
});

describe('ensurePushRegistered', () => {
  it('does nothing on a platform with no configured application id (e.g. iOS today)', async () => {
    await ensurePushRegistered(notStale, 'ios');

    expect(mockGetPermissionsAsync).not.toHaveBeenCalled();
    expect(mockRegisterPushToken).not.toHaveBeenCalled();
  });

  it('requests permission when undetermined, then registers on grant', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'undetermined', granted: false });
    mockRequestPermissionsAsync.mockResolvedValue({ status: 'granted', granted: true });
    mockGetInstallationId.mockResolvedValue('install-1');
    mockGetExpoPushTokenAsync.mockResolvedValue({ data: 'ExponentPushToken[xxx]' });
    mockRegisterPushToken.mockResolvedValue({ data: { registrationId: 'reg-1' }, error: null });

    const result = await ensurePushRegistered(notStale, 'android');

    expect(mockRequestPermissionsAsync).toHaveBeenCalledTimes(1);
    expect(mockRegisterPushToken).toHaveBeenCalledWith({
      installationId: 'install-1',
      expoPushToken: 'ExponentPushToken[xxx]',
      platform: 'ANDROID',
      applicationId: 'com.menizvet.dev',
    });
    expect(result).toBe('reg-1');
    expect(getCurrentPushRegistrationId()).toBe('reg-1');
  });

  it('registers without prompting when permission is already granted', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'granted', granted: true });
    mockGetInstallationId.mockResolvedValue('install-1');
    mockGetExpoPushTokenAsync.mockResolvedValue({ data: 'token' });
    mockRegisterPushToken.mockResolvedValue({ data: { registrationId: 'reg-1' }, error: null });

    await ensurePushRegistered(notStale, 'android');

    expect(mockRequestPermissionsAsync).not.toHaveBeenCalled();
    expect(mockRegisterPushToken).toHaveBeenCalledTimes(1);
  });

  it('never re-prompts after a prior denial and does not register', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'denied', granted: false });

    await ensurePushRegistered(notStale, 'android');

    expect(mockRequestPermissionsAsync).not.toHaveBeenCalled();
    expect(mockRegisterPushToken).not.toHaveBeenCalled();
  });

  it('settles without error when the user denies the prompt', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'undetermined', granted: false });
    mockRequestPermissionsAsync.mockResolvedValue({ status: 'denied', granted: false });

    await expect(ensurePushRegistered(notStale, 'android')).resolves.toBeNull();

    expect(mockRegisterPushToken).not.toHaveBeenCalled();
  });

  it('stops before any network call once the caller reports staleness', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'granted', granted: true });

    await ensurePushRegistered(() => true, 'android');

    expect(mockRequestPermissionsAsync).not.toHaveBeenCalled();
    expect(mockGetInstallationId).not.toHaveBeenCalled();
    expect(mockRegisterPushToken).not.toHaveBeenCalled();
  });

  it('settles safely without registering when the Expo token fetch fails', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'granted', granted: true });
    mockGetInstallationId.mockResolvedValue('install-1');
    mockGetExpoPushTokenAsync.mockRejectedValue(new Error('Network request failed'));

    await expect(ensurePushRegistered(notStale, 'android')).resolves.toBeNull();

    expect(mockRegisterPushToken).not.toHaveBeenCalled();
  });

  it('settles safely without recording a registration id when the Edge Function call fails', async () => {
    mockGetPermissionsAsync.mockResolvedValue({ status: 'granted', granted: true });
    mockGetInstallationId.mockResolvedValue('install-1');
    mockGetExpoPushTokenAsync.mockResolvedValue({ data: 'token' });
    mockRegisterPushToken.mockResolvedValue({ data: null, error: 'Unknown error' });

    await expect(ensurePushRegistered(notStale, 'android')).resolves.toBeNull();

    expect(getCurrentPushRegistrationId()).toBeNull();
  });
});
