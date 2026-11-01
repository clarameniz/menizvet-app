import { useCallback } from 'react';

import { BASIC_DISCOVERY_PAGE_SIZE } from '@/constants/discovery';
import {
  discoverPublishedClinicsPage,
  publishedClinicsCursorOf,
  type PublishedClinicSummary,
  type PublishedClinicsCursor,
} from '@/data/clinics';
import { usePagedList, type PageResult } from '@/hooks/use-paged-list';
import type { TranslationKey } from '@/i18n/i18n';

function clinicId(row: PublishedClinicSummary): string {
  return row.clinicId;
}

// A public read: there is no access to lose.
function neverAccessDenied(): boolean {
  return false;
}

function ignoreAccessLost(): void {}

function loadErrorKey(): TranslationKey {
  return 'discoveryBasic.loadError';
}

/**
 * The published Clinics, 20 per page, for one submitted search ('' = none),
 * through `discover_published_clinics` (SPEC-DIS-004). A new search is a new
 * list (see `usePagedList`): its rows and cursor are dropped at once and
 * answers to the previous one are ignored. A focus — back from a Clinic —
 * keeps the search, every loaded page and the position: nothing here changes
 * through a write elsewhere. "Load more" follows the read's own `has_more`.
 */
export function usePublishedClinicsPage(search: string) {
  const readPage = useCallback(
    async (
      cursor: PublishedClinicsCursor | null,
    ): Promise<PageResult<PublishedClinicSummary, never>> => {
      const result = await discoverPublishedClinicsPage(search === '' ? null : search, cursor);
      return result.error !== null
        ? result
        : {
            data: { rows: result.data.clinics, meta: null, hasMore: result.data.hasMore },
            error: null,
          };
    },
    [search],
  );
  return usePagedList({
    active: true,
    pageSize: BASIC_DISCOVERY_PAGE_SIZE,
    refreshOnFocus: false,
    readPage,
    idOf: clinicId,
    cursorOf: publishedClinicsCursorOf,
    isAccessDenied: neverAccessDenied,
    errorKeyOf: loadErrorKey,
    onAccessLost: ignoreAccessLost,
  });
}
