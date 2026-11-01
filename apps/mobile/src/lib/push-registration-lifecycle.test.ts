// Milestone H logout-race fix: unlike push-registration.test.ts (which mocks
// @/lib/push-registration-state to assert on registerPushToken's request
// mapping in isolation), these tests exercise the REAL state module so the
// single-flight/generation/in-flight-await coordination between
// ensurePushRegistered and disableCurrentPushRegistrations can be verified
// end to end — this is exactly the concurrency a physical logout test found
// broken (an older registration got disabled while a newer one, still in
// flight at sign-out time, was silently orphaned).

// Deliberately NOT mocked: these tests exercise the real coordination state.
import {
  beginRegistrationAttempt,
  getCurrentPushRegistrationId,
  setCurrentPushRegistrationId,
} from '@/lib/push-registration-state';

import { disableCurrentPushRegistrations, ensurePushRegistered } from '@/lib/push-registration';

const mockGetPermissionsAsync = jest.fn();
const mockRequestPermissionsAsync = jest.fn();
const mockGetExpoPushTokenAsync = jest.fn();
jest.mock('expo-notifications', () => ({
  getPermissionsAsync: (...args: unknown[]) => mockGetPermissionsAsync(...args),
  requestPermissionsAsync: (...args: unknown[]) => mockRequestPermissionsAsync(...args),
  getExpoPushTokenAsync: (...args: unknown[]) => mockGetExpoPushTokenAsync(...args),
}));

const mockRegisterPushToken = jest.fn();
const mockDisablePushRegistration = jest.fn();
jest.mock('@/data/push', () => ({
  registerPushToken: (...args: unknown[]) => mockRegisterPushToken(...args),
  disablePushRegistration: (...args: unknown[]) => mockDisablePushRegistration(...args),
}));

const mockGetInstallationId = jest.fn();
jest.mock('@/lib/installation-id', () => ({
  getInstallationId: (...args: unknown[]) => mockGetInstallationId(...args),
}));

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

type PushRegisterResult =
  { data: { registrationId: string }; error: null } | { data: null; error: string };

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

beforeEach(() => {
  mockGetPermissionsAsync.mockReset().mockResolvedValue({ status: 'granted', granted: true });
  mockRequestPermissionsAsync.mockReset();
  mockGetExpoPushTokenAsync.mockReset().mockResolvedValue({ data: 'ExponentPushToken[xxx]' });
  mockRegisterPushToken.mockReset();
  mockDisablePushRegistration
    .mockReset()
    .mockResolvedValue({ data: { invalidated: true }, error: null });
  mockGetInstallationId.mockReset().mockResolvedValue('install-1');

  // Reset the shared module state between tests (it is a real singleton).
  setCurrentPushRegistrationId(null);
});

describe('registration lifecycle', () => {
  it('1-2-3. a later successful registration becomes current, never the earlier id', async () => {
    mockRegisterPushToken.mockResolvedValueOnce({ data: { registrationId: 'A' }, error: null });
    await ensurePushRegistered(notStale, 'android');
    expect(getCurrentPushRegistrationId()).toBe('A');

    mockRegisterPushToken.mockResolvedValueOnce({ data: { registrationId: 'B' }, error: null });
    const result = await ensurePushRegistered(notStale, 'android');

    expect(result).toBe('B');
    expect(getCurrentPushRegistrationId()).toBe('B');
  });

  it('4. a stale (generation-invalidated) completion cannot overwrite a newer commit', async () => {
    const deferred = createDeferred<PushRegisterResult>();
    mockRegisterPushToken.mockReturnValueOnce(deferred.promise);

    const olderAttempt = ensurePushRegistered(notStale, 'android');

    // Simulate a newer attempt having already started and committed while
    // the older one is still in flight (e.g. sign-out's own invalidation,
    // or — defense in depth — a second attempt that somehow raced ahead).
    beginRegistrationAttempt();
    setCurrentPushRegistrationId('B');

    // The older attempt's network call finally resolves "successfully".
    deferred.resolve({ data: { registrationId: 'A-late' }, error: null });
    await olderAttempt;

    expect(getCurrentPushRegistrationId()).toBe('B');
  });

  it('5. logout disables the current registration', async () => {
    setCurrentPushRegistrationId('B');

    await disableCurrentPushRegistrations();

    expect(mockDisablePushRegistration).toHaveBeenCalledWith('B');
    expect(getCurrentPushRegistrationId()).toBeNull();
  });

  it('6. token rotation immediately followed by logout disables both the old and the new id', async () => {
    setCurrentPushRegistrationId('A');

    const deferred = createDeferred<PushRegisterResult>();
    mockRegisterPushToken.mockReturnValueOnce(deferred.promise);
    // Simulates the token-rotation listener firing and re-registering while
    // 'A' is still the tracked current id.
    const rotationAttempt = ensurePushRegistered(notStale, 'android');

    // Sign-out fires before the rotation's network call has resolved.
    const logout = disableCurrentPushRegistrations();

    // The rotation's register-push call finally completes, producing a new
    // registration id that was never adopted as "current" (generation
    // invalidated by disableCurrentPushRegistrations above) but was still
    // created server-side and must still be disabled.
    deferred.resolve({ data: { registrationId: 'B' }, error: null });

    await Promise.all([rotationAttempt, logout]);

    expect(mockDisablePushRegistration).toHaveBeenCalledWith('A');
    expect(mockDisablePushRegistration).toHaveBeenCalledWith('B');
    expect(mockDisablePushRegistration).toHaveBeenCalledTimes(2);
    expect(getCurrentPushRegistrationId()).toBeNull();
  });

  it('does not call disable-push at all when nothing was ever registered', async () => {
    await disableCurrentPushRegistrations();

    expect(mockDisablePushRegistration).not.toHaveBeenCalled();
  });

  it('7. a session change clears prior tracking and a fresh registration is adopted cleanly', async () => {
    setCurrentPushRegistrationId('A');
    await disableCurrentPushRegistrations();
    expect(getCurrentPushRegistrationId()).toBeNull();

    mockRegisterPushToken.mockResolvedValueOnce({ data: { registrationId: 'C' }, error: null });
    await ensurePushRegistered(notStale, 'android');

    expect(getCurrentPushRegistrationId()).toBe('C');
  });

  it('collapses overlapping calls into a single in-flight register-push request', async () => {
    const deferred = createDeferred<PushRegisterResult>();
    mockRegisterPushToken.mockReturnValueOnce(deferred.promise);

    const first = ensurePushRegistered(notStale, 'android');
    const second = ensurePushRegistered(notStale, 'android');

    deferred.resolve({ data: { registrationId: 'A' }, error: null });
    const [firstResult, secondResult] = await Promise.all([first, second]);

    expect(mockRegisterPushToken).toHaveBeenCalledTimes(1);
    expect(firstResult).toBe('A');
    expect(secondResult).toBe('A');
    expect(getCurrentPushRegistrationId()).toBe('A');
  });
});
