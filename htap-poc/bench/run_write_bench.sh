#!/usr/bin/env bash
# #61 ① supplemental logging overhead — 단일 run: t_bench 재생성 후
# bulk/single 두 페이즈를 각각 벽시계로 측정, CSV 한 줄 출력.
#   usage: run_write_bench.sh <db> <sqldir> <label>
# 선행: CUBRID/CUBRID_DATABASES/PATH 환경이 격리 설치본으로 설정돼 있을 것,
#       서버 기동 상태, gen_workload.py 산출물이 <sqldir>에 있을 것.
set -euo pipefail
DB="${1:?db}"; SQLDIR="${2:?sqldir}"; LABEL="${3:?label}"

CSQL=(csql -u dba --no-auto-commit "$DB")

"${CSQL[@]}" -i "$SQLDIR/bench_setup.sql" >/dev/null

t0=$(date +%s.%N)
"${CSQL[@]}" -i "$SQLDIR/bench_bulk.sql" >/dev/null
t1=$(date +%s.%N)
"${CSQL[@]}" -i "$SQLDIR/bench_single.sql" >/dev/null
t2=$(date +%s.%N)

bulk=$(echo "$t1 $t0" | awk '{printf "%.3f", $1-$2}')
single=$(echo "$t2 $t1" | awk '{printf "%.3f", $1-$2}')
echo "RESULT,$LABEL,bulk_s=$bulk,single_s=$single"
