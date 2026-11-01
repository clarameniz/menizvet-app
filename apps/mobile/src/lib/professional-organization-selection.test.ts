import {
  getProfessionalOrganizationSelection,
  setProfessionalOrganizationSelection,
  subscribeProfessionalOrganizationSelection,
} from '@/lib/professional-organization-selection';

const orgA = { membershipId: 'm-a', organizationId: 'org-a' };
const orgB = { membershipId: 'm-b', organizationId: 'org-b' };

afterEach(() => setProfessionalOrganizationSelection(null));

describe('professional Organization selection', () => {
  it('starts with no selection', () => {
    expect(getProfessionalOrganizationSelection()).toBeNull();
  });

  it('holds the latest selection and can be cleared', () => {
    setProfessionalOrganizationSelection(orgA);
    expect(getProfessionalOrganizationSelection()).toEqual(orgA);
    setProfessionalOrganizationSelection(orgB);
    expect(getProfessionalOrganizationSelection()).toEqual(orgB);
    setProfessionalOrganizationSelection(null);
    expect(getProfessionalOrganizationSelection()).toBeNull();
  });

  it('notifies subscribers only on a real change, and stops after unsubscribing', () => {
    const listener = jest.fn();
    const unsubscribe = subscribeProfessionalOrganizationSelection(listener);

    setProfessionalOrganizationSelection(orgA);
    setProfessionalOrganizationSelection({ ...orgA });
    expect(listener).toHaveBeenCalledTimes(1);

    setProfessionalOrganizationSelection(orgB);
    expect(listener).toHaveBeenCalledTimes(2);

    unsubscribe();
    setProfessionalOrganizationSelection(orgA);
    expect(listener).toHaveBeenCalledTimes(2);
  });

  it('keeps its own copy, so a caller mutating its object cannot change the selection', () => {
    const input = { ...orgA };
    setProfessionalOrganizationSelection(input);
    input.organizationId = 'org-b';
    expect(getProfessionalOrganizationSelection()).toEqual(orgA);
  });
});
