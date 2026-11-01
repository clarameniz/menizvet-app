import { fromRow, type ProfileRow } from '@/data/user-profile';

// fromRow doesn't use the Supabase client itself, but importing this module
// pulls in lib/supabase.ts, which throws if EXPO_PUBLIC_SUPABASE_* env vars
// are absent (as they are under Jest). Mocking it keeps this test isolated,
// deterministic, and free of any real network/Supabase contact. jest.mock
// calls are hoisted above imports by Jest's babel transform regardless of
// source order, so writing the import first here is safe.
jest.mock('@/lib/supabase', () => ({ supabase: {} }));

describe('fromRow', () => {
  it('maps a full row to the camelCase UserProfile shape', () => {
    const row: ProfileRow = {
      user_id: 'user-123',
      display_name: 'Maria',
      avatar_reference: 'avatar-ref-456',
    };

    expect(fromRow(row)).toEqual({
      userId: 'user-123',
      displayName: 'Maria',
      avatarReference: 'avatar-ref-456',
    });
  });

  it('preserves null display_name and avatar_reference rather than coercing them', () => {
    const row: ProfileRow = {
      user_id: 'user-123',
      display_name: null,
      avatar_reference: null,
    };

    expect(fromRow(row)).toEqual({
      userId: 'user-123',
      displayName: null,
      avatarReference: null,
    });
  });
});
