# Loads the shared SF10 DB (/home/cubrid/databases/tpch_sf10) on a reserved perf server.
# Runs through perfsrv.sh exec, which sets CUBRID to the pushed install and OUT to the run's out/:
#   perfsrv.sh exec <run> <sha12> "$(cat scripts/load-sf10.sh)"
# Volumes as QAHome (data 10G x4, temp 5G x1); the DWB is on for createdb/addvoldb, off for the load, on again at the end.
# SA mode, one table after another, so each table's sectors stay contiguous (P8); SA ignores --no-logging-index.
# Nothing else runs in the container meanwhile: the SA process holds data_buffer_size (P9).
set -euo pipefail
export CUBRID_DATABASES=/home/cubrid/databases
in=/data/tpch-sf10/sf10; db=tpch_sf10; log=$OUT/sf10; conf=$CUBRID/conf/cubrid.conf
mkdir -p "$log"
ts() { date '+%F %T'; }
dwb() { sed -i '/^double_write_buffer_size=/d' "$conf"; [ "$1" = on ] || echo 'double_write_buffer_size=0' >> "$conf"; echo "dwb=$1 $(ts)"; }
echo "BEGIN $(ts) $(sha256sum "$CUBRID/lib/libcubrid.so.11.5")"
test ! -e "$CUBRID_DATABASES/$db"   # deletedb leaves an empty lob/ dir: rmdir it and the db dir first
trap 'rc=$?; dwb on; echo "FINISH rc=$rc $(ts)"' EXIT
dwb on
mkdir -p "$CUBRID_DATABASES/$db"
echo "createdb $(ts)"; (cd "$CUBRID_DATABASES/$db" && cubrid createdb --db-volume-size=10G --log-volume-size=512M "$db" en_US.utf8) > "$log/createdb.out"
for i in 1 2 3; do echo "addvol data $i $(ts)"; cubrid addvoldb -S -p data --db-volume-size=10G "$db" >> "$log/addvol.out"; done
echo "addvol temp $(ts)"; cubrid addvoldb -S -p temp --db-volume-size=5G "$db" >> "$log/addvol.out"
dwb off
echo "schema $(ts)"; cubrid loaddb -S -u dba -s "$in/schema/schema_nopk" "$db" > "$log/schema.out"
for t in region nation supplier customer part partsupp orders lineitem; do
  echo "data $t $(ts)"; cubrid loaddb -S -u dba -d "$in/load_data/$t.load" -t "$t" --no-statistics "$db" > "$log/data-$t.out" 2>&1
done
echo "index $(ts)"; cubrid loaddb -S -u dba -i "$in/schema/index_all" "$db" > "$log/index.out"
echo "stats $(ts)"; csql -S -u dba "$db" -i "$in/schema/stats.sql" > "$log/stats.out"
echo "rowcounts $(ts)"; csql -S -u dba "$db" -i "$in/schema/rowcounts.sql" > "$log/rowcounts.out"
cubrid spacedb -S "$db" > "$log/spacedb.out" 2>&1 || :
grep -h 'object(s) inserted' "$log"/data-*.out
grep -E "^ *'" "$log/rowcounts.out"
echo "DONE $(ts)"
