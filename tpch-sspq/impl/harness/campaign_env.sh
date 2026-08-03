#!/usr/bin/env bash
# TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — shell-side
# pinned environment.
#
# IMPL-SSOT section 8-b requires the campaign-local copy to set the external-load
# THRESHOLD "explicitly from the pinned section 3-a value, never inherited by
# coincidence". The inherited shell scripts each carried their own `THRESHOLD=6.0`
# literal; here every shell script sources this file, which derives the value from
# campaign_config.py — the same single source the Python side uses. A future
# amendment to the gate therefore cannot be silently ignored by a stale constant.
#
# Usage: . "$(dirname "$0")/campaign_env.sh"
set -u

TPCH_SSPQ_HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TPCH_SSPQ_HARNESS

_cfg() { python3.11 -c "
import sys; sys.path.insert(0, '${TPCH_SSPQ_HARNESS}')
import campaign_config as c; print(getattr(c, '$1'))
"; }

CAMPAIGN="$(_cfg CAMPAIGN)"
RAW_ROOT="$(_cfg RAW_ROOT)"
IMPL_SSOT_COMMIT="$(_cfg IMPL_SSOT_COMMIT)"
IMPL_SSOT_BLOB="$(_cfg IMPL_SSOT_BLOB)"
CUBRID_HOME="$(_cfg CUBRID_HOME)"
CUBRID_DB="$(_cfg CUBRID_DB)"
CUBRID_DATABASES="$(_cfg CUBRID_DATABASES)"
CUBRID_TMP="$(_cfg CUBRID_TMP)"
CUBRID_PORT="$(_cfg CUBRID_PORT)"
CONF_SHA256="$(_cfg CONF_SHA256)"
SUT_CPUS="$(_cfg SUT_CPUS)"
COLLECTOR_CPUS="$(_cfg COLLECTOR_CPUS)"
MEMBIND_NODE="$(_cfg MEMBIND_NODE)"
# Section 3-a / AMEND-D. Explicit, from the pin — never an inherited literal.
THRESHOLD="$(_cfg EXTERNAL_LOAD_THRESHOLD)"
N_BLOCKS="$(_cfg N_BLOCKS)"

export CAMPAIGN RAW_ROOT IMPL_SSOT_COMMIT IMPL_SSOT_BLOB
export CUBRID_HOME CUBRID_DB CUBRID_DATABASES CUBRID_TMP CUBRID_PORT CONF_SHA256
export SUT_CPUS COLLECTOR_CPUS MEMBIND_NODE THRESHOLD N_BLOCKS

# The pinned client environment (section 6-a-2 / section 3-b).
export CUBRID="$CUBRID_HOME"
export LD_LIBRARY_PATH="$CUBRID_HOME/lib:$CUBRID_HOME/cci/lib"
export PATH="$CUBRID_HOME/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"

# Section 6-a-2 mandatory pre-run assertions, enforced at source time so no
# script that sources this file can run a block with the wrong temp dir or an
# unpinned cubrid.conf.
mkdir -p "$CUBRID_TMP"
if [ ! -d "$CUBRID_TMP" ]; then
  echo "FATAL campaign temp dir $CUBRID_TMP missing" >&2; exit 1
fi
case "$CUBRID_TMP" in
  /tmp|/tmp/*|"${TMPDIR:-/nonexistent}"*)
    echo "FATAL CUBRID_TMP resolves under /tmp — forbidden by section 8-e" >&2; exit 1 ;;
esac
_conf_got="$(sha256sum "$CUBRID_HOME/conf/cubrid.conf" | cut -d' ' -f1)"
if [ "$_conf_got" != "$CONF_SHA256" ]; then
  echo "FATAL $CUBRID_HOME/conf/cubrid.conf sha256 $_conf_got != pinned $CONF_SHA256 (section 6-a-2)" >&2
  exit 1
fi
unset _conf_got
