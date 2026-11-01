import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { TabSelector } from '@/components/design-system/tab-selector';
import {
  GuardianAppointmentList,
  type GuardianAppointmentListCopy,
} from '@/components/guardian-appointment-list';
import {
  useGuardianActiveAppointments,
  useGuardianAppointmentHistory,
} from '@/hooks/use-guardian-appointment-pages';
import { useLocale } from '@/i18n/locale-provider';
import { appointmentDetailHref } from '@/lib/appointments-navigation';
import type { GuardianAppointmentListItem } from '@/lib/guardian-appointments';
import { goBackOr } from '@/lib/navigation';
import { useSession } from '@/lib/session-provider';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type AppointmentsTab = 'active' | 'history';

const ACTIVE_COPY: GuardianAppointmentListCopy = {
  loadingKey: 'appointments.activeLoading',
  errorKey: 'appointments.activeLoadError',
  emptyKey: 'appointments.activeEmpty',
  emptyIcon: 'calendar-outline',
};

const HISTORY_COPY: GuardianAppointmentListCopy = {
  loadingKey: 'appointments.historyLoading',
  errorKey: 'appointments.historyLoadError',
  emptyKey: 'appointments.historyEmpty',
  emptyIcon: 'time-outline',
};

export default function AppointmentsRoute() {
  const { user } = useSession();
  // A different session owns fresh lists: one User's rows are never shown,
  // continued or refreshed under another.
  return <AppointmentsScreen key={user?.id ?? ''} />;
}

/**
 * "My appointments" (SPEC-APT-011 §13, BR-40): the Appointments of every Pet
 * the Guardian currently guards, in two tabs — Active (initial: REQUESTED and
 * CONFIRMED, including those whose time has passed, so it is not labelled
 * "Upcoming", §6) and History (terminal) — each ONE compact list read page by
 * page through its own read, only once its tab is shown, with its own rows,
 * cursor, loading and errors, kept while the other tab is shown. A focus (back
 * from the detail, where writes happen) restarts only the tab on screen; the
 * other restarts when shown again. Never `get_pet_appointments`.
 *
 * A row opens the existing Appointment detail with its Pet, which re-reads
 * and re-authorizes it; nothing is acted on here. Requesting an Appointment
 * keeps its entry point from the Clinic, where the Pet is chosen. A legacy
 * `?petId=` (the detail's back target) is ignored: every Pet is listed.
 */
function AppointmentsScreen() {
  const { t } = useLocale();
  const [tab, setTab] = useState<AppointmentsTab>('active');
  const active = useGuardianActiveAppointments(tab === 'active');
  const history = useGuardianAppointmentHistory(tab === 'history');

  const open = (row: GuardianAppointmentListItem) => {
    router.push(appointmentDetailHref(row.id, row.petId));
  };

  const header = (
    <View style={styles.header}>
      <AppTopBar onBack={() => goBackOr('/')} />
      <Text style={styles.title} accessibilityRole="header">
        {t('appointments.title')}
      </Text>
      <TabSelector
        tabs={[
          { value: 'active', label: t('appointments.activeSectionTitle') },
          { value: 'history', label: t('appointments.historicalSectionTitle') },
        ]}
        selected={tab}
        onSelect={setTab}
        testIDPrefix="appointments-tab"
      />
    </View>
  );

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      {tab === 'active' ? (
        <GuardianAppointmentList header={header} list={active} copy={ACTIVE_COPY} onOpen={open} />
      ) : (
        <GuardianAppointmentList header={header} list={history} copy={HISTORY_COPY} onOpen={open} />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  header: { gap: spacing.lg },
  title: { ...typography.h1, color: colors.textPrimary },
});
