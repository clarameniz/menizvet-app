import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps, ReactElement } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/design-system/button';
import type { PagedList } from '@/hooks/use-paged-list';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * The shared parts of a keyset-paged list screen (the professional agenda's
 * Pending and History, the Staff screen's Members and Invitations): its first
 * page status, its "Load more" footer, its empty message, and its rows framed
 * as ONE bordered list with discreet separators.
 */

type Paged = Pick<PagedList<unknown, unknown>, 'state' | 'loadMore' | 'retry'>;

const isSessionExpired = (key: TranslationKey) => key === 'errors.sessionExpired';

/**
 * The state of the first page: loading or failed before anything was shown
 * (with a retry), or a failed refresh above rows that stay on screen.
 */
export function PagedListStatus({
  list,
  loadingKey,
  errorKey,
}: {
  list: Paged;
  loadingKey: TranslationKey;
  errorKey: TranslationKey;
}) {
  const { t } = useLocale();
  const { state } = list;
  const firstError = state.error?.during === 'first' ? state.error : null;

  if (state.rows === null) {
    if (firstError === null) {
      return (
        <View style={styles.status}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text style={styles.mutedText}>{t(loadingKey)}</Text>
        </View>
      );
    }
    return (
      <View style={styles.status}>
        <Text style={styles.errorText}>
          {t(isSessionExpired(firstError.messageKey) ? 'errors.sessionExpired' : errorKey)}
        </Text>
        <RetryLink onPress={list.retry} />
      </View>
    );
  }
  if (firstError === null) return null;
  return (
    <View style={styles.status}>
      <Text style={styles.errorText}>
        {t(
          isSessionExpired(firstError.messageKey)
            ? 'errors.sessionExpired'
            : 'pagedList.refreshError',
        )}
      </Text>
      <RetryLink onPress={list.retry} />
    </View>
  );
}

/** "Load more" while the last page was full, its progress, and its failure with a retry. */
export function LoadMoreFooter({ list }: { list: Paged }) {
  const { t } = useLocale();
  const { state } = list;
  if (state.rows === null || state.rows.length === 0) return null;
  const moreError = state.error?.during === 'more' ? state.error : null;

  return (
    <View style={styles.footer}>
      {moreError !== null ? (
        <View style={styles.status}>
          <Text style={styles.errorText}>
            {t(
              isSessionExpired(moreError.messageKey)
                ? 'errors.sessionExpired'
                : 'pagedList.loadMoreError',
            )}
          </Text>
          <RetryLink onPress={list.retry} />
        </View>
      ) : state.hasMore ? (
        <Button
          variant="secondary"
          label={t('pagedList.loadMore')}
          onPress={list.loadMore}
          loading={state.loading === 'more'}
          disabled={state.loading !== null}
        />
      ) : null}
    </View>
  );
}

export function RetryLink({ onPress }: { onPress: () => void }) {
  const { t } = useLocale();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={t('professional.retry')}
      hitSlop={8}
    >
      <Text style={styles.retryText}>{t('professional.retry')}</Text>
    </Pressable>
  );
}

export function EmptyListMessage({
  icon,
  message,
}: {
  icon: ComponentProps<typeof Ionicons>['name'];
  message: string;
}) {
  return (
    <View style={styles.status}>
      <Ionicons
        name={icon}
        size={20}
        color={colors.textMuted}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.mutedText}>{message}</Text>
    </View>
  );
}

/** One row inside a single bordered list, with a discreet separator between rows. */
export function FramedRow({
  first,
  last,
  children,
}: {
  first: boolean;
  last: boolean;
  children: ReactElement;
}) {
  return (
    <View style={[styles.rowFrame, first && styles.rowFrameFirst, last && styles.rowFrameLast]}>
      {!first ? <View style={styles.separator} /> : null}
      {children}
    </View>
  );
}

/** The list screen's content padding and its header block, shared by every paged list. */
export const pagedListStyles = StyleSheet.create({
  content: {
    flexGrow: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
  },
  headerBlock: {
    gap: spacing.lg,
    paddingBottom: spacing.md,
  },
});

const styles = StyleSheet.create({
  rowFrame: {
    borderLeftWidth: 1,
    borderRightWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  rowFrameFirst: {
    borderTopWidth: 1,
    borderTopLeftRadius: radius.medium,
    borderTopRightRadius: radius.medium,
  },
  rowFrameLast: {
    borderBottomWidth: 1,
    borderBottomLeftRadius: radius.medium,
    borderBottomRightRadius: radius.medium,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginHorizontal: spacing.lg,
  },
  status: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: spacing.sm,
    paddingVertical: spacing.md,
  },
  footer: {
    paddingTop: spacing.md,
  },
  mutedText: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  errorText: {
    ...typography.caption,
    color: colors.errorDark,
    flexShrink: 1,
  },
  retryText: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primaryDark,
  },
});
