import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { StateMessage } from '@/components/design-system/state-message';
import { ProfessionalEntryAction } from '@/components/professional-entry-action';
import { getMyProfessionalClinics, type ProfessionalClinics } from '@/data/professional-clinics';
import {
  getMyProfessionalContext,
  type OrganizationProfessionalContext,
  type ProfessionalContext,
} from '@/data/professional-context';
import { useProfessionalOrganizationSelection } from '@/hooks/use-professional-organization-selection';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { mapProfessionalContextErrorToKey } from '@/i18n/professional-context-error-messages';
import { goBackOr } from '@/lib/navigation';
import { organizationStaffHref } from '@/lib/organization-staff';
import { organizationSubscriptionHref } from '@/lib/organization-subscription';
import { resolveSelectedOrganization } from '@/lib/professional-context-display';
import {
  needsVeterinarianProfile,
  professionalAccessLines,
  professionalManagementEntries,
  VETERINARIAN_PROFILE_HREF,
  type ProfessionalManagementEntry,
} from '@/lib/professional-home';
import {
  getProfessionalOrganizationSelection,
  setProfessionalOrganizationSelection,
} from '@/lib/professional-organization-selection';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'loaded'; context: ProfessionalContext };

/**
 * Professional context landing (SPEC-ORG-007, ADR-010). Authenticated-only,
 * top-level Stack.Screen pushed over (app) from Home — same pattern as
 * Profile. Not the professional dashboard yet: it only shows who the User is
 * professionally (Organization, Responsibilities, assigned Clinics). There
 * are deliberately no actions for operations that have no mobile contract.
 *
 * Re-reads get_my_professional_context() on every focus. Only the first load
 * shows the loading/error states; a later refresh updates in place and a
 * failed refresh keeps the last result on screen. Latest read wins.
 *
 * Effective capabilities and Entitlement availability are loaded into the
 * typed context but never rendered or turned into client-side permissions:
 * they are advisory presentation context for future screens, and every
 * professional operation is authorized by the backend itself (BR-6/BR-9).
 *
 * The "Professional clinics" entry point is driven by a separate read,
 * get_my_professional_clinics() (SPEC-ORG-008), never by the Clinic
 * Assignments above: Assignments are relationship/context facts, Professional
 * Clinics are the operational Clinics used for workflow navigation (ORG-008
 * BR-6). The two reads are loaded and guarded independently — a Professional
 * Clinics failure only leaves the entry point as it was (hidden until a read
 * succeeds) and never affects the Organization context shown here.
 *
 * The entry belongs to the selected Organization: it is offered only when
 * that Organization has Professional Clinics, and the list it opens shows
 * only that Organization's Clinics. The selection is shared in memory with
 * that list (`professional-organization-selection`) and re-resolved against
 * every fresh context read.
 */
export default function ProfessionalScreen() {
  const { t } = useLocale();
  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' });
  // Local presentation state only — never an authorization fact or persisted.
  const selection = useProfessionalOrganizationSelection();
  // Presentation only; `null` until a Professional Clinics read succeeds.
  const [clinics, setClinics] = useState<ProfessionalClinics | null>(null);

  const isMountedRef = useRef(true);
  const loadSeqRef = useRef(0);
  const clinicsLoadSeqRef = useRef(0);
  const hasLoadedRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const load = useCallback(() => {
    const seq = ++loadSeqRef.current;

    getMyProfessionalContext().then((result) => {
      if (!isMountedRef.current || seq !== loadSeqRef.current) return;

      if (result.error !== null) {
        // Only the first load may replace the screen with the error state.
        if (!hasLoadedRef.current) {
          setLoadState({
            kind: 'error',
            messageKey: mapProfessionalContextErrorToKey(result.error),
          });
        }
        return;
      }

      hasLoadedRef.current = true;
      setLoadState({ kind: 'loaded', context: result.data });
      // Keep the shared selection to an Organization of this read: the
      // previous pick while still present, otherwise the first one.
      const resolved = resolveSelectedOrganization(
        result.data.organizations,
        getProfessionalOrganizationSelection()?.membershipId ?? null,
      );
      setProfessionalOrganizationSelection(
        resolved === null
          ? null
          : { membershipId: resolved.membershipId, organizationId: resolved.organizationId },
      );
    });

    const clinicsSeq = ++clinicsLoadSeqRef.current;
    getMyProfessionalClinics().then((result) => {
      if (!isMountedRef.current || clinicsSeq !== clinicsLoadSeqRef.current) return;
      // A failed refresh keeps whatever is already shown.
      if (result.error !== null) return;
      setClinics(result.data);
    });
  }, []);

  useFocusEffect(load);

  function handleRetry() {
    setLoadState({ kind: 'loading' });
    load();
  }

  const goHome = () => goBackOr('/');

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppTopBar onBack={goHome} />

        <Text style={styles.title} accessibilityRole="header">
          {t('professional.title')}
        </Text>

        {loadState.kind === 'loading' ? (
          <StateMessage tone="loading" message={t('professional.loading')} />
        ) : loadState.kind === 'error' ? (
          <View style={styles.stateBlock}>
            <StateMessage tone="error" message={t(loadState.messageKey)} />
            <Button label={t('professional.retry')} onPress={handleRetry} />
            <Button variant="secondary" label={t('professional.backToHome')} onPress={goHome} />
          </View>
        ) : loadState.context.organizations.length === 0 ? (
          <View style={styles.stateBlock}>
            <StateMessage
              tone="empty"
              icon="briefcase-outline"
              message={t('professional.noAccess')}
            />
            <Button variant="secondary" label={t('professional.backToHome')} onPress={goHome} />
          </View>
        ) : (
          <>
            {needsVeterinarianProfile(loadState.context) ? (
              <ProfessionalEntryAction
                icon="id-card-outline"
                title={t('veterinarianProfile.homeAction')}
                support={t('veterinarianProfile.homeActionSupport')}
                onPress={() => router.push(VETERINARIAN_PROFILE_HREF)}
              />
            ) : null}
            <OrganizationsContent
              organizations={loadState.context.organizations}
              selectedMembershipId={selection?.membershipId ?? null}
              clinics={clinics}
            />
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

type OrganizationsContentProps = {
  organizations: OrganizationProfessionalContext[];
  selectedMembershipId: string | null;
  clinics: ProfessionalClinics | null;
};

/**
 * Context first — the Organization selector (or the single Organization's
 * name) with a compact, read-only card of the User's access there — then the
 * selected Organization's Management entries. The Organization name is shown
 * once; the access card never repeats it.
 */
function OrganizationsContent({
  organizations,
  selectedMembershipId,
  clinics,
}: OrganizationsContentProps) {
  const { t } = useLocale();
  const selected = resolveSelectedOrganization(organizations, selectedMembershipId);
  if (selected === null) return null;

  const onSelect = (organization: OrganizationProfessionalContext) =>
    setProfessionalOrganizationSelection({
      membershipId: organization.membershipId,
      organizationId: organization.organizationId,
    });
  const openEntry = (entry: ProfessionalManagementEntry) => {
    // The destination shows the Organization shown here, even before the
    // selection was first stored.
    onSelect(selected);
    router.push(
      entry === 'staff'
        ? organizationStaffHref(selected.organizationId)
        : entry === 'subscription'
          ? organizationSubscriptionHref(selected.organizationId)
          : '/professional/clinics',
    );
  };
  const entries = professionalManagementEntries(selected, clinics);

  return (
    <>
      <View style={styles.context}>
        {organizations.length > 1 ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              {t('professional.organizationsHeading')}
            </Text>
            <View style={styles.optionList} accessibilityRole="radiogroup">
              {organizations.map((organization) => (
                <OrganizationOption
                  key={organization.membershipId}
                  name={organization.organizationDisplayName}
                  selected={organization.membershipId === selected.membershipId}
                  onPress={() => onSelect(organization)}
                />
              ))}
            </View>
          </View>
        ) : (
          <Text style={styles.organizationName} accessibilityRole="header">
            {selected.organizationDisplayName}
          </Text>
        )}

        <AccessCard lines={professionalAccessLines(selected, t)} />
      </View>

      {entries.length > 0 ? (
        <View style={styles.section}>
          <Text style={styles.managementTitle} accessibilityRole="header">
            {t('professional.managementHeading')}
          </Text>
          {entries.map((entry) => (
            <ProfessionalEntryAction
              key={entry}
              icon={MANAGEMENT_ENTRY[entry].icon}
              title={t(MANAGEMENT_ENTRY[entry].title)}
              support={t(MANAGEMENT_ENTRY[entry].support)}
              onPress={() => openEntry(entry)}
            />
          ))}
        </View>
      ) : null}
    </>
  );
}

const MANAGEMENT_ENTRY = {
  staff: { icon: 'people-outline', title: 'staff.title', support: 'staff.entrySupport' },
  clinics: {
    icon: 'medkit-outline',
    title: 'professional.clinicsAction',
    support: 'professional.clinicsActionSupport',
  },
  subscription: {
    icon: 'receipt-outline',
    title: 'subscription.title',
    support: 'subscription.entrySupport',
  },
} as const satisfies Record<
  ProfessionalManagementEntry,
  { icon: keyof typeof Ionicons.glyphMap; title: TranslationKey; support: TranslationKey }
>;

type OrganizationOptionProps = {
  name: string;
  selected: boolean;
  onPress: () => void;
};

/**
 * One selectable Organization card. Selection is shown by border, weight,
 * and a check mark — never color alone — and announced as a radio state.
 */
function OrganizationOption({ name, selected, onPress }: OrganizationOptionProps) {
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="radio"
      accessibilityLabel={name}
      accessibilityState={{ selected, checked: selected }}
      style={({ pressed }) => [
        styles.option,
        selected && styles.optionSelected,
        pressed && !selected && styles.optionPressed,
      ]}
    >
      <Text style={[styles.optionLabel, selected && styles.optionLabelSelected]}>{name}</Text>
      <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
        <Ionicons
          name={selected ? 'checkmark-circle' : 'ellipse-outline'}
          size={22}
          color={selected ? colors.primary : colors.textMuted}
        />
      </View>
    </Pressable>
  );
}

/**
 * Compact, read-only card of the User's access in the selected Organization:
 * decorative badge, title, one line per active Responsibility. Announced as
 * one text element, never a control, and never repeating the Organization name.
 */
function AccessCard({ lines }: { lines: string[] }) {
  const { t } = useLocale();
  const title = t('professional.accessHeading');
  return (
    <View
      style={styles.accessCard}
      accessible
      accessibilityRole="text"
      accessibilityLabel={`${title}: ${lines.join('. ')}`}
    >
      <View
        style={styles.badge}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Ionicons name="ribbon-outline" size={20} color={colors.primary} />
      </View>
      <View style={styles.accessText}>
        <Text style={styles.accessTitle}>{title}</Text>
        {lines.map((line, index) => (
          <Text key={index} style={styles.accessLine}>
            {line}
          </Text>
        ))}
      </View>
    </View>
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
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  stateBlock: {
    gap: spacing.md,
  },
  section: {
    gap: spacing.sm,
  },
  sectionTitle: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  optionList: {
    gap: spacing.sm,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 56,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
  },
  optionSelected: {
    borderWidth: 2,
    borderColor: colors.primary,
    backgroundColor: colors.primarySoft,
  },
  optionPressed: {
    backgroundColor: colors.surfaceSoft,
  },
  optionLabel: {
    ...typography.body,
    color: colors.textPrimary,
    flex: 1,
  },
  optionLabelSelected: {
    fontWeight: '700',
  },
  context: {
    gap: spacing.md,
  },
  organizationName: {
    ...typography.h3,
    color: colors.textPrimary,
  },
  accessCard: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    padding: spacing.lg,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
  },
  badge: {
    width: 36,
    height: 36,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  accessText: {
    flex: 1,
    gap: 2,
  },
  accessTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  accessLine: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  managementTitle: {
    ...typography.h3,
    color: colors.textPrimary,
  },
});
