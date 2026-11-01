import { normalizeEmail } from '@/lib/email';

describe('normalizeEmail', () => {
  it('lowercases the email', () => {
    expect(normalizeEmail('Maria@Example.com')).toBe('maria@example.com');
  });

  it('trims leading and trailing whitespace', () => {
    expect(normalizeEmail('  maria@example.com  ')).toBe('maria@example.com');
  });

  it('trims tabs and newlines, matching the backend normalization', () => {
    expect(normalizeEmail('\t\nmaria@example.com\n\t')).toBe('maria@example.com');
  });

  it('combines trimming and lowercasing', () => {
    expect(normalizeEmail('  Maria@Example.COM  ')).toBe('maria@example.com');
  });

  it('leaves an already-normalized email unchanged', () => {
    expect(normalizeEmail('maria@example.com')).toBe('maria@example.com');
  });
});
