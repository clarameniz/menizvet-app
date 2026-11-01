import type {
  AppointmentClinicalEntry,
  AppointmentClinicalRecord,
} from '@/data/appointment-clinical-record';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import {
  canClarifyEntry,
  canEditEntry,
  documentationUnavailableKey,
  draftFromEntry,
  editSaveOutcome,
  EMPTY_CLINICAL_ENTRY_DRAFT,
  entryFieldsFromDraft,
  entrySaveOutcome,
  findSubmittedEntry,
  hasEntryChanges,
  isAssignmentRejection,
  isEntryDraftDirty,
  isSubmittedEditCurrent,
} from '@/lib/appointment-clinical-record';

const entry = (overrides: Partial<AppointmentClinicalEntry> = {}): AppointmentClinicalEntry => ({
  entryId: 'e-1',
  category: 'EXAMINATION',
  otherCategoryContext: null,
  clinicalContent: 'Peso 12 kg',
  clinicalEventAt: null,
  recordedAt: '2026-06-01T08:10:00Z',
  recordedByMe: true,
  mayEdit: true,
  version: 1,
  editedAt: null,
  previousVersions: [],
  previousVersionsTruncated: false,
  amendments: [],
  amendmentsTruncated: false,
  ...overrides,
});
const record = (overrides: Partial<AppointmentClinicalRecord> = {}): AppointmentClinicalRecord => ({
  appointmentId: 'appt-1',
  appointmentLifecycleState: 'CONFIRMED',
  canRecord: true,
  unavailableReason: null,
  entries: [entry()],
  entriesTruncated: false,
  ...overrides,
});

describe('record section (SPEC-MED-010 Part F)', () => {
  it('offers Add record only when the server says the reader can record', () => {
    expect(documentationUnavailableKey(record())).toBeNull();
  });

  it.each([
    ['APPOINTMENT_STATE', 'clinicalRecord.unavailableAppointmentState'],
    ['NO_VETERINARIAN_ASSIGNED', 'clinicalRecord.unavailableNoVeterinarian'],
    ['NOT_ASSIGNED_VETERINARIAN', 'clinicalRecord.unavailableNotAssigned'],
    ['CLINICAL_SERVICE_UNAVAILABLE', 'clinicalRecord.serviceUnavailable'],
  ] as const)('explains %s with one calm line', (reason, key) => {
    expect(
      documentationUnavailableKey(record({ canRecord: false, unavailableReason: reason })),
    ).toBe(key);
  });

  it('offers Edit only on the reader’s own record, and a clarification only on another’s', () => {
    const own = entry();
    const other = entry({ recordedByMe: false, mayEdit: false });
    expect(canEditEntry(own)).toBe(true);
    expect(canEditEntry(other)).toBe(false);
    expect(canClarifyEntry(own, record())).toBe(false);
    expect(canClarifyEntry(other, record())).toBe(true);
    // A clarification is a new record: only for whoever can record now.
    expect(
      canClarifyEntry(
        other,
        record({ canRecord: false, unavailableReason: 'NOT_ASSIGNED_VETERINARIAN' }),
      ),
    ).toBe(false);
  });

  it('offers View changes only when earlier versions or historical corrections exist', () => {
    expect(hasEntryChanges(entry())).toBe(false);
    expect(
      hasEntryChanges(
        entry({
          version: 2,
          previousVersions: [
            {
              version: 1,
              category: 'VACCINATION',
              otherCategoryContext: null,
              clinicalContent: 'Vacuna de la rabia anual',
              createdAt: '2026-06-01T08:10:00Z',
            },
          ],
        }),
      ),
    ).toBe(true);
    expect(
      hasEntryChanges(
        entry({
          amendments: [
            {
              amendmentId: 'am-1',
              reason: 'Dosis',
              amendmentContent: '5 mg',
              createdAt: '2026-06-02T09:00:00Z',
              amendedByMe: true,
            },
          ],
        }),
      ),
    ).toBe(true);
  });
});

describe('editor draft', () => {
  it('starts with nothing selected, asks for no time and is not dirty', () => {
    expect(EMPTY_CLINICAL_ENTRY_DRAFT).toEqual({ category: null, content: '', otherContext: '' });
    expect(isEntryDraftDirty(EMPTY_CLINICAL_ENTRY_DRAFT)).toBe(false);
  });

  it('is dirty as soon as anything is chosen or typed (whitespace is nothing)', () => {
    expect(isEntryDraftDirty({ ...EMPTY_CLINICAL_ENTRY_DRAFT, content: '  \n' })).toBe(false);
    expect(isEntryDraftDirty({ ...EMPTY_CLINICAL_ENTRY_DRAFT, content: 'x' })).toBe(true);
    expect(isEntryDraftDirty({ ...EMPTY_CLINICAL_ENTRY_DRAFT, category: 'DIAGNOSIS' })).toBe(true);
  });

  it('asks for the category, the OTHER context and the content, in that order', () => {
    expect(entryFieldsFromDraft(EMPTY_CLINICAL_ENTRY_DRAFT)).toEqual({
      kind: 'issue',
      field: 'category',
      messageKey: 'clinicalRecord.categoryRequired',
    });
    expect(
      entryFieldsFromDraft({ ...EMPTY_CLINICAL_ENTRY_DRAFT, category: 'OTHER', content: 'x' }),
    ).toMatchObject({ field: 'otherContext' });
    expect(
      entryFieldsFromDraft({ ...EMPTY_CLINICAL_ENTRY_DRAFT, category: 'TREATMENT' }),
    ).toMatchObject({ field: 'content', messageKey: 'clinicalRecord.contentRequired' });
  });

  it('trims the payload, sends OTHER context only with OTHER, and never a time', () => {
    expect(
      entryFieldsFromDraft({
        category: 'TREATMENT',
        content: '  Amoxicilina 50 mg \n',
        otherContext: 'leftover',
      }),
    ).toEqual({
      kind: 'ok',
      fields: {
        category: 'TREATMENT',
        clinicalContent: 'Amoxicilina 50 mg',
        otherCategoryContext: null,
      },
    });
    expect(
      entryFieldsFromDraft({ category: 'OTHER', content: 'x', otherContext: ' Conducta ' }),
    ).toMatchObject({ fields: { otherCategoryContext: 'Conducta' } });
  });

  it('Edit opens on the current version; it is dirty only when something differs from it', () => {
    const own = entry({ category: 'OTHER', otherCategoryContext: 'Peluquería', version: 3 });
    const opened = draftFromEntry(own);
    expect(opened).toEqual({
      category: 'OTHER',
      content: 'Peso 12 kg',
      otherContext: 'Peluquería',
    });
    expect(isEntryDraftDirty(opened, opened)).toBe(false);
    expect(isEntryDraftDirty({ ...opened, content: ' Peso 12 kg ' }, opened)).toBe(false);
    expect(isEntryDraftDirty({ ...opened, content: 'Peso 12,5 kg' }, opened)).toBe(true);
    expect(isEntryDraftDirty({ ...opened, otherContext: 'Baño' }, opened)).toBe(true);
    expect(isEntryDraftDirty({ ...opened, category: 'CLINICAL_NOTE' }, opened)).toBe(true);
  });
});

describe('save outcome (decided from the authoritative re-read)', () => {
  const fields = {
    category: 'EXAMINATION' as const,
    clinicalContent: 'Peso 12 kg',
    otherCategoryContext: null,
  };

  it('CREATED and ALREADY_CREATED are saved', () => {
    expect(entrySaveOutcome({ kind: 'outcome', outcome: 'CREATED', entryId: 'e-9' }, null)).toEqual(
      {
        kind: 'saved',
      },
    );
    expect(
      entrySaveOutcome({ kind: 'outcome', outcome: 'ALREADY_CREATED', entryId: 'e-9' }, null),
    ).toEqual({ kind: 'saved' });
  });

  it('a lost response is saved only when the re-read shows a NEW record of mine with these fields', () => {
    const known = new Set(['e-1']);
    // The identical earlier record does not count.
    expect(findSubmittedEntry(record(), fields, known)).toBeNull();
    const fresh = entry({ entryId: 'e-2' });
    expect(findSubmittedEntry(record({ entries: [entry(), fresh] }), fields, known)).toBe(fresh);
    expect(
      findSubmittedEntry(
        record({ entries: [entry({ entryId: 'e-2', recordedByMe: false })] }),
        fields,
        known,
      ),
    ).toBeNull();
    expect(entrySaveOutcome({ kind: 'uncertain' }, fresh)).toEqual({ kind: 'saved' });
    expect(entrySaveOutcome({ kind: 'uncertain' }, null)).toEqual({
      kind: 'kept',
      notice: { tone: 'error', messageKey: 'clinicalRecord.unconfirmedSave' },
    });
  });

  it.each([
    [{ kind: 'serviceUnavailable' as const }, 'clinicalRecord.serviceUnavailable'],
    [{ kind: 'denied' as const }, 'clinicalRecord.saveDenied'],
    [{ kind: 'authenticationRequired' as const }, 'errors.sessionExpired'],
    [{ kind: 'rejected' as const, reason: 'KEY_CONFLICT' as const }, 'clinicalRecord.keyConflict'],
    [
      { kind: 'rejected' as const, reason: 'APPOINTMENT_STATE_INVALID' as const },
      'clinicalRecord.unavailableAppointmentState',
    ],
    [
      { kind: 'rejected' as const, reason: 'NOT_ASSIGNED_VETERINARIAN' as const },
      'clinicalRecord.unavailableNotAssigned',
    ],
  ])('keeps the text after %o', (result, messageKey) => {
    expect(entrySaveOutcome(result, null)).toEqual({
      kind: 'kept',
      notice: { tone: 'error', messageKey },
    });
  });

  it('re-reads the assignment only after an assignment rejection', () => {
    expect(isAssignmentRejection({ kind: 'rejected', reason: 'NOT_ASSIGNED_VETERINARIAN' })).toBe(
      true,
    );
    expect(isAssignmentRejection({ kind: 'rejected', reason: 'NO_VETERINARIAN_ASSIGNED' })).toBe(
      true,
    );
    expect(isAssignmentRejection({ kind: 'rejected', reason: 'KEY_CONFLICT' })).toBe(false);
    expect(isAssignmentRejection({ kind: 'denied' })).toBe(false);
  });
});

describe('edit outcome (SPEC-MED-010 BR-23b)', () => {
  const corrected = {
    category: 'CLINICAL_NOTE' as const,
    clinicalContent: 'Solo se realizó un corte de uñas',
    otherCategoryContext: null,
  };
  const edited = entry({
    category: 'CLINICAL_NOTE',
    clinicalContent: 'Solo se realizó un corte de uñas',
    version: 2,
    editedAt: '2026-06-01T09:00:00Z',
  });

  it('EDITED and ALREADY_EDITED are saved; UNCHANGED closes saying nothing changed', () => {
    expect(editSaveOutcome({ kind: 'outcome', outcome: 'EDITED', version: 2 }, false)).toEqual({
      kind: 'saved',
      notice: { tone: 'info', messageKey: 'clinicalRecord.changesSaved' },
    });
    expect(
      editSaveOutcome({ kind: 'outcome', outcome: 'ALREADY_EDITED', version: 2 }, false),
    ).toMatchObject({ kind: 'saved', notice: { messageKey: 'clinicalRecord.changesSaved' } });
    expect(
      editSaveOutcome({ kind: 'outcome', outcome: 'UNCHANGED', version: 1 }, false),
    ).toMatchObject({ kind: 'saved', notice: { messageKey: 'clinicalRecord.noChanges' } });
  });

  it('a lost response is saved only when the re-read shows a newer current version with these fields', () => {
    expect(isSubmittedEditCurrent(record({ entries: [edited] }), 'e-1', 1, corrected)).toBe(true);
    // Not newer than the version the editor opened on.
    expect(isSubmittedEditCurrent(record({ entries: [edited] }), 'e-1', 2, corrected)).toBe(false);
    // Newer, but someone saved something else.
    expect(
      isSubmittedEditCurrent(
        record({ entries: [{ ...edited, clinicalContent: 'Corte de uñas y baño' }] }),
        'e-1',
        1,
        corrected,
      ),
    ).toBe(false);
    expect(isSubmittedEditCurrent(null, 'e-1', 1, corrected)).toBe(false);
    expect(editSaveOutcome({ kind: 'uncertain' }, true)).toMatchObject({ kind: 'saved' });
    expect(editSaveOutcome({ kind: 'uncertain' }, false)).toEqual({
      kind: 'kept',
      notice: { tone: 'error', messageKey: 'clinicalRecord.unconfirmedEdit' },
    });
  });

  it('a stale version keeps the text and is told apart from every other refusal', () => {
    expect(editSaveOutcome({ kind: 'rejected', reason: 'STALE_VERSION' }, false)).toEqual({
      kind: 'stale',
    });
    expect(editSaveOutcome({ kind: 'rejected', reason: 'ENTRY_AUTHOR_REQUIRED' }, false)).toEqual({
      kind: 'kept',
      notice: { tone: 'error', messageKey: 'clinicalRecord.editAuthorOnly' },
    });
    // Permission lost (offboarding, another Clinic): the text stays.
    expect(editSaveOutcome({ kind: 'denied' }, false)).toEqual({
      kind: 'kept',
      notice: { tone: 'error', messageKey: 'clinicalRecord.editDenied' },
    });
    expect(editSaveOutcome({ kind: 'rejected', reason: 'KEY_CONFLICT' }, false)).toMatchObject({
      kind: 'kept',
      notice: { messageKey: 'clinicalRecord.keyConflict' },
    });
  });
});

describe('approved wording', () => {
  it('uses the approved Spanish and English labels', () => {
    expect(es.clinicalRecord.addRecord).toBe('Añadir registro');
    expect(es.clinicalRecord.saveRecord).toBe('Guardar registro');
    expect(es.clinicalRecord.edit).toBe('Editar');
    expect(es.clinicalRecord.saveChanges).toBe('Guardar cambios');
    expect(es.clinicalRecord.viewChanges).toBe('Ver cambios');
    expect(es.clinicalRecord.cancelEditor).toBe('Cancelar');
    expect(es.clinicalRecord.recordedOn).toBe('Registrado el {{time}}');
    expect(es.clinicalRecord.publishNotice).toBe(
      'El registro será visible para los responsables de la mascota. Los cambios posteriores quedarán documentados.',
    );
    expect(es.clinicalRecord.clarify).toBe('Añadir registro aclaratorio');
    expect(es.clinicalRecord.clarifyNote).toBe(
      'Esto crea un registro nuevo tuyo. El registro original y su autoría no cambian.',
    );
    expect(es.clinicalRecord.unavailableNotAssigned).toBe(
      'Solo el veterinario asignado puede añadir registros.',
    );
    expect(es.professionalHistory.action).toBe('Ver registros anteriores');
    expect(en.professionalHistory.action).toBe('View previous records');
    expect(en.clinicalRecord.addRecord).toBe('Add record');
    expect(en.clinicalRecord.saveRecord).toBe('Save record');
    expect(en.clinicalRecord.edit).toBe('Edit');
    expect(en.clinicalRecord.saveChanges).toBe('Save changes');
    expect(en.clinicalRecord.viewChanges).toBe('View changes');
    expect(en.clinicalRecord.clarify).toBe('Add a clarifying record');
    expect(en.clinicalRecord.unavailableNotAssigned).toBe(
      'Only the assigned veterinarian can add records.',
    );
  });

  it('asks for no clinical time and no reason for an edit', () => {
    for (const catalog of [es.clinicalRecord, en.clinicalRecord]) {
      const keys = Object.keys(catalog).join(' ');
      expect(keys).not.toMatch(/eventTime|rectif|amendmentReasonField|saveAndPublish/i);
      expect(Object.values(catalog).join(' ')).not.toMatch(
        /Momento clínico|Clinical time|Rectificar|Rectify/,
      );
    }
  });

  it('never mentions an Encounter, a Care Authorization, an Entitlement, drafts or finalizing', () => {
    for (const catalog of [
      es.clinicalRecord,
      en.clinicalRecord,
      es.veterinarianAssignment,
      en.veterinarianAssignment,
    ]) {
      const text = Object.values(catalog).join(' ');
      expect(text).not.toMatch(
        /[Ee]ncounter|[Aa]utorizaci[oó]n|[Aa]uthori[sz]ation|[Ee]ntitlement|[Bb]orrador|[Dd]raft|[Ff]inaliz/,
      );
    }
  });
});
