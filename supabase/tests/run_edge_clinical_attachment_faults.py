"""Reproducible stage M4 Edge-route mutation regression for clinical-attachments.

Copies supabase/functions into a temporary directory, applies one behavioural
mutant at a time to the route table or the Guardian download route, and
requires the Deno clinical-attachments tests to fail; the unmodified copy must
pass. The repository source is never rewritten and no network, database, or
provider is used. Run from the repository root with Deno installed.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, ROOT

ROUTES = '_shared/clinical-attachments/routes.ts'
FUNCTION = 'clinical-attachments/index.ts'

GUARDIAN_ARGS = '      p_attachment_id: requiredUuid(body.attachment_id, "attachment_id"),\n'

# (name, file, before, after)
FAULTS = [
    ('a retired professional route reappears', ROUTES,
     '  "maintenance",\n] as const;', '  "maintenance",\n  "initiate",\n] as const;'),
    ('the professional download route reappears', ROUTES,
     '  "maintenance",\n] as const;', '  "maintenance",\n  "professional-download",\n] as const;'),
    ('route names matched case-insensitively', ROUTES,
     'CLINICAL_ATTACHMENT_ROUTES.find((route) => route === name)',
     'CLINICAL_ATTACHMENT_ROUTES.find((route) => route === name.toLowerCase())'),
    ('a route selected from the query string', ROUTES,
     'const pathname = new URL(url).pathname.replace(/\\/+$/u, "");',
     'const parsed = new URL(url);\n  const pathname = (parsed.searchParams.get("route") ?? parsed.pathname).replace(/\\/+$/u, "");'),
    ('a route matched by substring', ROUTES,
     'CLINICAL_ATTACHMENT_ROUTES.find((route) => route === name)',
     'CLINICAL_ATTACHMENT_ROUTES.find((route) => name.includes(route))'),
    ('the Guardian route forwards a client Care Authorization', FUNCTION, GUARDIAN_ARGS,
     GUARDIAN_ARGS + '      p_care_authorization_id: body.care_authorization_id,\n'),
    ('the Guardian route forwards a client Clinic', FUNCTION, GUARDIAN_ARGS,
     GUARDIAN_ARGS + '      p_accessing_clinic_id: body.accessing_clinic_id,\n'),
    ('the Guardian route forwards a client Encounter', FUNCTION, GUARDIAN_ARGS,
     GUARDIAN_ARGS + '      p_accessing_clinical_encounter_id: body.clinical_encounter_id,\n'),
    ('the Guardian route calls the retired multi-context authorizer', FUNCTION,
     '    "authorize_guardian_clinical_attachment_download",\n', '    "authorize_clinical_attachment_download",\n'),
]


def run_tests(functions):
    try:
        return subprocess.run(['deno', 'test', '--allow-read', 'tests'], cwd=functions / 'clinical-attachments',
                              capture_output=True, text=True, encoding='utf-8', timeout=300)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise HarnessFailure(f'Deno infrastructure failed: {error}') from error


def main():
    with tempfile.TemporaryDirectory(prefix='menizvet_edge_attachment_faults_') as temporary:
        functions = Path(temporary) / 'functions'
        shutil.copytree(ROOT / 'supabase/functions', functions)
        # The parity tests read config.toml and the migrations beside functions/.
        shutil.copy2(ROOT / 'supabase/config.toml', Path(temporary) / 'config.toml')
        shutil.copytree(ROOT / 'supabase/migrations', Path(temporary) / 'migrations')
        baseline = run_tests(functions)
        if baseline.returncode:
            raise HarnessFailure('Baseline Edge tests must pass:\n' + baseline.stdout + baseline.stderr)
        print('PASS baseline clinical-attachments tests', flush=True)
        for name, relative, before, after in FAULTS:
            path = functions / relative
            original = path.read_text(encoding='utf-8')
            if original.count(before) != 1:
                raise HarnessFailure(f'{name}: fault anchor must occur exactly once')
            path.write_text(original.replace(before, after), encoding='utf-8')
            try:
                result = run_tests(functions)
            finally:
                path.write_text(original, encoding='utf-8')
            if result.returncode == 0:
                raise HarnessFailure(f'{name}: mutant survived')
            # A type or syntax error is not evidence: the mutant must reach a failing test.
            if 'FAILED' not in result.stdout:
                raise HarnessFailure(f'{name}: failed outside the tests:\n{result.stdout}{result.stderr}')
            print(f'CAUGHT {name}', flush=True)
        if run_tests(functions).returncode:
            raise HarnessFailure('Restored copy must pass again')
        print(f'{len(FAULTS)}/{len(FAULTS)} clinical-attachments Edge mutants caught', flush=True)


if __name__ == '__main__':
    main()
