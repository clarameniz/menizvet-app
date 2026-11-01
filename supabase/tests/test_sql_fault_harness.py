"""Negative controls for permanent SQL mutation evidence and restoration."""
import subprocess
import unittest
from unittest.mock import patch

from sql_fault_harness import Fault, HarnessFailure, LocalSql


class FaultEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.client = LocalSql()
        self.fault = Fault('probe','select 1;','EXPECTED')
        self.source = 'begin;\nrollback;'

    def result(self, stderr, code=1):
        return subprocess.CompletedProcess([],code,'',stderr)

    def check_rejected(self, stderr, code=1):
        with patch.object(self.client,'execute',return_value=self.result(stderr,code)):
            with self.assertRaises(HarnessFailure):
                self.client.faults(self.source,[self.fault])

    def test_exact_expected_assertion_is_accepted(self):
        with patch.object(self.client,'execute',return_value=self.result(
                'ERROR:  P0001: EXPECTED\nCONTEXT: PL/pgSQL function pg_temp_17.assert_true(boolean,text) line 2 at RAISE\n')):
            self.client.faults(self.source,[self.fault])

    def test_generic_error_and_context_are_not_evidence(self):
        self.check_rejected('ERROR: syntax error\nCONTEXT: PL/pgSQL function pg_temp_17.assert_true(boolean,text)\n')

    def test_wrong_assertion_is_rejected(self):
        self.check_rejected('ERROR: P0001: OTHER\nCONTEXT: PL/pgSQL function pg_temp_17.assert_true(boolean,text)\n')

    def test_wrong_sqlstate_is_rejected(self):
        self.check_rejected('ERROR: 42501: EXPECTED\nCONTEXT: PL/pgSQL function pg_temp_17.assert_true(boolean,text)\n')

    def test_wrong_raising_function_is_rejected(self):
        self.check_rejected('ERROR: P0001: EXPECTED\nCONTEXT: PL/pgSQL function public.some_operation()\n')

    def test_infrastructure_failure_is_rejected(self):
        self.check_rejected('permission denied while connecting to Docker')

    def test_surviving_mutant_is_rejected(self):
        self.check_rejected('',code=0)

    def test_interrupt_runs_cleanup_and_checks_restoration(self):
        with patch.object(self.client,'fingerprint',side_effect=['original','original']) as fingerprint, \
                patch.object(self.client,'terminate_sessions') as terminate:
            with self.assertRaises(KeyboardInterrupt):
                with self.client.restored():
                    raise KeyboardInterrupt
            terminate.assert_called_once()
            self.assertEqual(fingerprint.call_count,2)

    def test_changed_definition_or_row_counts_fail_restoration(self):
        with patch.object(self.client,'fingerprint',side_effect=['original','changed']), \
                patch.object(self.client,'terminate_sessions'):
            with self.assertRaises(HarnessFailure):
                with self.client.restored():
                    pass


if __name__ == '__main__':
    unittest.main()
