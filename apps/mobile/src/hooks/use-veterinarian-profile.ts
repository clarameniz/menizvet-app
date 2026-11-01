import { useCallback, useEffect, useState } from 'react';

import { getMyProfessionalContext } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import { mapProfessionalContextErrorToKey } from '@/i18n/professional-context-error-messages';
import { createAppointmentHoursLifecycle } from '@/lib/appointment-hours-lifecycle';
import {
  veterinarianProfileAvailability,
  type VeterinarianProfileAvailability,
} from '@/lib/veterinarian-profile';

export type VeterinarianProfileState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'loaded'; availability: VeterinarianProfileAvailability };

/**
 * The self-service Profile screen's read of the advisory professional context
 * (SPEC-VET-001 §13), with the shared terminal lifecycle: latest read wins and
 * nothing updates the screen once it is leaving.
 */
export function useVeterinarianProfile() {
  const [state, setState] = useState<VeterinarianProfileState>({ kind: 'loading' });
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  useEffect(() => {
    lifecycle.setMounted(true);
    return () => lifecycle.setMounted(false);
  }, [lifecycle]);
  const reload = useCallback(async () => {
    const token = lifecycle.beginLoad();
    const result = await getMyProfessionalContext();
    if (!lifecycle.isCurrentLoad(token)) return;
    setState(
      result.error === null
        ? { kind: 'loaded', availability: veterinarianProfileAvailability(result.data) }
        : { kind: 'error', messageKey: mapProfessionalContextErrorToKey(result.error) },
    );
  }, [lifecycle]);
  /** A re-read showed an existing Profile: creation is no longer offered. */
  const markCompleted = useCallback(() => {
    if (lifecycle.isActive()) setState({ kind: 'loaded', availability: 'completed' });
  }, [lifecycle]);
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);
  const isActive = useCallback(() => lifecycle.isActive(), [lifecycle]);
  return { state, reload, markCompleted, leave, isActive };
}
