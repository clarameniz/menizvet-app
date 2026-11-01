import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';

import {
  getOrganizationPendingInvitationsPage,
  getOrganizationStaffMembersPage,
  STAFF_ACCESS_DENIED,
  staffInvitationsCursorOf,
  staffMembersCursorOf,
  type PendingStaffInvitation,
  type StaffInvitationsCursor,
  type StaffMemberRow,
  type StaffMembersCursor,
} from '@/data/organization-staff';
import {
  getMyProfessionalContext,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
} from '@/data/professional-context';
import { usePagedList, type PageResult } from '@/hooks/use-paged-list';
import type { TranslationKey } from '@/i18n/i18n';
import { setProfessionalOrganizationSelection } from '@/lib/professional-organization-selection';
import { NO_STAFF_ACTIONS, staffActionsFor, type StaffActions } from '@/lib/staff-invitation';

/** Members per page on the Staff screen (SPEC-ORG-009 BR-13: 1–50). */
export const STAFF_MEMBERS_PAGE_SIZE = 25;

/** Pending Invitations per page on the Staff screen (SPEC-ORG-009 BR-15: 1–50). */
export const STAFF_INVITATIONS_PAGE_SIZE = 20;

function isStaffAccessDenied(error: string): boolean {
  return error === STAFF_ACCESS_DENIED;
}

function staffErrorKey(error: string): TranslationKey {
  return error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED ? 'errors.sessionExpired' : 'staff.loadError';
}

function memberId(row: StaffMemberRow): string {
  return row.membershipId;
}

function invitationId(invitation: PendingStaffInvitation): string {
  return invitation.invitationId;
}

/** The Staff screen's Members tab (SPEC-ORG-009 BR-13, BR-16); see `usePagedList`. */
export function useStaffMembers(organizationId: string, active: boolean, onAccessLost: () => void) {
  const readPage = useCallback(
    async (cursor: StaffMembersCursor | null): Promise<PageResult<StaffMemberRow, never>> => {
      const result = await getOrganizationStaffMembersPage(
        organizationId,
        cursor,
        STAFF_MEMBERS_PAGE_SIZE,
      );
      return result.error !== null
        ? result
        : { data: { rows: result.data, meta: null }, error: null };
    },
    [organizationId],
  );
  return usePagedList({
    active,
    pageSize: STAFF_MEMBERS_PAGE_SIZE,
    readPage,
    idOf: memberId,
    cursorOf: staffMembersCursorOf,
    isAccessDenied: isStaffAccessDenied,
    errorKeyOf: staffErrorKey,
    onAccessLost,
  });
}

/** The Staff screen's Invitations tab (SPEC-ORG-009 BR-15, BR-16); see `usePagedList`. */
export function useStaffInvitations(
  organizationId: string,
  active: boolean,
  onAccessLost: () => void,
) {
  const readPage = useCallback(
    async (
      cursor: StaffInvitationsCursor | null,
    ): Promise<PageResult<PendingStaffInvitation, never>> => {
      const result = await getOrganizationPendingInvitationsPage(
        organizationId,
        cursor,
        STAFF_INVITATIONS_PAGE_SIZE,
      );
      return result.error !== null
        ? result
        : { data: { rows: result.data, meta: null }, error: null };
    },
    [organizationId],
  );
  return usePagedList({
    active,
    pageSize: STAFF_INVITATIONS_PAGE_SIZE,
    readPage,
    idOf: invitationId,
    cursorOf: staffInvitationsCursorOf,
    isAccessDenied: isStaffAccessDenied,
    errorKeyOf: staffErrorKey,
    onAccessLost,
  });
}

export type StaffScreenContext = {
  /** Advisory actions (SPEC-ORG-009 §7); none until, or unless, the context is read. */
  actions: StaffActions;
  /** The route Organization's display name, or `null` while unknown. */
  organizationName: string | null;
};

/**
 * The Staff screen's professional context (SPEC-ORG-007), read on every
 * focus, latest answer wins: the route Organization's advisory Staff actions
 * and display name. A failed read keeps what was known (no action before the
 * first success). Reading it also returns the landing's in-memory Organization
 * selection to this Organization — presentation only, never read authority.
 */
export function useStaffScreenContext(organizationId: string): StaffScreenContext {
  const [context, setContext] = useState<StaffScreenContext>({
    actions: NO_STAFF_ACTIONS,
    organizationName: null,
  });
  const isMountedRef = useRef(true);
  const seqRef = useRef(0);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useFocusEffect(
    useCallback(() => {
      const seq = ++seqRef.current;
      void getMyProfessionalContext().then((result) => {
        if (!isMountedRef.current || seq !== seqRef.current || result.error !== null) return;
        const organization = result.data.organizations.find(
          (candidate) => candidate.organizationId.toLowerCase() === organizationId.toLowerCase(),
        );
        setContext({
          actions: staffActionsFor(result.data, organizationId),
          organizationName: organization?.organizationDisplayName ?? null,
        });
        if (organization !== undefined) {
          setProfessionalOrganizationSelection({
            membershipId: organization.membershipId,
            organizationId: organization.organizationId,
          });
        }
      });
    }, [organizationId]),
  );

  return context;
}
