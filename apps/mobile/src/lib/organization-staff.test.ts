import type { StaffMember } from '@/data/organization-staff';
import type {
  OrganizationProfessionalContext,
  ProfessionalCapability,
  ScopedCapability,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import {
  endAccessConfirmation,
  offersOrganizationStaff,
  organizationStaffHref,
  staffMemberIdentity,
  staffMemberTargetLabel,
  staffResponsibilityLabel,
  staffRoleBadges,
  staffShortDateLabel,
  staffRoleLabel,
  staffScopeLabel,
  staffTaskLabel,
} from '@/lib/organization-staff';

const organization = (capabilities: ScopedCapability[]): OrganizationProfessionalContext => ({
  organizationId: 'A',
  membershipId: 'm',
  organizationDisplayName: 'A',
  capabilities,
  responsibilities: [],
  unknownCapabilities: [],
  clinicAssignments: [],
  entitlements: {
    APPOINTMENT_MANAGEMENT: false,
    PROFESSIONAL_SCHEDULING: false,
    CLINICAL_CARE: false,
    CLINICAL_DOCUMENTATION: false,
  },
});
const orgCapability = (capability: ProfessionalCapability): ScopedCapability => ({
  capability,
  scope: { type: 'ORGANIZATION' },
});
const member: StaffMember = {
  membershipId: 'm',
  effectiveStart: '2020-01-01T00:00:00Z',
  isSelf: false,
  displayName: null,
  invitationRecipientEmail: null,
  responsibilities: [],
};
afterEach(() => {
  i18n.locale = 'es';
});
it.each(['ORGANIZATION_INVITE_MEMBERS', 'ORGANIZATION_END_MEMBERSHIPS'] as const)(
  'offers entry for %s alone without Entitlements',
  (cap) => {
    expect(offersOrganizationStaff(organization([orgCapability(cap)]))).toBe(true);
  },
);
it('does not infer entry from roles, unrelated capabilities, unknown capabilities or Clinic scope', () => {
  const org = organization([
    orgCapability('ORGANIZATION_REVOKE_INVITATIONS'),
    orgCapability('APPOINTMENT_VIEW_SCHEDULE'),
  ]);
  org.responsibilities = [{ responsibility: 'OWNER', scope: { type: 'ORGANIZATION' } }];
  org.unknownCapabilities = ['FUTURE'];
  expect(offersOrganizationStaff(org)).toBe(false);
  org.capabilities = [
    {
      capability: 'ORGANIZATION_INVITE_MEMBERS',
      scope: { type: 'CLINIC', clinic: { clinicId: 'c', displayName: 'Clinic' } },
    },
  ];
  expect(offersOrganizationStaff(org)).toBe(false);
  expect(offersOrganizationStaff(organization([]))).toBe(false);
});
it('carries selected Organization identity explicitly in navigation', () => {
  expect(organizationStaffHref('A')).toEqual({
    pathname: '/professional/organizations/[organizationId]/staff',
    params: { organizationId: 'A' },
  });
  expect(organizationStaffHref('B')).toMatchObject({ params: { organizationId: 'B' } });
});
describe.each([
  ['es', 'Miembro sin nombre'],
  ['en', 'Unnamed member'],
])('member identity in %s (SPEC-ORG-009 §7 order)', (locale, unnamed) => {
  beforeEach(() => {
    i18n.locale = locale;
  });
  const t = (key: Parameters<typeof i18n.t>[0], options?: Record<string, string | number>) =>
    i18n.t(key, options);
  const EMAIL = 'invited@example.test';

  it('display name only: the name, no supporting line', () => {
    expect(staffMemberIdentity({ ...member, displayName: 'Ana' }, t)).toEqual({
      heading: 'Ana',
      supporting: null,
    });
  });

  it('display name and Invitation address: name first, the address labelled as Invitation context', () => {
    expect(
      staffMemberIdentity({ ...member, displayName: 'Ana', invitationRecipientEmail: EMAIL }, t),
    ).toEqual({ heading: 'Ana', supporting: i18n.t('staff.invitedAddress', { email: EMAIL }) });
  });

  it('no name but an Invitation address: the address as heading, with context, never repeated', () => {
    const identity = staffMemberIdentity({ ...member, invitationRecipientEmail: EMAIL }, t);
    expect(identity).toEqual({
      heading: EMAIL,
      supporting: i18n.t('staff.invitationAddressContext'),
    });
    expect(identity.supporting).not.toContain(EMAIL);
  });

  it('neither: the safe fallback and no invented supporting line', () => {
    expect(staffMemberIdentity(member, t)).toEqual({ heading: unnamed, supporting: null });
  });

  it('a long Invitation address is kept whole for the card to wrap', () => {
    const long = `${'a'.repeat(60)}+staff.invitation.address@example-long-domain.test`;
    expect(staffMemberIdentity({ ...member, invitationRecipientEmail: long }, t).heading).toBe(
      long,
    );
  });

  it('target label uses the fullest approved identity and distinguishes same-named members', () => {
    const first = staffMemberTargetLabel(
      { ...member, displayName: 'Ana', invitationRecipientEmail: 'ana.one@example.test' },
      t,
    );
    const second = staffMemberTargetLabel(
      { ...member, displayName: 'Ana', invitationRecipientEmail: 'ana.two@example.test' },
      t,
    );
    expect(first).not.toBe(second);
    expect(first).toBe('Ana (ana.one@example.test)');
    expect(staffMemberTargetLabel({ ...member, invitationRecipientEmail: EMAIL }, t)).toBe(EMAIL);
    expect(staffMemberTargetLabel(member, t)).toBe(unnamed);
  });

  it('confirmation shows identity, address, every role with its Clinic, Organization and consequences', () => {
    const target: StaffMember = {
      ...member,
      displayName: 'Ana',
      invitationRecipientEmail: EMAIL,
      responsibilities: [
        {
          responsibilityGrantId: 'g-142',
          responsibility: 'RECEPTIONIST',
          scope: { type: 'ORGANIZATION' },
        },
        {
          responsibilityGrantId: 'g-143',
          responsibility: 'ADMINISTRATOR',
          scope: { type: 'CLINIC', clinic: { clinicId: 'c1', displayName: 'Centro' } },
        },
      ],
    };
    const { title, message } = endAccessConfirmation(target, 'Animalia', t);
    expect(title).toBe(i18n.t('staff.endAccessConfirmTitle', { organization: 'Animalia' }));
    const [identityBlock, consequences] = message.split('\n\n');
    expect(identityBlock.split('\n')).toEqual([
      'Ana',
      i18n.t('staff.invitedAddress', { email: EMAIL }),
      ...target.responsibilities.map((role) => staffResponsibilityLabel(role, t)),
    ]);
    expect(identityBlock).toContain('Centro');
    expect(consequences).toBe(
      i18n.t('staff.endAccessConfirmMessage', { name: 'Ana', organization: 'Animalia' }),
    );
  });

  it('confirmation falls back to the Invitation address, then to the unnamed label', () => {
    const byEmail = endAccessConfirmation({ ...member, invitationRecipientEmail: EMAIL }, 'A', t);
    expect(byEmail.message.split('\n').slice(0, 2)).toEqual([
      EMAIL,
      i18n.t('staff.invitationAddressContext'),
    ]);
    expect(byEmail.message).toContain(
      i18n.t('staff.endAccessConfirmMessage', { name: EMAIL, organization: 'A' }),
    );
    const unnamedTarget = endAccessConfirmation(member, 'A', t);
    expect(unnamedTarget.message.split('\n')[0]).toBe(unnamed);
    expect(unnamedTarget.message).not.toContain('@');
  });
});
it.each(['es', 'en'])('labels OWNER, VETERINARIAN and Clinic scopes in %s', (locale) => {
  i18n.locale = locale;
  const t = i18n.t.bind(i18n);
  for (const responsibility of [
    'OWNER',
    'VETERINARIAN',
    'ADMINISTRATOR',
    'RECEPTIONIST',
  ] as const) {
    const text = staffResponsibilityLabel({ responsibility, scope: { type: 'ORGANIZATION' } }, t);
    expect(text).not.toContain(responsibility);
    expect(text).toContain(t('staff.organizationScope'));
  }
  const clinic = staffResponsibilityLabel(
    {
      responsibility: 'ADMINISTRATOR',
      scope: { type: 'CLINIC', clinic: { clinicId: 'c', displayName: 'Centro' } },
    },
    t,
  );
  expect(clinic).toContain('Centro');
  expect(clinic).toContain(t('staff.clinicScope'));
});

it('names responsibilities as clinic tasks, with future Clinics only where the scope covers them', () => {
  const t = i18n.t.bind(i18n);
  const organizationWide = (
    responsibility: 'OWNER' | 'ADMINISTRATOR' | 'RECEPTIONIST' | 'VETERINARIAN',
  ) => staffTaskLabel({ responsibility, scope: { type: 'ORGANIZATION' } }, t);
  i18n.locale = 'es';
  expect(organizationWide('RECEPTIONIST')).toBe(
    'Recepción · Todas las clínicas, incluidas las futuras',
  );
  expect(organizationWide('ADMINISTRATOR')).toBe(
    'Administración · Todas las clínicas, incluidas las futuras',
  );
  // VETERINARIAN practises through Clinic Assignments; OWNER has no Clinic coverage of its own.
  expect(organizationWide('VETERINARIAN')).toBe('Veterinario/a');
  expect(organizationWide('OWNER')).toBe('Propietario/a');
  const clinicRole = {
    responsibility: 'RECEPTIONIST' as const,
    scope: { type: 'CLINIC' as const, clinic: { clinicId: 'c', displayName: null } },
  };
  expect(staffScopeLabel(clinicRole, t)).toBe(t('professional.unnamedClinic'));
  expect(staffRoleLabel('RECEPTIONIST', t)).toBe('Recepción');
  i18n.locale = 'en';
  try {
    expect(organizationWide('RECEPTIONIST')).toBe('Reception · All clinics, including future ones');
  } finally {
    i18n.locale = 'es';
  }
});

describe('Staff list summary', () => {
  const t = i18n.t.bind(i18n);
  const clinic = (clinicId: string) => ({
    type: 'CLINIC' as const,
    clinic: { clinicId, displayName: `Clinic ${clinicId}` },
  });
  it('gives one badge per responsibility in detail order, with Clinic coverage as a count', () => {
    i18n.locale = 'es';
    expect(
      staffRoleBadges(
        [
          { responsibility: 'ADMINISTRATOR', scope: clinic('c1') },
          { responsibility: 'RECEPTIONIST', scope: clinic('c1') },
          { responsibility: 'RECEPTIONIST', scope: clinic('c2') },
          { responsibility: 'VETERINARIAN', scope: { type: 'ORGANIZATION' } },
          { responsibility: 'OWNER', scope: { type: 'ORGANIZATION' } },
        ],
        t,
      ),
    ).toEqual([
      'Propietario/a',
      'Veterinario/a',
      'Recepción · 2 clínicas',
      'Administración · 1 clínica',
    ]);
  });
  it('reports every Clinic when an Organization-scoped Grant exists, even beside Clinic Grants', () => {
    expect(
      staffRoleBadges(
        [
          { responsibility: 'RECEPTIONIST', scope: { type: 'ORGANIZATION' } },
          { responsibility: 'RECEPTIONIST', scope: clinic('c1') },
        ],
        t,
      ),
    ).toEqual(['Recepción · todas las clínicas']);
    expect(staffRoleBadges([], t)).toEqual([]);
    i18n.locale = 'en';
    try {
      expect(
        staffRoleBadges([{ responsibility: 'ADMINISTRATOR', scope: { type: 'ORGANIZATION' } }], t),
      ).toEqual(['Administration · all clinics']);
    } finally {
      i18n.locale = 'es';
    }
  });
});

describe('staffShortDateLabel', () => {
  const now = new Date(2030, 0, 15, 12);
  it('omits the year in the current year and shows it otherwise, in both languages', () => {
    expect(staffShortDateLabel(new Date(2030, 9, 28, 12).toISOString(), 'es', now)).toBe('28 oct');
    expect(staffShortDateLabel(new Date(2031, 9, 28, 12).toISOString(), 'es', now)).toBe(
      '28 oct 2031',
    );
    expect(staffShortDateLabel(new Date(2030, 9, 28, 12).toISOString(), 'en', now)).toBe('28 Oct');
  });
});
