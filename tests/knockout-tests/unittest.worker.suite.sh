#!/usr/bin/env bash
# Runs the Python unittest tests (tests/test_*.py) with knockout.sh: one process, a fork per test.
cd "$(dirname "$0")/../.." && exec knockout.sh python3-unittest discover -s tests "$@"
