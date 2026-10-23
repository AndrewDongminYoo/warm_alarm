"""Inspection result handling; the Apple Events boundary is mocked."""
import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch


class InspectionTest(unittest.TestCase):
    def inspect(self, output):
        module = runpy.run_path(str(Path(__file__).with_name('demo.py')))
        completed = subprocess.CompletedProcess([], 0, stdout=output, stderr='')
        with patch.object(sys, 'argv', ['demo.py', '--scenario', str(Path(__file__).with_name('scenario-example-qa.json')), '--inspect', '--confirmed-target']), \
                patch.object(subprocess, 'run', return_value=completed), \
                contextlib.redirect_stdout(io.StringIO()) as captured:
            module['main']()
        return captured.getvalue()

    def test_empty_inspection_is_failure(self):
        with self.assertRaisesRegex(RuntimeError, 'No labeled AXButtons found'):
            self.inspect(' \n')

    def test_labeled_inspection_is_printed(self):
        self.assertEqual(self.inspect('Inspect Alarm API, Schedule 1 minute alarm\n'),
                         'Inspect Alarm API, Schedule 1 minute alarm\n')


class MainCueTest(unittest.TestCase):
    def test_unmeasured_framing_templates_cannot_render(self):
        module = runpy.run_path(str(Path(__file__).with_name('edit.py')))
        for name in ('timeline-example-qa.json', 'timeline-b-macos.json'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'framing awaits review'):
                module['load_timeline'](Path(__file__).with_name(name))

    def test_default_has_no_external_actions(self):
        module = runpy.run_path(str(Path(__file__).with_name('demo.py')))
        with patch.object(sys, 'argv', ['demo.py']), patch.object(subprocess, 'run') as external, \
                contextlib.redirect_stdout(io.StringIO()) as captured:
            module['main']()
        external.assert_not_called()
        self.assertIn('MANUAL A/B CUES', captured.getvalue())
        self.assertIn('INPUT REQUIRED', captured.getvalue())

    def test_confirmed_flag_cannot_execute_main_cues(self):
        module = runpy.run_path(str(Path(__file__).with_name('demo.py')))
        for flag in ('--run', '--inspect'):
            with self.subTest(flag=flag), patch.object(sys, 'argv', ['demo.py', flag, '--confirmed-target']), \
                    patch.object(subprocess, 'run') as external, contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit) as error:
                module['main']()
            self.assertEqual(error.exception.code, 2)
            external.assert_not_called()


if __name__ == '__main__':
    unittest.main()
