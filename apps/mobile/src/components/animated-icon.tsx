import * as SplashScreen from 'expo-splash-screen';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { Easing, Keyframe } from 'react-native-reanimated';
import { scheduleOnRN } from 'react-native-worklets';

import { ARTWORK_TO_GLYPH, BrandMark } from '@/components/design-system/brand-mark';
import { colors } from '@/theme/colors';

const DURATION = 600;

/**
 * The native splash draws the symbol artwork at app.config.ts's
 * expo-splash-screen `imageWidth` (dp/pt), centred on the screen. The overlay
 * must draw the same artwork at the same size so the handoff never jumps.
 * Keep in sync with that `imageWidth`.
 */
const SPLASH_ARTWORK_SIZE = 112;

/**
 * Upper bound on waiting for the mark to be drawn before handing over from the
 * native splash. The local SVG normally displays within a frame or two; this
 * only guarantees startup can never be held by an image problem.
 */
const MARK_WAIT_LIMIT_MS = 1000;

type AnimatedSplashOverlayProps = {
  /** Whether app bootstrap (e.g. initial session restoration) has finished. */
  ready: boolean;
};

/**
 * Covers the app while it bootstraps, then fades out once the native splash
 * has been hidden. It matches the native splash exactly — the same Design
 * System background (app.config.ts's BRAND_BACKGROUND, equal to
 * `colors.background`) and the same centred brand symbol at the same size —
 * and the native splash is only hidden once the overlay's symbol is on
 * screen, so the native→JS handoff shows no visible change.
 */
export function AnimatedSplashOverlay({ ready }: AnimatedSplashOverlayProps) {
  const [animate, setAnimate] = useState(false);
  const [visible, setVisible] = useState(true);
  const [isLaidOut, setIsLaidOut] = useState(false);
  const [isMarkShown, setIsMarkShown] = useState(false);

  useEffect(() => {
    const timeout = setTimeout(() => setIsMarkShown(true), MARK_WAIT_LIMIT_MS);
    return () => clearTimeout(timeout);
  }, []);

  useEffect(() => {
    if (!ready || !isLaidOut || !isMarkShown) return;
    SplashScreen.hideAsync().finally(() => setAnimate(true));
  }, [ready, isLaidOut, isMarkShown]);

  if (!visible) return null;

  const splashKeyframe = new Keyframe({
    0: {
      transform: [{ scale: 1 }],
      opacity: 1,
    },
    20: {
      opacity: 1,
    },
    70: {
      opacity: 0,
      easing: Easing.elastic(0.7),
    },
    100: {
      opacity: 0,
      transform: [{ scale: 1 }],
      easing: Easing.elastic(0.7),
    },
  });

  // BrandMark's `size` is the paw footprint; derive it from the artwork size
  // so the drawn artwork is exactly SPLASH_ARTWORK_SIZE, like the native one.
  const mark = (
    <BrandMark size={SPLASH_ARTWORK_SIZE / ARTWORK_TO_GLYPH} onReady={() => setIsMarkShown(true)} />
  );

  return animate ? (
    <Animated.View
      entering={splashKeyframe.duration(DURATION).withCallback((finished) => {
        'worklet';
        if (finished) {
          scheduleOnRN(setVisible, false);
        }
      })}
      style={styles.splashOverlay}
    >
      {mark}
    </Animated.View>
  ) : (
    <View onLayout={() => setIsLaidOut(true)} style={styles.splashOverlay}>
      {mark}
    </View>
  );
}

const styles = StyleSheet.create({
  splashOverlay: {
    ...StyleSheet.absoluteFill,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1000,
  },
});
