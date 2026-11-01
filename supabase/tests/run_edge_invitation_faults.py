"""Reproducible Staff Slice B1 Edge-route mutation regression.

Copies supabase/functions into a temporary directory, applies one behavioural
mutant at a time to the invite module (or route), and requires the Deno
organization-invitation tests to fail; the unmodified copy must pass. The
repository source is never rewritten and no network, database, or provider is
used. Run from the repository root with Deno installed.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, ROOT

MODULE = '_shared/communications/organization-invitation.ts'
ROUTE = 'communications/index.ts'
TEST = 'tests/organization-invitation.test.ts'

# (name, file, before, after)
FAULTS = [
    ('client expiry accepted', MODULE, '  "clinic_id",\n]);', '  "clinic_id",\n  "expires_at",\n]);'),
    ('recipient_user_id accepted from the client', MODULE, '  "clinic_id",\n]);', '  "clinic_id",\n  "recipient_user_id",\n]);'),
    ('expiry not 7 days', MODULE, '7 * 24 * 60 * 60 * 1000', '6 * 24 * 60 * 60 * 1000'),
    ('creation instant from the Edge clock', MODULE,
     'const createdAt = creationInstant(authorized.data);',
     'const createdAt = (creationInstant(authorized.data), new Date());'),
    ('secret leaked in response', MODULE,
     'return { invitation_id: created.data.toLowerCase() };',
     'return { invitation_id: created.data.toLowerCase(), secret: envelope.secret } as {\n    invitation_id: string;\n  };'),
    ('product route offers OWNER', MODULE, '  "VETERINARIAN",\n]);\nconst CLINIC', '  "VETERINARIAN",\n  "OWNER",\n]);\nconst CLINIC'),
    ('Clinic-scoped Veterinarian accepted', MODULE,
     'new Set(["ADMINISTRATOR", "RECEPTIONIST"])', 'new Set(["ADMINISTRATOR", "RECEPTIONIST", "VETERINARIAN"])'),
    ('Clinic scope without a Clinic', MODULE,
     '(clinicId === null || !CLINIC_RESPONSIBILITIES.has(responsibility))',
     '!CLINIC_RESPONSIBILITIES.has(responsibility)'),
    ('values judged before authorization', MODULE,
     '  const request = parseStaffInvitationRequest(body);\n',
     '  const request = parseStaffInvitationRequest(body);\n  validatedValues(request);\n'),
    ('duplicate conflict surfaced as server error', MODULE,
     '      return new StaffInvitationError(\n        409,', '      return new StaffInvitationError(\n        500,'),
    ('active Member conflated with pending duplicate', MODULE,
     'error.hint === "ACTIVE_MEMBER"', 'error.hint === "ACTIVE"'),
    ('unverified inviter reported as unavailable Organization', MODULE,
     'error.hint === "ACCOUNT_VERIFICATION_REQUIRED"', 'error.hint === "UNVERIFIED"'),
    ('failed creation retried', MODULE,
     '  if (created.error) throw staffInvitationRpcFailure(created.error);',
     '  if (created.error) {\n    await rpc("create_staff_organization_invitation_with_communication", {});\n'
     '    throw staffInvitationRpcFailure(created.error);\n  }'),
    ('raw database error exposed', MODULE,
     '    default:\n      return new StaffInvitationError(500, "INTERNAL_ERROR");',
     '    default:\n      return Object.assign(new StaffInvitationError(500, "INTERNAL_ERROR"), {\n'
     '        message: error.message,\n      });'),
    ('acting User taken from request data', ROUTE,
     '  const auth = await authenticatedContext(admin, request);\n  const body = await requestBody(request);\n  return response(',
     '  const body = await requestBody(request);\n  const auth = { subject: String(body.organization_id) };\n  return response('),
]


def run_tests(functions):
    try:
        return subprocess.run(['deno', 'test', '--allow-read', TEST], cwd=functions / 'communications',
                              capture_output=True, text=True, encoding='utf-8', timeout=300)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise HarnessFailure(f'Deno infrastructure failed: {error}') from error


def main():
    with tempfile.TemporaryDirectory(prefix='menizvet_edge_faults_') as temporary:
        functions = Path(temporary) / 'functions'
        shutil.copytree(ROOT / 'supabase/functions', functions)
        baseline = run_tests(functions)
        if baseline.returncode:
            raise HarnessFailure('Baseline Edge tests must pass:\n' + baseline.stdout + baseline.stderr)
        print('PASS baseline organization-invitation tests', flush=True)
        for name, relative, before, after in FAULTS:
            path = functions / relative
            original = path.read_text(encoding='utf-8')
            if original.count(before) != 1:
                raise HarnessFailure(f'{name}: mutation anchor must occur exactly once')
            path.write_text(original.replace(before, after, 1), encoding='utf-8', newline='\n')
            try:
                result = run_tests(functions)
            finally:
                path.write_text(original, encoding='utf-8', newline='\n')
            output = result.stdout + result.stderr
            # A type error is not evidence: the mutant must run and fail a test.
            if result.returncode == 0 or 'running' not in output or 'FAILED' not in output:
                raise HarnessFailure(f'{name}: mutant survived or did not reach the tests:\n{output}')
            print(f'CAUGHT {name}', flush=True)
        print(f'{len(FAULTS)}/{len(FAULTS)} Edge mutants caught by failing tests', flush=True)


if __name__ == '__main__':
    main()
