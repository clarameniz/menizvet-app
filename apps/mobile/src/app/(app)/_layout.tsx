import { Stack } from 'expo-router';

/**
 * Plain header-less Stack, same as (auth)/_layout.tsx. This group previously
 * rendered the Expo template's NativeTabs shell with a single "Home" tab;
 * Pets/Appointments/Profile were always top-level root-Stack routes pushed
 * over (app), never tabs, so that bar navigated nowhere. Route tree, guards
 * (src/app/_layout.tsx) and the `/` / `/(app)` URLs are unchanged.
 */
export default function AppLayout() {
  return <Stack screenOptions={{ headerShown: false }} />;
}
