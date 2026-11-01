import { CLINIC_SERVICE_CATEGORIES } from '@/data/clinics';
import { i18n } from '@/i18n/i18n';
import { serviceCategoryLabelKey } from '@/lib/clinic-service-display';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const EXPECTED_LABELS = {
  GENERAL_CONSULTATION: { es: 'Consulta general', en: 'General consultation' },
  VACCINATION: { es: 'Vacunación', en: 'Vaccination' },
  SURGERY: { es: 'Cirugía', en: 'Surgery' },
  DENTISTRY: { es: 'Odontología', en: 'Dentistry' },
  DIAGNOSTIC_IMAGING: { es: 'Diagnóstico por imagen', en: 'Diagnostic imaging' },
  LABORATORY: { es: 'Laboratorio', en: 'Laboratory' },
  EMERGENCY_CARE: { es: 'Urgencias', en: 'Emergency care' },
  HOSPITALIZATION: { es: 'Hospitalización', en: 'Hospitalization' },
  OTHER: { es: 'Otros servicios', en: 'Other services' },
} as const;

describe('serviceCategoryLabelKey', () => {
  it('covers exactly the 9 database service categories', () => {
    expect([...CLINIC_SERVICE_CATEGORIES].sort()).toEqual(Object.keys(EXPECTED_LABELS).sort());
  });

  it.each(CLINIC_SERVICE_CATEGORIES)('localizes %s in Spanish and English', (category) => {
    const key = serviceCategoryLabelKey(category);
    expect(key.startsWith('clinicServices.category')).toBe(true);
    expect(key).not.toBe('clinicServices.categoryUnknown');
    expect(i18n.t(key, { locale: 'es' })).toBe(EXPECTED_LABELS[category].es);
    expect(i18n.t(key, { locale: 'en' })).toBe(EXPECTED_LABELS[category].en);
    expect(i18n.t(key, { locale: 'es' })).not.toBe(category);
    expect(i18n.t(key, { locale: 'en' })).not.toBe(category);
  });

  it('maps every category to a distinct key (no two categories collapse to the same label)', () => {
    const keys = new Set(CLINIC_SERVICE_CATEGORIES.map(serviceCategoryLabelKey));
    expect(keys.size).toBe(CLINIC_SERVICE_CATEGORIES.length);
  });

  it.each(['GROOMING', '', 'vaccination', 'constructor', 'toString'])(
    'resolves the unknown runtime value %p to the generic localized label',
    (category) => {
      const key = serviceCategoryLabelKey(category);
      expect(key).toBe('clinicServices.categoryUnknown');
      expect(i18n.t(key, { locale: 'es' })).toBe('Servicio veterinario');
      expect(i18n.t(key, { locale: 'en' })).toBe('Veterinary service');
    },
  );

  it('does not reuse the clinical-history category keys', () => {
    for (const category of CLINIC_SERVICE_CATEGORIES) {
      expect(serviceCategoryLabelKey(category).startsWith('clinicalHistory.')).toBe(false);
    }
  });
});
