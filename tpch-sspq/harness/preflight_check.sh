#!/usr/bin/env bash
# TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — stage 14.1 preflight capture.
# SSOT section 14.1: identity / schema / ownership / NUMA / cpuset preflight.
# Also re-verifies the section 7 8-FK/8-child-B-tree gate, the section 8 statistics
# contract, the section 9 parallel + buffer/cache contract and section 6 query
# provenance for the target QNN. Read-only against both engines.
#
# Usage: preflight_check.sh QNN SSOT_COMMIT SSOT_BLOB SESSION_ID
set -uo pipefail

QNN="${1:?usage: preflight_check.sh QNN SSOT_COMMIT SSOT_BLOB SESSION_ID}"
SSOT_COMMIT="${2:?}"
SSOT_BLOB="${3:?}"
SESSION_ID="${4:?}"
N="$((10#${QNN#Q}))"

CAMPAIGN=tpch-sspq-fk-r1-20260730
REPO=/home/cubrid/dev/workspace/tpch-sspq
WS=/home/cubrid/dev/workspace
RAW_ROOT="/data/tpch-sspq/${CAMPAIGN}"
CANON=/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries
PG_PREFIX=/home/cubrid/pg/pg20devel-5713b437
PGDATA_DIR=/home/cubrid/pg/pgdata-tpch-sspq

# shellcheck disable=SC1091
. "${RAW_ROOT}/raw/Q01/campaign-env.sh"

TABLES="region nation supplier customer part partsupp orders lineitem"

echo "TPCH-SSPQ FK campaign preflight — ${QNN}"
echo "campaign_id: ${CAMPAIGN}"
echo "ssot_commit: ${SSOT_COMMIT}"
echo "ssot_blob_sha: ${SSOT_BLOB}"
echo "session_id: ${SESSION_ID}"
echo "captured_at: $(date -Is)"
echo "stage: 14.1 identity/schema/ownership/NUMA/cpuset preflight"

echo
echo "[git]"
echo "HEAD=$(git -C "$WS" rev-parse HEAD)"
echo "origin/main=$(git -C "$WS" rev-parse origin/main)"
echo "branch=$(git -C "$WS" rev-parse --abbrev-ref HEAD)"
echo "SSOT blob at HEAD=$(git -C "$WS" rev-parse HEAD:tpch-sspq/SSOT.md)"
PORC="$(git -C "$WS" status --porcelain -- tpch-sspq)"
echo "porcelain(tpch-sspq)=${PORC:-<empty>}"
if [ "$(git -C "$WS" rev-parse HEAD:tpch-sspq/SSOT.md)" = "${SSOT_BLOB}" ]; then
  echo "ssot_drift=NONE (HEAD blob == pinned blob)"
else
  echo "ssot_drift=SSOT_DRIFT (HEAD blob != pinned blob)"
fi

echo
echo "[ownership gate — SSOT section 10, pre-block]"
for pat in cub_master "cub_server ${CUBRID_DB}" "${PG_PREFIX}/bin/postgres -D ${PGDATA_DIR}"; do
  for pid in $(pgrep -f "$pat"); do
    printf 'pat=%-52s pid=%-8s exe=%s\n' "$pat" "$pid" "$(readlink -f "/proc/${pid}/exe")"
  done
done
echo "port 1523/5442 owners:"
ss -ltnp 2>/dev/null | grep -E '1523|5442' | sed 's/^/  /'
sha256sum "${CUBRID}/bin/cub_server" "${PG_PREFIX}/bin/postgres"
echo "expected from frozen reports/bootstrap/build-manifest.json:"
python3.11 - <<'PY'
import json
m = json.load(open('/home/cubrid/dev/workspace/tpch-sspq/reports/bootstrap/build-manifest.json'))
print('  cubrid    ', m['cubrid']['binary_sha256'], m['cubrid']['binary_path'])
print('  postgresql', m['postgresql']['binary_sha256'], m['postgresql']['binary_path'])
print('  frozen    ', m['frozen'])
PY
echo "PGDATA=$(readlink -f "${PGDATA_DIR}") CUBRID_DB=${CUBRID_DB} CUBRID_DATABASES=${CUBRID_DATABASES}"

echo
echo "[cpuset / NUMA / external load — SSOT section 9]"
numactl --hardware | sed -n '1,7p' | sed 's/^/  /'
python3.11 - <<'PY'
import os, subprocess, time
SUT = set(range(0, 16))
def aff(pid):
    off, tot = [], 0
    for tid in os.listdir(f"/proc/{pid}/task"):
        tot += 1
        try:
            m = os.sched_getaffinity(int(tid))
        except OSError:
            continue
        if not m <= SUT:
            off.append((tid, sorted(m)[:4]))
    return tot, off
def pids(pat, x=False):
    r = subprocess.run(["pgrep"] + (["-x"] if x else ["-f"]) + [pat], capture_output=True, text=True)
    return [int(p) for p in r.stdout.split()]
groups = {}
db = os.environ["CUBRID_DB"]
groups["cub_master"] = pids("cub_master")
groups["cub_server"] = pids(f"cub_server {db}")
pm = pids("/home/cubrid/pg/pg20devel-5713b437/bin/postgres -D /home/cubrid/pg/pgdata-tpch-sspq")
groups["postmaster"] = pm
kids = []
for p in pm:
    r = subprocess.run(["pgrep", "-P", str(p)], capture_output=True, text=True)
    kids += [int(c) for c in r.stdout.split()]
groups["pg_children"] = kids
gt = go = 0
for label, ps in groups.items():
    t = o = 0
    for p in ps:
        a, b = aff(p)
        t += a; o += len(b)
    gt += t; go += o
    print(f"  {label:<12} pids={len(ps):<3} tids={t:<4} off_cpuset={o}")
print(f"  TOTAL engine tids={gt} off_cpuset={go} -> {'PASS' if go == 0 else 'FAIL (invalidate run, reapply affinity)'}")
def snap():
    d = {}
    for line in open("/proc/stat"):
        if line.startswith("cpu") and line[3].isdigit():
            p = line.split(); n = int(p[0][3:])
            if n in SUT:
                v = [int(x) for x in p[1:]]
                d[n] = (v[3] + v[4], sum(v))
    return d
a = snap(); t0 = time.time(); time.sleep(5); b = snap(); dt = time.time() - t0
tk = os.sysconf("SC_CLK_TCK")
busy = sum((b[c][1] - a[c][1]) - (b[c][0] - a[c][0]) for c in a)
v = busy / tk / dt
print(f"  external SUT-set busy = {v:.3f} core-seconds/second (threshold 6.0) -> {'PASS' if v <= 6.0 else 'WAIT / INVALID_BACKGROUND_LOAD'}")
PY
for pid in $(pgrep -f "cub_server ${CUBRID_DB}") $(pgrep -f "${PG_PREFIX}/bin/postgres -D ${PGDATA_DIR}"); do
  echo "  numastat pid=${pid} ($(basename "$(readlink -f "/proc/${pid}/exe")")):"
  numastat -p "$pid" 2>/dev/null | tail -3 | sed 's/^/    /'
done

echo
echo "[row counts: exact COUNT(*), both engines]"
CUB_SQL=""; PG_SQL=""
for t in $TABLES; do
  CUB_SQL="${CUB_SQL}${CUB_SQL:+ union all }select '$t' as t,count(*) as c from $t"
  PG_SQL="${PG_SQL}${PG_SQL:+ union all }select '$t' as t,count(*) as c from $t"
done
csql -u dba "${CUBRID_DB}" -q -N -c "${CUB_SQL};" 2>&1 | tr -d "'" | tr -s ' ' | sed 's/^/  cubrid  /'
psql -Atc "${PG_SQL};" | sed 's/^/  pg      /'

echo
echo "[schema contract — SSOT section 7, 8 FK / 8 child B-tree gate]"
echo "  CUBRID FK-owned B-trees (class,index,key,order):"
csql -u dba "${CUBRID_DB}" -q -N -c "select i.class_name, i.index_name, k.key_attr_name, k.key_order from db_index i, db_index_key k where i.index_name=k.index_name and i.class_name=k.class_name and i.is_foreign_key='YES' order by i.class_name, i.index_name, k.key_order;" 2>&1 | sed 's/^/    /'
echo "  CUBRID FK count = $(csql -u dba "${CUBRID_DB}" -q -N -c "select count(*) from db_index where is_foreign_key='YES';" 2>/dev/null | tr -d ' \n')"
echo "  PostgreSQL FKs (name,convalidated,table,def):"
psql -Atc "select c.conname, c.convalidated, c.conrelid::regclass, pg_get_constraintdef(c.oid) from pg_constraint c where c.contype='f' order by c.conname;" | sed 's/^/    /'
echo "  PostgreSQL idx_fk_* (name,method,def):"
psql -Atc "select i.relname, am.amname, pg_get_indexdef(i.oid) from pg_class i join pg_index x on x.indexrelid=i.oid join pg_am am on am.oid=i.relam where i.relname like 'idx\_fk\_%' order by i.relname;" | sed 's/^/    /'
echo "  PostgreSQL counts (fk, idx_fk_*, convalidated) = $(psql -Atc "select (select count(*) from pg_constraint where contype='f')||'/'||(select count(*) from pg_class where relname like 'idx\_fk\_%' and relkind='i')||'/'||(select count(*) from pg_constraint where contype='f' and convalidated);")"

echo
echo "[statistics — SSOT section 8]"
cubrid paramdump "${CUBRID_DB}" 2>/dev/null | grep -iE 'histogram' | sed 's/^/  cubrid  /'
psql -Atc "select 'default_statistics_target='||setting from pg_settings where name='default_statistics_target';" | sed 's/^/  pg      /'
echo "  pg per-table reltuples/relpages and ANALYZE state:"
psql -Atc "select c.relname||' reltuples='||c.reltuples||' relpages='||c.relpages||' last_analyze='||coalesce(s.last_analyze::text,'never')||' last_autoanalyze='||coalesce(s.last_autoanalyze::text,'never') from pg_class c join pg_stat_user_tables s on s.relid=c.oid order by c.relname;" | sed 's/^/    /'

echo
echo "[parallel + buffer/cache contract — SSOT section 9]"
cubrid paramdump "${CUBRID_DB}" 2>/dev/null | grep -iE '^\[S.\] (parallelism|max_parallel_workers|data_buffer_size)|^\[S \] (parallelism|max_parallel_workers|data_buffer_size)' | sed 's/^/  cubrid  /'
psql -Atc "select name||' = '||setting||coalesce(' '||unit,'') from pg_settings where name in ('max_parallel_workers_per_gather','max_parallel_workers','parallel_leader_participation','max_worker_processes','shared_buffers','statement_timeout','jit') order by name;" | sed 's/^/  pg      /'
echo "  label: configured node/gather-cap comparison; configured-equal buffer budget"

echo
echo "[stored size of ${QNN} referenced relations]"
echo "  CUBRID (heap pages x 16 KiB):"
for t in $TABLES; do
  # non-executing plan dump prints dba.<t>(<cardinality>/<heap pages>); 16 KiB pages
  line="$(csql -u dba "${CUBRID_DB}" -q -N --no-pager -c "SET OPTIMIZATION LEVEL 514; select count(*) from ${t};" 2>/dev/null | grep -oE "dba\.${t}\([0-9]+/[0-9]+\)" | head -1)"
  pages="${line##*/}"; pages="${pages%)}"
  if [ -n "${pages}" ]; then
    printf '    %-10s card/pages=%-24s heap=%s MiB\n' "$t" "${line#dba.${t}}" "$(awk "BEGIN{printf \"%.1f\", ${pages}*16384/1048576}")"
  else
    printf '    %-10s <page count unavailable>\n' "$t"
  fi
done
echo "  PostgreSQL (relpages x 8 KiB, plus index size):"
psql -Atc "select relname||' relpages='||relpages||' heap='||pg_size_pretty(pg_relation_size(oid))||' total='||pg_size_pretty(pg_total_relation_size(oid)) from pg_class where relkind='r' and relnamespace='public'::regnamespace order by relname;" | sed 's/^/    /'

echo
echo "[query provenance ${QNN} — SSOT section 6]"
sha256sum "${CANON}/q${N}.sql" "${REPO}/queries/q${N}-cubrid.sql" "${REPO}/queries/q${N}-pg.sql" | sed 's/^/  /'
if cmp -s "${CANON}/q${N}.sql" "${REPO}/queries/q${N}-cubrid.sql"; then
  echo "  active queries/q${N}-cubrid.sql byte-match canonical = OK"
else
  echo "  active queries/q${N}-cubrid.sql byte-match canonical = FAIL"
fi
echo "  dialect diff queries/diff/q${N}.diff ($(stat -c%s "${REPO}/queries/diff/q${N}.diff") bytes):"
if [ -s "${REPO}/queries/diff/q${N}.diff" ]; then
  sed 's/^/    /' "${REPO}/queries/diff/q${N}.diff"
else
  echo "    <empty> — PostgreSQL dialect is byte-identical to the canonical CUBRID file"
  cmp -s "${REPO}/queries/q${N}-cubrid.sql" "${REPO}/queries/q${N}-pg.sql" \
    && echo "    verified: cmp q${N}-cubrid.sql q${N}-pg.sql identical (zero dialect changes)" \
    || echo "    WARNING: files differ but diff artifact is empty"
fi

echo
echo "[engine block order — SSOT section 12]"
if [ $((N % 2)) -eq 0 ]; then
  echo "  ${QNN} is even -> PostgreSQL block first, then CUBRID block"
else
  echo "  ${QNN} is odd  -> CUBRID block first, then PostgreSQL block"
fi
echo
echo "preflight complete"
