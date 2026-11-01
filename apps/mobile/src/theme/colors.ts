/**
 * Design System v1 — "Warm Clinical" palette, used by every user-facing
 * screen. Fixed values: the app is light-mode only (no dark variants are
 * approved yet).
 */
export const colors = {
  primary: '#147D73',
  primaryDark: '#0D5F58',
  primarySoft: '#E8F4F1',

  background: '#FAFCFB',
  surface: '#FFFFFF',
  surfaceSoft: '#F2F7F5',

  textPrimary: '#183044',
  textSecondary: '#667985',
  textMuted: '#8998A1',

  border: '#DDE7E3',

  success: '#2E9B63',
  successSoft: '#E8F6EE',

  warning: '#E59A2F',
  warningSoft: '#FFF5E5',

  error: '#D94A4A',
  /** Text-safe error tone (≈5.9:1 on white, ≈5.1:1 on `errorSoft`) — `error`
   * itself is under AA for body-size text, so destructive labels use this. */
  errorDark: '#B23B3B',
  errorSoft: '#FDECEC',

  accent: '#E97B68',
  accentSoft: '#FCEDE9',
} as const;

export type DesignSystemColor = keyof typeof colors;
