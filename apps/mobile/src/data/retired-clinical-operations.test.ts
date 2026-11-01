/// <reference types="node" />
import { readdirSync, readFileSync, statSync } from 'fs';
import { join } from 'path';

/**
 * SPEC-MED-010 BR-25: the Encounter, Draft and Finalize operations are
 * removed with no replacement, and since stage M5 so are the
 * reason-and-addition correction operations and the clinical time of a new
 * record (an Entry is edited, BR-23b; the server records its own time, BR-5).
 * No mobile source — screen, data module or Edge Function call — may name
 * one, so a stale path can never be reached.
 */
const RETIRED = [
  'start_appointment_clinical_encounter',
  'conclude_appointment_clinical_encounter',
  'create_appointment_clinical_draft',
  'update_appointment_clinical_draft',
  'finalize_appointment_clinical_entry',
  'create_clinical_encounter',
  'conclude_clinical_encounter',
  'create_draft_clinical_record_entry',
  'update_draft_clinical_record_entry',
  'finalize_clinical_record_entry',
  'view_care_authorization_clinical_work_context',
  'view_professional_pet_medical_history',
  'view_clinical_record_entry',
  'get_professional_pet_active_care_authorizations',
  'clinical_encounter_id',
  'create_appointment_clinical_amendment',
  'create_clinical_amendment',
  'p_clinical_event_at',
  'p_clinical_event_now',
];

function sources(directory: string): string[] {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) return sources(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : [];
  });
}

it('no mobile source names a retired clinical operation', () => {
  const offenders = sources(join(__dirname, '..')).flatMap((path) => {
    const text = readFileSync(path, 'utf8');
    // Even a comment naming one would invite a call: cite the Specification instead.
    return RETIRED.filter((name) => text.includes(name)).map((name) => `${path}: ${name}`);
  });
  expect(offenders).toEqual([]);
});
