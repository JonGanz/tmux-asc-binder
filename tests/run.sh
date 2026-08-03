#!/usr/bin/env bash
# Single entrypoint for the test suite: `tests/run.sh` (or `bats tests/`).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec bats tests/
