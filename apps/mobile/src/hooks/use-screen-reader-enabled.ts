import { useEffect, useState } from 'react';
import { AccessibilityInfo } from 'react-native';

/**
 * Whether a screen reader (TalkBack, VoiceOver) is on, following changes
 * while the screen is shown. `false` until the platform answers. A change
 * reported before the first answer wins over that answer.
 */
export function useScreenReaderEnabled(): boolean {
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    let active = true;
    let changed = false;
    const subscription = AccessibilityInfo.addEventListener('screenReaderChanged', (value) => {
      changed = true;
      setEnabled(value);
    });
    AccessibilityInfo.isScreenReaderEnabled()
      .then((value) => {
        if (active && !changed) setEnabled(value);
      })
      .catch(() => {});
    return () => {
      active = false;
      subscription.remove();
    };
  }, []);

  return enabled;
}
