import { useCallback } from 'react';

import {
  getMyOrganizationProfessionalClinicsPage,
  organizationClinicsCursorOf,
  type OrganizationClinicsCursor,
  type OrganizationProfessionalClinic,
} from '@/data/professional-clinics';
import { usePagedList, type PageResult } from '@/hooks/use-paged-list';
import { mapProfessionalClinicsErrorToKey } from '@/i18n/professional-context-error-messages';

/** Clinics per page on the Organization's Clinics screen (SPEC-ORG-008 BR-26). */
export const ORGANIZATION_CLINICS_PAGE_SIZE = 20;

function clinicId(row: OrganizationProfessionalClinic): string {
  return row.clinicId;
}

// The read has no denial (BR-21): no access is an empty page.
function neverAccessDenied(): boolean {
  return false;
}

function ignoreAccessLost(): void {}

/**
 * The Professional Clinics of one Organization, page by page, for one
 * submitted search ('' = none). A new Organization or search is a new list
 * (see `usePagedList`): its rows and cursor are dropped at once and answers to
 * the previous one are ignored.
 */
export function useOrganizationClinicsPage(
  organizationId: string | null,
  search: string,
  active: boolean,
) {
  const readPage = useCallback(
    async (
      cursor: OrganizationClinicsCursor | null,
    ): Promise<PageResult<OrganizationProfessionalClinic, never>> => {
      if (organizationId === null) return { data: { rows: [], meta: null }, error: null };
      const result = await getMyOrganizationProfessionalClinicsPage(
        organizationId,
        search === '' ? null : search,
        cursor,
        ORGANIZATION_CLINICS_PAGE_SIZE,
      );
      return result.error !== null
        ? result
        : { data: { rows: result.data, meta: null }, error: null };
    },
    [organizationId, search],
  );
  return usePagedList({
    active,
    pageSize: ORGANIZATION_CLINICS_PAGE_SIZE,
    readPage,
    idOf: clinicId,
    cursorOf: organizationClinicsCursorOf,
    isAccessDenied: neverAccessDenied,
    errorKeyOf: mapProfessionalClinicsErrorToKey,
    onAccessLost: ignoreAccessLost,
  });
}
