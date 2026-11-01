import { Image } from 'expo-image';
import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import type { ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BrandMark } from '@/components/design-system/brand-mark';
import { Button } from '@/components/design-system/button';
import {
  CalendarMark,
  CheckMark,
  ChevronMark,
  HeartMark,
  InfoMark,
  ListMark,
  PinMark,
  SearchMark,
} from '@/components/design-system/icon';
import { QuickAction } from '@/components/design-system/quick-action';
import { LanguageSelector } from '@/components/language-selector';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** Phone-appropriate reading width cap so large phones (and web) don't
 * stretch text lines edge to edge — this screen stays single-column. On any
 * screen narrower than this, it has no effect: the hero and lower block are
 * full width of the device either way (see the full-bleed/padded split
 * below). */
const MAX_CONTENT_WIDTH = 480;

/** Below this viewport width, the account area falls back to its vertical
 * stack (see `PublicHomeScreen`'s `isAccountRowLayout`) rather than a
 * two-column layout. Deliberately low: the left column is `flex: 1` (see
 * `accountPromptStackLeft`), so it absorbs whatever width the button
 * doesn't need rather than requiring both elements' natural sizes to fit
 * side by side — row layout is the normal case on real phones, and this
 * only guards against genuinely narrow devices. */
const ACCOUNT_ROW_MIN_WIDTH = 340;

/**
 * Hero photograph — warm, human, real subject (person + pet), matching the
 * "Modern Premium" reference direction. The source frame (1448×1086, 4:3)
 * has its subjects weighted toward the upper-right, with dark, low-detail
 * negative space on the left — `contentPosition` below biases the crop
 * toward that upper-right area so the faces are never lost, and the hero's
 * text content deliberately claims the darker left side of the frame rather
 * than fighting the subject for space.
 */
const HERO_IMAGE_SOURCE = require('@/assets/images/hero-pet.png');

/**
 * Public unauthenticated home (Design System v1, "Warm Clinical", brand
 * v1.0, "Modern Premium" composition). Bare "/" resolves here whenever the
 * (auth) group is active (see src/app/_layout.tsx's Stack.Protected guards)
 * — this replaces the previous unconditional redirect straight to /sign-in,
 * since Clinic Discovery (SPEC-DIS-001/002/003) is genuinely usable before
 * authentication and the approved product hierarchy puts "Buscar clínicas"
 * ahead of login. Sign-in and account creation remain one tap away via the
 * existing /sign-in and /register routes, which this screen does not
 * otherwise change.
 *
 * Layout follows one rule throughout: the hero and the lower value/account
 * block are full-bleed (no outer horizontal margin, and — see below — no
 * reserved top/bottom safe-area margin either), while the discovery card
 * and quick-action row are padded content that sits between those two
 * full-bleed regions. There is deliberately no single container that wraps
 * the whole screen in one horizontal padding value.
 */
export default function PublicHomeScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const isAccountRowLayout = width >= ACCOUNT_ROW_MIN_WIDTH;

  return (
    <View style={styles.container}>
      {/* True edge-to-edge: this screen doesn't reserve the top/bottom
          safe-area insets at the container level (no SafeAreaView here) —
          the hero's photo/scrim renders all the way to the physical top
          edge, behind the status bar, and the lower block's fill renders
          all the way to the physical bottom edge, behind the gesture bar /
          home indicator. Only the CONTENT inside each — the brand row and
          the account actions — gets pushed clear of system chrome, via
          `insets.top`/`insets.bottom` used as internal padding below. Now
          that the status bar sits directly over the dark hero photo, its
          icons need to be light to stay legible. Still light-mode only,
          still scoped to this one screen. */}
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <View style={styles.page}>
          {/* Hero: real photo, one coherent scrim, and the brand row +
              headline both living inside it — the very first thing on the
              screen, starting at the physical top edge, full width of the
              device. */}
          <View style={styles.heroBand}>
            <Image
              source={HERO_IMAGE_SOURCE}
              style={styles.heroImage}
              contentFit="cover"
              contentPosition={{ top: '30%', right: '25%' }}
              accessible={false}
              accessibilityElementsHidden
              importantForAccessibility="no-hide-descendants"
            />
            <View style={styles.heroScrim} pointerEvents="none" />

            <View style={[styles.heroInner, { paddingTop: insets.top + spacing.md }]}>
              <View style={styles.heroTopRow}>
                <View style={styles.brandRow}>
                  <BrandMark size={32} variant="light" />
                  <Text style={styles.brand}>{t('publicHome.brandName')}</Text>
                </View>
                <LanguageSelector />
              </View>

              <View style={styles.heroContent}>
                <Text style={styles.heroHeadline} accessibilityRole="header">
                  {t('publicHome.headline')}
                </Text>
                <Text style={styles.heroSubheadline}>{t('publicHome.subheadline')}</Text>
              </View>
            </View>
          </View>

          {/* Primary discovery action — the strongest action on the page.
              Pulled up over the hero's bottom edge with a negative margin
              (ordinary flow, not absolute positioning). Padded content:
              carries its own horizontal margin rather than relying on a
              page-wide padding container. */}
          <Pressable
            onPress={() => router.push('/clinics')}
            accessibilityRole="button"
            accessibilityLabel={`${t('publicHome.searchClinicsAction')}. ${t('publicHome.searchClinicsSupport')}`}
            style={({ pressed }) => [styles.discoveryCard, pressed && styles.discoveryCardPressed]}
          >
            <View style={styles.discoveryIconWrap}>
              <SearchMark color={colors.primary} size={24} />
            </View>
            <View style={styles.discoveryTextWrap}>
              <Text style={styles.discoveryTitle}>{t('publicHome.searchClinicsAction')}</Text>
              <Text style={styles.discoverySupport}>{t('publicHome.searchClinicsSupport')}</Text>
            </View>
            <ChevronMark color={colors.primary} size={20} />
          </Pressable>

          {/* Quick actions: padded content, sitting on the light background
              between the two full-bleed regions. */}
          <View style={styles.quickRow}>
            <QuickAction
              icon={<CalendarMark size={20} />}
              label={t('publicHome.quickAvailabilityLabel')}
              accessibilityLabel={`${t('publicHome.quickAvailabilityLabel')}. ${t('publicHome.quickAvailabilitySupport')}`}
              onPress={() => router.push('/clinics')}
            />
            <QuickAction
              icon={<PinMark size={20} />}
              label={t('publicHome.quickNearbyLabel')}
              onPress={() => router.push('/clinics/nearby')}
            />
            <QuickAction
              icon={<InfoMark size={20} />}
              label={t('publicHome.quickHowItWorksLabel')}
              onPress={() => router.push('/how-it-works')}
            />
          </View>

          {/* Consolidated lower block: full-bleed, rounded top corners
              only — it reads as the screen's second major region, not a
              floating card. Bottom safe-area inset is added as internal
              padding so the dark fill reaches the true screen edge while
              the button above stays clear of the gesture bar / home
              indicator. */}
          <View style={[styles.lowerBlock, { paddingBottom: insets.bottom + spacing.lg }]}>
            <View style={styles.lowerHeadingRow}>
              <HeartMark color={colors.primarySoft} size={20} />
              <Text style={styles.lowerHeading} accessibilityRole="header">
                {t('publicHome.lowerHeading')}
              </Text>
            </View>

            <View style={styles.valueRow}>
              <ValuePoint
                icon={<CalendarMark color={colors.primarySoft} size={22} />}
                label={t('publicHome.valueAppointments')}
              />
              <ValuePoint
                icon={<ListMark color={colors.primarySoft} size={22} />}
                label={t('publicHome.valueHistory')}
              />
              <ValuePoint
                icon={<CheckMark color={colors.primarySoft} size={22} />}
                label={t('publicHome.valueDataProtected')}
              />
            </View>

            <View style={[styles.accountBlock, isAccountRowLayout && styles.accountBlockRow]}>
              <View
                style={[
                  styles.accountPromptStack,
                  isAccountRowLayout && styles.accountPromptStackLeft,
                ]}
              >
                <Text style={[styles.accountPrompt, isAccountRowLayout && styles.accountTextLeft]}>
                  {t('publicHome.alreadyHaveAccount')}
                </Text>
                <Pressable
                  onPress={() => router.push('/sign-in')}
                  accessibilityRole="button"
                  accessibilityLabel={`${t('publicHome.alreadyHaveAccount')} ${t('publicHome.signInAction')}`}
                  hitSlop={8}
                >
                  <Text
                    style={[
                      styles.accountPromptAction,
                      isAccountRowLayout && styles.accountTextLeft,
                    ]}
                  >
                    {t('publicHome.signInAction')}
                  </Text>
                </Pressable>
              </View>
              <Button
                variant="secondary"
                label={t('publicHome.createAccountAction')}
                onPress={() => router.push('/register')}
                fullWidth={!isAccountRowLayout}
              />
            </View>
          </View>
        </View>
      </ScrollView>
    </View>
  );
}

function ValuePoint({ icon, label }: { icon: ReactNode; label: string }) {
  return (
    <View style={styles.valueItem}>
      <View
        style={styles.valueIconWrap}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        {icon}
      </View>
      <Text style={styles.valueLabel} numberOfLines={2}>
        {label}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    flexGrow: 1,
    alignItems: 'center',
  },
  page: {
    width: '100%',
    maxWidth: MAX_CONTENT_WIDTH,
    // `scrollContent`'s `flexGrow: 1` stretches the scroll content
    // container to at least viewport height when content is short, but
    // without this, `page` itself just sat at its natural (shorter)
    // content height at the top of that container, leaving blank space
    // below `lowerBlock` that fell through to `container`'s light
    // background — the white strip above the gesture bar. `flexGrow: 1`
    // (not `flex: 1` — no `flexBasis: 0`, so this only adds space beyond
    // the natural content height, never shrinks it) lets `page` fill any
    // leftover viewport height; see `lowerBlock` below for where that
    // extra height actually goes.
    flexGrow: 1,
  },
  heroBand: {
    minHeight: 370,
    backgroundColor: colors.primaryDark,
    overflow: 'hidden',
  },
  heroImage: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  heroScrim: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(13, 95, 88, 0.48)',
  },
  heroInner: {
    flex: 1,
    justifyContent: 'space-between',
    paddingHorizontal: spacing.screenHorizontal,
    // Bigger than the discovery card's overlap (`-spacing.xxl` below) on
    // purpose — the difference between the two is the visible gap between
    // the hero copy and the top of the floating card.
    paddingBottom: spacing.xxxl + spacing.xl,
  },
  heroTopRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    rowGap: spacing.sm,
    columnGap: spacing.md,
  },
  brandRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  brand: {
    ...typography.h1,
    color: colors.surface,
    letterSpacing: -0.5,
  },
  heroContent: {
    alignSelf: 'flex-start',
    maxWidth: '85%',
    gap: spacing.xs,
    // Guaranteed minimum gap from the brand row above, on top of whatever
    // `heroInner`'s `justifyContent: 'space-between'` distributes — on a
    // short hero, space-between alone left the wordmark and headline
    // reading as one connected block.
    marginTop: spacing.xl,
  },
  heroHeadline: {
    ...typography.display,
    color: colors.surface,
    letterSpacing: -0.3,
  },
  heroSubheadline: {
    ...typography.body,
    color: colors.primarySoft,
  },
  discoveryCard: {
    marginTop: -spacing.xxl,
    marginHorizontal: spacing.screenHorizontal,
    backgroundColor: colors.surface,
    borderRadius: radius.medium,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    shadowColor: colors.textPrimary,
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.12,
    shadowRadius: 16,
    elevation: 4,
  },
  discoveryCardPressed: {
    opacity: 0.9,
  },
  discoveryIconWrap: {
    width: 36,
    height: 36,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  discoveryTextWrap: {
    flex: 1,
    gap: 1,
  },
  discoveryTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  discoverySupport: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  quickRow: {
    marginTop: spacing.md,
    marginHorizontal: spacing.screenHorizontal,
    flexDirection: 'row',
    gap: spacing.sm,
  },
  lowerBlock: {
    marginTop: spacing.xl,
    // Absorbs whatever extra height `page`'s `flexGrow: 1` adds on a short
    // screen, so it's this block's own dark fill — not blank space next to
    // it — that reaches the physical bottom edge. Content stays top-anchored
    // (no `justifyContent`), so heading/value-row/account spacing is
    // unaffected; any extra space lands below the account block, using the
    // same background color, indistinguishable from the existing bottom
    // padding.
    flexGrow: 1,
    backgroundColor: colors.primaryDark,
    borderTopLeftRadius: radius.large,
    borderTopRightRadius: radius.large,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.xl,
    gap: spacing.xl,
  },
  lowerHeadingRow: {
    flexDirection: 'row',
    alignSelf: 'center',
    alignItems: 'center',
    gap: spacing.xs,
  },
  lowerHeading: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.surface,
    textAlign: 'center',
  },
  valueRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  valueItem: {
    flex: 1,
    alignItems: 'center',
    gap: spacing.xs,
  },
  valueIconWrap: {
    width: 32,
    height: 32,
    borderRadius: radius.pill,
    backgroundColor: 'rgba(255, 255, 255, 0.14)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  valueLabel: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.surface,
    textAlign: 'center',
  },
  accountBlock: {
    gap: spacing.lg,
  },
  accountBlockRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
  },
  accountPromptStack: {
    alignItems: 'center',
    gap: 10,
  },
  accountPromptStackLeft: {
    flex: 1,
    alignItems: 'flex-start',
  },
  accountPrompt: {
    ...typography.caption,
    textAlign: 'center',
    color: colors.primarySoft,
  },
  accountPromptAction: {
    ...typography.caption,
    fontWeight: '700',
    color: colors.surface,
  },
  accountTextLeft: {
    textAlign: 'left',
  },
});
