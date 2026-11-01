import type { ExpoConfig } from 'expo/config';

/**
 * Converted from the previous static app.json to the smallest dynamic
 * config necessary to inject the Android Google Maps API key at build time
 * (Milestone E). Every other field is carried over unchanged. The key is
 * deliberately read from a plain (non-EXPO_PUBLIC_) environment variable: it
 * only needs to reach the compiled Android manifest via the react-native-maps
 * config plugin below, never the JS bundle, so it must not be exposed through
 * the EXPO_PUBLIC_ mechanism used for genuinely runtime-readable config (see
 * src/lib/supabase.ts). The real value is supplied externally (EAS
 * environment variable for cloud builds, .env.local — already gitignored —
 * for local builds) and is never committed here.
 */
/**
 * MenizVet Design System v1 surface colors (src/theme/colors.ts), repeated
 * here because native config is evaluated outside the app bundle:
 * - background (#FAFCFB): the app's light screen background, so the native
 *   splash, the JS splash overlay (animated-icon.tsx) and the first screen
 *   all share one color with no flash between them.
 * - primarySoft (#E8F4F1): the soft brand tint the app already uses behind
 *   icons (avatar and icon badges).
 */
const BRAND_BACKGROUND = '#FAFCFB';
const BRAND_PRIMARY_SOFT = '#E8F4F1';

const isProduction = process.env.APP_VARIANT === 'production';

const androidPackage = isProduction ? 'com.menizvet' : 'com.menizvet.dev';

const appName = isProduction ? 'MenizVet' : 'MenizVet Dev';

const config: ExpoConfig = {
  // User-facing app name (launcher label / home screen). The slug and the
  // bundle/package identifiers below are deliberately unchanged.
  name: appName,
  slug: 'menizvet-mobile',
  version: '1.0.0',
  orientation: 'portrait',
  // Used for iOS too (no ios.icon override). This and the Android icon/favicon
  // PNGs are derived from assets/brand/logo-symbol.svg — regenerate them with
  // scripts/generate-brand-icons.js, never edit them by hand.
  icon: './assets/images/icon.png',
  scheme: 'com.menizvet',
  // Design System v1 is light-only: native UI (keyboard, system dialogs,
  // splash) must not switch to dark with the device setting.
  userInterfaceStyle: 'light',
  android: {
    adaptiveIcon: {
      backgroundColor: BRAND_PRIMARY_SOFT,
      foregroundImage: './assets/images/android-icon-foreground.png',
      monochromeImage: './assets/images/android-icon-monochrome.png',
    },
    predictiveBackGestureEnabled: false,
    package: androidPackage,
    googleServicesFile: './google-services.json',
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [
          {
            scheme: 'https',
            host: 'app.menizvet.com',
            pathPrefix: '/appointments',
          },
          {
            scheme: 'https',
            host: 'app.menizvet.com',
            pathPrefix: '/invitations',
          },
        ],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
  web: {
    output: 'static',
    favicon: './assets/images/favicon.png',
  },
  plugins: [
    'expo-router',
    [
      'expo-splash-screen',
      {
        backgroundColor: BRAND_BACKGROUND,
        // The brand symbol (generated from assets/brand/logo-symbol.svg by
        // scripts/generate-brand-icons.js), centred by the OS on both
        // platforms. imageWidth is the artwork box in dp/pt; the paw itself
        // is 45.6/64 of it (~80dp). The JS overlay (src/components/
        // animated-icon.tsx, SPLASH_ARTWORK_SIZE) must use the same value.
        image: './assets/images/splash-icon.png',
        imageWidth: 112,
      },
    ],
    'expo-notifications',
    'expo-secure-store',
    [
      'expo-localization',
      {
        supportedLocales: ['es', 'en'],
      },
    ],
    [
      'expo-location',
      {
        // Native permission strings are baked in at build time and cannot
        // follow the in-app language switch (src/i18n) the way ordinary
        // product strings do; Spanish is this app's default/fallback locale
        // (src/i18n/i18n.ts), so it's used here too. It covers both approved
        // foreground uses: nearby/map discovery (SPEC-DIS-002/003) and placing
        // a Clinic's map marker (SPEC-CLI-002 BR-18). It becomes iOS
        // NSLocationWhenInUseUsageDescription, so a change only takes effect
        // in a new native build; Android shows no app-provided purpose text.
        // No background location is configured.
        locationWhenInUsePermission:
          'MenizVet usa tu ubicación para mostrarte clínicas veterinarias cercanas y, si gestionas una clínica, para ayudarte a situarla en el mapa.',
      },
    ],
    [
      'react-native-maps',
      {
        androidGoogleMapsApiKey: process.env.GOOGLE_MAPS_ANDROID_API_KEY,
      },
    ],
    'expo-image',
    'expo-web-browser',
  ],
  experiments: {
    typedRoutes: true,
    reactCompiler: true,
  },
  extra: {
    router: {},
    eas: {
      projectId: 'd39ddb24-8116-4a5f-a418-08531647b891',
    },
  },
  owner: 'clarameniz',
};

export default config;
