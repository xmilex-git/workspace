#!/usr/bin/env bash
# IMP-015 D6 two-layer TC orchestrator (CTP-shell-style arming proof).
# Runs the battery on the immutable base install and on install/IMP-015,
# asserts the layer-2 arming proof per variant inside imp015_tc.py, then does
# the section 6-b layer-1 exact comparison across variants.
#
# Usage: imp015_tc.sh [OUT_ROOT]
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="${1:-/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-015/tc}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT_ROOT}/${STAMP}"
mkdir -p "$OUT"

python3.11 "${HARNESS}/imp015_tc.py" run --variant base    --outdir "${OUT}/base"
python3.11 "${HARNESS}/imp015_tc.py" run --variant IMP-015 --outdir "${OUT}/IMP-015"
python3.11 "${HARNESS}/imp015_tc.py" compare "${OUT}/base" "${OUT}/IMP-015"

echo "IMP015-TC: ALL PASS (${OUT})"
