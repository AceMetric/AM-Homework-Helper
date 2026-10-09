#!/usr/bin/env python3
"""Run UI fixtures in isolated storage; quiet fixtures also intercept activation."""
import os
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='quiet-', dir=root / 'build/tests') as directory:
    environment = {k: v for k, v in os.environ.items() if k not in ('GH_TOKEN', 'GITHUB_TOKEN', 'GH_DEBUG', 'GH_CONFIG_DIR')}
    environment['AM_TEST_DATA'] = directory
    result = subprocess.run([*sys.argv[1:], '--quiet-test'], env=environment, cwd=root)
    sys.exit(1 if result.returncode else 0)
