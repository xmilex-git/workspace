#!/usr/bin/env bash
# Regenerate KeyRewindTraceData.tla from traces/raw/*.log.xz (run from docs/tla/CBRD-28030).
set -euo pipefail
conv() { TRACE_LABEL="raw/$1.log.xz" python3 -I traces/convert.py <(xzcat "traces/raw/$1.log.xz") "$2" auto "$3" ${4:-}; }
{
  echo '---- MODULE KeyRewindTraceData ----'
  echo 'EXTENDS Sequences'
  conv n1 N1 6500,7000
  conv n2 N2 6500,7000
  conv n3 N3 6500,7000
  conv n4 N4 1,2
  conv n5 N5 1,2
  conv n1 R1 6500,7000 stale-off
  conv n2 R2 6500,7000 skip-leaf
  conv n5 R3 1,2 count-off
  echo '===='
} > KeyRewindTraceData.tla
