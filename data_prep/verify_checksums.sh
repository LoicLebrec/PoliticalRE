#!/usr/bin/env bash
# Verify the raw/frozen data files pinned in checksums.sha256 haven't changed.
# Run from anywhere; cd's to the repo root itself.
set -euo pipefail
cd "$(dirname "$0")/.."
sha256sum -c data_prep/checksums.sha256
