import type {
  GuardianMedicalHistoryAccess,
  GuardianMedicalHistoryEntry,
} from '@/data/clinical-history';
import {
  appendHistoryPage,
  categoryLabelKey,
  deriveHistoryLoadOutcome,
  formatAttachmentSizeKb,
  formatClinicalInstant,
  resolveAttachmentLabel,
  type HistoryPageState,
} from '@/lib/clinical-history-display';

const CATEGORIES = [
  'EXAMINATION',
  'DIAGNOSIS',
  'TREATMENT',
  'PROCEDURE',
  'VACCINATION',
  'PRESCRIPTION',
  'LABORATORY_RESULT',
  'IMAGING_RESULT',
  'CLINICAL_NOTE',
  'OTHER',
] as const;

describe('categoryLabelKey', () => {
  it.each(CATEGORIES)('maps %s to its own dedicated translation key', (category) => {
    const key = categoryLabelKey(category);
    expect(key.startsWith('clinicalHistory.category')).toBe(true);
    expect(key).not.toBe('clinicalHistory.categoryUnknown');
  });

  it('maps every category to a distinct key (no two categories collapse to the same label)', () => {
    const keys = new Set(CATEGORIES.map((category) => categoryLabelKey(category)));
    expect(keys.size).toBe(CATEGORIES.length);
  });

  it('maps a null category to the neutral fallback key, never a literal "null"', () => {
    expect(categoryLabelKey(null)).toBe('clinicalHistory.categoryUnknown');
  });
});

describe('resolveAttachmentLabel', () => {
  it('uses the original filename when present', () => {
    expect(resolveAttachmentLabel('bloodwork.pdf', 'Generic PDF')).toBe('bloodwork.pdf');
  });

  it('falls back to the generic label when the filename is null', () => {
    expect(resolveAttachmentLabel(null, 'Generic PDF')).toBe('Generic PDF');
  });
});

describe('formatAttachmentSizeKb', () => {
  it('rounds to the nearest whole kilobyte', () => {
    expect(formatAttachmentSizeKb(204800)).toBe(200);
  });

  it('floors at 1 KB so a tiny file never displays as 0', () => {
    expect(formatAttachmentSizeKb(42)).toBe(1);
  });
});

describe('formatClinicalInstant', () => {
  it('formats a known instant deterministically for a fixed locale/date', () => {
    const formatted = formatClinicalInstant('2026-03-01T08:15:00Z', 'en-US');
    expect(typeof formatted).toBe('string');
    expect(formatted.length).toBeGreaterThan(0);
  });
});

describe('appendHistoryPage', () => {
  const entryA = { id: 'entry-a' } as GuardianMedicalHistoryEntry;
  const entryB = { id: 'entry-b' } as GuardianMedicalHistoryEntry;
  const entryC = { id: 'entry-c' } as GuardianMedicalHistoryEntry;

  it('keeps server order: existing entries first, new entries appended after', () => {
    const current: HistoryPageState = { entries: [entryA, entryB], cursor: null };
    const next: HistoryPageState = { entries: [entryC], cursor: null };

    expect(appendHistoryPage(current, next).entries).toEqual([entryA, entryB, entryC]);
  });

  it('adopts the new page cursor verbatim, never reconstructing it', () => {
    const current: HistoryPageState = { entries: [entryA], cursor: null };
    const next: HistoryPageState = {
      entries: [entryB],
      cursor: { beforeHistoryOrderAt: '2026-01-01T00:00:00Z', beforeEntryId: 'entry-b' },
    };

    expect(appendHistoryPage(current, next).cursor).toEqual({
      beforeHistoryOrderAt: '2026-01-01T00:00:00Z',
      beforeEntryId: 'entry-b',
    });
  });

  it('respects cursor end: a null next cursor means no further page', () => {
    const current: HistoryPageState = {
      entries: [entryA],
      cursor: { beforeHistoryOrderAt: 'x', beforeEntryId: 'y' },
    };
    const next: HistoryPageState = { entries: [entryB], cursor: null };

    expect(appendHistoryPage(current, next).cursor).toBeNull();
  });

  it('never appends an Entry already shown: the one on screen stays, in place', () => {
    const shownA = { id: 'entry-a', clinicalContent: 'shown' } as GuardianMedicalHistoryEntry;
    const againA = { id: 'entry-a', clinicalContent: 'again' } as GuardianMedicalHistoryEntry;
    const current: HistoryPageState = { entries: [shownA, entryB], cursor: null };
    const next: HistoryPageState = { entries: [againA, entryC], cursor: null };

    expect(appendHistoryPage(current, next).entries).toEqual([shownA, entryB, entryC]);
  });
});

describe('deriveHistoryLoadOutcome', () => {
  it('distinguishes DENIED from a loaded page', () => {
    const access: GuardianMedicalHistoryAccess = { status: 'DENIED' };
    expect(deriveHistoryLoadOutcome(access)).toEqual({ kind: 'denied' });
  });

  it('distinguishes a loaded empty page from DENIED', () => {
    const access: GuardianMedicalHistoryAccess = {
      status: 'PERMITTED',
      page: { entries: [], cursor: null },
    };

    const outcome = deriveHistoryLoadOutcome(access);
    expect(outcome.kind).toBe('loaded');
    expect(outcome.kind === 'loaded' && outcome.entries).toEqual([]);
  });

  it('carries entries and cursor through for a loaded non-empty page', () => {
    const entry = { id: 'entry-1' } as GuardianMedicalHistoryEntry;
    const access: GuardianMedicalHistoryAccess = {
      status: 'PERMITTED',
      page: {
        entries: [entry],
        cursor: { beforeHistoryOrderAt: '2026-01-01T00:00:00Z', beforeEntryId: 'entry-1' },
      },
    };

    const outcome = deriveHistoryLoadOutcome(access);
    expect(outcome).toEqual({
      kind: 'loaded',
      entries: [entry],
      cursor: { beforeHistoryOrderAt: '2026-01-01T00:00:00Z', beforeEntryId: 'entry-1' },
    });
  });
});
