# Loads the shared SF10 DB (/home/cubrid/databases/tpch_sf10) on a reserved perf server.
# Runs through perfsrv.sh exec, which sets CUBRID to the pushed install and OUT to the run's out/:
#   perfsrv.sh exec <run> <sha12> "$(cat scripts/load-sf10.sh)"
# Volumes as QAHome (data 10G x4, temp 5G x1); the DWB is on for createdb/addvoldb, off for the load, on again at the end.
set -euo pipefail
export CUBRID_DATABASES=/home/cubrid/databases
in=/data/tpch-sf10/sf10; db=tpch_sf10; log=$OUT/sf10; conf=$CUBRID/conf/cubrid.conf
mkdir -p "$log"
ts() { date '+%F %T'; }
dwb() { sed -i '/^double_write_buffer_size=/d' "$conf"; [ "$1" = on ] || echo 'double_write_buffer_size=0' >> "$conf"; echo "dwb=$1 $(ts)"; }
echo "BEGIN $(ts) $(sha256sum "$CUBRID/lib/libcubrid.so.11.5")"
test ! -e "$CUBRID_DATABASES/$db"
trap 'rc=$?; cubrid server stop "$db" > "$log/server-stop.out" 2>&1 || :; dwb on; echo "FINISH rc=$rc $(ts)"' EXIT
dwb on
mkdir -p "$CUBRID_DATABASES/$db"
echo "createdb $(ts)"; (cd "$CUBRID_DATABASES/$db" && cubrid createdb --db-volume-size=10G --log-volume-size=512M "$db" en_US.utf8) > "$log/createdb.out"
for i in 1 2 3; do echo "addvol data $i $(ts)"; cubrid addvoldb -S -p data --db-volume-size=10G "$db" >> "$log/addvol.out"; done
echo "addvol temp $(ts)"; cubrid addvoldb -S -p temp --db-volume-size=5G "$db" >> "$log/addvol.out"
dwb off
cubrid server start "$db" > "$log/server-start.out" 2>&1
echo "schema $(ts)"; cubrid loaddb -C -u dba -s "$in/schema/schema_nopk" "$db" > "$log/schema.out"
echo "data $(ts)"
pids=()
for t in lineitem orders partsupp part customer supplier nation region; do
  cubrid loaddb -C -u dba -d "$in/load_data/$t.load" -t "$t" --no-statistics "$db" > "$log/data-$t.out" 2>&1 &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
echo "index $(ts)"; cubrid loaddb -C -u dba -i "$in/schema/index_all" --no-logging-index "$db" > "$log/index.out"
echo "stats $(ts)"; csql -u dba "$db" -i "$in/schema/stats.sql" > "$log/stats.out"
echo "rowcounts $(ts)"; csql -u dba "$db" -i "$in/schema/rowcounts.sql" > "$log/rowcounts.out"
cubrid spacedb "$db" > "$log/spacedb.out" 2>&1 || :
grep -h 'object(s) inserted' "$log"/data-*.out
cat "$log/rowcounts.out" | grep -E "^ *'"
echo "DONE $(ts)"
