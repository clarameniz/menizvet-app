import { disablePushRegistration, registerPushToken } from '@/data/push';

// Same isolation rationale as data/appointments.test.ts: importing this
// module pulls in lib/supabase.ts, which throws under Jest without
// EXPO_PUBLIC_SUPABASE_* env vars. Mocking it also captures the last
// functions.invoke(...) call so request-body mapping can be asserted
// without any real Supabase/Edge Function contact.
const mockInvoke = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: { functions: { invoke: (...args: unknown[]) => mockInvoke(...args) } },
}));

beforeEach(() => {
  mockInvoke.mockReset();
});

describe('registerPushToken', () => {
  it('maps every field to the register-push request body', async () => {
    mockInvoke.mockResolvedValue({ data: { registration_id: 'reg-1' }, error: null });

    const result = await registerPushToken({
      installationId: 'install-1',
      expoPushToken: 'ExponentPushToken[xxx]',
      platform: 'ANDROID',
      applicationId: 'com.menizvet.dev',
    });

    expect(mockInvoke).toHaveBeenCalledWith('communications/register-push', {
      body: {
        device_installation_id: 'install-1',
        expo_push_token: 'ExponentPushToken[xxx]',
        platform: 'ANDROID',
        application_id: 'com.menizvet.dev',
      },
    });
    expect(result).toEqual({ data: { registrationId: 'reg-1' }, error: null });
  });

  it('settles into the error shape on a backend error, never throwing', async () => {
    mockInvoke.mockResolvedValue({
      data: null,
      error: new Error('Edge Function returned a non-2xx status code'),
    });

    const result = await registerPushToken({
      installationId: 'install-1',
      expoPushToken: 'token',
      platform: 'IOS',
      applicationId: 'com.menizvet.dev',
    });

    expect(result).toEqual({ data: null, error: 'Edge Function returned a non-2xx status code' });
  });

  it('settles into the error shape when the underlying call rejects', async () => {
    mockInvoke.mockRejectedValue(new Error('Failed to send a request to the Edge Function'));

    const result = await registerPushToken({
      installationId: 'install-1',
      expoPushToken: 'token',
      platform: 'IOS',
      applicationId: 'com.menizvet.dev',
    });

    expect(result).toEqual({ data: null, error: 'Failed to send a request to the Edge Function' });
  });

  it('settles into a safe unknown-error shape when the response is missing registration_id', async () => {
    mockInvoke.mockResolvedValue({ data: {}, error: null });

    const result = await registerPushToken({
      installationId: 'install-1',
      expoPushToken: 'token',
      platform: 'IOS',
      applicationId: 'com.menizvet.dev',
    });

    expect(result).toEqual({ data: null, error: 'Unknown error' });
  });
});

describe('disablePushRegistration', () => {
  it('maps the registration id to the disable-push request body', async () => {
    mockInvoke.mockResolvedValue({ data: { invalidated: true }, error: null });

    const result = await disablePushRegistration('reg-1');

    expect(mockInvoke).toHaveBeenCalledWith('communications/disable-push', {
      body: { registration_id: 'reg-1' },
    });
    expect(result).toEqual({ data: { invalidated: true }, error: null });
  });

  it('settles into the error shape when the underlying call rejects', async () => {
    mockInvoke.mockRejectedValue(new Error('Failed to send a request to the Edge Function'));

    const result = await disablePushRegistration('reg-1');

    expect(result).toEqual({ data: null, error: 'Failed to send a request to the Edge Function' });
  });
});
