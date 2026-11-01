import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react';

import {
  acceptOrganizationInvitation,
  previewOrganizationInvitation,
} from '@/data/organization-invitations';
import { getMyProfessionalContext } from '@/data/professional-context';
import {
  acceptStep,
  invitationExitHref,
  phaseForPreview,
  UNAVAILABLE_PHASE,
  type InvitationFlowPhase,
} from '@/lib/organization-invitation-flow';
import {
  getOrganizationInvitationIntakeVersion,
  registerOrganizationInvitationScreen,
  subscribeOrganizationInvitationIntake,
  takeStagedOrganizationInvitationLink,
} from '@/lib/organization-invitation-intake';
import {
  clearPendingOrganizationInvitation,
  readPendingOrganizationInvitation,
  savePendingOrganizationInvitation,
} from '@/lib/pending-organization-invitation';
import { setProfessionalOrganizationSelection } from '@/lib/professional-organization-selection';

type FlowSession = {
  isSessionLoading: boolean;
  hasSession: boolean;
  /** Re-runs the preview when the signed-in User changes. */
  userId: string | null;
  /** Advisory (session-reported); the backend enforces confirmation itself. */
  isEmailConfirmed: boolean;
};

type AcceptedMembership = { organizationId: string; membershipId: string };
type Settled = { key: string; phase: InvitationFlowPhase };

const LOADING: InvitationFlowPhase = { kind: 'loading' };

/**
 * Orchestrates SPEC-ORG-003 §12 on the acceptance screen: takes a newly
 * received link into the secure store, previews it once authenticated,
 * accepts only on explicit request, and after acceptance re-reads the
 * professional context before entering the Professional area.
 *
 * The secret is read from the secure store inside each async step and passed
 * straight to the RPC; it is never put in React state, route params, or logs.
 * A phase belongs to the request (link, session, User) it was produced for,
 * so a new request shows loading until its own result arrives, and every
 * async completion is dropped once a newer step started or the screen left.
 */
export function useOrganizationInvitationFlow(session: FlowSession) {
  const { isSessionLoading, hasSession, userId, isEmailConfirmed } = session;
  const intakeVersion = useSyncExternalStore(
    subscribeOrganizationInvitationIntake,
    getOrganizationInvitationIntakeVersion,
    getOrganizationInvitationIntakeVersion,
  );
  const requestKey = `${intakeVersion}|${hasSession ? (userId ?? '') : '-'}`;
  const [settled, setSettled] = useState<Settled | null>(null);
  const generation = useRef(0);
  const accepted = useRef<AcceptedMembership | null>(null);
  const leaving = useRef(false);
  const phase = !isSessionLoading && settled?.key === requestKey ? settled.phase : LOADING;

  useEffect(() => registerOrganizationInvitationScreen(), []);
  useEffect(
    () => () => {
      generation.current += 1;
    },
    [],
  );

  const begin = useCallback(() => {
    generation.current += 1;
    const current = generation.current;
    return () => generation.current !== current;
  }, []);

  const showPreviewOf = useCallback(async (key: string, isStale: () => boolean) => {
    const credential = await readPendingOrganizationInvitation();
    if (isStale()) return;
    if (credential === null) {
      setSettled({ key, phase: UNAVAILABLE_PHASE });
      return;
    }
    const result = await previewOrganizationInvitation(credential);
    if (isStale()) return;
    const next = phaseForPreview(result);
    if (next.clearCredential) await clearPendingOrganizationInvitation();
    if (isStale()) return;
    setSettled({ key, phase: next.phase });
  }, []);

  const enterProfessional = useCallback(
    async (membership: AcceptedMembership, key: string, isStale: () => boolean) => {
      accepted.current = {
        organizationId: membership.organizationId,
        membershipId: membership.membershipId,
      };
      setSettled({ key, phase: { kind: 'completing' } });
      const context = await getMyProfessionalContext();
      if (isStale()) return;
      const organization = context.data?.organizations.find(
        (candidate) =>
          candidate.organizationId === membership.organizationId &&
          candidate.membershipId === membership.membershipId,
      );
      if (organization === undefined) {
        setSettled({ key, phase: { kind: 'contextFailed' } });
        return;
      }
      setProfessionalOrganizationSelection({
        membershipId: organization.membershipId,
        organizationId: organization.organizationId,
      });
      router.replace('/professional');
    },
    [],
  );

  // Intake, then the authoritative preview — again whenever a new link
  // arrives or the signed-in User changes (sign-in resumes here).
  useEffect(() => {
    if (isSessionLoading) return;
    const key = requestKey;
    const isStale = begin();
    // A newly received link (or a new session) makes the screen live again.
    leaving.current = false;
    void (async () => {
      const link = takeStagedOrganizationInvitationLink();
      // A newer link replaces any older pending proof; an invalid one stores
      // nothing and shows the generic unavailable state.
      if (link?.kind === 'credential') await savePendingOrganizationInvitation(link.credential);
      if (link?.kind === 'invalid') await clearPendingOrganizationInvitation();
      if (isStale()) return;
      if (!hasSession) {
        const credential = await readPendingOrganizationInvitation();
        if (isStale()) return;
        setSettled({ key, phase: credential === null ? UNAVAILABLE_PHASE : { kind: 'signedOut' } });
        return;
      }
      await showPreviewOf(key, isStale);
    })();
  }, [begin, hasSession, isSessionLoading, requestKey, showPreviewOf]);

  const accept = useCallback(async () => {
    if (phase.kind !== 'review') return;
    const step = acceptStep(phase, isEmailConfirmed);
    if (step === 'blocked') return;
    const key = requestKey;
    if (step === 'confirmMismatch') {
      setSettled({ key, phase: { ...phase, step: 'confirmMismatch', notice: null } });
      return;
    }
    const review = phase;
    const isStale = begin();
    setSettled({ key, phase: { ...review, step: 'accepting', notice: null } });

    const credential = await readPendingOrganizationInvitation();
    if (isStale()) return;
    if (credential === null) {
      setSettled({ key, phase: UNAVAILABLE_PHASE });
      return;
    }
    const result = await acceptOrganizationInvitation(credential);
    if (isStale()) return;

    if (result.kind === 'accepted') {
      await clearPendingOrganizationInvitation();
      if (isStale()) return;
      await enterProfessional(result, key, isStale);
      return;
    }
    if (result.kind === 'verificationRequired') {
      setSettled({ key, phase: { ...review, step: 'ready', notice: 'verificationRequired' } });
      return;
    }
    if (result.kind === 'authenticationRequired') {
      setSettled({ key, phase: { kind: 'signedOut' } });
      return;
    }

    // Failure or lost response: the authoritative preview decides.
    const again = await previewOrganizationInvitation(credential);
    if (isStale()) return;
    if (again.kind === 'preview' && again.preview.state === 'ACCEPTED_BY_YOU') {
      // Provenance proves this User's acceptance committed; the idempotent
      // acceptance (BR-21) creates nothing and names the Membership.
      const settledAcceptance = await acceptOrganizationInvitation(credential);
      if (isStale()) return;
      await clearPendingOrganizationInvitation();
      if (isStale()) return;
      if (settledAcceptance.kind === 'accepted') {
        await enterProfessional(settledAcceptance, key, isStale);
      } else {
        setSettled({ key, phase: phaseForPreview(again).phase });
      }
      return;
    }
    if (again.kind === 'preview' && again.preview.state === 'PENDING') {
      setSettled({
        key,
        phase: { kind: 'review', preview: again.preview, step: 'ready', notice: 'notAccepted' },
      });
      return;
    }
    const next = phaseForPreview(again);
    if (next.clearCredential) await clearPendingOrganizationInvitation();
    if (isStale()) return;
    setSettled({
      key,
      phase:
        next.phase.kind === 'failed'
          ? { ...review, step: 'ready', notice: 'notAccepted' }
          : next.phase,
    });
  }, [begin, enterProfessional, isEmailConfirmed, phase, requestKey]);

  const cancelMismatch = useCallback(() => {
    if (phase.kind === 'review' && phase.step === 'confirmMismatch') {
      setSettled({ key: requestKey, phase: { ...phase, step: 'ready' } });
    }
  }, [phase, requestKey]);

  const retry = useCallback(() => {
    const isStale = begin();
    setSettled({ key: requestKey, phase: LOADING });
    void showPreviewOf(requestKey, isStale);
  }, [begin, requestKey, showPreviewOf]);

  const reloadAccess = useCallback(() => {
    if (accepted.current === null) return;
    void enterProfessional(accepted.current, requestKey, begin());
  }, [begin, enterProfessional, requestKey]);

  /**
   * "Not now": local abandonment only — the Invitation stays pending on the
   * server and no RPC is called. Forgets every local trace (a not-yet-taken
   * staged link, the in-process and keystore proof, in-flight steps), then
   * leaves to the neutral landing of the current session. Repeated taps while
   * leaving are ignored.
   */
  const notNow = useCallback(async () => {
    if (leaving.current) return;
    leaving.current = true;
    begin();
    takeStagedOrganizationInvitationLink();
    await clearPendingOrganizationInvitation();
    router.replace(invitationExitHref(hasSession));
  }, [begin, hasSession]);

  return { phase, accept, cancelMismatch, retry, reloadAccess, notNow };
}
