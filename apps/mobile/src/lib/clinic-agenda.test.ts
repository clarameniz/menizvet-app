import {
  PENDING_REASONS,
  type ClinicPendingAppointment,
  type PendingReason,
} from '@/data/clinic-calendar';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import {
  PENDING_CATEGORY_PRESENTATION,
  PENDING_REASON_PRESENTATION,
  pendingListItems,
} from '@/lib/clinic-agenda';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

function row(id: string, reason: PendingReason): ClinicPendingAppointment {
  return {
    appointment: { id } as ClinicScheduleAppointment,
    reason,
    category: PENDING_REASONS[reason].category,
    rank: PENDING_REASONS[reason].rank,
  };
}

const TOTALS = { ACTION_REQUIRED: 3, AWAITING_GUARDIAN: 4, INFORMATIONAL: 1 };

describe('pendingListItems (SPEC-APT-012 BR-57)', () => {
  it("puts a heading before each run of one category, in the backend's order", () => {
    const items = pendingListItems(
      [
        row('a', 'ATTENDANCE_OUTCOME'),
        row('b', 'REQUEST_DECISION'),
        row('c', 'GUARDIAN_PROPOSAL'),
        row('d', 'AWAITING_GUARDIAN'),
      ],
      TOTALS,
    );
    expect(
      items.map((item) =>
        item.kind === 'category'
          ? `${item.category} ${item.loaded}/${item.total}`
          : `${item.row.appointment.id}${item.first ? ' first' : ''}${item.last ? ' last' : ''}`,
      ),
    ).toEqual([
      'ACTION_REQUIRED 2/3',
      'a first',
      'b last',
      'INFORMATIONAL 1/1',
      'c first last',
      'AWAITING_GUARDIAN 1/4',
      'd first last',
    ]);
  });

  it('shows no heading for a category none of whose rows is loaded yet', () => {
    const items = pendingListItems([row('a', 'ATTENDANCE_OUTCOME')], TOTALS);
    expect(items.filter((item) => item.kind === 'category')).toEqual([
      { kind: 'category', category: 'ACTION_REQUIRED', loaded: 1, total: 3 },
    ]);
    expect(pendingListItems([], TOTALS)).toEqual([]);
  });
});

describe('Pending presentation', () => {
  it('labels every category and reason in Spanish and English', () => {
    const keys = [
      ...Object.values(PENDING_CATEGORY_PRESENTATION).flatMap((item) => [
        item.titleKey,
        ...(item.noteKey === null ? [] : [item.noteKey]),
      ]),
      ...Object.values(PENDING_REASON_PRESENTATION).flatMap((item) => [
        item.shortKey,
        item.labelKey,
      ]),
    ];
    for (const key of keys) {
      const [namespace, name] = key.split('.');
      for (const locale of [es, en] as Record<string, Record<string, string>>[]) {
        expect(locale[namespace][name]).toEqual(expect.any(String));
      }
    }
    expect(Object.keys(PENDING_REASON_PRESENTATION).sort()).toEqual(
      Object.keys(PENDING_REASONS).sort(),
    );
  });

  it('presents only ACTION_REQUIRED as work; the other two are explained', () => {
    expect(PENDING_CATEGORY_PRESENTATION.ACTION_REQUIRED.noteKey).toBeNull();
    expect(PENDING_CATEGORY_PRESENTATION.AWAITING_GUARDIAN.noteKey).not.toBeNull();
    expect(PENDING_CATEGORY_PRESENTATION.INFORMATIONAL.noteKey).not.toBeNull();
  });
});
