#!/usr/bin/env bash
# Copies the fixture app into the empty eval workspace.
set -euo pipefail
cp -R "$(dirname "$0")/fixture/." .
