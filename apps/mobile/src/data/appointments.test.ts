import {
  acceptRequestedAlternativeTime,
  acceptRescheduleProposal,
  cancelAppointment,
  fromAppointmentScheduleHistoryRow,
  fromAppointmentVeterinarianAssignmentHistoryRow,
  fromPetAppointmentRow,
  fromRequestableCandidateRow,
  getAppointmentSchedulingHistory,
  getAppointmentVeterinarianAssignmentHistory,
  getPetAppointments,
  getRequestableAppointmentStartTimes,
  PET_APPOINTMENTS_MALFORMED,
  RESCHEDULE_ACCEPTANCE_INVALID_REQUEST,
  RESCHEDULE_ACCEPTANCE_MALFORMED,
  requestAppointment,
  rescheduleRequestedAppointment,
  withdrawAppointmentMedicalAccess,
  type AppointmentScheduleHistoryRow,
  type AppointmentVeterinarianAssignmentHistoryRow,
  type PetAppointmentRow,
  type RequestableCandidateRow,
} from '@/data/appointments';

// Same isolation rationale as data/pets.test.ts: importing this module pulls
// in lib/supabase.ts, which throws under Jest without EXPO_PUBLIC_SUPABASE_*
// env vars. Mocking it also captures the last rpc(...) call so parameter
// mapping can be asserted without any real Supabase contact.
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...args: unknown[]) => mockRpc(...args) },
}));

beforeEach(() => {
  mockRpc.mockReset();
});

describe('fromPetAppointmentRow', () => {
  const baseRow: PetAppointmentRow = {
    id: 'apt-1',
    clinic_id: 'clinic-1',
    requesting_user_id: 'user-1',
    reason_for_visit: 'Limping since yesterday',
    guardian_notes: null,
    lifecycle_state: 'REQUESTED',
    created_at: '2026-01-01T00:00:00Z',
    current_scheduled_start_at: '2026-02-01T10:00:00Z',
    current_scheduled_end_at: '2026-02-01T10:30:00Z',
    current_scheduling_timezone_name: 'Europe/Madrid',
    current_veterinarian_clinic_assignment_id: null,
    pending_reschedule_proposal_id: null,
    pending_reschedule_proposal_state: null,
    pending_reschedule_proposing_context: null,
    pending_reschedule_proposed_start_at: null,
    pending_reschedule_proposed_end_at: null,
    pending_reschedule_proposed_timezone_name: null,
    pending_reschedule_reason: null,
    cancellation_reason: null,
    current_schedule_source_proposal_id: null,
    current_schedule_source_proposing_context: null,
    pending_reschedule_currently_acceptable: null,
    medical_access_state: 'ACTIVE',
  };

  it('maps a row with no pending reschedule to a null pendingReschedule', () => {
    expect(fromPetAppointmentRow(baseRow)).toEqual({
      id: 'apt-1',
      clinicId: 'clinic-1',
      requestingUserId: 'user-1',
      reasonForVisit: 'Limping since yesterday',
      guardianNotes: null,
      lifecycleState: 'REQUESTED',
      createdAt: '2026-01-01T00:00:00Z',
      currentScheduledStartAt: '2026-02-01T10:00:00Z',
      currentScheduledEndAt: '2026-02-01T10:30:00Z',
      currentSchedulingTimezoneName: 'Europe/Madrid',
      currentVeterinarianClinicAssignmentId: null,
      pendingReschedule: null,
      cancellationReason: null,
      currentScheduleSource: null,
      medicalAccessState: 'ACTIVE',
    });
  });

  it('maps the provenance of an accepted Clinic alternative (SPEC-APT-011 BR-33)', () => {
    expect(
      fromPetAppointmentRow({
        ...baseRow,
        current_schedule_source_proposal_id: '33333333-3333-4333-8333-333333333333',
        current_schedule_source_proposing_context: 'CLINIC',
      }).currentScheduleSource,
    ).toEqual({ proposalId: '33333333-3333-4333-8333-333333333333', proposingContext: 'CLINIC' });
  });

  it.each<[string, string]>([
    ['a Clinic cancellation reason', 'Veterinarian unavailable that day'],
    ['a Guardian cancellation reason', 'We moved house'],
  ])('maps %s without touching the reason for visit', (_label, reason) => {
    const mapped = fromPetAppointmentRow({
      ...baseRow,
      lifecycle_state: 'CANCELLED',
      cancellation_reason: reason,
    });

    expect(mapped.cancellationReason).toBe(reason);
    expect(mapped.reasonForVisit).toBe('Limping since yesterday');
  });

  it('maps a fully-populated pending reschedule proposal on a CONFIRMED Appointment', () => {
    const row: PetAppointmentRow = {
      ...baseRow,
      lifecycle_state: 'CONFIRMED',
      pending_reschedule_proposal_id: '33333333-3333-4333-8333-333333333333',
      pending_reschedule_proposal_state: 'PENDING',
      pending_reschedule_proposing_context: 'CLINIC',
      pending_reschedule_proposed_start_at: '2026-02-02T09:00:00Z',
      pending_reschedule_proposed_end_at: '2026-02-02T09:30:00Z',
      pending_reschedule_proposed_timezone_name: 'Europe/Madrid',
      pending_reschedule_reason: 'Vet unavailable',
      pending_reschedule_currently_acceptable: false,
    };

    expect(fromPetAppointmentRow(row).pendingReschedule).toEqual({
      kind: 'confirmedReschedule',
      proposalId: '33333333-3333-4333-8333-333333333333',
      proposingContext: 'CLINIC',
      proposedStartAt: '2026-02-02T09:00:00Z',
      proposedEndAt: '2026-02-02T09:30:00Z',
      proposedTimezoneName: 'Europe/Madrid',
      reason: 'Vet unavailable',
      currentlyAcceptable: false,
    });
  });
});

describe('fromAppointmentScheduleHistoryRow', () => {
  it('maps a revision row to the camelCase shape', () => {
    const row: AppointmentScheduleHistoryRow = {
      revision_sequence: 1,
      revision_context: 'REQUESTED',
      scheduled_start_at: '2026-02-01T10:00:00Z',
      scheduled_end_at: '2026-02-01T10:30:00Z',
      establishment_timezone_name: 'Europe/Madrid',
      established_by_user_id: 'user-1',
      established_at: '2026-01-01T00:00:00Z',
      is_accepted_reschedule: false,
      reschedule_proposing_context: null,
      reschedule_proposed_by_user_id: null,
      reschedule_reason: null,
      reschedule_proposed_at: null,
      reschedule_accepting_context: null,
      reschedule_accepted_by_user_id: null,
      reschedule_accepted_at: null,
    };

    expect(fromAppointmentScheduleHistoryRow(row)).toEqual({
      revisionSequence: 1,
      revisionContext: 'REQUESTED',
      scheduledStartAt: '2026-02-01T10:00:00Z',
      scheduledEndAt: '2026-02-01T10:30:00Z',
      establishmentTimezoneName: 'Europe/Madrid',
      establishedByUserId: 'user-1',
      establishedAt: '2026-01-01T00:00:00Z',
      isAcceptedReschedule: false,
      rescheduleProposingContext: null,
      rescheduleProposedByUserId: null,
      rescheduleReason: null,
      rescheduleProposedAt: null,
      rescheduleAcceptingContext: null,
      rescheduleAcceptedByUserId: null,
      rescheduleAcceptedAt: null,
    });
  });
});

describe('fromAppointmentVeterinarianAssignmentHistoryRow', () => {
  it('maps a current (open-ended) assignment row', () => {
    const row: AppointmentVeterinarianAssignmentHistoryRow = {
      appointment_veterinarian_assignment_id: 'assignment-1',
      veterinarian_professional_profile_id: 'vet-1',
      effective_start: '2026-01-05T00:00:00Z',
      effective_end: null,
      assigned_by_user_id: 'user-2',
    };

    expect(fromAppointmentVeterinarianAssignmentHistoryRow(row)).toEqual({
      appointmentVeterinarianAssignmentId: 'assignment-1',
      veterinarianProfessionalProfileId: 'vet-1',
      effectiveStart: '2026-01-05T00:00:00Z',
      effectiveEnd: null,
      assignedByUserId: 'user-2',
    });
  });
});

describe('getPetAppointments', () => {
  it('calls get_pet_appointments with the exact Pet id parameter', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    await getPetAppointments('pet-1');

    expect(mockRpc).toHaveBeenCalledWith('get_pet_appointments', { p_pet_id: 'pet-1' });
  });

  it('settles into the error shape on a backend error, never throwing', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Current Guardianship of the Pet is required' },
    });

    const result = await getPetAppointments('pet-1');

    expect(result).toEqual({ data: null, error: 'Current Guardianship of the Pet is required' });
  });

  it('settles into the error shape when the underlying network call rejects', async () => {
    mockRpc.mockRejectedValue(new Error('Network request failed'));

    const result = await getPetAppointments('pet-1');

    expect(result).toEqual({ data: null, error: 'Network request failed' });
  });

  const lifecycleRow = (lifecycle_state: unknown) => ({
    id: 'apt-1',
    clinic_id: 'clinic-1',
    requesting_user_id: 'user-1',
    reason_for_visit: 'Vacunación',
    guardian_notes: null,
    lifecycle_state,
    created_at: '2026-01-01T00:00:00Z',
    current_scheduled_start_at: '2026-02-01T10:00:00Z',
    current_scheduled_end_at: '2026-02-01T10:30:00Z',
    current_scheduling_timezone_name: 'Europe/Madrid',
    current_veterinarian_clinic_assignment_id: null,
    pending_reschedule_proposal_id: null,
    pending_reschedule_proposal_state: null,
    pending_reschedule_proposing_context: null,
    pending_reschedule_proposed_start_at: null,
    pending_reschedule_proposed_end_at: null,
    pending_reschedule_proposed_timezone_name: null,
    pending_reschedule_reason: null,
    cancellation_reason: null as unknown,
    current_schedule_source_proposal_id: null,
    current_schedule_source_proposing_context: null,
    pending_reschedule_currently_acceptable: null,
    medical_access_state: 'ACTIVE',
  });

  it('accepts an EXPIRED Appointment alongside the other states (SPEC-APT-015)', async () => {
    mockRpc.mockResolvedValue({
      data: [lifecycleRow('REQUESTED'), { ...lifecycleRow('EXPIRED'), id: 'apt-2' }],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.error).toBeNull();
    expect(result.data?.map((appointment) => appointment.lifecycleState)).toEqual([
      'REQUESTED',
      'EXPIRED',
    ]);
  });

  it.each<[string, unknown]>([
    ['an unknown lifecycle state', 'ARCHIVED'],
    ['a lowercase lifecycle state', 'expired'],
    ['a missing lifecycle state', undefined],
  ])('rejects the whole payload for %s instead of passing it to the UI', async (_l, state) => {
    mockRpc.mockResolvedValue({
      data: [lifecycleRow('CONFIRMED'), { ...lifecycleRow(state), id: 'apt-2' }],
      error: null,
    });

    await expect(getPetAppointments('pet-1')).resolves.toEqual({
      data: null,
      error: PET_APPOINTMENTS_MALFORMED,
    });
  });

  it('accepts CANCELLED rows with and without a cancellation reason, and null elsewhere', async () => {
    mockRpc.mockResolvedValue({
      data: [
        { ...lifecycleRow('CANCELLED'), cancellation_reason: 'Clinic closed that day' },
        { ...lifecycleRow('CANCELLED'), id: 'apt-2' },
        ...(['REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'] as const).map(
          (state, index) => ({ ...lifecycleRow(state), id: `apt-${index + 3}` }),
        ),
      ],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.error).toBeNull();
    expect(result.data?.map((appointment) => appointment.cancellationReason)).toEqual([
      'Clinic closed that day',
      null,
      null,
      null,
      null,
      null,
      null,
    ]);
    expect(result.data?.[0].reasonForVisit).toBe('Vacunación');
  });

  it.each<[string, Record<string, unknown>]>([
    ['a non-string reason', { lifecycle_state: 'CANCELLED', cancellation_reason: 42 }],
    ['an empty reason', { lifecycle_state: 'CANCELLED', cancellation_reason: '' }],
    ['a blank reason', { lifecycle_state: 'CANCELLED', cancellation_reason: '  ' }],
    ['a missing reason column', { lifecycle_state: 'CANCELLED', cancellation_reason: undefined }],
    [
      'a reason on a non-CANCELLED Appointment',
      { lifecycle_state: 'CONFIRMED', cancellation_reason: 'Clinic closed' },
    ],
  ])('rejects the whole payload for %s', async (_label, change) => {
    mockRpc.mockResolvedValue({
      data: [lifecycleRow('REQUESTED'), { ...lifecycleRow('CANCELLED'), id: 'apt-2', ...change }],
      error: null,
    });

    await expect(getPetAppointments('pet-1')).resolves.toEqual({
      data: null,
      error: PET_APPOINTMENTS_MALFORMED,
    });
  });

  it('rejects a non-array payload', async () => {
    mockRpc.mockResolvedValue({ data: { rows: [] }, error: null });

    await expect(getPetAppointments('pet-1')).resolves.toEqual({
      data: null,
      error: PET_APPOINTMENTS_MALFORMED,
    });
  });

  it('maps every medical-access state in any lifecycle (SPEC-APT-011 BR-35)', async () => {
    mockRpc.mockResolvedValue({
      data: [
        { ...lifecycleRow('COMPLETED'), medical_access_state: 'ACTIVE' },
        { ...lifecycleRow('CONFIRMED'), id: 'apt-2', medical_access_state: 'REVOKED' },
        { ...lifecycleRow('CANCELLED'), id: 'apt-3', medical_access_state: 'INACTIVE' },
      ],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.error).toBeNull();
    expect(result.data?.map((appointment) => appointment.medicalAccessState)).toEqual([
      'ACTIVE',
      'REVOKED',
      'INACTIVE',
    ]);
  });

  it.each<[string, unknown]>([
    ['an unknown medical-access state', 'ENDED'],
    ['a lowercase medical-access state', 'active'],
    ['a boolean instead of a state', true],
    ['a backend without the medical-access column', undefined],
  ])('rejects the whole payload for %s', async (_label, state) => {
    mockRpc.mockResolvedValue({
      data: [
        lifecycleRow('CONFIRMED'),
        { ...lifecycleRow('CONFIRMED'), id: 'apt-2', medical_access_state: state },
      ],
      error: null,
    });

    await expect(getPetAppointments('pet-1')).resolves.toEqual({
      data: null,
      error: PET_APPOINTMENTS_MALFORMED,
    });
  });
});

describe('withdrawAppointmentMedicalAccess (SPEC-ACC-002 BR-56–BR-59)', () => {
  const APPOINTMENT_ID = '44444444-4444-4444-8444-444444444444';

  it('sends only the Appointment id to the Appointment-keyed operation', async () => {
    mockRpc.mockResolvedValue({ data: { outcome: 'REVOKED' }, error: null });

    await expect(withdrawAppointmentMedicalAccess(APPOINTMENT_ID)).resolves.toEqual({
      kind: 'withdrawn',
    });
    expect(mockRpc).toHaveBeenCalledWith('revoke_my_appointment_care_authorization', {
      p_appointment_id: APPOINTMENT_ID,
    });
  });

  it('treats an exact retry or an already ended access as a calm reconciled outcome', async () => {
    mockRpc.mockResolvedValue({ data: { outcome: 'ALREADY_INACTIVE' }, error: null });

    await expect(withdrawAppointmentMedicalAccess(APPOINTMENT_ID)).resolves.toEqual({
      kind: 'alreadyInactive',
    });
  });

  it.each<[string, { code: string; message: string }, string]>([
    [
      'the uniform denial',
      { code: '42501', message: 'Appointment medical access unavailable' },
      'unavailable',
    ],
    [
      'a lost session',
      { code: '28000', message: 'Authentication is required' },
      'authenticationRequired',
    ],
    ['any other error', { code: '22023', message: 'An Appointment is required' }, 'failed'],
  ])('maps %s without exposing backend text', async (_label, error, kind) => {
    mockRpc.mockResolvedValue({ data: null, error });

    await expect(withdrawAppointmentMedicalAccess(APPOINTMENT_ID)).resolves.toEqual({ kind });
  });

  it.each<[string, unknown]>([
    ['an unknown outcome', { outcome: 'DELETED' }],
    [
      'an outcome with an identifier',
      { outcome: 'REVOKED', care_authorization_id: APPOINTMENT_ID },
    ],
    ['no payload', null],
  ])('treats %s as a failure', async (_label, data) => {
    mockRpc.mockResolvedValue({ data, error: null });

    await expect(withdrawAppointmentMedicalAccess(APPOINTMENT_ID)).resolves.toEqual({
      kind: 'failed',
    });
  });

  it('settles a network rejection into a failure', async () => {
    mockRpc.mockRejectedValue(new Error('Network request failed'));

    await expect(withdrawAppointmentMedicalAccess(APPOINTMENT_ID)).resolves.toEqual({
      kind: 'failed',
    });
  });

  it('never calls the backend with something that is not an Appointment id', async () => {
    await expect(withdrawAppointmentMedicalAccess('not-a-uuid')).resolves.toEqual({
      kind: 'unavailable',
    });
    expect(mockRpc).not.toHaveBeenCalled();
  });
});

describe('fromRequestableCandidateRow', () => {
  it('maps a candidate row to the camelCase shape', () => {
    const row: RequestableCandidateRow = {
      candidate_local_date: '2026-02-01',
      candidate_local_time: '10:00:00',
      utc_offset_seconds: 3600,
    };

    expect(fromRequestableCandidateRow(row)).toEqual({
      localDate: '2026-02-01',
      localTime: '10:00:00',
      utcOffsetSeconds: 3600,
    });
  });
});

describe('getRequestableAppointmentStartTimes', () => {
  it('calls get_requestable_appointment_start_times with the exact parameter names', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    await getRequestableAppointmentStartTimes('clinic-1', '2026-02-01', '2026-02-01');

    expect(mockRpc).toHaveBeenCalledWith('get_requestable_appointment_start_times', {
      p_clinic_id: 'clinic-1',
      p_start_date: '2026-02-01',
      p_end_date: '2026-02-01',
    });
  });

  it('returns the same bare empty result whatever the hidden reason (SPEC-APT-014 BR-5)', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const result = await getRequestableAppointmentStartTimes(
      'clinic-1',
      '2026-02-01',
      '2026-02-07',
    );
    // Nothing distinguishes missing Entitlement from no availability: no
    // reason, status, or commercial member exists on the result.
    expect(result).toStrictEqual({ data: [], error: null });
  });

  it('returns an empty, non-error result when the Clinic currently has no requestable candidates', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    const result = await getRequestableAppointmentStartTimes(
      'clinic-1',
      '2026-02-01',
      '2026-02-01',
    );

    expect(result).toEqual({ data: [], error: null });
  });

  it('maps every returned candidate row', async () => {
    mockRpc.mockResolvedValue({
      data: [
        {
          candidate_local_date: '2026-02-01',
          candidate_local_time: '09:00:00',
          utc_offset_seconds: 3600,
        },
        {
          candidate_local_date: '2026-02-01',
          candidate_local_time: '09:30:00',
          utc_offset_seconds: 3600,
        },
      ],
      error: null,
    });

    const result = await getRequestableAppointmentStartTimes(
      'clinic-1',
      '2026-02-01',
      '2026-02-01',
    );

    expect(result).toEqual({
      data: [
        { localDate: '2026-02-01', localTime: '09:00:00', utcOffsetSeconds: 3600 },
        { localDate: '2026-02-01', localTime: '09:30:00', utcOffsetSeconds: 3600 },
      ],
      error: null,
    });
  });

  it('settles into the error shape on a backend error, never throwing', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Requested range must not span more than 60 days' },
    });

    const result = await getRequestableAppointmentStartTimes(
      'clinic-1',
      '2026-02-01',
      '2026-05-01',
    );

    expect(result).toEqual({
      data: null,
      error: 'Requested range must not span more than 60 days',
    });
  });

  it('settles into the error shape when the underlying network call rejects', async () => {
    mockRpc.mockRejectedValue(new Error('Network request failed'));

    const result = await getRequestableAppointmentStartTimes(
      'clinic-1',
      '2026-02-01',
      '2026-02-01',
    );

    expect(result).toEqual({ data: null, error: 'Network request failed' });
  });

  it('is called exactly once for a whole bounded range, never once per date in that range', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    // The 30-Clinic-local-day range the Request/Reschedule screens now query
    // (requestableDateRange) in a single call, rather than the old
    // one-call-per-selected-date pattern.
    await getRequestableAppointmentStartTimes('clinic-1', '2026-02-01', '2026-03-02');

    expect(mockRpc).toHaveBeenCalledTimes(1);
    expect(mockRpc).toHaveBeenCalledWith('get_requestable_appointment_start_times', {
      p_clinic_id: 'clinic-1',
      p_start_date: '2026-02-01',
      p_end_date: '2026-03-02',
    });
  });
});

describe('requestAppointment', () => {
  it('maps every field to the exact request_appointment RPC parameter names', async () => {
    mockRpc.mockResolvedValue({ data: 'apt-new', error: null });

    const result = await requestAppointment({
      petId: 'pet-1',
      clinicId: 'clinic-1',
      candidate: {
        localDate: '2026-02-01',
        localTime: '10:00:00',
        utcOffsetSeconds: 3600,
      },
      reasonForVisit: 'Limping since yesterday',
      guardianNotes: 'Prefers morning slots',
    });

    expect(mockRpc).toHaveBeenCalledWith('request_appointment', {
      p_pet_id: 'pet-1',
      p_clinic_id: 'clinic-1',
      p_start_local_date: '2026-02-01',
      p_start_local_time: '10:00:00',
      p_start_utc_offset_seconds: 3600,
      p_reason_for_visit: 'Limping since yesterday',
      p_guardian_notes: 'Prefers morning slots',
    });
    expect(result).toEqual({ data: { appointmentId: 'apt-new' }, error: null });
  });

  it('never sends a Guardian-supplied end date/time/offset', async () => {
    mockRpc.mockResolvedValue({ data: 'apt-new', error: null });

    await requestAppointment({
      petId: 'pet-1',
      clinicId: 'clinic-1',
      candidate: { localDate: '2026-02-01', localTime: '10:00:00', utcOffsetSeconds: 3600 },
      reasonForVisit: 'Limping since yesterday',
      guardianNotes: null,
    });

    const [, params] = mockRpc.mock.calls[0] as [string, Record<string, unknown>];
    expect(Object.keys(params).sort()).toEqual(
      [
        'p_pet_id',
        'p_clinic_id',
        'p_start_local_date',
        'p_start_local_time',
        'p_start_utc_offset_seconds',
        'p_reason_for_visit',
        'p_guardian_notes',
      ].sort(),
    );
  });

  it('passes null guardian notes through unchanged, never coercing to an empty string', async () => {
    mockRpc.mockResolvedValue({ data: 'apt-new', error: null });

    await requestAppointment({
      petId: 'pet-1',
      clinicId: 'clinic-1',
      candidate: { localDate: '2026-02-01', localTime: '10:00:00', utcOffsetSeconds: 3600 },
      reasonForVisit: 'Limping since yesterday',
      guardianNotes: null,
    });

    expect(mockRpc).toHaveBeenCalledWith(
      'request_appointment',
      expect.objectContaining({ p_guardian_notes: null }),
    );
  });

  it('settles into the error shape when no standard duration is configured', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Clinic has no currently configured standard Appointment duration' },
    });

    const result = await requestAppointment({
      petId: 'pet-1',
      clinicId: 'clinic-1',
      candidate: { localDate: '2026-02-01', localTime: '10:00:00', utcOffsetSeconds: 3600 },
      reasonForVisit: 'Limping since yesterday',
      guardianNotes: null,
    });

    expect(result).toEqual({
      data: null,
      error: 'Clinic has no currently configured standard Appointment duration',
    });
  });
});

describe('rescheduleRequestedAppointment', () => {
  it('maps the Appointment id and candidate to the exact RPC parameter names, with no end parameter', async () => {
    mockRpc.mockResolvedValue({ data: 'apt-1', error: null });

    const result = await rescheduleRequestedAppointment('apt-1', {
      localDate: '2026-02-02',
      localTime: '09:00:00',
      utcOffsetSeconds: 3600,
    });

    expect(mockRpc).toHaveBeenCalledWith('reschedule_requested_appointment', {
      p_appointment_id: 'apt-1',
      p_start_local_date: '2026-02-02',
      p_start_local_time: '09:00:00',
      p_start_utc_offset_seconds: 3600,
    });
    expect(result).toEqual({ data: { appointmentId: 'apt-1' }, error: null });
  });

  it('settles into the error shape when the underlying network call rejects', async () => {
    mockRpc.mockRejectedValue(new Error('Network request failed'));

    const result = await rescheduleRequestedAppointment('apt-1', {
      localDate: '2026-02-02',
      localTime: '09:00:00',
      utcOffsetSeconds: 3600,
    });

    expect(result).toEqual({ data: null, error: 'Network request failed' });
  });
});

describe('cancelAppointment', () => {
  it('always calls with the GUARDIAN cancelling context', async () => {
    mockRpc.mockResolvedValue({ data: 'apt-1', error: null });

    await cancelAppointment('apt-1', 'No longer needed');

    expect(mockRpc).toHaveBeenCalledWith('cancel_appointment', {
      p_appointment_id: 'apt-1',
      p_cancelling_context: 'GUARDIAN',
      p_reason: 'No longer needed',
    });
  });

  it('passes a null reason through unchanged when none is supplied', async () => {
    mockRpc.mockResolvedValue({ data: 'apt-1', error: null });

    await cancelAppointment('apt-1', null);

    expect(mockRpc).toHaveBeenCalledWith('cancel_appointment', {
      p_appointment_id: 'apt-1',
      p_cancelling_context: 'GUARDIAN',
      p_reason: null,
    });
  });

  it('settles into the error shape on a lifecycle-state conflict', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Only a REQUESTED or CONFIRMED Appointment may be cancelled' },
    });

    const result = await cancelAppointment('apt-1', null);

    expect(result).toEqual({
      data: null,
      error: 'Only a REQUESTED or CONFIRMED Appointment may be cancelled',
    });
  });
});

describe('getAppointmentSchedulingHistory', () => {
  it('calls get_appointment_scheduling_history with the exact Appointment id parameter', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    await getAppointmentSchedulingHistory('apt-1');

    expect(mockRpc).toHaveBeenCalledWith('get_appointment_scheduling_history', {
      p_appointment_id: 'apt-1',
    });
  });
});

describe('getAppointmentVeterinarianAssignmentHistory', () => {
  it('calls get_appointment_veterinarian_assignment_history with the exact Appointment id parameter', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    await getAppointmentVeterinarianAssignmentHistory('apt-1');

    expect(mockRpc).toHaveBeenCalledWith('get_appointment_veterinarian_assignment_history', {
      p_appointment_id: 'apt-1',
    });
  });
});

describe('getPetAppointments pending reschedule validation (SPEC-APT-011 BR-32)', () => {
  const PROPOSAL_ID = '33333333-3333-4333-8333-333333333333';
  const confirmedRow = (overrides: Record<string, unknown> = {}) => ({
    id: 'apt-1',
    clinic_id: 'clinic-1',
    requesting_user_id: 'user-1',
    reason_for_visit: 'Vacunación',
    guardian_notes: null,
    lifecycle_state: 'CONFIRMED',
    created_at: '2026-01-01T00:00:00Z',
    current_scheduled_start_at: '2026-02-01T10:00:00Z',
    current_scheduled_end_at: '2026-02-01T10:30:00Z',
    current_scheduling_timezone_name: 'Europe/Madrid',
    current_veterinarian_clinic_assignment_id: null,
    pending_reschedule_proposal_id: PROPOSAL_ID,
    pending_reschedule_proposal_state: 'PENDING',
    pending_reschedule_proposing_context: 'CLINIC',
    pending_reschedule_proposed_start_at: '2026-02-02T09:00:00Z',
    pending_reschedule_proposed_end_at: '2026-02-02T09:30:00Z',
    pending_reschedule_proposed_timezone_name: 'Europe/Madrid',
    pending_reschedule_reason: 'Vet unavailable',
    cancellation_reason: null,
    current_schedule_source_proposal_id: null,
    current_schedule_source_proposing_context: null,
    pending_reschedule_currently_acceptable: true,
    medical_access_state: 'ACTIVE',
    ...overrides,
  });

  it('accepts a complete Clinic proposal and exposes its exact stored interval and reason', async () => {
    mockRpc.mockResolvedValue({ data: [confirmedRow()], error: null });

    const result = await getPetAppointments('pet-1');

    expect(result.data?.[0].pendingReschedule).toEqual({
      kind: 'confirmedReschedule',
      proposalId: PROPOSAL_ID,
      proposingContext: 'CLINIC',
      proposedStartAt: '2026-02-02T09:00:00Z',
      proposedEndAt: '2026-02-02T09:30:00Z',
      proposedTimezoneName: 'Europe/Madrid',
      reason: 'Vet unavailable',
      currentlyAcceptable: true,
    });
  });

  it('accepts a Clinic alternative on a REQUESTED Appointment as requestedAlternativeTime (SPEC-APT-011 BR-32)', async () => {
    mockRpc.mockResolvedValue({
      data: [confirmedRow({ lifecycle_state: 'REQUESTED' })],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.data?.[0].pendingReschedule).toEqual({
      kind: 'requestedAlternativeTime',
      proposalId: PROPOSAL_ID,
      proposingContext: 'CLINIC',
      proposedStartAt: '2026-02-02T09:00:00Z',
      proposedEndAt: '2026-02-02T09:30:00Z',
      proposedTimezoneName: 'Europe/Madrid',
      reason: 'Vet unavailable',
      currentlyAcceptable: true,
    });
    expect(result.data?.[0].lifecycleState).toBe('REQUESTED');
  });

  it('accepts the provenance of an accepted alternative on a REQUESTED Appointment (SPEC-APT-011 BR-33)', async () => {
    mockRpc.mockResolvedValue({
      data: [
        confirmedRow({
          lifecycle_state: 'REQUESTED',
          pending_reschedule_proposal_id: null,
          pending_reschedule_proposal_state: null,
          pending_reschedule_proposing_context: null,
          pending_reschedule_proposed_start_at: null,
          pending_reschedule_proposed_end_at: null,
          pending_reschedule_proposed_timezone_name: null,
          pending_reschedule_reason: null,
          current_schedule_source_proposal_id: PROPOSAL_ID,
          current_schedule_source_proposing_context: 'CLINIC',
          pending_reschedule_currently_acceptable: null,
        }),
      ],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.data?.[0].pendingReschedule).toBeNull();
    expect(result.data?.[0].currentScheduleSource).toEqual({
      proposalId: PROPOSAL_ID,
      proposingContext: 'CLINIC',
    });
  });

  it('keeps a proposal that is not currently acceptable visible (SPEC-APT-011 BR-32)', async () => {
    mockRpc.mockResolvedValue({
      data: [confirmedRow({ pending_reschedule_currently_acceptable: false })],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.data?.[0].pendingReschedule?.proposalId).toBe(PROPOSAL_ID);
    expect(result.data?.[0].pendingReschedule?.currentlyAcceptable).toBe(false);
  });

  it('accepts a Guardian proposal without a reason', async () => {
    mockRpc.mockResolvedValue({
      data: [
        confirmedRow({
          pending_reschedule_proposing_context: 'GUARDIAN',
          pending_reschedule_reason: null,
        }),
      ],
      error: null,
    });

    const result = await getPetAppointments('pet-1');

    expect(result.data?.[0].pendingReschedule?.proposingContext).toBe('GUARDIAN');
  });

  it.each<[string, Record<string, unknown>]>([
    ['a partial proposal', { pending_reschedule_proposed_end_at: null }],
    [
      'a reason without a proposal',
      {
        pending_reschedule_proposal_id: null,
        pending_reschedule_proposal_state: null,
        pending_reschedule_proposing_context: null,
        pending_reschedule_proposed_start_at: null,
        pending_reschedule_proposed_end_at: null,
        pending_reschedule_proposed_timezone_name: null,
      },
    ],
    ['a non-UUID proposal id', { pending_reschedule_proposal_id: 'proposal-1' }],
    ['a non-PENDING state', { pending_reschedule_proposal_state: 'ACCEPTED' }],
    ['a WITHDRAWN state', { pending_reschedule_proposal_state: 'WITHDRAWN' }],
    ['an unknown proposing context', { pending_reschedule_proposing_context: 'SYSTEM' }],
    ['a Clinic proposal without its reason', { pending_reschedule_reason: null }],
    ['an end not after the start', { pending_reschedule_proposed_end_at: '2026-02-02T09:00:00Z' }],
    ['an invalid timezone', { pending_reschedule_proposed_timezone_name: 'Mars/Olympus' }],
    ['a proposal on a CANCELLED Appointment', { lifecycle_state: 'CANCELLED' }],
    [
      'a Guardian proposal on a REQUESTED Appointment',
      {
        lifecycle_state: 'REQUESTED',
        pending_reschedule_proposing_context: 'GUARDIAN',
        pending_reschedule_reason: null,
      },
    ],
    ['a partial schedule provenance', { current_schedule_source_proposal_id: PROPOSAL_ID }],
    [
      'a REQUESTED interval sourced by a Guardian proposal',
      {
        lifecycle_state: 'REQUESTED',
        pending_reschedule_proposal_id: null,
        pending_reschedule_proposal_state: null,
        pending_reschedule_proposing_context: null,
        pending_reschedule_proposed_start_at: null,
        pending_reschedule_proposed_end_at: null,
        pending_reschedule_proposed_timezone_name: null,
        pending_reschedule_reason: null,
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
    ['a proposal without its acceptability', { pending_reschedule_currently_acceptable: null }],
    ['a non-boolean acceptability', { pending_reschedule_currently_acceptable: 'false' }],
    [
      'a backend without the acceptability column',
      { pending_reschedule_currently_acceptable: undefined },
    ],
    [
      'an acceptability without a proposal',
      {
        pending_reschedule_proposal_id: null,
        pending_reschedule_proposal_state: null,
        pending_reschedule_proposing_context: null,
        pending_reschedule_proposed_start_at: null,
        pending_reschedule_proposed_end_at: null,
        pending_reschedule_proposed_timezone_name: null,
        pending_reschedule_reason: null,
        pending_reschedule_currently_acceptable: true,
      },
    ],
    [
      'the Clinic feasibility column instead of acceptability',
      {
        pending_reschedule_currently_acceptable: undefined,
        pending_reschedule_currently_feasible: true,
      },
    ],
  ])('rejects the whole read for %s', async (_label, overrides) => {
    mockRpc.mockResolvedValue({ data: [confirmedRow(overrides)], error: null });

    await expect(getPetAppointments('pet-1')).resolves.toEqual({
      data: null,
      error: PET_APPOINTMENTS_MALFORMED,
    });
  });
});

describe('acceptRescheduleProposal', () => {
  const PROPOSAL_ID = '33333333-3333-4333-8333-333333333333';

  it('calls accept_appointment_reschedule_proposal in the GUARDIAN context with only the proposal id', async () => {
    mockRpc.mockResolvedValue({ data: PROPOSAL_ID, error: null });

    await expect(acceptRescheduleProposal(PROPOSAL_ID)).resolves.toEqual({
      data: { proposalId: PROPOSAL_ID },
      error: null,
    });
    expect(mockRpc).toHaveBeenCalledWith('accept_appointment_reschedule_proposal', {
      p_proposal_id: PROPOSAL_ID,
      p_accepting_context: 'GUARDIAN',
    });
  });

  it('refuses a malformed proposal id without calling the backend', async () => {
    await expect(acceptRescheduleProposal('proposal-1')).resolves.toEqual({
      data: null,
      error: RESCHEDULE_ACCEPTANCE_INVALID_REQUEST,
    });
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it('rejects a success payload that is not the accepted proposal id', async () => {
    mockRpc.mockResolvedValue({ data: '44444444-4444-4444-8444-444444444444', error: null });

    await expect(acceptRescheduleProposal(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: RESCHEDULE_ACCEPTANCE_MALFORMED,
    });
  });

  it('keeps the backend message for mapping and never throws', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Reschedule Proposal is no longer actionable' },
    });
    await expect(acceptRescheduleProposal(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: 'Reschedule Proposal is no longer actionable',
    });

    mockRpc.mockRejectedValue(new Error('Network request failed'));
    await expect(acceptRescheduleProposal(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

describe('acceptRequestedAlternativeTime (SPEC-APT-019)', () => {
  const PROPOSAL_ID = '33333333-3333-4333-8333-333333333333';

  it('calls the Guardian-only acceptance with only the proposal id (no context, no stale token)', async () => {
    mockRpc.mockResolvedValue({ data: PROPOSAL_ID, error: null });

    await expect(acceptRequestedAlternativeTime(PROPOSAL_ID)).resolves.toEqual({
      data: { proposalId: PROPOSAL_ID },
      error: null,
    });
    expect(mockRpc).toHaveBeenCalledWith('accept_requested_appointment_alternative_time', {
      p_proposal_id: PROPOSAL_ID,
    });
  });

  it('refuses a malformed proposal id without calling the backend', async () => {
    await expect(acceptRequestedAlternativeTime('proposal-1')).resolves.toEqual({
      data: null,
      error: RESCHEDULE_ACCEPTANCE_INVALID_REQUEST,
    });
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it('rejects a success payload that is not the accepted proposal id', async () => {
    mockRpc.mockResolvedValue({ data: '44444444-4444-4444-8444-444444444444', error: null });
    await expect(acceptRequestedAlternativeTime(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: RESCHEDULE_ACCEPTANCE_MALFORMED,
    });
  });

  it('keeps the backend message for mapping and never throws or retries', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Appointment must remain REQUESTED to accept an alternative time' },
    });
    await expect(acceptRequestedAlternativeTime(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: 'Appointment must remain REQUESTED to accept an alternative time',
    });
    expect(mockRpc).toHaveBeenCalledTimes(1);

    mockRpc.mockRejectedValue(new Error('Network request failed'));
    await expect(acceptRequestedAlternativeTime(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});
