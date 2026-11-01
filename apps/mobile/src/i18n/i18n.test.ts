import * as Localization from 'expo-localization';

import { resolveSystemLocale } from '@/i18n/i18n';

jest.mock('expo-localization', () => ({
  getLocales: jest.fn(),
}));

const mockedGetLocales = Localization.getLocales as jest.Mock;

describe('resolveSystemLocale', () => {
  it('resolves any Spanish device locale to es', () => {
    mockedGetLocales.mockReturnValue([{ languageCode: 'es' }]);
    expect(resolveSystemLocale()).toBe('es');

    mockedGetLocales.mockReturnValue([{ languageCode: 'ES' }]);
    expect(resolveSystemLocale()).toBe('es');
  });

  it('resolves any English device locale to en', () => {
    mockedGetLocales.mockReturnValue([{ languageCode: 'en' }]);
    expect(resolveSystemLocale()).toBe('en');
  });

  it('falls back to Spanish for an unsupported locale', () => {
    mockedGetLocales.mockReturnValue([{ languageCode: 'fr' }]);
    expect(resolveSystemLocale()).toBe('es');
  });

  it('only considers the single most-preferred device locale, not the whole list', () => {
    mockedGetLocales.mockReturnValue([{ languageCode: 'fr' }, { languageCode: 'en' }]);
    expect(resolveSystemLocale()).toBe('es');
  });

  it('falls back to Spanish when no locales are reported', () => {
    mockedGetLocales.mockReturnValue([]);
    expect(resolveSystemLocale()).toBe('es');
  });
});
