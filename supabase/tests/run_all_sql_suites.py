"""Runs every LOCAL SQL regression suite under supabase/tests (*.sql).
Run from the repository root after a clean local reset:
python supabase/tests/run_all_sql_suites.py
Each suite must be explicitly rollback-only; afterwards every public/Auth data
table must have zero rows (Auth migration ledger excluded) and public function
definitions/ACLs must be unchanged.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import LocalSql


def main():
    client = LocalSql()
    with client.restored():
        client.all_suites()


if __name__ == "__main__":
    main()
