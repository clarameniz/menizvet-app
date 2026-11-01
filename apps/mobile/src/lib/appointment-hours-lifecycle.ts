/**
 * Lifecycle gate shared by the Appointment hours screens (via
 * `useAppointmentHours`), following the repository's established terminal
 * leaving pattern (professional reschedule / alternative-time screens):
 *
 * - leaving has a single owner: `leave(navigate)` runs the navigation once and
 *   marks the screen as leaving; later calls do nothing;
 * - once leaving (or unmounted), no async continuation may update the screen —
 *   not an initial or focus read, not editor initialization, not mutation
 *   reconciliation, not a `finally` — because React Native's Fabric renderer
 *   (with react-native-screens) moves a popped screen's native views for the
 *   exit transition, and inserting a new native child into that subtree fails
 *   with "The specified child already has a parent";
 * - leaving also invalidates any read in flight;
 * - latest read wins: a read applies only if no later read began.
 *
 * Plain, React-free logic so the decisions are unit-tested; the hook holds one
 * instance per screen.
 */
export type AppointmentHoursLifecycle = {
  /** Mount/unmount bookkeeping (from the hook's effect). */
  setMounted: (mounted: boolean) => void;
  /** Starts a read; returns its token. */
  beginLoad: () => number;
  /** Whether a read with this token may still update the screen. */
  isCurrentLoad: (token: number) => boolean;
  /** Whether any async continuation may still update the screen. */
  isActive: () => boolean;
  /** Navigates away exactly once; returns whether this call did. */
  leave: (navigate: () => void) => boolean;
};

export function createAppointmentHoursLifecycle(): AppointmentHoursLifecycle {
  let mounted = true;
  let leaving = false;
  let latestLoad = 0;

  const isActive = () => mounted && !leaving;

  return {
    setMounted(value) {
      mounted = value;
    },
    beginLoad() {
      latestLoad += 1;
      return latestLoad;
    },
    isCurrentLoad(token) {
      return isActive() && token === latestLoad;
    },
    isActive,
    leave(navigate) {
      if (leaving) return false;
      leaving = true;
      // Any read still in flight can no longer apply.
      latestLoad += 1;
      navigate();
      return true;
    },
  };
}

/**
 * Whether a fresh read replaces what the screen shows: always, except that a
 * failed refresh after a successful load keeps the loaded screen (the caller
 * still receives the failed read to decide what to do).
 */
export function shouldApplyRead(
  readKind: 'error' | 'unavailable' | 'loaded',
  hasLoaded: boolean,
): boolean {
  return readKind !== 'error' || !hasLoaded;
}
