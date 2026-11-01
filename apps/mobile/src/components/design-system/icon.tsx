import { Ionicons } from '@expo/vector-icons';

import { colors } from '@/theme/colors';

/**
 * Icon family for Design System v1: Ionicons (`@expo/vector-icons`), outline
 * style throughout — one consistent family, never mixed with anything else.
 * Each export below keeps the same `{color, size}` shape the hand-built
 * Views they replaced used, so call sites across the app didn't need to
 * change. Purely decorative — always paired with a visible text label, so
 * callers are expected to hide these from screen readers at the wrapping
 * element.
 */
type MarkProps = { color?: string; size?: number };

const DEFAULT_COLOR = colors.primary;
/** ~24px is the approved "standard icon" size; callers override where a
 * smaller badge/context genuinely needs it (quick-action tiles, the
 * language pill's chevron, etc). */
const DEFAULT_SIZE = 24;

export function SearchMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="search-outline" size={size} color={color} />;
}

export function PinMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="location-outline" size={size} color={color} />;
}

export function CalendarMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="calendar-outline" size={size} color={color} />;
}

export function InfoMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="information-circle-outline" size={size} color={color} />;
}

/** Used for "data protected" (the lower block's protection value point). */
export function CheckMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="shield-checkmark-outline" size={size} color={color} />;
}

/** Used for "clinical history" (the lower block's history value point). */
export function ListMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="document-text-outline" size={size} color={color} />;
}

export function ChevronMark({ color = DEFAULT_COLOR, size = 20 }: MarkProps) {
  return <Ionicons name="chevron-forward-outline" size={size} color={color} />;
}

/** Used next to the lower block's small "Tu mascota, en buenas manos" /
 * "Your pet, in good hands" line. */
export function HeartMark({ color = DEFAULT_COLOR, size = DEFAULT_SIZE }: MarkProps) {
  return <Ionicons name="heart-outline" size={size} color={color} />;
}
