import { supabase } from '@/lib/supabase';

/**
 * Owns the two authenticated communications Edge Function routes the mobile
 * app calls directly for the Push Registration lifecycle
 * (docs/COMMUNICATIONS_BACKEND.md "Authenticated client contract"):
 *
 * - communications/register-push — idempotent; a token or installation id
 *   rebound to a different session/User invalidates the previous active
 *   registration server-side. Requires the caller's current Supabase access
 *   token, attached automatically by supabase.functions.invoke.
 * - communications/disable-push — only the verified User and exact
 *   registering session may disable a registration through this route.
 *
 * Every lifecycle rule (idempotency, cross-session/User rebinding, the
 * auth_session_id eligibility check before dispatch) is enforced
 * server-side (SPEC-COM-002); this module only shapes the request/response
 * and never reproduces that logic client-side. Errors settle into the
 * ordinary { data, error } shape using only the fixed, already-safe message
 * each @supabase/functions-js error class carries — never raw HTTP status
 * codes, response bodies, tokens, or session ids.
 */
export type PushResult<T> = { data: T; error: null } | { data: null; error: string };

export type PushPlatform = 'IOS' | 'ANDROID';

export type RegisterPushInput = {
  installationId: string;
  expoPushToken: string;
  platform: PushPlatform;
  applicationId: string;
};

export type RegisterPushOutput = { registrationId: string };
export type DisablePushOutput = { invalidated: boolean };

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export async function registerPushToken(
  input: RegisterPushInput,
): Promise<PushResult<RegisterPushOutput>> {
  try {
    const { data, error } = await supabase.functions.invoke<Record<string, unknown>>(
      'communications/register-push',
      {
        body: {
          device_installation_id: input.installationId,
          expo_push_token: input.expoPushToken,
          platform: input.platform,
          application_id: input.applicationId,
        },
      },
    );

    if (error) {
      return { data: null, error: toErrorMessage(error) };
    }

    const registrationId =
      isRecord(data) && typeof data.registration_id === 'string' ? data.registration_id : null;

    if (!registrationId) {
      return { data: null, error: 'Unknown error' };
    }

    return { data: { registrationId }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/**
 * Best-effort cleanup: the backend's auth_session_id binding remains the
 * real security boundary regardless of whether this call succeeds
 * (SPEC-COM-002 BR-22, docs/COMMUNICATIONS_BACKEND.md). Callers must never
 * let a failure here block sign-out.
 */
export async function disablePushRegistration(
  registrationId: string,
): Promise<PushResult<DisablePushOutput>> {
  try {
    const { data, error } = await supabase.functions.invoke<Record<string, unknown>>(
      'communications/disable-push',
      {
        body: { registration_id: registrationId },
      },
    );

    if (error) {
      return { data: null, error: toErrorMessage(error) };
    }

    const invalidated = isRecord(data) && data.invalidated === true;

    return { data: { invalidated }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}
