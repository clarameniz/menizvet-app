import { FunctionsHttpError, FunctionsRelayError } from '@supabase/supabase-js';

import {
  fromClinicalAmendmentRow,
  fromClinicalAttachmentRow,
  fromGuardianMedicalHistoryEntryRow,
  getGuardianClinicalAttachmentDownloadUrl,
  getGuardianPetMedicalHistory,
  type ClinicalAmendmentRow,
  type ClinicalAttachmentRow,
  type GuardianMedicalHistoryEntryRow,
} from '@/data/clinical-history';

// Same isolation rationale as data/pets.test.ts and data/appointments.test.ts:
// importing this module pulls in lib/supabase.ts, which throws under Jest
// without EXPO_PUBLIC_SUPABASE_* env vars. Mocking it also captures the last
// rpc(...)/functions.invoke(...) call so parameter mapping can be asserted
// without any real Supabase/Edge Function contact.
const mockRpc = jest.fn();
const mockInvoke = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: (...args: unknown[]) => mockRpc(...args),
    functions: { invoke: (...args: unknown[]) => mockInvoke(...args) },
  },
}));

beforeEach(() => {
  mockRpc.mockReset();
  mockInvoke.mockReset();
});

// ---------------------------------------------------------------------------
// Mappers
// ---------------------------------------------------------------------------

describe('fromClinicalAmendmentRow', () => {
  it('maps a full row to the camelCase shape', () => {
    const row: ClinicalAmendmentRow = {
      id: 'amendment-1',
      reason: 'Documentation error',
      amendment_content: 'Correct dose: 5 mg',
      created_at: '2026-03-01T10:00:00Z',
    };

    expect(fromClinicalAmendmentRow(row)).toEqual({
      id: 'amendment-1',
      reason: 'Documentation error',
      amendmentContent: 'Correct dose: 5 mg',
      createdAt: '2026-03-01T10:00:00Z',
    });
  });
});

describe('fromClinicalAttachmentRow', () => {
  it('maps a full row, narrowing validation fields to non-null', () => {
    const row: ClinicalAttachmentRow = {
      id: 'attachment-1',
      original_filename: 'bloodwork.pdf',
      created_at: '2026-03-01T09:00:00Z',
      trusted_media_type: 'application/pdf',
      trusted_byte_size: 204800,
      validation_completed_at: '2026-03-01T09:05:00Z',
    };

    expect(fromClinicalAttachmentRow(row)).toEqual({
      id: 'attachment-1',
      originalFilename: 'bloodwork.pdf',
      createdAt: '2026-03-01T09:00:00Z',
      trustedMediaType: 'application/pdf',
      trustedByteSize: 204800,
      validationCompletedAt: '2026-03-01T09:05:00Z',
    });
  });

  it('preserves a null original_filename', () => {
    const row: ClinicalAttachmentRow = {
      id: 'attachment-2',
      original_filename: null,
      created_at: '2026-03-01T09:00:00Z',
      trusted_media_type: 'application/pdf',
      trusted_byte_size: 1024,
      validation_completed_at: '2026-03-01T09:05:00Z',
    };

    expect(fromClinicalAttachmentRow(row).originalFilename).toBeNull();
  });
});

describe('fromGuardianMedicalHistoryEntryRow', () => {
  const baseRow: GuardianMedicalHistoryEntryRow = {
    id: 'entry-1',
    clinic_display_name: 'MenizVet Demo Valverde Centro',
    organization_display_name: 's3rt-20260825-1642 Duplicate',
    clinical_content: 'Routine annual examination, no findings.',
    category: 'EXAMINATION',
    other_category_context: null,
    clinical_event_at: '2026-03-01T08:15:00Z',
    history_order_at: '2026-03-01T08:15:00Z',
    finalized_at: '2026-03-01T08:30:00Z',
    version: 1,
    edited_at: null,
    previous_versions: [],
    previous_versions_truncated: false,
    amendments: [],
    amendment_count: 0,
    amendments_truncated: false,
    attachments: [],
  };

  it('maps a fully-populated entry to the camelCase shape', () => {
    expect(fromGuardianMedicalHistoryEntryRow(baseRow)).toEqual({
      id: 'entry-1',
      clinicDisplayName: 'MenizVet Demo Valverde Centro',
      organizationDisplayName: 's3rt-20260825-1642 Duplicate',
      clinicalContent: 'Routine annual examination, no findings.',
      category: 'EXAMINATION',
      otherCategoryContext: null,
      clinicalEventAt: '2026-03-01T08:15:00Z',
      historyOrderAt: '2026-03-01T08:15:00Z',
      finalizedAt: '2026-03-01T08:30:00Z',
      version: 1,
      editedAt: null,
      previousVersions: [],
      previousVersionsTruncated: false,
      amendments: [],
      amendmentCount: 0,
      amendmentsTruncated: false,
      attachments: [],
    });
  });

  it('maps an edited entry: its current version, edit time and earlier versions (SPEC-MED-010 BR-22)', () => {
    const entry = fromGuardianMedicalHistoryEntryRow({
      ...baseRow,
      category: 'CLINICAL_NOTE',
      clinical_content: 'Solo se realizó un corte de uñas',
      version: 2,
      edited_at: '2026-03-01T09:00:00Z',
      previous_versions: [
        {
          version: 1,
          category: 'VACCINATION',
          other_category_context: null,
          clinical_content: 'Vacuna de la rabia anual',
          created_at: '2026-03-01T08:30:00Z',
        },
      ],
    });
    expect(entry).toMatchObject({
      category: 'CLINICAL_NOTE',
      clinicalContent: 'Solo se realizó un corte de uñas',
      finalizedAt: '2026-03-01T08:30:00Z',
      version: 2,
      editedAt: '2026-03-01T09:00:00Z',
      previousVersions: [
        {
          version: 1,
          category: 'VACCINATION',
          otherCategoryContext: null,
          clinicalContent: 'Vacuna de la rabia anual',
          createdAt: '2026-03-01T08:30:00Z',
        },
      ],
    });
  });

  it('never carries internal identifiers into the Guardian entry, even if a row had them', () => {
    const leaky = {
      ...baseRow,
      appointment_id: 'appointment-1',
      clinic_id: 'clinic-1',
      created_by_user_id: 'user-1',
      amendments: [
        {
          id: 'amendment-1',
          reason: 'Documentation error',
          amendment_content: 'Correct dose: 5 mg',
          created_at: '2026-03-02T10:00:00Z',
          amending_user_id: 'user-1',
          amending_veterinarian_clinic_assignment_id: 'vca-1',
        },
      ],
      amendment_count: 1,
    } as unknown as GuardianMedicalHistoryEntryRow;

    const text = JSON.stringify(fromGuardianMedicalHistoryEntryRow(leaky));
    expect(text).not.toMatch(/appointment-1|clinic-1|user-1|vca-1/);
  });

  it('maps a null clinic_display_name to a null clinicDisplayName', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      clinic_display_name: null,
    };

    expect(fromGuardianMedicalHistoryEntryRow(row).clinicDisplayName).toBeNull();
  });

  it('maps a null organization_display_name to a null organizationDisplayName', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      organization_display_name: null,
    };

    expect(fromGuardianMedicalHistoryEntryRow(row).organizationDisplayName).toBeNull();
  });

  it('preserves a null category and null other_category_context', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      category: null,
      other_category_context: null,
    };

    const entry = fromGuardianMedicalHistoryEntryRow(row);
    expect(entry.category).toBeNull();
    expect(entry.otherCategoryContext).toBeNull();
  });

  it('preserves a null clinical_event_at (entry dated by its recording time)', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      clinical_event_at: null,
      // The server already resolved history_order_at via
      // coalesce(clinical_event_at, recorded time) — distinct from
      // finalized_at here only to prove the mapper never recomputes it.
      history_order_at: '2026-03-01T08:00:00Z',
    };

    const entry = fromGuardianMedicalHistoryEntryRow(row);
    expect(entry.clinicalEventAt).toBeNull();
    expect(entry.historyOrderAt).toBe('2026-03-01T08:00:00Z');
  });

  it('takes historyOrderAt verbatim from the payload, never recomputed client-side', () => {
    // A deliberately "wrong" value relative to clinical_event_at/
    // finalized_at proves the mapper is a pure passthrough, not a
    // client-side coalesce of the other two fields.
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      clinical_event_at: '2026-03-01T08:15:00Z',
      history_order_at: '2099-01-01T00:00:00Z',
    };

    expect(fromGuardianMedicalHistoryEntryRow(row).historyOrderAt).toBe('2099-01-01T00:00:00Z');
  });

  it('maps embedded amendments', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      amendments: [
        {
          id: 'amendment-1',
          reason: 'Documentation error',
          amendment_content: 'Correct dose: 5 mg',
          created_at: '2026-03-02T10:00:00Z',
        },
      ],
      amendment_count: 1,
      amendments_truncated: false,
    };

    const entry = fromGuardianMedicalHistoryEntryRow(row);
    expect(entry.amendments).toEqual([
      {
        id: 'amendment-1',
        reason: 'Documentation error',
        amendmentContent: 'Correct dose: 5 mg',
        createdAt: '2026-03-02T10:00:00Z',
      },
    ]);
  });

  it('preserves amendmentCount and amendmentsTruncated independently of the embedded array length', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      amendments: [],
      amendment_count: 137,
      amendments_truncated: true,
    };

    const entry = fromGuardianMedicalHistoryEntryRow(row);
    expect(entry.amendmentCount).toBe(137);
    expect(entry.amendmentsTruncated).toBe(true);
  });

  it('maps embedded attachments', () => {
    const row: GuardianMedicalHistoryEntryRow = {
      ...baseRow,
      attachments: [
        {
          id: 'attachment-1',
          original_filename: 'bloodwork.pdf',
          created_at: '2026-03-01T09:00:00Z',
          trusted_media_type: 'application/pdf',
          trusted_byte_size: 204800,
          validation_completed_at: '2026-03-01T09:05:00Z',
        },
      ],
    };

    const entry = fromGuardianMedicalHistoryEntryRow(row);
    expect(entry.attachments).toEqual([
      {
        id: 'attachment-1',
        originalFilename: 'bloodwork.pdf',
        createdAt: '2026-03-01T09:00:00Z',
        trustedMediaType: 'application/pdf',
        trustedByteSize: 204800,
        validationCompletedAt: '2026-03-01T09:05:00Z',
      },
    ]);
  });
});

// ---------------------------------------------------------------------------
// getGuardianPetMedicalHistory
// ---------------------------------------------------------------------------

describe('getGuardianPetMedicalHistory', () => {
  it('maps an empty PERMITTED page (valid empty history, not an error)', async () => {
    mockRpc.mockResolvedValueOnce({
      data: { status: 'PERMITTED', payload: { entries: [] }, cursor: null },
      error: null,
    });

    const result = await getGuardianPetMedicalHistory('pet-1');

    expect(result).toEqual({
      data: { status: 'PERMITTED', page: { entries: [], cursor: null } },
      error: null,
    });
  });

  it('requests the first page with a null cursor', async () => {
    mockRpc.mockResolvedValueOnce({
      data: { status: 'PERMITTED', payload: { entries: [] }, cursor: null },
      error: null,
    });

    await getGuardianPetMedicalHistory('pet-1');

    expect(mockRpc).toHaveBeenCalledWith('view_guardian_pet_medical_history', {
      p_pet_id: 'pet-1',
      p_limit: 20,
      p_before_history_order_at: null,
      p_before_entry_id: null,
    });
  });

  it('forwards the exact server-returned cursor for the next page, never reconstructing it', async () => {
    mockRpc.mockResolvedValueOnce({
      data: {
        status: 'PERMITTED',
        payload: { entries: [] },
        cursor: { before_history_order_at: '2026-02-01T00:00:00Z', before_entry_id: 'entry-50' },
      },
      error: null,
    });

    const firstPage = await getGuardianPetMedicalHistory('pet-1');
    expect(firstPage.data).toEqual({
      status: 'PERMITTED',
      page: {
        entries: [],
        cursor: { beforeHistoryOrderAt: '2026-02-01T00:00:00Z', beforeEntryId: 'entry-50' },
      },
    });
    const cursor = firstPage.data?.status === 'PERMITTED' ? firstPage.data.page.cursor : null;
    expect(cursor).not.toBeNull();

    mockRpc.mockResolvedValueOnce({
      data: { status: 'PERMITTED', payload: { entries: [] }, cursor: null },
      error: null,
    });

    await getGuardianPetMedicalHistory('pet-1', cursor);

    expect(mockRpc).toHaveBeenLastCalledWith('view_guardian_pet_medical_history', {
      p_pet_id: 'pet-1',
      p_limit: 20,
      p_before_history_order_at: '2026-02-01T00:00:00Z',
      p_before_entry_id: 'entry-50',
    });
  });

  it('represents DENIED as a typed domain state in `data`, never as `error`', async () => {
    mockRpc.mockResolvedValueOnce({ data: { status: 'DENIED' }, error: null });

    const result = await getGuardianPetMedicalHistory('pet-1');

    expect(result).toEqual({ data: { status: 'DENIED' }, error: null });
    expect(result.error).toBeNull();
  });

  it('maps a resolved PostgREST error to the error side', async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Page limit must be positive' },
    });

    const result = await getGuardianPetMedicalHistory('pet-1');

    expect(result).toEqual({ data: null, error: 'Page limit must be positive' });
  });

  it('settles into {data:null,error:string} instead of rejecting on a network failure', async () => {
    mockRpc.mockRejectedValueOnce(new Error('Network request failed'));

    const result = await getGuardianPetMedicalHistory('pet-1');

    expect(result).toEqual({ data: null, error: 'Network request failed' });
  });
});

// ---------------------------------------------------------------------------
// getGuardianClinicalAttachmentDownloadUrl
// ---------------------------------------------------------------------------

describe('getGuardianClinicalAttachmentDownloadUrl', () => {
  it('maps a PERMITTED Edge Function response to the typed success shape', async () => {
    mockInvoke.mockResolvedValueOnce({
      data: {
        status: 'PERMITTED',
        signed_download_url: 'https://storage.example/signed?token=abc',
        original_filename: 'bloodwork.pdf',
        expires_in_seconds: 60,
      },
      error: null,
      response: undefined,
    });

    const result = await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    expect(result).toEqual({
      data: {
        status: 'PERMITTED',
        signedDownloadUrl: 'https://storage.example/signed?token=abc',
        originalFilename: 'bloodwork.pdf',
        expiresInSeconds: 60,
      },
      error: null,
    });
  });

  it('invokes the exact route with the attachment id body', async () => {
    mockInvoke.mockResolvedValueOnce({
      data: {
        status: 'PERMITTED',
        signed_download_url: 'https://storage.example/signed',
        original_filename: null,
        expires_in_seconds: 60,
      },
      error: null,
      response: undefined,
    });

    await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    expect(mockInvoke).toHaveBeenCalledWith('clinical-attachments/guardian-download', {
      body: { attachment_id: 'attachment-1' },
    });
  });

  it('maps a DENIED (HTTP 403) Edge Function response to the typed domain state, not error', async () => {
    const fakeResponse = { json: async () => ({ status: 'DENIED' }) } as unknown as Response;
    mockInvoke.mockResolvedValueOnce({
      data: null,
      error: new FunctionsHttpError(fakeResponse),
      response: fakeResponse,
    });

    const result = await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    expect(result).toEqual({ data: { status: 'DENIED' }, error: null });
    expect(result.error).toBeNull();
  });

  it('maps an Edge Function technical failure body to the error side without leaking it into data', async () => {
    const fakeResponse = { json: async () => ({ error: 'INTERNAL_ERROR' }) } as unknown as Response;
    mockInvoke.mockResolvedValueOnce({
      data: null,
      error: new FunctionsHttpError(fakeResponse),
      response: fakeResponse,
    });

    const result = await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    expect(result).toEqual({ data: null, error: 'INTERNAL_ERROR' });
  });

  it('maps a relay error with an unparsable body to a generic technical error, not a thrown rejection', async () => {
    const fakeResponse = {
      json: async () => {
        throw new Error('not json');
      },
    } as unknown as Response;
    const relayError = new FunctionsRelayError(fakeResponse);
    mockInvoke.mockResolvedValueOnce({ data: null, error: relayError, response: fakeResponse });

    const result = await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    expect(result.data).toBeNull();
    expect(typeof result.error).toBe('string');
  });

  it('settles into {data:null,error:string} instead of rejecting on a network failure', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('Network request failed'));

    const result = await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    expect(result).toEqual({ data: null, error: 'Network request failed' });
  });

  it('never exposes a raw backend/Edge Function token as the success payload', async () => {
    const fakeResponse = { json: async () => ({ status: 'DENIED' }) } as unknown as Response;
    mockInvoke.mockResolvedValueOnce({
      data: null,
      error: new FunctionsHttpError(fakeResponse),
      response: fakeResponse,
    });

    const result = await getGuardianClinicalAttachmentDownloadUrl('attachment-1');

    // DENIED must never surface as a raw string/code in `error` — it is a
    // typed domain state, and `error` stays null alongside it.
    expect(result.error).toBeNull();
    expect(result.data).toEqual({ status: 'DENIED' });
  });
});
