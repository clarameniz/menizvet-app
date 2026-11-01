import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { StateMessage } from '@/components/design-system/state-message';
import { ProfessionalEntryAction } from '@/components/professional-entry-action';
import {
  getMyProfessionalClinics,
  type ProfessionalClinic,
  type ProfessionalClinics,
} from '@/data/professional-clinics';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { mapProfessionalClinicsErrorToKey } from '@/i18n/professional-context-error-messages';
import { appointmentHoursHref } from '@/lib/appointment-hours';
import { findProfessionalClinic, professionalClinicWorkflows } from '@/lib/clinic-schedule-display';
import { clinicSettingsHref } from '@/lib/clinic-settings';
import { goBackOr } from '@/lib/navigation';
import { professionalClinicLabel } from '@/lib/professional-clinics-display';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'loaded'; result: ProfessionalClinics };

/**
 * Professional Clinic screen (SPEC-ORG-008): one Professional Clinic's
 * professional context and the workflows this app offers for it. Not the
 * public Clinic detail.
 *
 * The Clinic is resolved only from a fresh get_my_professional_clinics() read
 * by the route's `clinicId` — never from navigation parameters — so a Clinic
 * that is no longer a Professional Clinic (refresh or direct entry) shows a
 * calm "no longer available" state. Workflow entries derive only from KNOWN
 * capabilities and are advisory: each workflow's own read re-authorizes
 * server-side. A Clinic whose capabilities are all unknown to this app version
 * stays valid and simply offers no entry.
 *
 * Re-reads on every focus. Only the first load shows the loading/error
 * states; a later refresh updates in place and a failed refresh keeps the
 * screen as it is. Latest read wins.
 */
export default function ProfessionalClinicScreen() {
  const { t } = useLocale();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' });

  const isMountedRef = useRef(true);
  const loadSeqRef = useRef(0);
  const hasLoadedRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const load = useCallback(() => {
    const seq = ++loadSeqRef.current;

    getMyProfessionalClinics().then((result) => {
      if (!isMountedRef.current || seq !== loadSeqRef.current) return;

      if (result.error !== null) {
        // Only the first load may replace the screen with the error state.
        if (!hasLoadedRef.current) {
          setLoadState({
            kind: 'error',
            messageKey: mapProfessionalClinicsErrorToKey(result.error),
          });
        }
        return;
      }

      hasLoadedRef.current = true;
      setLoadState({ kind: 'loaded', result: result.data });
    });
  }, []);

  useFocusEffect(load);

  function handleRetry() {
    setLoadState({ kind: 'loading' });
    load();
  }

  const goBack = () => goBackOr('/professional/clinics');
  const backToClinics = () => router.dismissTo('/professional/clinics');

  const clinic =
    loadState.kind === 'loaded' ? findProfessionalClinic(loadState.result, clinicId) : null;

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppTopBar onBack={goBack} />

        {loadState.kind === 'loading' ? (
          <StateMessage tone="loading" message={t('professionalClinic.loading')} />
        ) : loadState.kind === 'error' ? (
          <View style={styles.stateBlock}>
            <StateMessage tone="error" message={t(loadState.messageKey)} />
            <Button label={t('professional.retry')} onPress={handleRetry} />
            <Button variant="secondary" label={t('common.back')} onPress={goBack} />
          </View>
        ) : clinic === null ? (
          <View style={styles.stateBlock}>
            <StateMessage
              tone="empty"
              icon="medkit-outline"
              message={t('professionalClinic.notAvailable')}
            />
            <Button
              variant="secondary"
              label={t('professionalClinic.backToClinics')}
              onPress={backToClinics}
            />
          </View>
        ) : (
          <ClinicContent clinic={clinic} />
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function ClinicContent({ clinic }: { clinic: ProfessionalClinic }) {
  const { t } = useLocale();
  const name = professionalClinicLabel(clinic, t('professional.unnamedClinic'));
  const workflows = professionalClinicWorkflows(clinic);

  return (
    <>
      <View style={styles.header}>
        <Text
          style={[styles.title, clinic.clinicDisplayName === null && styles.unnamed]}
          accessibilityRole="header"
        >
          {name}
        </Text>
        <Text style={styles.organizationName}>{clinic.organizationDisplayName}</Text>
      </View>

      {workflows.length === 0 ? (
        <Text style={styles.mutedText}>{t('professionalClinic.noWorkflows')}</Text>
      ) : (
        <View style={styles.workflowList}>
          {workflows.includes('APPOINTMENT_SCHEDULE') ? (
            <ProfessionalEntryAction
              icon="calendar-outline"
              title={t('professionalClinic.scheduleAction')}
              support={t('professionalClinic.scheduleActionSupport')}
              onPress={() =>
                router.push({
                  pathname: '/professional/clinics/[clinicId]/calendar',
                  params: { clinicId: clinic.clinicId },
                })
              }
            />
          ) : null}
          {workflows.includes('APPOINTMENT_HOURS') ? (
            <ProfessionalEntryAction
              icon="time-outline"
              title={t('professionalClinic.hoursAction')}
              support={t('professionalClinic.hoursActionSupport')}
              onPress={() => router.push(appointmentHoursHref(clinic.clinicId))}
            />
          ) : null}
          {workflows.includes('CLINIC_SETTINGS') ? (
            <ProfessionalEntryAction
              icon="settings-outline"
              title={t('professionalClinic.settingsAction')}
              support={t('professionalClinic.settingsActionSupport')}
              onPress={() => router.push(clinicSettingsHref(clinic.clinicId))}
            />
          ) : null}
        </View>
      )}
    </>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  stateBlock: {
    gap: spacing.md,
  },
  header: {
    gap: spacing.xs,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  unnamed: {
    fontStyle: 'italic',
  },
  organizationName: {
    ...typography.body,
    color: colors.textSecondary,
  },
  workflowList: {
    gap: spacing.md,
  },
  mutedText: {
    ...typography.body,
    color: colors.textSecondary,
  },
});
