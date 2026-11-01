import {
  CLINICAL_RECORD_CATEGORIES,
  createAppointmentClinicalEntry,
  editAppointmentClinicalEntry,
  parseAppointmentClinicalRecord,
  viewAppointmentClinicalRecord,
} from '@/data/appointment-clinical-record';
import * as clinicalRecordModule from '@/data/appointment-clinical-record';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;

const CLINIC = 'd0340000-0000-4000-8000-000000004001';
const APPOINTMENT = 'd0340000-0000-4000-8000-000000011001';
const ENTRY = 'd0340000-0000-4000-8000-000000016001';
const KEY = 'd0340000-0000-4000-8000-000000013001';
const AMENDMENT = 'd0340000-0000-4000-8000-000000020001';

const amendmentRow = (overrides: Record<string, unknown> = {}) => ({
  amendment_id: AMENDMENT,
  reason: 'Incorrect dose documented',
  amendment_content: 'Dose is 5 mg',
  created_at: '2026-06-02T09:00:00+00:00',
  amended_by_me: true,
  ...overrides,
});
const versionRow = (version: number, overrides: Record<string, unknown> = {}) => ({
  version,
  category: 'VACCINATION',
  other_category_context: null,
  clinical_content: `Version ${version}`,
  created_at: '2026-06-01T10:10:00+00:00',
  ...overrides,
});
const entryRow = (overrides: Record<string, unknown> = {}) => ({
  entry_id: ENTRY,
  category: 'EXAMINATION',
  other_category_context: null,
  clinical_content: 'Weight 12 kg',
  clinical_event_at: null,
  recorded_at: '2026-06-01T10:10:00+00:00',
  recorded_by_me: true,
  may_edit: true,
  version: 1,
  edited_at: null,
  previous_versions: [],
  previous_versions_truncated: false,
  amendments: [],
  amendments_truncated: false,
  ...overrides,
});
const editedRow = (overrides: Record<string, unknown> = {}) =>
  entryRow({
    category: 'CLINICAL_NOTE',
    clinical_content: 'Only a nail trim was performed',
    version: 2,
    edited_at: '2026-06-01T11:00:00+00:00',
    previous_versions: [versionRow(1, { clinical_content: 'Rabies vaccine, annual' })],
    ...overrides,
  });
const payload = (overrides: Record<string, unknown> = {}) => ({
  status: 'PERMITTED',
  appointment: { appointment_id: APPOINTMENT, lifecycle_state: 'CONFIRMED' },
  documentation: { can_record: true, unavailable_reason: null },
  entries: [entryRow()],
  entries_truncated: false,
  ...overrides,
});
const firstEntry = (raw: unknown) => {
  const parsed = parseAppointmentClinicalRecord(raw);
  return parsed?.kind === 'permitted' ? parsed.record.entries[0] : null;
};

beforeEach(() => rpc.mockReset());

describe('parseAppointmentClinicalRecord', () => {
  it('maps the documentation state and the Entries, with no internal identifier', () => {
    expect(parseAppointmentClinicalRecord(payload())).toEqual({
      kind: 'permitted',
      record: {
        appointmentId: APPOINTMENT,
        appointmentLifecycleState: 'CONFIRMED',
        canRecord: true,
        unavailableReason: null,
        entries: [
          {
            entryId: ENTRY,
            category: 'EXAMINATION',
            otherCategoryContext: null,
            clinicalContent: 'Weight 12 kg',
            clinicalEventAt: null,
            recordedAt: '2026-06-01T10:10:00+00:00',
            recordedByMe: true,
            mayEdit: true,
            version: 1,
            editedAt: null,
            previousVersions: [],
            previousVersionsTruncated: false,
            amendments: [],
            amendmentsTruncated: false,
          },
        ],
        entriesTruncated: false,
      },
    });
  });

  it('maps an edited Entry: the current version, its edit time and the earlier version', () => {
    expect(firstEntry(payload({ entries: [editedRow()] }))).toMatchObject({
      category: 'CLINICAL_NOTE',
      clinicalContent: 'Only a nail trim was performed',
      recordedAt: '2026-06-01T10:10:00+00:00',
      version: 2,
      editedAt: '2026-06-01T11:00:00+00:00',
      previousVersions: [
        {
          version: 1,
          category: 'VACCINATION',
          otherCategoryContext: null,
          clinicalContent: 'Rabies vaccine, annual',
          createdAt: '2026-06-01T10:10:00+00:00',
        },
      ],
    });
  });

  it('maps another Veterinarian’s historical Entry with its event time and earlier corrections', () => {
    expect(
      firstEntry(
        payload({
          entries: [
            entryRow({
              recorded_by_me: false,
              may_edit: false,
              clinical_event_at: '2026-06-01T09:55:00+00:00',
              amendments: [amendmentRow({ amended_by_me: false })],
            }),
          ],
        }),
      ),
    ).toMatchObject({
      recordedByMe: false,
      mayEdit: false,
      clinicalEventAt: '2026-06-01T09:55:00+00:00',
      amendments: [
        {
          amendmentId: AMENDMENT,
          reason: 'Incorrect dose documented',
          amendmentContent: 'Dose is 5 mg',
          createdAt: '2026-06-02T09:00:00+00:00',
          amendedByMe: false,
        },
      ],
    });
  });

  it('accepts a truncated history of exactly the first 100 earlier versions', () => {
    const versions = Array.from({ length: 100 }, (_, index) => versionRow(index + 1));
    expect(
      firstEntry(
        payload({
          entries: [
            editedRow({
              version: 150,
              previous_versions: versions,
              previous_versions_truncated: true,
            }),
          ],
        }),
      ),
    ).toMatchObject({ version: 150, previousVersionsTruncated: true });
  });

  it.each([
    'APPOINTMENT_STATE',
    'NO_VETERINARIAN_ASSIGNED',
    'NOT_ASSIGNED_VETERINARIAN',
    'CLINICAL_SERVICE_UNAVAILABLE',
  ])('maps the unavailable reason %s', (reason) => {
    const parsed = parseAppointmentClinicalRecord(
      payload({ documentation: { can_record: false, unavailable_reason: reason } }),
    );
    expect(parsed?.kind === 'permitted' && parsed.record).toMatchObject({
      canRecord: false,
      unavailableReason: reason,
    });
  });

  it('keeps DENIED as its own typed state', () => {
    expect(parseAppointmentClinicalRecord({ status: 'DENIED' })).toEqual({ kind: 'denied' });
  });

  it.each<[string, unknown]>([
    ['not an object', null],
    ['an unknown status', { ...payload(), status: 'MAYBE' }],
    ['the retired Encounter payload', { ...payload(), documentation: undefined, encounter: {} }],
    [
      'can_record contradicting the reason',
      payload({ documentation: { can_record: true, unavailable_reason: 'APPOINTMENT_STATE' } }),
    ],
    [
      'no reason while unable to record',
      payload({ documentation: { can_record: false, unavailable_reason: null } }),
    ],
    [
      'an unknown reason',
      payload({ documentation: { can_record: false, unavailable_reason: 'ENCOUNTER' } }),
    ],
    ['a missing entries_truncated', { ...payload(), entries_truncated: undefined }],
    ['an Entry without content', payload({ entries: [entryRow({ clinical_content: '  ' })] })],
    ['an Entry without category', payload({ entries: [entryRow({ category: null })] })],
    ['an unknown category', payload({ entries: [entryRow({ category: 'SURGERY' })] })],
    ['a malformed recording time', payload({ entries: [entryRow({ recorded_at: 'yesterday' })] })],
    ['a missing may_edit', payload({ entries: [entryRow({ may_edit: undefined })] })],
    [
      'the retired may_amend only',
      payload({ entries: [entryRow({ may_edit: undefined, may_amend: true })] }),
    ],
    ['a missing version', payload({ entries: [entryRow({ version: undefined })] })],
    ['a version 0', payload({ entries: [entryRow({ version: 0 })] })],
    [
      'an edit time on an unedited Entry',
      payload({ entries: [entryRow({ edited_at: '2026-06-01T11:00:00Z' })] }),
    ],
    ['an edited Entry without edit time', payload({ entries: [editedRow({ edited_at: null })] })],
    ['a missing earlier version', payload({ entries: [editedRow({ previous_versions: [] })] })],
    [
      'earlier versions out of order',
      payload({
        entries: [editedRow({ version: 3, previous_versions: [versionRow(2), versionRow(1)] })],
      }),
    ],
    [
      'the current version among the earlier ones',
      payload({ entries: [editedRow({ previous_versions: [versionRow(1), versionRow(2)] })] }),
    ],
    [
      'an earlier version with an extra key',
      payload({
        entries: [editedRow({ previous_versions: [{ ...versionRow(1), author_user_id: ENTRY }] })],
      }),
    ],
    [
      'an earlier version without content',
      payload({
        entries: [editedRow({ previous_versions: [versionRow(1, { clinical_content: ' ' })] })],
      }),
    ],
    [
      'a truncated flag on a short history',
      payload({ entries: [editedRow({ previous_versions_truncated: true })] }),
    ],
    ['a duplicated Entry', payload({ entries: [entryRow(), entryRow()] })],
    [
      'a duplicated earlier correction',
      payload({ entries: [entryRow({ amendments: [amendmentRow(), amendmentRow()] })] }),
    ],
  ])('rejects %s', (_label, raw) => {
    expect(parseAppointmentClinicalRecord(raw)).toBeNull();
  });

  it('exposes all ten categories in the approved order', () => {
    expect(CLINICAL_RECORD_CATEGORIES).toEqual([
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
    ]);
  });
});

describe('viewAppointmentClinicalRecord', () => {
  it('reads by Clinic and Appointment only', async () => {
    rpc.mockResolvedValue({ data: payload(), error: null });
    await viewAppointmentClinicalRecord(CLINIC, APPOINTMENT);
    expect(rpc).toHaveBeenCalledWith('view_appointment_clinical_record', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
    });
  });

  it('maps DENIED and 42501 to denied, 28000 to authentication, anything else to failed', async () => {
    rpc.mockResolvedValueOnce({ data: { status: 'DENIED' }, error: null });
    expect(await viewAppointmentClinicalRecord(CLINIC, APPOINTMENT)).toEqual({ kind: 'denied' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    expect(await viewAppointmentClinicalRecord(CLINIC, APPOINTMENT)).toEqual({ kind: 'denied' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000' } });
    expect(await viewAppointmentClinicalRecord(CLINIC, APPOINTMENT)).toEqual({
      kind: 'authenticationRequired',
    });
    rpc.mockResolvedValueOnce({ data: { status: 'PERMITTED' }, error: null });
    expect(await viewAppointmentClinicalRecord(CLINIC, APPOINTMENT)).toEqual({ kind: 'failed' });
    rpc.mockRejectedValueOnce(new Error('offline'));
    expect(await viewAppointmentClinicalRecord(CLINIC, APPOINTMENT)).toEqual({ kind: 'failed' });
  });
});

describe('createAppointmentClinicalEntry', () => {
  const fields = {
    category: 'OTHER' as const,
    clinicalContent: 'Behaviour note',
    otherCategoryContext: 'Behaviour',
  };

  it('sends the key and the three fields — no clinical time — and nothing else', async () => {
    rpc.mockResolvedValue({ data: { outcome: 'CREATED', entry_id: ENTRY }, error: null });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'outcome',
      outcome: 'CREATED',
      entryId: ENTRY,
    });
    expect(rpc).toHaveBeenCalledWith('create_appointment_clinical_entry', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
      p_idempotency_key: KEY,
      p_category: 'OTHER',
      p_clinical_content: 'Behaviour note',
      p_other_category_context: 'Behaviour',
    });
  });

  it('accepts a replay as ALREADY_CREATED', async () => {
    rpc.mockResolvedValue({ data: { outcome: 'ALREADY_CREATED', entry_id: ENTRY }, error: null });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toMatchObject({
      outcome: 'ALREADY_CREATED',
    });
  });

  it.each([
    ['23505', 'KEY_CONFLICT'],
    ['23514', 'APPOINTMENT_STATE_INVALID'],
    ['23514', 'NO_VETERINARIAN_ASSIGNED'],
    ['23514', 'NOT_ASSIGNED_VETERINARIAN'],
    ['22023', 'CATEGORY_REQUIRED'],
    ['22023', 'CONTENT_REQUIRED'],
    ['22023', 'OTHER_CONTEXT_REQUIRED'],
  ])('maps %s %s to a rejection', async (code, hint) => {
    rpc.mockResolvedValue({ data: null, error: { code, hint } });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'rejected',
      reason: hint,
    });
  });

  it('maps the missing Entitlement apart from the uniform denial', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '42501', hint: 'CLINICAL_SERVICE_UNAVAILABLE' },
    });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'serviceUnavailable',
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', hint: null } });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'denied',
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000' } });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'authenticationRequired',
    });
  });

  it('a lost or unreadable answer is uncertain, never a failure to retry blindly', async () => {
    rpc.mockRejectedValueOnce(new Error('network'));
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'uncertain',
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: 'XX000', hint: 'SOMETHING_NEW' } });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'uncertain',
    });
    rpc.mockResolvedValueOnce({ data: { outcome: 'UPDATED', entry_id: ENTRY }, error: null });
    expect(await createAppointmentClinicalEntry(CLINIC, APPOINTMENT, KEY, fields)).toEqual({
      kind: 'uncertain',
    });
  });
});

describe('editAppointmentClinicalEntry', () => {
  const fields = {
    category: 'CLINICAL_NOTE' as const,
    clinicalContent: 'Only a nail trim was performed',
    otherCategoryContext: null,
  };
  const edit = () => editAppointmentClinicalEntry(CLINIC, APPOINTMENT, ENTRY, KEY, 1, fields);

  it('is keyed by Clinic, Appointment, Entry, the edit key and the opened version only; no reason', async () => {
    rpc.mockResolvedValue({ data: { outcome: 'EDITED', version: 2 }, error: null });
    expect(await edit()).toEqual({ kind: 'outcome', outcome: 'EDITED', version: 2 });
    expect(rpc).toHaveBeenCalledWith('edit_appointment_clinical_entry', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
      p_entry_id: ENTRY,
      p_idempotency_key: KEY,
      p_expected_version: 1,
      p_category: 'CLINICAL_NOTE',
      p_clinical_content: 'Only a nail trim was performed',
      p_other_category_context: null,
    });
  });

  it.each(['ALREADY_EDITED', 'UNCHANGED'])('accepts %s', async (outcome) => {
    rpc.mockResolvedValue({ data: { outcome, version: 2 }, error: null });
    expect(await edit()).toEqual({ kind: 'outcome', outcome, version: 2 });
  });

  it.each([
    ['P0001', 'STALE_VERSION'],
    ['23514', 'ENTRY_AUTHOR_REQUIRED'],
    ['23505', 'KEY_CONFLICT'],
    ['22023', 'INVALID_VERSION'],
    ['22023', 'CONTENT_REQUIRED'],
  ])('maps %s %s to a rejection', async (code, hint) => {
    rpc.mockResolvedValue({ data: null, error: { code, hint } });
    expect(await edit()).toEqual({ kind: 'rejected', reason: hint });
  });

  it('maps a lost permission to the uniform denial and a lost answer to uncertain', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', hint: null } });
    expect(await edit()).toEqual({ kind: 'denied' });
    rpc.mockRejectedValueOnce(new Error('network'));
    expect(await edit()).toEqual({ kind: 'uncertain' });
    rpc.mockResolvedValueOnce({ data: { outcome: 'EDITED', version: 0 }, error: null });
    expect(await edit()).toEqual({ kind: 'uncertain' });
    rpc.mockResolvedValueOnce({ data: { outcome: 'CREATED', entry_id: ENTRY }, error: null });
    expect(await edit()).toEqual({ kind: 'uncertain' });
  });
});

it('exposes none of the retired Encounter, Draft, Finalize or reason-and-addition operations', () => {
  const exported = Object.keys(clinicalRecordModule).join(' ');
  expect(exported).not.toMatch(/Encounter|Draft|finalize|conclude|start|Amendment/i);
});
