import { i18n } from '@/i18n/i18n';
import {
  requesterLine,
  requesterMailtoUrl,
  requesterName,
} from '@/lib/appointment-requester-contact';

const translate =
  (locale: 'es' | 'en') => (key: string, options?: Record<string, string | number>) =>
    i18n.t(key, { ...options, locale });

describe('requesterLine', () => {
  it('names the requester, or uses a neutral fallback, in Spanish and English', () => {
    expect(requesterLine('María López', translate('es'))).toBe('Solicitada por María López');
    expect(requesterLine('María López', translate('en'))).toBe('Requested by María López');
    expect(requesterLine(null, translate('es'))).toBe('Solicitante sin nombre');
    expect(requesterLine(null, translate('en'))).toBe('Requester without a name');
  });
});

describe('requesterName', () => {
  it('returns the name or a neutral fallback', () => {
    expect(requesterName('Ana Gil', translate('es'))).toBe('Ana Gil');
    expect(requesterName(null, translate('es'))).toBe('Sin nombre registrado');
    expect(requesterName(null, translate('en'))).toBe('No name on record');
  });
});

describe('requesterMailtoUrl', () => {
  it('opens exactly the address, with nothing prefilled', () => {
    expect(requesterMailtoUrl('maria@example.test')).toBe('mailto:maria@example.test');
    expect(requesterMailtoUrl('maria.lopez+citas@sub.example.es')).toBe(
      'mailto:maria.lopez+citas@sub.example.es',
    );
  });

  it.each([
    null,
    '',
    'not-an-email',
    'a@b',
    'a@@b.c',
    'a@b.c@d.e',
    'maria@example.test?bcc=evil@example.test',
    'maria@example.test&cc=evil@example.test',
    'maria@example.test#x',
    'maria@example.test,evil@example.test',
    'maria@example.test;evil@example.test',
    'maria@example.test%0Abcc:evil@example.test',
    'maria@example.test\nbcc:evil@example.test',
    'maria @example.test',
    'javascript:alert(1)@x.y',
    'maria@example.test/../x',
  ])('offers no action for %p', (email) => {
    expect(requesterMailtoUrl(email)).toBeNull();
  });
});
