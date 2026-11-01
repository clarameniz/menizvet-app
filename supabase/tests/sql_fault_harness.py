"""Shared, dependency-free infrastructure for permanent LOCAL SQL fault tests.

Candidates live only in rollback-only psql sessions. Each session carries a
unique application_name; finally terminates only these sessions and verifies
all public function definitions/ACLs and public/Auth row counts are restored.
No remote connection string, deployment, source edit, or COMMIT is supported.
"""
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


class HarnessFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class Fault:
    name: str
    definitions: str
    assertion: str
    assertion_function: str = "assert_true"


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise HarnessFailure(f"Fault anchor must occur exactly once: {before}")
    return source.replace(before, after, 1)


class LocalSql:
    def __init__(self):
        self.application_name = "menizvet_fault_" + uuid.uuid4().hex

    def execute(self, statement, *, cleanup=False):
        command = ["docker", "exec", "-i", "-e", "PGAPPNAME=" +
                   (self.application_name + "_cleanup" if cleanup else self.application_name),
                   "supabase_db_petcare", "psql", "-X", "-U", "postgres", "-d", "postgres",
                   "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-q", "-t", "-A"]
        try:
            return subprocess.run(command, input=statement, text=True, encoding="utf-8",
                                  capture_output=True, timeout=180)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise HarnessFailure(f"Local SQL infrastructure failed: {error}") from error

    def require_success(self, statement, label):
        result = self.execute(statement)
        if result.returncode:
            raise HarnessFailure(f"{label} failed (not a caught mutant):\n{result.stderr}")
        return result.stdout.strip()

    def definition(self, signature):
        # Signatures are repository-owned identifiers, never caller input.
        if not re.fullmatch(r"public\.\w+\([\w, ]*\)", signature):
            raise HarnessFailure("Invalid repository function signature")
        definition = self.require_success(f"select pg_get_functiondef('{signature}'::regprocedure);",
                                          "Read original definition")
        return definition.rstrip().rstrip(';') + ';\n'

    def fingerprint(self):
        return self.require_success("""select jsonb_build_object(
            'functions', (select jsonb_object_agg(p.oid::regprocedure::text,
                jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl)
                order by p.oid::regprocedure::text)
                from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f'),
            'rows', (select jsonb_object_agg(table_schema || '.' || table_name, row_count)
                from (select table_schema,table_name,
                    (xpath('/row/c/text()',query_to_xml(format('select count(*) c from %I.%I',table_schema,table_name),false,true,'')))[1]::text::bigint row_count
                    from information_schema.tables where table_schema in ('public','auth') and table_type='BASE TABLE') counts)
        );""", "Capture restoration fingerprint")

    def terminate_sessions(self):
        result = self.execute("select pg_terminate_backend(pid) from pg_stat_activity "
                              f"where application_name='{self.application_name}' and pid<>pg_backend_pid();",
                              cleanup=True)
        if result.returncode:
            raise HarnessFailure("Could not terminate harness sessions:\n" + result.stderr)

    @contextmanager
    def restored(self):
        before = self.fingerprint()
        try:
            yield
        finally:
            # Runs on test failure and KeyboardInterrupt as well as success.
            # Terminating the exact psql backend rolls back any in-flight mutant.
            self.terminate_sessions()
            after = self.fingerprint()
            if after != before:
                raise HarnessFailure("Function definitions/ACLs or data row counts were not restored")
            print("Restoration verified: public function definitions/ACLs and data row counts unchanged", flush=True)

    def suite(self, path):
        source = path.read_text(encoding="utf-8")
        # Some established suites verify zero retained rows in a read-only DO
        # after ROLLBACK. Require the explicit rollback, not end-of-file position.
        if not re.search(r"^begin;\s*$", source, re.M | re.I) or not re.search(r"^rollback;\s*$", source, re.M | re.I):
            raise HarnessFailure(f"Suite is not explicitly rollback-only: {path}")
        if re.search(r"^\s*commit\s*;", source, re.M | re.I):
            raise HarnessFailure(f"COMMIT is forbidden in this harness: {path}")
        self.require_success(source, path.name)
        print("PASS " + path.name, flush=True)
        return source

    def faults(self, source, faults):
        for fault in faults:
            injected = replace_once(source, "begin;", "begin;\n" + fault.definitions)
            result = self.execute(injected)
            # Only the named assertion, raised with the expected SQLSTATE by
            # the designated test helper, is evidence of a caught mutation.
            expected_error = re.search(r"^ERROR:\s+P0001:\s+" + re.escape(fault.assertion) + r"\s*$",
                                       result.stderr, re.M)
            expected_context = re.search(r"PL/pgSQL function pg_temp_\d+\." +
                                         re.escape(fault.assertion_function) + r"\(", result.stderr)
            if result.returncode == 0 or not expected_error or not expected_context:
                raise HarnessFailure(f"{fault.name}: mutant survived or failed unexpectedly; "
                                     f"expected assertion {fault.assertion!r}:\n{result.stderr}")
            print(f"CAUGHT {fault.name}: {fault.assertion}", flush=True)
        print(f"{len(faults)}/{len(faults)} expected mutation assertions observed", flush=True)

    def verify_zero_fixtures(self, prefixes):
        for prefix in prefixes:
            if not re.fullmatch(r"[a-f0-9]{8}-", prefix):
                raise HarnessFailure("Invalid fixture prefix")
            self.require_success(f"""do $$ declare t record; n bigint; begin
                for t in select table_schema,table_name from information_schema.columns
                    where table_schema in ('public','auth') and column_name='id' loop
                    execute format('select count(*) from %I.%I where id::text like %L',
                        t.table_schema,t.table_name,'{prefix}%') into n;
                    if n<>0 then raise exception 'Retained fixtures in %.%',t.table_schema,t.table_name; end if;
                end loop;
            end $$;""", "Zero retained fixture rows")
        print("Zero retained fixture rows: " + ", ".join(prefixes), flush=True)

    def all_suites(self):
        paths = sorted((ROOT / "supabase/tests").glob("*.sql"))
        for path in paths:
            self.suite(path)
        fingerprint = json.loads(self.fingerprint())
        retained = {key: count for key, count in fingerprint["rows"].items()
                    if count and key != "auth.schema_migrations"}
        if retained:
            raise HarnessFailure(f"Nonzero data rows after clean-reset regression: {retained}")
        print(f"{len(paths)} SQL suites PASS; zero public/Auth data rows (Auth migration ledger excluded)", flush=True)

    def verify_interruption(self):
        """Simulate Ctrl-C while a real backend holds an uncommitted mutant."""
        definition = replace_once(self.definition('public.get_organization_staff(uuid)'),
                                  'Organization Staff unavailable', 'Interrupted harness fixture')
        executor = ThreadPoolExecutor(max_workers=1)
        pending = None
        try:
            try:
                with self.restored():
                    pending = executor.submit(self.execute,
                        'begin;\n' + definition + '\nselect pg_sleep(60);\nrollback;')
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline:
                        waiting = self.require_success("select exists(select 1 from pg_stat_activity "
                            f"where application_name='{self.application_name}' and wait_event='PgSleep');",
                            'Observe interruptible mutant transaction')
                        if waiting == 't':
                            raise KeyboardInterrupt
                        if pending.done():
                            raise HarnessFailure('Interruption fixture exited early: ' + pending.result().stderr)
                        time.sleep(0.1)
                    raise HarnessFailure('Interruption fixture did not reach its wait')
            except KeyboardInterrupt:
                if pending is None or pending.result(timeout=10).returncode == 0:
                    raise HarnessFailure('Interruption did not abort the mutant backend')
                print('PASS simulated interruption: mutant backend terminated and original definitions/ACLs/data restored', flush=True)
        finally:
            executor.shutdown(wait=True)
