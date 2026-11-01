import {
  CLINIC_SCHEDULE_MALFORMED,
  getClinicAppointment,
  parseClinicAppointment,
  parseClinicAppointmentSchedule,
} from '@/data/clinic-appointment-schedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const APPOINTMENT_ID = '11111111-1111-4111-8111-111111111111';
const PET_ID = '22222222-2222-4222-8222-222222222222';
const USER_ID = '33333333-3333-4333-8333-333333333333';
const VCA_ID = '44444444-4444-4444-8444-444444444444';
const PROPOSAL_ID = '55555555-5555-4555-8555-555555555555';
const CLINIC_ID = '66666666-6666-4666-8666-666666666666';

/** One backend row, exactly as get_clinic_appointment_schedule returns it. */
function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: APPOINTMENT_ID,
    pet_id: PET_ID,
    pet_name: 'Luna',
    requesting_user_id: USER_ID,
    requester_display_name: 'María López',
    reason_for_visit: 'Vacunación',
    guardian_notes: null,
    lifecycle_state: 'REQUESTED',
    created_at: '2026-09-01T10:00:00+00:00',
    current_scheduled_start_at: '2035-02-06T17:00:00+00:00',
    current_scheduled_end_at: '2035-02-06T17:45:00+00:00',
    current_scheduling_timezone_name: 'Atlantic/Canary',
    current_schedule_revision_sequence: 2,
    current_veterinarian_clinic_assignment_id: null,
    pending_reschedule_proposal_id: null,
    pending_reschedule_proposal_state: null,
    pending_reschedule_proposing_context: null,
    pending_reschedule_proposed_start_at: null,
    pending_reschedule_proposed_end_at: null,
    pending_reschedule_proposed_timezone_name: null,
    pending_reschedule_reason: null,
    current_schedule_source_proposal_id: null,
    current_schedule_source_proposing_context: null,
    pending_reschedule_currently_feasible: null,
    cancellation_reason: null,
    has_clinical_record: false,
    ...overrides,
  };
}

const PENDING = {
  lifecycle_state: 'CONFIRMED',
  pending_reschedule_proposal_id: PROPOSAL_ID,
  pending_reschedule_proposal_state: 'PENDING',
  pending_reschedule_proposing_context: 'CLINIC',
  pending_reschedule_proposed_start_at: '2035-02-09T10:00:00+00:00',
  pending_reschedule_proposed_end_at: '2035-02-09T10:45:00+00:00',
  pending_reschedule_proposed_timezone_name: 'Atlantic/Canary',
  pending_reschedule_reason: 'Veterinario no disponible',
  pending_reschedule_currently_feasible: true,
};

describe('parseClinicAppointmentSchedule', () => {
  it('accepts an empty schedule', () => {
    expect(parseClinicAppointmentSchedule([])).toEqual([]);
  });

  it('maps a REQUESTED row to camelCase, including the current pet_name', () => {
    expect(parseClinicAppointmentSchedule([row()])).toEqual([
      {
        id: APPOINTMENT_ID,
        petId: PET_ID,
        petName: 'Luna',
        requestingUserId: USER_ID,
        requesterDisplayName: 'María López',
        reasonForVisit: 'Vacunación',
        guardianNotes: null,
        lifecycleState: 'REQUESTED',
        createdAt: '2026-09-01T10:00:00+00:00',
        currentScheduledStartAt: '2035-02-06T17:00:00+00:00',
        currentScheduledEndAt: '2035-02-06T17:45:00+00:00',
        currentSchedulingTimezoneName: 'Atlantic/Canary',
        currentScheduleRevisionSequence: 2,
        currentVeterinarianClinicAssignmentId: null,
        pendingReschedule: null,
        currentScheduleSource: null,
        cancellationReason: null,
        hasClinicalRecord: false,
      },
    ]);
  });

  it('maps a requester without a display name to null (SPEC-APT-012 BR-49)', () => {
    expect(
      parseClinicAppointmentSchedule([row({ requester_display_name: null })])?.[0]
        .requesterDisplayName,
    ).toBeNull();
  });

  it.each<[string, unknown]>([
    ['the column missing (a backend older than this app)', undefined],
    ['a blank name', '   '],
    ['an empty name', ''],
    ['a non-string', 42],
  ])('rejects the whole schedule for %s', (_label, value) => {
    expect(parseClinicAppointmentSchedule([row({ requester_display_name: value })])).toBeNull();
  });

  it('ignores an email the schedule must never carry', () => {
    const parsed = parseClinicAppointmentSchedule([
      row({ requester_email: 'maria@example.test' }),
    ])?.[0];
    expect(parsed).toBeDefined();
    expect(JSON.stringify(parsed)).not.toContain('maria@example.test');
  });

  it('keeps the recorded cancellation reason of a CANCELLED Appointment verbatim, multiline included', () => {
    const reason = 'El veterinario se puso enfermo.\nAvisamos por teléfono a las 9:30.';
    expect(
      parseClinicAppointmentSchedule([
        row({ lifecycle_state: 'CANCELLED', cancellation_reason: reason }),
      ])?.[0].cancellationReason,
    ).toBe(reason);
  });

  it('accepts a CANCELLED Appointment cancelled without a reason', () => {
    expect(
      parseClinicAppointmentSchedule([row({ lifecycle_state: 'CANCELLED' })])?.[0]
        .cancellationReason,
    ).toBeNull();
  });

  it.each<[string, Record<string, unknown>]>([
    ['the column missing', { cancellation_reason: undefined }],
    ['an empty reason', { lifecycle_state: 'CANCELLED', cancellation_reason: '' }],
    ['a blank reason', { lifecycle_state: 'CANCELLED', cancellation_reason: '  \n ' }],
    ['a non-string reason', { lifecycle_state: 'CANCELLED', cancellation_reason: 42 }],
    [
      'a reason on a COMPLETED Appointment',
      { lifecycle_state: 'COMPLETED', cancellation_reason: 'x' },
    ],
    [
      'a reason on a CONFIRMED Appointment',
      { lifecycle_state: 'CONFIRMED', cancellation_reason: 'x' },
    ],
  ])('rejects the whole read for %s', (_label, overrides) => {
    const malformed = row(overrides);
    if (overrides.cancellation_reason === undefined) delete malformed.cancellation_reason;
    expect(parseClinicAppointmentSchedule([malformed])).toBeNull();
  });

  it('maps has_clinical_record (SPEC-MED-010 BR-9) for CONFIRMED and COMPLETED rows', () => {
    const parsed = parseClinicAppointmentSchedule([
      row({ lifecycle_state: 'CONFIRMED', has_clinical_record: true }),
      row({
        id: '44444444-4444-4444-8444-444444444444',
        lifecycle_state: 'COMPLETED',
        has_clinical_record: true,
      }),
    ]);
    expect(parsed?.map((appointment) => appointment.hasClinicalRecord)).toEqual([true, true]);
  });

  it.each<[string, unknown]>([
    ['missing', undefined],
    ['null', null],
    ['a string', 'true'],
  ])('rejects the whole read when has_clinical_record is %s', (_label, value) => {
    const malformed = row({ has_clinical_record: value });
    if (value === undefined) delete malformed.has_clinical_record;
    expect(parseClinicAppointmentSchedule([malformed])).toBeNull();
  });

  it('accepts an EXPIRED Appointment as a known terminal state (SPEC-APT-015)', () => {
    const parsed = parseClinicAppointmentSchedule([row({ lifecycle_state: 'EXPIRED' })]);
    expect(parsed?.map((appointment) => appointment.lifecycleState)).toEqual(['EXPIRED']);
  });

  it('keeps each row’s own revision sequence alongside its own interval', () => {
    const second = '77777777-7777-4777-8777-777777777777';
    const parsed = parseClinicAppointmentSchedule([
      row({ current_schedule_revision_sequence: 1 }),
      row({
        id: second,
        current_scheduled_start_at: '2035-02-07T09:00:00+00:00',
        current_scheduled_end_at: '2035-02-07T09:30:00+00:00',
        current_schedule_revision_sequence: 4,
      }),
    ]);
    expect(
      parsed?.map((appointment) => [
        appointment.id,
        appointment.currentScheduledStartAt,
        appointment.currentScheduleRevisionSequence,
      ]),
    ).toEqual([
      [APPOINTMENT_ID, '2035-02-06T17:00:00+00:00', 1],
      [second, '2035-02-07T09:00:00+00:00', 4],
    ]);
  });

  it.each(['CONFIRMED', 'COMPLETED', 'CANCELLED', 'NO_SHOW'])('accepts %s', (state) => {
    expect(parseClinicAppointmentSchedule([row({ lifecycle_state: state })])?.[0]).toMatchObject({
      lifecycleState: state,
    });
  });

  it('keeps guardian notes when present', () => {
    expect(
      parseClinicAppointmentSchedule([row({ guardian_notes: 'Es tímida' })])?.[0].guardianNotes,
    ).toBe('Es tímida');
  });

  it('keeps multiline guardian notes verbatim', () => {
    const notes = 'Es tímida con desconocidos.\nPrefiere entrar en transportín.';
    expect(
      parseClinicAppointmentSchedule([row({ guardian_notes: notes })])?.[0].guardianNotes,
    ).toBe(notes);
  });

  it('accepts a nullable or present current Veterinarian Assignment id', () => {
    expect(
      parseClinicAppointmentSchedule([
        row({ lifecycle_state: 'CONFIRMED', current_veterinarian_clinic_assignment_id: VCA_ID }),
      ])?.[0].currentVeterinarianClinicAssignmentId,
    ).toBe(VCA_ID);
    expect(
      parseClinicAppointmentSchedule([row()])?.[0].currentVeterinarianClinicAssignmentId,
    ).toBeNull();
  });

  it('maps a coherent pending reschedule without replacing the scheduled interval', () => {
    const [appointment] = parseClinicAppointmentSchedule([row(PENDING)]) ?? [];
    expect(appointment.pendingReschedule).toEqual({
      kind: 'confirmedReschedule',
      proposalId: PROPOSAL_ID,
      proposingContext: 'CLINIC',
      proposedStartAt: '2035-02-09T10:00:00+00:00',
      proposedEndAt: '2035-02-09T10:45:00+00:00',
      proposedTimezoneName: 'Atlantic/Canary',
      reason: 'Veterinario no disponible',
      currentlyFeasible: true,
    });
    expect(appointment.currentScheduledStartAt).toBe('2035-02-06T17:00:00+00:00');
  });

  it('maps a Clinic alternative on a REQUESTED Appointment as requestedAlternativeTime, never as the current interval (SPEC-APT-012 BR-44)', () => {
    const [appointment] =
      parseClinicAppointmentSchedule([row({ ...PENDING, lifecycle_state: 'REQUESTED' })]) ?? [];
    expect(appointment.pendingReschedule).toEqual({
      kind: 'requestedAlternativeTime',
      proposalId: PROPOSAL_ID,
      proposingContext: 'CLINIC',
      proposedStartAt: '2035-02-09T10:00:00+00:00',
      proposedEndAt: '2035-02-09T10:45:00+00:00',
      proposedTimezoneName: 'Atlantic/Canary',
      reason: 'Veterinario no disponible',
      currentlyFeasible: true,
    });
    expect(appointment.lifecycleState).toBe('REQUESTED');
    expect(appointment.currentScheduledStartAt).toBe('2035-02-06T17:00:00+00:00');
    expect(appointment.currentScheduleRevisionSequence).toBe(2);
  });

  it('maps the provenance of an accepted Clinic alternative on a REQUESTED Appointment (SPEC-APT-012 BR-45)', () => {
    const [appointment] =
      parseClinicAppointmentSchedule([
        row({
          current_schedule_source_proposal_id: PROPOSAL_ID,
          current_schedule_source_proposing_context: 'CLINIC',
        }),
      ]) ?? [];
    expect(appointment.currentScheduleSource).toEqual({
      proposalId: PROPOSAL_ID,
      proposingContext: 'CLINIC',
    });
    expect(appointment.pendingReschedule).toBeNull();
  });

  it('maps the provenance of an accepted Guardian reschedule on a CONFIRMED Appointment', () => {
    const [appointment] =
      parseClinicAppointmentSchedule([
        row({
          lifecycle_state: 'CONFIRMED',
          current_schedule_source_proposal_id: PROPOSAL_ID,
          current_schedule_source_proposing_context: 'GUARDIAN',
        }),
      ]) ?? [];
    expect(appointment.currentScheduleSource).toEqual({
      proposalId: PROPOSAL_ID,
      proposingContext: 'GUARDIAN',
    });
  });

  it('keeps an infeasible proposal visible with currentlyFeasible false (SPEC-APT-012 BR-44)', () => {
    const [appointment] =
      parseClinicAppointmentSchedule([
        row({ ...PENDING, pending_reschedule_currently_feasible: false }),
      ]) ?? [];
    expect(appointment.pendingReschedule?.proposalId).toBe(PROPOSAL_ID);
    expect(appointment.pendingReschedule?.currentlyFeasible).toBe(false);
  });

  it('accepts a Guardian-originated pending reschedule without a reason', () => {
    expect(
      parseClinicAppointmentSchedule([
        row({
          ...PENDING,
          pending_reschedule_proposing_context: 'GUARDIAN',
          pending_reschedule_reason: null,
        }),
      ])?.[0].pendingReschedule?.reason,
    ).toBeNull();
  });

  it('preserves backend order', () => {
    const second = '77777777-7777-4777-8777-777777777777';
    expect(
      parseClinicAppointmentSchedule([row(), row({ id: second })])?.map(
        (appointment) => appointment.id,
      ),
    ).toEqual([APPOINTMENT_ID, second]);
  });

  describe('rejects the whole schedule', () => {
    it.each<[string, unknown]>([
      ['a non-array payload', { rows: [] }],
      ['null', null],
      ['a non-object row', ['x']],
      ['an unknown lifecycle state', [row({ lifecycle_state: 'BOOKED' })]],
      ['a lowercase lifecycle state', [row({ lifecycle_state: 'requested' })]],
      ['an empty Pet name', [row({ pet_name: '' })]],
      ['a blank Pet name', [row({ pet_name: '   ' })]],
      ['a missing Pet name', [row({ pet_name: null })]],
      ['a non-string Pet name', [row({ pet_name: 7 })]],
      ['a malformed Appointment id', [row({ id: 'not-a-uuid' })]],
      ['a malformed Pet id', [row({ pet_id: '' })]],
      [
        'a malformed Veterinarian Assignment id',
        [row({ current_veterinarian_clinic_assignment_id: 'x' })],
      ],
      ['an empty reason for visit', [row({ reason_for_visit: '' })]],
      ['an empty guardian note', [row({ guardian_notes: '' })]],
      ['a malformed created_at', [row({ created_at: 'yesterday' })]],
      ['a missing scheduled start', [row({ current_scheduled_start_at: null })]],
      ['a malformed scheduled start', [row({ current_scheduled_start_at: '2035-02-06' })]],
      ['an impossible scheduled end', [row({ current_scheduled_end_at: '2035-02-30T25:00:00Z' })]],
      ['an end before the start', [row({ current_scheduled_end_at: '2035-02-06T16:00:00+00:00' })]],
      [
        'an end equal to the start',
        [row({ current_scheduled_end_at: '2035-02-06T17:00:00+00:00' })],
      ],
      ['a missing timezone', [row({ current_scheduling_timezone_name: null })]],
      ['an unknown timezone', [row({ current_scheduling_timezone_name: 'Mars/Olympus' })]],
      [
        'a missing revision sequence',
        [
          Object.fromEntries(
            Object.entries(row()).filter(([key]) => key !== 'current_schedule_revision_sequence'),
          ),
        ],
      ],
      ['a null revision sequence', [row({ current_schedule_revision_sequence: null })]],
      ['a zero revision sequence', [row({ current_schedule_revision_sequence: 0 })]],
      ['a negative revision sequence', [row({ current_schedule_revision_sequence: -1 })]],
      ['a fractional revision sequence', [row({ current_schedule_revision_sequence: 1.5 })]],
      ['a string revision sequence', [row({ current_schedule_revision_sequence: '2' })]],
      ['a NaN revision sequence', [row({ current_schedule_revision_sequence: Number.NaN })]],
      ['a duplicated Appointment', [row(), row()]],
    ])('for %s', (_label, payload) => {
      expect(parseClinicAppointmentSchedule(payload)).toBeNull();
    });

    it.each<[string, Record<string, unknown>]>([
      ['a partial pending proposal', { ...PENDING, pending_reschedule_proposed_end_at: null }],
      [
        'a pending proposal on a CANCELLED Appointment',
        { ...PENDING, lifecycle_state: 'CANCELLED' },
      ],
      [
        'a Guardian proposal on a REQUESTED Appointment',
        {
          ...PENDING,
          lifecycle_state: 'REQUESTED',
          pending_reschedule_proposing_context: 'GUARDIAN',
          pending_reschedule_reason: null,
        },
      ],
      [
        'a Clinic alternative without a reason',
        { ...PENDING, lifecycle_state: 'REQUESTED', pending_reschedule_reason: null },
      ],
      ['a partial schedule provenance', { current_schedule_source_proposal_id: PROPOSAL_ID }],
      [
        'a schedule provenance without its proposal id',
        { current_schedule_source_proposing_context: 'CLINIC' },
      ],
      [
        'a malformed schedule provenance id',
        {
          current_schedule_source_proposal_id: 'p-1',
          current_schedule_source_proposing_context: 'CLINIC',
        },
      ],
      [
        'an unknown schedule provenance context',
        {
          current_schedule_source_proposal_id: PROPOSAL_ID,
          current_schedule_source_proposing_context: 'SYSTEM',
        },
      ],
      [
        'a REQUESTED interval sourced by a Guardian proposal',
        {
          current_schedule_source_proposal_id: PROPOSAL_ID,
          current_schedule_source_proposing_context: 'GUARDIAN',
        },
      ],
      [
        'a backend without the provenance columns',
        {
          current_schedule_source_proposal_id: undefined,
          current_schedule_source_proposing_context: undefined,
        },
      ],
      [
        'a non-PENDING proposal state',
        { ...PENDING, pending_reschedule_proposal_state: 'ACCEPTED' },
      ],
      ['an unknown proposing context', { ...PENDING, pending_reschedule_proposing_context: 'VET' }],
      ['a Clinic proposal without a reason', { ...PENDING, pending_reschedule_reason: null }],
      ['a malformed proposal id', { ...PENDING, pending_reschedule_proposal_id: 'p-1' }],
      [
        'a malformed proposed interval',
        { ...PENDING, pending_reschedule_proposed_start_at: 'soon' },
      ],
      ['a reason without a proposal', { pending_reschedule_reason: 'stray' }],
      [
        'a proposal without its feasibility',
        { ...PENDING, pending_reschedule_currently_feasible: null },
      ],
      ['a non-boolean feasibility', { ...PENDING, pending_reschedule_currently_feasible: 'true' }],
      ['a feasibility without a proposal', { pending_reschedule_currently_feasible: false }],
      [
        'a backend without the feasibility column',
        { ...PENDING, pending_reschedule_currently_feasible: undefined },
      ],
      [
        'the Guardian acceptability column instead of feasibility',
        {
          ...PENDING,
          pending_reschedule_currently_feasible: undefined,
          pending_reschedule_currently_acceptable: true,
        },
      ],
    ])('for %s', (_label, overrides) => {
      expect(parseClinicAppointmentSchedule([row(overrides)])).toBeNull();
    });
  });
});

describe('parseClinicAppointment (SPEC-APT-012 BR-51/BR-52)', () => {
  it.each([
    ['REQUESTED', row()],
    ['CONFIRMED with a pending Clinic proposal', row(PENDING)],
    [
      'CONFIRMED after an accepted reschedule (revision 4)',
      row({
        lifecycle_state: 'CONFIRMED',
        current_schedule_revision_sequence: 4,
        current_schedule_source_proposal_id: PROPOSAL_ID,
        current_schedule_source_proposing_context: 'GUARDIAN',
      }),
    ],
    [
      'COMPLETED with clinical records',
      row({ lifecycle_state: 'COMPLETED', has_clinical_record: true }),
    ],
    [
      'CANCELLED with its reason',
      row({ lifecycle_state: 'CANCELLED', cancellation_reason: 'Cerrado' }),
    ],
    ['NO_SHOW', row({ lifecycle_state: 'NO_SHOW' })],
    [
      'EXPIRED, years old',
      row({
        lifecycle_state: 'EXPIRED',
        current_scheduled_start_at: '2019-03-01T09:00:00+00:00',
        current_scheduled_end_at: '2019-03-01T09:30:00+00:00',
      }),
    ],
  ])('reads %s exactly as the schedule parser reads that row', (_label, raw) => {
    expect(parseClinicAppointment([raw], APPOINTMENT_ID)).toEqual(
      parseClinicAppointmentSchedule([raw])?.[0],
    );
    expect(parseClinicAppointment([raw], APPOINTMENT_ID)).not.toBeNull();
  });

  it('matches the asked-for id case-insensitively', () => {
    expect(parseClinicAppointment([row()], APPOINTMENT_ID.toUpperCase())?.id).toBe(APPOINTMENT_ID);
  });

  it.each([
    ['no row', []],
    ['two rows', [row(), row({ id: VCA_ID })]],
    ['another Appointment', [row({ id: VCA_ID })]],
    ['a malformed row', [row({ requester_display_name: '   ' })]],
    ['a single object instead of rows', row()],
    ['null', null],
  ])('rejects %s', (_label, raw) => {
    expect(parseClinicAppointment(raw, APPOINTMENT_ID)).toBeNull();
  });
});

describe('getClinicAppointment', () => {
  const rpc = supabase.rpc as jest.Mock;

  afterEach(() => rpc.mockReset());

  it('reads only the asked-for Appointment through get_clinic_appointment', async () => {
    rpc.mockResolvedValue({ data: [row(PENDING)], error: null });

    const result = await getClinicAppointment(CLINIC_ID, APPOINTMENT_ID);

    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('get_clinic_appointment', {
      p_clinic_id: CLINIC_ID,
      p_appointment_id: APPOINTMENT_ID,
    });
    expect(result).toEqual({
      data: parseClinicAppointmentSchedule([row(PENDING)])?.[0],
      error: null,
    });
    // The single read carries no requester email (SPEC-APT-012 BR-50).
    expect(Object.keys(result.data ?? {}).some((key) => /email/i.test(key))).toBe(false);
  });

  it('turns the uniform 42501 (unknown, foreign, or denied) into an unavailable Appointment', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '42501', message: 'Clinic Appointment unavailable' },
    });
    expect(await getClinicAppointment(CLINIC_ID, APPOINTMENT_ID)).toEqual({
      data: null,
      error: null,
    });
  });

  it('normalizes SQLSTATE 28000 to the shared auth-required error', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });
    expect(await getClinicAppointment(CLINIC_ID, APPOINTMENT_ID)).toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
  });

  it.each([
    ['an empty result', []],
    ['another Appointment', [row({ id: VCA_ID })]],
    ['a malformed row', [row({ pet_name: '' })]],
    ['two rows', [row(), row()]],
  ])('reports %s as CLINIC_SCHEDULE_MALFORMED', async (_label, data) => {
    rpc.mockResolvedValue({ data, error: null });
    expect(await getClinicAppointment(CLINIC_ID, APPOINTMENT_ID)).toEqual({
      data: null,
      error: CLINIC_SCHEDULE_MALFORMED,
    });
  });

  it('settles a network rejection and other failures into errors instead of throwing', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));
    expect(await getClinicAppointment(CLINIC_ID, APPOINTMENT_ID)).toEqual({
      data: null,
      error: 'Network request failed',
    });
    rpc.mockResolvedValue({ data: null, error: { code: '57014', message: 'canceling statement' } });
    expect(await getClinicAppointment(CLINIC_ID, APPOINTMENT_ID)).toEqual({
      data: null,
      error: 'canceling statement',
    });
  });
});
