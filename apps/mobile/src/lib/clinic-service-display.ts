import type { ClinicServiceCategory } from '@/data/clinics';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure presentation helper for published Clinic Service offerings
 * (clinics/[id].tsx). Clinic Services are stable domain categories with
 * localized labels (SPEC-CLI-005 BR-5/BR-6); they are distinct from Clinical
 * Record event categories (BR-16), so they have their own keys rather than
 * reusing clinicalHistory.*.
 */

const SERVICE_CATEGORY_LABEL_KEYS: Record<ClinicServiceCategory, TranslationKey> = {
  GENERAL_CONSULTATION: 'clinicServices.categoryGeneralConsultation',
  VACCINATION: 'clinicServices.categoryVaccination',
  SURGERY: 'clinicServices.categorySurgery',
  DENTISTRY: 'clinicServices.categoryDentistry',
  DIAGNOSTIC_IMAGING: 'clinicServices.categoryDiagnosticImaging',
  LABORATORY: 'clinicServices.categoryLaboratory',
  EMERGENCY_CARE: 'clinicServices.categoryEmergencyCare',
  HOSPITALIZATION: 'clinicServices.categoryHospitalization',
  OTHER: 'clinicServices.categoryOther',
};

/**
 * The localized-label i18n key for a Clinic Service category — the raw
 * backend code must never be shown directly. A code this client doesn't know
 * resolves to a generic Veterinary service label.
 */
export function serviceCategoryLabelKey(category: string): TranslationKey {
  return Object.prototype.hasOwnProperty.call(SERVICE_CATEGORY_LABEL_KEYS, category)
    ? SERVICE_CATEGORY_LABEL_KEYS[category as ClinicServiceCategory]
    : 'clinicServices.categoryUnknown';
}
