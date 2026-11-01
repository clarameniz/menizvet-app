/**
 * Web counterpart of animated-icon.tsx: the native animated splash overlay
 * has no web equivalent (there is no native splash screen to hand off from),
 * so it renders nothing.
 */
export function AnimatedSplashOverlay(_props: { ready: boolean }) {
  return null;
}
