import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';

describe('createAppointmentHoursLifecycle', () => {
  it('lets the latest read apply while mounted and not leaving', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    const token = lifecycle.beginLoad();
    expect(lifecycle.isActive()).toBe(true);
    expect(lifecycle.isCurrentLoad(token)).toBe(true);
  });

  it('keeps latest-request-wins: an earlier read never applies after a later one began', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    const first = lifecycle.beginLoad();
    const second = lifecycle.beginLoad();
    expect(lifecycle.isCurrentLoad(first)).toBe(false);
    expect(lifecycle.isCurrentLoad(second)).toBe(true);
  });

  it('navigates exactly once, however many times leaving is requested', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    const navigate = jest.fn();
    expect(lifecycle.leave(navigate)).toBe(true);
    expect(lifecycle.leave(navigate)).toBe(false);
    expect(navigate).toHaveBeenCalledTimes(1);
  });

  it('marks the screen as leaving before navigation runs', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    let activeDuringNavigation: boolean | null = null;
    lifecycle.leave(() => {
      activeDuringNavigation = lifecycle.isActive();
    });
    expect(activeDuringNavigation).toBe(false);
  });

  it('after leaving, invalidates a read in flight and blocks every later update', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    const inFlight = lifecycle.beginLoad();
    lifecycle.leave(() => undefined);
    expect(lifecycle.isActive()).toBe(false);
    expect(lifecycle.isCurrentLoad(inFlight)).toBe(false);
    // A focus read or retry started after leaving cannot apply either.
    expect(lifecycle.isCurrentLoad(lifecycle.beginLoad())).toBe(false);
  });

  it('after unmount, blocks updates even without leaving', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    const token = lifecycle.beginLoad();
    lifecycle.setMounted(false);
    expect(lifecycle.isActive()).toBe(false);
    expect(lifecycle.isCurrentLoad(token)).toBe(false);
  });

  it('tolerates a development remount before leaving', () => {
    const lifecycle = createAppointmentHoursLifecycle();
    lifecycle.setMounted(false);
    lifecycle.setMounted(true);
    expect(lifecycle.isCurrentLoad(lifecycle.beginLoad())).toBe(true);
  });
});

describe('shouldApplyRead', () => {
  it('applies every first-load outcome', () => {
    expect(shouldApplyRead('loaded', false)).toBe(true);
    expect(shouldApplyRead('unavailable', false)).toBe(true);
    expect(shouldApplyRead('error', false)).toBe(true);
  });

  it('keeps a loaded screen on a failed refresh, but applies loss of access', () => {
    expect(shouldApplyRead('error', true)).toBe(false);
    expect(shouldApplyRead('loaded', true)).toBe(true);
    expect(shouldApplyRead('unavailable', true)).toBe(true);
  });
});
