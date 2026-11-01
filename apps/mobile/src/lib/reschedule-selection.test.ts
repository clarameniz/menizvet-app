import type { RequestableCandidate } from '@/data/appointments';
import { canSubmitReschedule } from '@/lib/reschedule-selection';

const SLOT_A: RequestableCandidate = {
  localDate: '2026-09-22',
  localTime: '16:30:00',
  utcOffsetSeconds: 7200,
};

describe('canSubmitReschedule', () => {
  it('is disabled until a slot is selected', () => {
    expect(canSubmitReschedule(null)).toBe(false);
    expect(canSubmitReschedule(SLOT_A)).toBe(true);
  });
});
