import { StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import type {
  InvitationFlowPhase,
  InvitationTerminalReason,
} from '@/lib/organization-invitation-flow';
import { staffInstantLabel, staffResponsibilityLabel } from '@/lib/organization-staff';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

export type OrganizationInvitationActions = {
  accept: () => void;
  cancelMismatch: () => void;
  retry: () => void;
  reloadAccess: () => void;
  notNow: () => void;
  signIn: () => void;
  createAccount: () => void;
  close: () => void;
  goToProfessional: () => void;
};

type Props = {
  phase: InvitationFlowPhase;
  isEmailConfirmed: boolean;
  actions: OrganizationInvitationActions;
};

const TERMINAL_COPY: Record<
  InvitationTerminalReason,
  { title: TranslationKey; body: TranslationKey; toProfessional: boolean }
> = {
  EXPIRED: {
    title: 'organizationInvitation.expiredTitle',
    body: 'organizationInvitation.expiredBody',
    toProfessional: false,
  },
  REVOKED: {
    title: 'organizationInvitation.revokedTitle',
    body: 'organizationInvitation.revokedBody',
    toProfessional: false,
  },
  ALREADY_MEMBER: {
    title: 'organizationInvitation.alreadyMemberTitle',
    body: 'organizationInvitation.alreadyMemberBody',
    toProfessional: true,
  },
  ACCEPTED_BY_YOU: {
    title: 'organizationInvitation.acceptedByYouTitle',
    body: 'organizationInvitation.acceptedByYouBody',
    toProfessional: true,
  },
  UNAVAILABLE: {
    title: 'organizationInvitation.unavailableTitle',
    body: 'organizationInvitation.unavailableBody',
    toProfessional: false,
  },
};

/**
 * Presentation of every SPEC-ORG-003 §12 screen state. Shows only what the
 * authoritative preview returned (never the secret, never the full invited
 * address); signed out it shows generic copy only. No Decline action exists.
 */
export function OrganizationInvitationContent({ phase, isEmailConfirmed, actions }: Props) {
  const { t, locale } = useLocale();

  switch (phase.kind) {
    case 'loading':
      return <StateMessage tone="loading" message={t('organizationInvitation.loading')} />;

    case 'completing':
      return <StateMessage tone="loading" message={t('organizationInvitation.completing')} />;

    case 'failed':
      return (
        <View style={styles.section}>
          <StateMessage tone="error" message={t('organizationInvitation.loadError')} />
          <Button label={t('organizationInvitation.retry')} onPress={actions.retry} />
          <Button
            label={t('organizationInvitation.notNow')}
            variant="tertiary"
            onPress={actions.notNow}
          />
        </View>
      );

    case 'contextFailed':
      return (
        <View style={styles.section}>
          <StateMessage
            tone="error"
            title={t('organizationInvitation.contextFailedTitle')}
            message={t('organizationInvitation.contextFailedBody')}
          />
          <Button label={t('organizationInvitation.reloadAccess')} onPress={actions.reloadAccess} />
        </View>
      );

    case 'signedOut':
      return (
        <View style={styles.section}>
          <Text style={styles.headline} accessibilityRole="header">
            {t('organizationInvitation.signedOutTitle')}
          </Text>
          <Text style={styles.body}>{t('organizationInvitation.signedOutBody')}</Text>
          <Button label={t('organizationInvitation.signIn')} onPress={actions.signIn} />
          <Button
            label={t('organizationInvitation.createAccount')}
            variant="secondary"
            onPress={actions.createAccount}
          />
          <Button
            label={t('organizationInvitation.notNow')}
            variant="tertiary"
            onPress={actions.notNow}
          />
        </View>
      );

    case 'terminal': {
      const copy = TERMINAL_COPY[phase.reason];
      const organization = phase.organizationDisplayName ?? '';
      return (
        <View style={styles.section}>
          <StateMessage
            tone="empty"
            icon="mail-outline"
            title={t(copy.title)}
            message={t(copy.body, { organization })}
          />
          {copy.toProfessional ? (
            <Button
              label={t('organizationInvitation.goToProfessional')}
              onPress={actions.goToProfessional}
            />
          ) : null}
          <Button
            label={t('organizationInvitation.close')}
            variant={copy.toProfessional ? 'tertiary' : 'primary'}
            onPress={actions.close}
          />
        </View>
      );
    }

    case 'review': {
      const { preview, step, notice } = phase;
      const organization = preview.organizationDisplayName ?? '';
      const maskedEmail = preview.maskedRecipientEmail ?? '';
      const isMismatch = preview.invitedEmailMatchesCurrentAccount === false;
      return (
        <View style={styles.section}>
          <Text style={styles.headline} accessibilityRole="header">
            {t('organizationInvitation.reviewTitle', { organization })}
          </Text>
          <Text style={styles.body}>{t('organizationInvitation.reviewSupport')}</Text>

          <View style={styles.card}>
            <Text style={styles.cardHeading}>{t('organizationInvitation.accessHeading')}</Text>
            {preview.responsibilities.map((role) => (
              <Text
                key={`${role.responsibility}:${role.scope.type === 'CLINIC' ? role.scope.clinic.clinicId : ''}`}
                style={styles.cardLine}
              >
                {staffResponsibilityLabel(role, t)}
              </Text>
            ))}
            <Text style={styles.cardMeta}>
              {t('organizationInvitation.invitedAddress', { email: maskedEmail })}
            </Text>
            {preview.expiresAt !== null ? (
              <Text style={styles.cardMeta}>
                {t('organizationInvitation.expiresAt', {
                  date: staffInstantLabel(preview.expiresAt, locale),
                })}
              </Text>
            ) : null}
          </View>

          {isMismatch ? (
            <Notice
              tone="info"
              message={t('organizationInvitation.mismatchWarning', { email: maskedEmail })}
            />
          ) : null}
          {!isEmailConfirmed || notice === 'verificationRequired' ? (
            <Notice tone="error" message={t('organizationInvitation.verificationRequired')} />
          ) : null}
          {notice === 'notAccepted' ? (
            <Notice tone="error" message={t('organizationInvitation.notAccepted')} />
          ) : null}

          {step === 'confirmMismatch' ? (
            <View style={styles.confirmation} accessibilityRole="alert">
              <Text style={styles.cardHeading}>
                {t('organizationInvitation.mismatchConfirmTitle')}
              </Text>
              <Text style={styles.body}>
                {t('organizationInvitation.mismatchConfirmBody', {
                  organization,
                  email: maskedEmail,
                })}
              </Text>
              <Button
                label={t('organizationInvitation.mismatchConfirm')}
                onPress={actions.accept}
              />
              <Button
                label={t('organizationInvitation.mismatchCancel')}
                variant="secondary"
                onPress={actions.cancelMismatch}
              />
            </View>
          ) : (
            <>
              <Button
                label={t('organizationInvitation.accept')}
                onPress={actions.accept}
                loading={step === 'accepting'}
                disabled={!isEmailConfirmed}
              />
              <Button
                label={t('organizationInvitation.notNow')}
                variant="tertiary"
                onPress={actions.notNow}
                disabled={step === 'accepting'}
              />
            </>
          )}
        </View>
      );
    }
  }
}

const styles = StyleSheet.create({
  section: {
    gap: spacing.md,
  },
  headline: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  body: {
    ...typography.body,
    color: colors.textSecondary,
  },
  card: {
    gap: spacing.xs,
    padding: spacing.lg,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  confirmation: {
    gap: spacing.md,
    padding: spacing.lg,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  cardHeading: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  cardLine: {
    ...typography.body,
    color: colors.textPrimary,
  },
  cardMeta: {
    ...typography.caption,
    color: colors.textSecondary,
  },
});
