import { Image } from 'expo-image';

type BrandMarkVariant = 'color' | 'dark' | 'light';

type BrandMarkProps = {
  /** On-screen footprint of the paw, in dp (see ARTWORK_TO_GLYPH below). */
  size?: number;
  /**
   * `color` on light backgrounds, `light` on dark/photo backgrounds, `dark`
   * for single-ink contexts — see the brand usage notes for assets/brand/.
   */
  variant?: BrandMarkVariant;
  /**
   * Called once the mark is actually on screen — or failed to load, so a
   * caller waiting on it can never be blocked. The SVG decodes
   * asynchronously; the splash overlay uses this to avoid the paw popping in.
   */
  onReady?: () => void;
};

// The final brand symbol (assets/brand/), rendered through expo-image's
// built-in SVG decoders — its geometry lives only in those files.
const SOURCES: Record<BrandMarkVariant, number> = {
  color: require('@/assets/brand/logo-symbol.svg'),
  dark: require('@/assets/brand/logo-symbol-dark.svg'),
  light: require('@/assets/brand/logo-symbol-light.svg'),
};

/**
 * The symbol SVGs are drawn on a 64-unit square with built-in clear space
 * around a paw that spans ~46 units. `size` is the paw's footprint, so the
 * artwork is rendered slightly larger and the clear space is pulled back in
 * with equal negative margins: the component occupies exactly `size` × `size`
 * in layout, like a plain icon, and callers never compensate for padding.
 */
export const ARTWORK_TO_GLYPH = 64 / 46;

/**
 * MenizVet brand symbol. Decorative: it is always shown next to the native
 * "MenizVet" text, so it is hidden from screen readers to avoid a duplicate
 * announcement.
 */
export function BrandMark({ size = 24, variant = 'color', onReady }: BrandMarkProps) {
  const artworkSize = size * ARTWORK_TO_GLYPH;
  const trim = (size - artworkSize) / 2;

  return (
    <Image
      source={SOURCES[variant]}
      contentFit="contain"
      style={{ width: artworkSize, height: artworkSize, margin: trim }}
      // Keep the decoded mark in memory: a remount (e.g. the splash overlay
      // switching to its fade view) then redraws it immediately, never blank.
      cachePolicy="memory-disk"
      onDisplay={onReady}
      onError={onReady}
      pointerEvents="none"
      accessible={false}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    />
  );
}
