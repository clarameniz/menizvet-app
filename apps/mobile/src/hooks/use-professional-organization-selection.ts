import { useSyncExternalStore } from 'react';

import {
  getProfessionalOrganizationSelection,
  subscribeProfessionalOrganizationSelection,
  type ProfessionalOrganizationSelection,
} from '@/lib/professional-organization-selection';

/** The current professional Organization selection; re-renders when it changes. */
export function useProfessionalOrganizationSelection(): ProfessionalOrganizationSelection | null {
  return useSyncExternalStore(
    subscribeProfessionalOrganizationSelection,
    getProfessionalOrganizationSelection,
    getProfessionalOrganizationSelection,
  );
}
