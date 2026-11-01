import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Alert,
  FlatList,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { CompactAction } from '@/components/design-system/compact-action';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import { SearchField } from '@/components/design-system/search-field';
import { StateMessage } from '@/components/design-system/state-message';
import {
  EmptyListMessage,
  FramedRow,
  LoadMoreFooter,
  PagedListStatus,
  pagedListStyles,
} from '@/components/paged-list-parts';
import { createClinic } from '@/data/clinic-creation';
import type { OrganizationProfessionalClinic } from '@/data/professional-clinics';
import { getMyProfessionalContext, type ProfessionalContext } from '@/data/professional-context';
import { useOrganizationClinicsPage } from '@/hooks/use-organization-clinics-page';
import { useProfessionalOrganizationSelection } from '@/hooks/use-professional-organization-selection';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { mapProfessionalContextErrorToKey } from '@/i18n/professional-context-error-messages';
import {
  clinicCreationContext,
  clinicCreationStep,
  forgetClinicCreation,
  newClinicCreationIntent,
  rememberClinicCreation,
  unresolvedClinicCreation,
  type ClinicCreationIntent,
} from '@/lib/clinic-creation';
import { clinicSettingsHref } from '@/lib/clinic-settings';
import { goBackOr } from '@/lib/navigation';
import {
  CLINIC_SEARCH_DEBOUNCE_MS,
  CLINIC_SEARCH_MAX_LENGTH,
  offersClinicSearch,
  organizationClinicLabel,
  organizationClinicsBody,
  organizationClinicsHeading,
  submittedClinicSearch,
} from '@/lib/professional-clinics-display';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ContextState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'loaded'; context: ProfessionalContext };

/**
 * Professional Clinics of the Organization selected on `/professional`
 * (SPEC-ORG-008 §11, BR-26). A changed selection owns fresh state: one
 * Organization's search, rows or notices are never shown under another.
 */
export default function ProfessionalClinicsRoute() {
  const selection = useProfessionalOrganizationSelection();
  const organizationId = selection?.organizationId ?? null;
  return <ProfessionalClinicsScreen key={organizationId ?? ''} organizationId={organizationId} />;
}

/**
 * The heading (title and the Organization's name), whether Add Clinic is
 * offered (advisory `ORGANIZATION_CREATE_CLINICS`, SPEC-CLI-001 BR-17) and
 * whether the selection is an Organization of the User at all come from the
 * professional context, read on every focus — never from an empty page of the
 * Clinics read, which is the same for "no access" and "no Clinic". Without a
 * selection the context contains, no Clinic is read and the User is sent back
 * to choose an Organization. Only the first context read shows the loading and
 * error states; a failed later read keeps what is shown.
 *
 * The Clinics are ONE compact list (name and chevron per row) read 20 at a
 * time through `get_my_organization_professional_clinics`, with "Load more".
 * The search is sent to the backend after a 300 ms pause (at once when
 * cleared or submitted); every new search withdraws the previous rows and
 * cursor at once, shows the loading state, and ignores late answers.
 * "No matches" appears only once the new search's first page arrived empty.
 * A focus (back from a Clinic or a new Clinic's settings) restarts the first
 * page and keeps the search. The whole row opens the professional Clinic
 * screen by id, which re-reads and re-authorizes. Capabilities are never
 * rendered.
 *
 * Add Clinic: one confirmation, then one creation intent with one key; a
 * success opens the new Clinic's settings. An uncertain answer keeps the
 * intent and offers a retry with the same key; no new key is created for the
 * Organization until it resolves. No placeholder Clinic is ever shown.
 */
function ProfessionalClinicsScreen({ organizationId }: { organizationId: string | null }) {
  const { t } = useLocale();
  const [contextState, setContextState] = useState<ContextState>({ kind: 'loading' });
  const [typed, setTyped] = useState('');
  const [search, setSearch] = useState('');
  const [clinicsListed, setClinicsListed] = useState(false);
  const [creating, setCreating] = useState(false);
  const [notice, setNotice] = useState<{
    tone: 'info' | 'error';
    messageKey: TranslationKey;
  } | null>(null);

  const isMountedRef = useRef(true);
  const contextSeqRef = useRef(0);
  const hasContextRef = useRef(false);
  const creatingRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const loadContext = useCallback(() => {
    const seq = ++contextSeqRef.current;
    getMyProfessionalContext().then((result) => {
      if (!isMountedRef.current || seq !== contextSeqRef.current) return;
      if (result.error !== null) {
        // Only the first read may replace the screen with the error state.
        if (!hasContextRef.current) {
          setContextState({
            kind: 'error',
            messageKey: mapProfessionalContextErrorToKey(result.error),
          });
        }
        return;
      }
      hasContextRef.current = true;
      setContextState({ kind: 'loaded', context: result.data });
    });
  }, []);

  useFocusEffect(
    useCallback(() => {
      setNotice(null);
      loadContext();
    }, [loadContext]),
  );

  const heading =
    contextState.kind === 'loaded'
      ? organizationClinicsHeading(
          contextState.context,
          organizationId,
          clinicCreationContext(contextState.context, organizationId),
        )
      : null;
  const listOrganizationId = heading?.kind === 'organization' ? heading.organizationId : null;
  const list = useOrganizationClinicsPage(listOrganizationId, search, listOrganizationId !== null);
  const rows = list.state.rows;
  const body = organizationClinicsBody(rows, search);

  // A typed search is submitted after a pause (clearing is submitted at once,
  // in `changeTyped`).
  useEffect(() => {
    const next = submittedClinicSearch(typed);
    if (next === '' || next === search) return;
    const timer = setTimeout(() => setSearch(next), CLINIC_SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [typed, search]);

  // Once Clinics were listed the field stays, so it never disappears under
  // the keyboard while a new search loads.
  if (!clinicsListed && rows !== null && rows.length > 0) setClinicsListed(true);

  const changeTyped = useCallback((value: string) => {
    setTyped(value);
    if (submittedClinicSearch(value) === '') setSearch('');
  }, []);

  const clearSearch = useCallback(() => {
    setTyped('');
    setSearch('');
  }, []);

  const reloadAll = useCallback(() => {
    loadContext();
    void list.reload();
  }, [list, loadContext]);

  function handleRetry() {
    setContextState({ kind: 'loading' });
    loadContext();
  }

  // SPEC-CLI-001 BR-18: one intent at a time, settled only by an
  // authoritative answer for that intent's own Organization.
  const submit = useCallback(
    async (intent: ClinicCreationIntent) => {
      if (creatingRef.current) return;
      creatingRef.current = true;
      setCreating(true);
      setNotice(null);
      rememberClinicCreation(intent);
      AccessibilityInfo.announceForAccessibility(t('clinicCreation.creating'));
      try {
        const step = clinicCreationStep(await createClinic(intent.organizationId, intent.key));
        if (step.kind !== 'uncertain') forgetClinicCreation(intent.organizationId);
        // A User who already left keeps the intent (if unresolved) for later.
        if (!isMountedRef.current) return;
        if (step.kind === 'open') {
          AccessibilityInfo.announceForAccessibility(t('clinicCreation.created'));
          router.push(clinicSettingsHref(step.clinicId));
          return;
        }
        // The uncertain notice derives from the kept intent; a failure is shown once.
        if (step.kind === 'failed') setNotice({ tone: 'error', messageKey: step.messageKey });
        AccessibilityInfo.announceForAccessibility(
          t(step.kind === 'failed' ? step.messageKey : 'clinicCreation.uncertain'),
        );
        reloadAll();
      } finally {
        creatingRef.current = false;
        if (isMountedRef.current) setCreating(false);
      }
    },
    [reloadAll, t],
  );

  const confirmAdd = useCallback(
    (targetOrganizationId: string, organizationDisplayName: string) => {
      if (creatingRef.current) return;
      Alert.alert(
        t('clinicCreation.confirmTitle', { organization: organizationDisplayName }),
        t('clinicCreation.confirmMessage'),
        [
          { text: t('clinicCreation.cancel'), style: 'cancel' },
          {
            text: t('clinicCreation.confirm'),
            onPress: () => {
              // An unresolved intent for this Organization is reused, never replaced.
              const intent =
                unresolvedClinicCreation(targetOrganizationId) ??
                newClinicCreationIntent(targetOrganizationId);
              if (intent === null) {
                setNotice({ tone: 'error', messageKey: 'clinicCreation.failed' });
                return;
              }
              void submit(intent);
            },
          },
        ],
      );
    },
    [submit, t],
  );

  const goBack = () => goBackOr('/professional');
  const chooseOrganization = () => router.dismissTo('/professional');

  const title = (
    <Text style={styles.title} accessibilityRole="header">
      {t('professionalClinics.title')}
    </Text>
  );

  if (heading === null || heading.kind === 'noOrganization') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <ScrollView
          contentContainerStyle={styles.stateContent}
          showsVerticalScrollIndicator={false}
        >
          <AppTopBar onBack={goBack} />
          {title}
          {contextState.kind === 'loading' ? (
            <StateMessage tone="loading" message={t('professionalClinics.loading')} />
          ) : contextState.kind === 'error' ? (
            <View style={styles.stateBlock}>
              <StateMessage tone="error" message={t(contextState.messageKey)} />
              <Button label={t('professional.retry')} onPress={handleRetry} />
              <Button variant="secondary" label={t('common.back')} onPress={goBack} />
            </View>
          ) : (
            <View style={styles.stateBlock}>
              <StateMessage
                tone="empty"
                icon="business-outline"
                message={t('professionalClinics.chooseOrganization')}
              />
              <Button
                variant="secondary"
                label={t('professionalClinics.goToProfessional')}
                onPress={chooseOrganization}
              />
            </View>
          )}
        </ScrollView>
      </SafeAreaView>
    );
  }

  // An unresolved intent not in flight here (lost response, or left while in
  // flight) is finished only by a retry with its own key.
  const pending = creating ? null : unresolvedClinicCreation(heading.organizationId);
  const shownNotice =
    notice ??
    (pending !== null
      ? { tone: 'error' as const, messageKey: 'clinicCreation.uncertain' as const }
      : null);
  const addAccessibility = t('clinicCreation.addAccessibility', {
    organization: heading.organizationDisplayName,
  });
  const offersAdd = heading.canCreate && pending === null;
  const showSearch = offersClinicSearch({ body, search, typed, clinicsListed });
  const openAdd = () => confirmAdd(heading.organizationId, heading.organizationDisplayName);

  const header = (
    <View style={styles.header}>
      <AppTopBar onBack={goBack} />
      <View style={styles.heading}>
        {title}
        <View
          style={styles.organization}
          accessible
          accessibilityLabel={t('professionalClinics.organizationAccessibility', {
            organization: heading.organizationDisplayName,
          })}
        >
          <Ionicons name="business-outline" size={18} color={colors.textSecondary} />
          <Text style={styles.organizationName}>{heading.organizationDisplayName}</Text>
        </View>
      </View>
      {shownNotice !== null ? (
        <Notice tone={shownNotice.tone} message={t(shownNotice.messageKey)} />
      ) : null}
      {pending !== null ? (
        <Button
          label={t('clinicCreation.retry')}
          accessibilityLabel={t('clinicCreation.retryAccessibility')}
          onPress={() => {
            void submit(pending);
          }}
        />
      ) : null}
      {/* With no Clinic, Add Clinic is the empty state's primary action instead. */}
      {offersAdd && body !== 'noClinics' && (body !== 'pending' || clinicsListed) ? (
        <View style={styles.actions}>
          <PillButton
            icon="add-circle-outline"
            label={t('clinicCreation.addAction')}
            accessibilityLabel={addAccessibility}
            loading={creating}
            onPress={openAdd}
          />
        </View>
      ) : null}
      {showSearch ? (
        <SearchField
          value={typed}
          onChangeText={changeTyped}
          onClear={clearSearch}
          onSubmit={() => setSearch(submittedClinicSearch(typed))}
          placeholder={t('professionalClinics.searchPlaceholder')}
          accessibilityLabel={t('professionalClinics.searchAccessibility')}
          clearAccessibilityLabel={t('professionalClinics.clearSearch')}
          maxLength={CLINIC_SEARCH_MAX_LENGTH}
        />
      ) : null}
    </View>
  );

  const shownRows = rows ?? [];

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <FlatList
        data={shownRows}
        keyExtractor={(clinic) => clinic.clinicId}
        contentContainerStyle={pagedListStyles.content}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        ListHeaderComponent={
          <View style={pagedListStyles.headerBlock}>
            {header}
            <PagedListStatus
              list={list}
              loadingKey={
                search === '' ? 'professionalClinics.loading' : 'professionalClinics.searching'
              }
              errorKey="professionalClinics.loadError"
            />
          </View>
        }
        renderItem={({ item, index }) => (
          <FramedRow first={index === 0} last={index === shownRows.length - 1}>
            <ClinicRow clinic={item} />
          </FramedRow>
        )}
        ListEmptyComponent={
          body === 'noMatches' ? (
            <View style={styles.emptyBlock}>
              <EmptyListMessage
                icon="search-outline"
                message={t('professionalClinics.noMatches', { search })}
              />
              <View style={styles.actions}>
                <CompactAction
                  icon="close-circle-outline"
                  label={t('professionalClinics.clearSearch')}
                  accessibilityLabel={t('professionalClinics.clearSearch')}
                  onPress={clearSearch}
                />
              </View>
            </View>
          ) : body === 'noClinics' ? (
            heading.canCreate ? (
              <View style={styles.stateBlock}>
                <StateMessage
                  tone="empty"
                  icon="medkit-outline"
                  title={t('clinicCreation.emptyTitle')}
                  message={t('clinicCreation.emptyMessage')}
                />
                {offersAdd ? (
                  <Button
                    label={t('clinicCreation.addAction')}
                    accessibilityLabel={addAccessibility}
                    loading={creating}
                    onPress={openAdd}
                  />
                ) : null}
              </View>
            ) : (
              <View style={styles.stateBlock}>
                <StateMessage
                  tone="empty"
                  icon="medkit-outline"
                  message={t('professionalClinics.empty')}
                />
                <Button variant="secondary" label={t('common.back')} onPress={goBack} />
              </View>
            )
          ) : null
        }
        ListFooterComponent={<LoadMoreFooter list={list} />}
      />
    </SafeAreaView>
  );
}

/**
 * One Clinic: its name (or the unnamed label) and a chevron, announced as one
 * button that opens its professional Clinic screen. Only the id travels in the
 * route; that screen re-reads the Clinic itself.
 */
function ClinicRow({ clinic }: { clinic: OrganizationProfessionalClinic }) {
  const { t } = useLocale();
  const name = organizationClinicLabel(clinic, t('professional.unnamedClinic'));

  return (
    <Pressable
      onPress={() =>
        router.push({
          pathname: '/professional/clinics/[clinicId]',
          params: { clinicId: clinic.clinicId },
        })
      }
      accessibilityRole="button"
      accessibilityLabel={name}
      accessibilityHint={t('professionalClinics.openClinicHint')}
      style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
    >
      <Text
        style={[styles.clinicName, clinic.clinicDisplayName === null && styles.unnamed]}
        numberOfLines={2}
      >
        {name}
      </Text>
      <Ionicons
        name="chevron-forward"
        size={18}
        color={colors.textMuted}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  stateContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  header: {
    gap: spacing.lg,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  heading: {
    gap: spacing.xs,
  },
  organization: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.xs,
  },
  organizationName: {
    ...typography.body,
    color: colors.textSecondary,
    flex: 1,
  },
  stateBlock: {
    gap: spacing.md,
  },
  emptyBlock: {
    gap: spacing.xs,
  },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 52,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    backgroundColor: colors.surface,
  },
  rowPressed: {
    backgroundColor: colors.surfaceSoft,
  },
  clinicName: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    flex: 1,
  },
  unnamed: {
    fontStyle: 'italic',
  },
});
