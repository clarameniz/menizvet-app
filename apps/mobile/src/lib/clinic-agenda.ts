import type { ComponentProps } from 'react';
import type { Ionicons } from '@expo/vector-icons';

import type {
  ClinicPendingAppointment,
  PendingCategory,
  PendingReason,
  PendingTotals,
} from '@/data/clinic-calendar';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure presentation helpers for the agenda's Pending view (SPEC-APT-012
 * BR-57). The backend's classification is used as it is: nothing here
 * recomputes a reason, a category, an order or a capability.
 */

type IconName = ComponentProps<typeof Ionicons>['name'];

/**
 * How each category reads. Only ACTION_REQUIRED is presented as work for the
 * actor; the other two are explained as waiting for the Guardian or as
 * information, never as tasks.
 */
export const PENDING_CATEGORY_PRESENTATION: Readonly<
  Record<
    PendingCategory,
    { titleKey: TranslationKey; noteKey: TranslationKey | null; icon: IconName }
  >
> = {
  ACTION_REQUIRED: {
    titleKey: 'clinicAgenda.categoryActionRequired',
    noteKey: null,
    icon: 'alert-circle-outline',
  },
  AWAITING_GUARDIAN: {
    titleKey: 'clinicAgenda.categoryAwaitingGuardian',
    noteKey: 'clinicAgenda.categoryAwaitingGuardianNote',
    icon: 'hourglass-outline',
  },
  INFORMATIONAL: {
    titleKey: 'clinicAgenda.categoryInformational',
    noteKey: 'clinicAgenda.categoryInformationalNote',
    icon: 'information-circle-outline',
  },
};

/**
 * Each reason as a neutral statement of the situation — never the name of an
 * operation, so it never promises one the actor may not be able to perform
 * (the detail decides what to offer; the backend decides what succeeds). The
 * row shows the short label; its accessible name carries the full one.
 */
export const PENDING_REASON_PRESENTATION: Readonly<
  Record<PendingReason, { shortKey: TranslationKey; labelKey: TranslationKey; icon: IconName }>
> = {
  ATTENDANCE_OUTCOME: {
    shortKey: 'clinicAgenda.reasonAttendanceOutcomeShort',
    labelKey: 'clinicAgenda.reasonAttendanceOutcome',
    icon: 'clipboard-outline',
  },
  REQUEST_DECISION: {
    shortKey: 'clinicAgenda.reasonRequestDecisionShort',
    labelKey: 'clinicAgenda.reasonRequestDecision',
    icon: 'mail-unread-outline',
  },
  PROPOSAL_NOT_FEASIBLE: {
    shortKey: 'clinicAgenda.reasonProposalNotFeasibleShort',
    labelKey: 'clinicAgenda.reasonProposalNotFeasible',
    icon: 'warning-outline',
  },
  GUARDIAN_PROPOSAL: {
    shortKey: 'clinicAgenda.reasonGuardianProposalShort',
    labelKey: 'clinicAgenda.reasonGuardianProposal',
    icon: 'information-circle-outline',
  },
  AWAITING_GUARDIAN: {
    shortKey: 'clinicAgenda.reasonAwaitingGuardianShort',
    labelKey: 'clinicAgenda.reasonAwaitingGuardian',
    icon: 'hourglass-outline',
  },
};

/** The summary's categories: the main figure first, the two secondary ones after. */
export const PENDING_SUMMARY_ORDER: readonly PendingCategory[] = [
  'ACTION_REQUIRED',
  'AWAITING_GUARDIAN',
  'INFORMATIONAL',
];

/** One item of the Pending list: a category heading, or a row framed within its category. */
export type PendingListItem =
  | {
      kind: 'category';
      category: PendingCategory;
      /** Rows of this category loaded so far. */
      loaded: number;
      /** The whole classification's count, from the backend. */
      total: number;
    }
  | { kind: 'row'; row: ClinicPendingAppointment; first: boolean; last: boolean };

/**
 * The loaded rows, in the backend's order, with a heading before each run of
 * one category. A category whose rows are not all loaded yet shows how many
 * of its total are shown; a category with no row loaded yet gets no heading
 * (the summary still counts it).
 */
export function pendingListItems(
  rows: readonly ClinicPendingAppointment[],
  totals: PendingTotals,
): PendingListItem[] {
  const loaded: Record<PendingCategory, number> = {
    ACTION_REQUIRED: 0,
    AWAITING_GUARDIAN: 0,
    INFORMATIONAL: 0,
  };
  for (const row of rows) loaded[row.category] += 1;

  const items: PendingListItem[] = [];
  rows.forEach((row, index) => {
    const previous = rows[index - 1];
    const next = rows[index + 1];
    const first = previous === undefined || previous.category !== row.category;
    if (first) {
      items.push({
        kind: 'category',
        category: row.category,
        loaded: loaded[row.category],
        total: totals[row.category],
      });
    }
    items.push({
      kind: 'row',
      row,
      first,
      last: next === undefined || next.category !== row.category,
    });
  });
  return items;
}
