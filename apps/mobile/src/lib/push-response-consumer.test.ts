import { createPushResponseConsumer } from '@/lib/push-response-consumer';
import type { PushNavigationTarget } from '@/lib/push-notification-payload';

const target: PushNavigationTarget = {
  screen: 'appointment',
  appointmentId: '11111111-2222-3333-4444-555555555555',
  petId: '66666666-7777-8888-9999-aaaaaaaaaaaa',
};

const LOADING = { isSessionLoading: true, hasSession: false, isPasswordRecovery: false };
const READY_WITH_SESSION = {
  isSessionLoading: false,
  hasSession: true,
  isPasswordRecovery: false,
};
const READY_NO_SESSION = { isSessionLoading: false, hasSession: false, isPasswordRecovery: false };
const READY_RECOVERY_ONLY = {
  isSessionLoading: false,
  hasSession: true,
  isPasswordRecovery: true,
};

describe('createPushResponseConsumer', () => {
  it('1. holds a cold-start response as pending while the session is still loading', () => {
    const consumer = createPushResponseConsumer();
    consumer.updateReadiness(LOADING);

    const outcome = consumer.capture('response-1', target);

    expect(outcome).toEqual({ kind: 'pending' });
  });

  it('2. emits exactly one navigation target once the session becomes ready', () => {
    const consumer = createPushResponseConsumer();

    expect(consumer.capture('response-1', target)).toEqual({ kind: 'pending' });

    const outcome = consumer.updateReadiness(READY_WITH_SESSION);

    expect(outcome).toEqual({ kind: 'navigate', target });
    // A later readiness update must not re-emit navigation for the same
    // already-resolved response.
    expect(consumer.updateReadiness(READY_WITH_SESSION)).toEqual({ kind: 'none' });
  });

  it('3. does not mark a response consumed merely because the session is not ready', () => {
    const consumer = createPushResponseConsumer();

    consumer.capture('response-1', target);
    // Observing the exact same response again (e.g. cold-start check plus
    // a live-listener echo) while still loading must not be treated as a
    // brand new/duplicate/handled response — it must still be pending.
    const outcome = consumer.capture('response-1', target);

    expect(outcome).toEqual({ kind: 'pending' });
  });

  it('4. discards without navigating when bootstrap completes with no session', () => {
    const consumer = createPushResponseConsumer();

    consumer.capture('response-1', target);
    const outcome = consumer.updateReadiness(READY_NO_SESSION);

    expect(outcome).toEqual({ kind: 'discarded' });
  });

  it('4b. discards without navigating when only a password-recovery session exists', () => {
    const consumer = createPushResponseConsumer();

    consumer.capture('response-1', target);
    const outcome = consumer.updateReadiness(READY_RECOVERY_ONLY);

    expect(outcome).toEqual({ kind: 'discarded' });
  });

  it('5. never re-navigates for the same response id after successful consumption', () => {
    const consumer = createPushResponseConsumer();

    consumer.capture('response-1', target);
    consumer.updateReadiness(READY_WITH_SESSION);

    expect(consumer.capture('response-1', target)).toEqual({ kind: 'none' });
  });

  it('5b. never re-navigates for the same response id after a discard', () => {
    const consumer = createPushResponseConsumer();

    consumer.capture('response-1', target);
    consumer.updateReadiness(READY_NO_SESSION);

    expect(consumer.capture('response-1', target)).toEqual({ kind: 'none' });
  });

  it('6. navigates immediately when the session is already ready (background/live path)', () => {
    const consumer = createPushResponseConsumer();
    consumer.updateReadiness(READY_WITH_SESSION);

    const outcome = consumer.capture('response-1', target);

    expect(outcome).toEqual({ kind: 'navigate', target });
  });

  it('7. discards a malformed/unknown payload regardless of session readiness', () => {
    const loadingConsumer = createPushResponseConsumer();
    expect(loadingConsumer.capture('response-1', null)).toEqual({ kind: 'discarded' });

    const readyConsumer = createPushResponseConsumer();
    readyConsumer.updateReadiness(READY_WITH_SESSION);
    expect(readyConsumer.capture('response-2', null)).toEqual({ kind: 'discarded' });
  });

  it('does not duplicate navigation when a distinct second response arrives after the first resolves', () => {
    const consumer = createPushResponseConsumer();
    consumer.updateReadiness(READY_WITH_SESSION);

    expect(consumer.capture('response-1', target)).toEqual({ kind: 'navigate', target });

    const secondTarget: PushNavigationTarget = {
      screen: 'appointment',
      appointmentId: '22222222-3333-4444-5555-666666666666',
      petId: '77777777-8888-9999-aaaa-bbbbbbbbbbbb',
    };
    expect(consumer.capture('response-2', secondTarget)).toEqual({
      kind: 'navigate',
      target: secondTarget,
    });
  });
});
