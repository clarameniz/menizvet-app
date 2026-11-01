import { TabSelector } from '@/components/design-system/tab-selector';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';

/** The professional agenda's views (SPEC-APT-012 §14). */
export type ClinicAgendaTab = 'calendar' | 'pending' | 'history';

const TABS: readonly { tab: ClinicAgendaTab; labelKey: TranslationKey }[] = [
  { tab: 'calendar', labelKey: 'clinicAgenda.calendarTab' },
  { tab: 'pending', labelKey: 'clinicAgenda.pendingTab' },
  { tab: 'history', labelKey: 'clinicAgenda.historyTab' },
];

/** The agenda's three-way selector under its header (Calendar, Pending, History). */
export function ClinicAgendaTabs({
  selected,
  onSelect,
}: {
  selected: ClinicAgendaTab;
  onSelect: (tab: ClinicAgendaTab) => void;
}) {
  const { t } = useLocale();
  return (
    <TabSelector
      tabs={TABS.map(({ tab, labelKey }) => ({ value: tab, label: t(labelKey) }))}
      selected={selected}
      onSelect={onSelect}
      testIDPrefix="agenda-tab"
    />
  );
}
