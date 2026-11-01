import {
  parseProfessionalHistory,
  viewAppointmentProfessionalMedicalHistory,
} from '@/data/professional-medical-history';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;

const ENTRY_ID = '11111111-1111-4111-8111-111111111111';
const AMENDMENT_ID = '22222222-2222-4222-8222-222222222222';

const rawEntry = (overrides: Record<string, unknown> = {}) => ({
  entry_id: ENTRY_ID,
  category: 'TREATMENT',
  other_category_context: null,
  clinical_content: 'Dose 50 mg',
  clinical_event_at: null,
  history_order_at: '2025-03-01T09:00:00+00:00',
  finalized_at: '2025-12-01T00:00:00+00:00',
  clinic_display_name: 'Clínica Norte',
  organization_display_name: 'Org X',
  is_this_appointment: false,
  author: { display_name: 'Elena Vidal', is_me: false },
  finalizer: null,
  version: 1,
  edited_at: null,
  previous_versions: [],
  previous_versions_truncated: false,
  amendments: [
    {
      amendment_id: AMENDMENT_ID,
      reason: 'Incorrect dose',
      amendment_content: 'Correct dose is 5 mg',
      created_at: '2025-12-05T00:00:00+00:00',
      author: { display_name: null, is_me: true },
    },
  ],
  amendment_count: 1,
  amendments_truncated: false,
  ...overrides,
});

beforeEach(() => rpc.mockReset());

describe('parseProfessionalHistory', () => {
  it('maps a permitted page with provenance and Amendments', () => {
    const parsed = parseProfessionalHistory({
      status: 'PERMITTED',
      entries: [rawEntry()],
      cursor: { before_history_order_at: '2025-03-01T09:00:00+00:00', before_entry_id: ENTRY_ID },
    });
    expect(parsed).toEqual({
      kind: 'permitted',
      page: {
        entries: [
          {
            entryId: ENTRY_ID,
            category: 'TREATMENT',
            otherCategoryContext: null,
            clinicalContent: 'Dose 50 mg',
            clinicalEventAt: null,
            historyOrderAt: '2025-03-01T09:00:00+00:00',
            finalizedAt: '2025-12-01T00:00:00+00:00',
            clinicDisplayName: 'Clínica Norte',
            organizationDisplayName: 'Org X',
            isThisAppointment: false,
            author: { displayName: 'Elena Vidal', isMe: false },
            version: 1,
            editedAt: null,
            previousVersions: [],
            previousVersionsTruncated: false,
            amendments: [
              {
                amendmentId: AMENDMENT_ID,
                reason: 'Incorrect dose',
                amendmentContent: 'Correct dose is 5 mg',
                createdAt: '2025-12-05T00:00:00+00:00',
                author: { displayName: null, isMe: true },
              },
            ],
            amendmentCount: 1,
            amendmentsTruncated: false,
          },
        ],
        cursor: { beforeHistoryOrderAt: '2025-03-01T09:00:00+00:00', beforeEntryId: ENTRY_ID },
      },
    });
  });

  it('maps an edited Entry in its current version, with every earlier version (SPEC-MED-010 BR-22)', () => {
    const parsed = parseProfessionalHistory({
      status: 'PERMITTED',
      entries: [
        rawEntry({
          clinical_content: 'Dose 5 mg',
          version: 2,
          edited_at: '2025-12-02T00:00:00+00:00',
          previous_versions: [
            {
              version: 1,
              category: 'TREATMENT',
              other_category_context: null,
              clinical_content: 'Dose 50 mg',
              created_at: '2025-12-01T00:00:00+00:00',
            },
          ],
        }),
      ],
      cursor: null,
    });
    expect(parsed?.kind === 'permitted' && parsed.page.entries[0]).toMatchObject({
      clinicalContent: 'Dose 5 mg',
      finalizedAt: '2025-12-01T00:00:00+00:00',
      version: 2,
      editedAt: '2025-12-02T00:00:00+00:00',
      previousVersions: [{ version: 1, clinicalContent: 'Dose 50 mg' }],
    });
  });

  it('rejects an incoherent version history', () => {
    for (const entry of [
      rawEntry({ version: 2, edited_at: '2025-12-02T00:00:00+00:00' }),
      rawEntry({ version: 1, edited_at: '2025-12-02T00:00:00+00:00' }),
      rawEntry({ version: undefined }),
      rawEntry({ previous_versions_truncated: undefined }),
    ]) {
      expect(
        parseProfessionalHistory({ status: 'PERMITTED', entries: [entry], cursor: null }),
      ).toBeNull();
    }
  });

  it('accepts an empty history', () => {
    expect(parseProfessionalHistory({ status: 'PERMITTED', entries: [], cursor: null })).toEqual({
      kind: 'permitted',
      page: { entries: [], cursor: null },
    });
  });

  it('rejects the retired Encounter projection: a start time or a separate finalizer', () => {
    for (const entry of [
      rawEntry({ encounter_started_at: '2025-03-01T09:00:00+00:00' }),
      rawEntry({ finalizer: { display_name: 'Carlos Ruiz', is_me: false } }),
    ]) {
      expect(
        parseProfessionalHistory({ status: 'PERMITTED', entries: [entry], cursor: null }),
      ).toBeNull();
    }
  });

  it('a denial is exactly DENIED and carries nothing else', () => {
    expect(parseProfessionalHistory({ status: 'DENIED' })).toEqual({ kind: 'denied' });
    expect(parseProfessionalHistory({ status: 'DENIED', reason: 'UNKNOWN' })).toBeNull();
  });

  it('rejects a page carrying an unexpected key such as a leaked identifier', () => {
    expect(
      parseProfessionalHistory({
        status: 'PERMITTED',
        entries: [rawEntry({ author_user_id: '33333333-3333-4333-8333-333333333333' })],
        cursor: null,
      }),
    ).toBeNull();
    expect(
      parseProfessionalHistory({
        status: 'PERMITTED',
        entries: [
          rawEntry({ amendments: [{ ...rawEntry().amendments[0], amending_user_id: 'x' }] }),
        ],
        cursor: null,
      }),
    ).toBeNull();
    expect(
      parseProfessionalHistory({
        status: 'PERMITTED',
        entries: [rawEntry({ author: { display_name: 'Ana', is_me: false, user_id: 'x' } })],
        cursor: null,
      }),
    ).toBeNull();
  });

  it('rejects malformed pages', () => {
    for (const bad of [
      null,
      { status: 'PERMITTED' },
      { status: 'PERMITTED', entries: [rawEntry({ category: 'SURGERY' })], cursor: null },
      { status: 'PERMITTED', entries: [rawEntry({ author: null })], cursor: null },
      { status: 'PERMITTED', entries: [rawEntry({ amendment_count: 0 })], cursor: null },
      { status: 'PERMITTED', entries: [rawEntry(), rawEntry()], cursor: null },
      { status: 'PERMITTED', entries: [rawEntry()], cursor: { before_entry_id: ENTRY_ID } },
    ]) {
      expect(parseProfessionalHistory(bad)).toBeNull();
    }
  });
});

describe('viewAppointmentProfessionalMedicalHistory', () => {
  it('sends only the Clinic, Appointment, page size and cursor', async () => {
    rpc.mockResolvedValue({ data: { status: 'DENIED' }, error: null });
    await viewAppointmentProfessionalMedicalHistory('clinic-a', 'appt-1');
    await viewAppointmentProfessionalMedicalHistory('clinic-a', 'appt-1', {
      beforeHistoryOrderAt: '2025-03-01T09:00:00Z',
      beforeEntryId: ENTRY_ID,
    });
    expect(rpc.mock.calls).toEqual([
      [
        'view_appointment_professional_medical_history',
        {
          p_clinic_id: 'clinic-a',
          p_appointment_id: 'appt-1',
          p_limit: 50,
          p_before_history_order_at: null,
          p_before_entry_id: null,
        },
      ],
      [
        'view_appointment_professional_medical_history',
        {
          p_clinic_id: 'clinic-a',
          p_appointment_id: 'appt-1',
          p_limit: 50,
          p_before_history_order_at: '2025-03-01T09:00:00Z',
          p_before_entry_id: ENTRY_ID,
        },
      ],
    ]);
  });

  it('maps denial, session loss, failures and malformed data', async () => {
    rpc.mockResolvedValueOnce({ data: { status: 'DENIED' }, error: null });
    expect(await viewAppointmentProfessionalMedicalHistory('c', 'a')).toEqual({ kind: 'denied' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000' } });
    expect(await viewAppointmentProfessionalMedicalHistory('c', 'a')).toEqual({
      kind: 'authenticationRequired',
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '22023', hint: 'INVALID_CURSOR' } });
    expect(await viewAppointmentProfessionalMedicalHistory('c', 'a')).toEqual({ kind: 'failed' });
    rpc.mockResolvedValueOnce({ data: { status: 'MAYBE' }, error: null });
    expect(await viewAppointmentProfessionalMedicalHistory('c', 'a')).toEqual({ kind: 'failed' });
    rpc.mockRejectedValueOnce(new Error('offline'));
    expect(await viewAppointmentProfessionalMedicalHistory('c', 'a')).toEqual({ kind: 'failed' });
  });
});
