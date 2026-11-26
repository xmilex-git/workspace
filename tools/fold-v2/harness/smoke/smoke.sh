#!/bin/bash
# cas-fold-v2 wire smoke: the cases the env-gated in-process tracer ran until B2, now through a DIRECT_HANDOFF
# broker and JDBC (WireTracer.java honors the tracer's CUBRID_M0_TRACER_* environment and prints its lines), then require
# "M0_TRACER: SUCCESS" (and "first value = <expect>" when given) and no core/assert.
# Usage: smoke.sh <install> <dbdir> <db>   (db already created in <dbdir>, server not running).  Applies the session
#        conf and a one-broker cubrid_broker.conf to the install and restores both on exit.
#        ENVX="VAR=v ..." is added to the server's environment (the memory check).
# A case is "SQL" or "SQL@@expect"; CASE_ENV[<n>] holds tracer env for case <n> (1-based, "VAR=value" words
# eval'ed into an array) and CASE_EVENT[<n>] a pattern the server event log must gain during the case.
# A4: CASE_COUNT[<n>] = how many "first value" lines (one per session) the case must print; CASE_OUTCOME[<n>] = a
# regex the tracer output must match instead of SUCCESS; CASE_CSQL[<n>] = statements a CS csql session runs
# alongside the tracer; CASE_HOLD[<n>] = seconds the server stays up after the tracer finished (session expiry,
# session_state_timeout=60 in the session conf).
# A5: CASE_VALUES[<n>] = first values (one per session, space-separated, in any order) the case must print; the
# session conf carries update_use_attribute_references=yes (case 25, a client parameter loaded from the conf) and
# test_mode=yes (case 27 changes the test-only ansi_quotes).
# A6: CASE_ALSO[<n>] = a regex the tracer output must also match (besides SUCCESS or CASE_OUTCOME).
# A7: PL/CSQL routines are created in a fixture through a CS csql session (cub_pl compiles them); the cases call them
# from the tracer, whose callbacks now end on the tracer thread.
# A8: the parser's nesting limit (cases 49-51).
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
WS=/home/cubrid/dev/workspace
HERE=$WS/.git_ignored_dir/scratch/fold-v2/smoke
OUT=$HERE/out-${TAG:-$(basename "$(dirname "$INST")")}
mkdir -p "$OUT/java" "$OUT/confbak"
WPORT=36713
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
cp -p "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$OUT/confbak/"
broker() { cubrid broker "$@" < /dev/null > "$OUT/broker-$1.out" 2>&1; }
cleanup() {
  broker stop
  "$CTL" stop "$DB" > "$OUT/final.stop" 2>&1
  cp -p "$OUT/confbak/cubrid.conf" "$OUT/confbak/cubrid_broker.conf" "$INST/conf/"
}
trap cleanup EXIT
(cd $WS && CONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf} CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
cat > "$INST/conf/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36795
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%WT]
SERVICE                 =ON
BROKER_PORT             =$WPORT
MIN_NUM_APPL_SERVER     =10
MAX_NUM_APPL_SERVER     =10
APPL_SERVER_SHM_ID      =36796
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =ON
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =${HANDOFF:-ON}
EOC
javac -d "$OUT/java" "$HERE/WireTracer.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
# fixtures (SA, server down): a1t.r's domain class is dropped (deleted-class downgrade); a1p.o is a live OBJECT
FIXTURE="drop table if exists a1t, a1ref, a1p, a1o, a3s, a3d, a4r, a5u, a5s, a6t, a6o, a6r, a6q, a6d, a7t, a7e, a7l;
create table a7t (id int primary key, v int); insert into a7t values (1, 10), (2, 20), (3, 30);
create table a7e (id int); create table a7l (id int);
drop table if exists a7k, a7cnt; create table a7k (k int); insert into a7k values (1), (1), (1); create table a7cnt (x int);
drop table if exists a7big; create table a7big (id int, c char(2000)); insert into a7big select rownum, 'x' from db_class a, db_class b limit 4000;
drop class if exists a7m; create class a7m (x int) method class a7m_f () int function a7m_func file '/nonexistent/a7m.o';
create table a6t (x int); insert into a6t values (1), (2); create table a6o (x int); insert into a6o values (1);
create table a6r (x int); insert into a6r values (1), (2), (3); create table a6q (x int); insert into a6q values (4);
create table a6d (x int primary key, y int unique); insert into a6d values (1, 1);
create table a5u (id int primary key, x int, y int); insert into a5u values (1, 1, 0);
create table a3d (id int primary key, x int); insert into a3d values (1, 1), (2, 2);
create table a4r (id int primary key, x int); insert into a4r values (1, 1), (2, 2);
create table a1ref (x int) dont_reuse_oid; create table a1t (id int, r a1ref);
insert into a1ref values (7); insert into a1t select 1, a1ref from a1ref; drop table a1ref;
create table a1o (x int) dont_reuse_oid; create table a1p (id int, o a1o);
insert into a1o values (5); insert into a1p select 1, a1o from a1o;"
(cd "$DBDIR" && csql -S -u dba -c "$FIXTURE" "$DB" < /dev/null > "$OUT/fixture.out" 2>&1) || { echo "ABORT: fixture"; tail -5 "$OUT/fixture.out"; exit 2; }
(cd "$DBDIR" && csql -S -u dba -c "drop user a3u" "$DB" < /dev/null > /dev/null 2>&1)   # left by an interrupted run; absent is fine
# A6: the grantee of the REVOKE cases (a6d: DROP of an indexed class that has a grant)
(cd "$DBDIR" && csql -S -u dba -c "drop user a6u" "$DB" < /dev/null > /dev/null 2>&1)
(cd "$DBDIR" && csql -S -u dba -c "create user a6u; grant select on a6t to a6u; grant select on a6o to a6u; grant select on a6r to a6u; grant select on a6q to a6u; grant select on a6d to a6u" "$DB" < /dev/null >> "$OUT/fixture.out" 2>&1) || { echo "ABORT: fixture user a6u"; exit 2; }
# A5: a user who is not a DBA (SET of a server parameter)
(cd "$DBDIR" && csql -S -u dba -c "drop user a5n" "$DB" < /dev/null > /dev/null 2>&1)
(cd "$DBDIR" && csql -S -u dba -c "create user a5n; grant select on a3d to a5n" "$DB" < /dev/null >> "$OUT/fixture.out" 2>&1) || { echo "ABORT: fixture user a5n"; exit 2; }
# A7: the user the builtin method case creates, and the PL/CSQL routines (cub_pl compiles them: a CS session)
(cd "$DBDIR" && csql -S -u dba -c "drop user a7x" "$DB" < /dev/null > /dev/null 2>&1)
"$CTL" start "$DB" > "$OUT/a7-routines.start" 2>&1 || { echo "ABORT: start for A7 routines"; exit 2; }
(cd "$DBDIR" && csql -u dba -i /home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2/smoke/a7-routines.sql "$DB" < /dev/null > "$OUT/a7-routines.out" 2>&1); rc=$?
"$CTL" stop "$DB" > "$OUT/a7-routines.stop" 2>&1
[ $rc -eq 0 ] && ! grep -q 'ERROR' "$OUT/a7-routines.out" || { echo "ABORT: A7 routines"; tail -5 "$OUT/a7-routines.out"; exit 2; }
EXPECT_DB_CLASS=${EXPECT_DB_CLASS:-$(cd "$DBDIR" && csql -S -u dba -l -c "select count(*) from db_class" "$DB" < /dev/null 2>/dev/null | awk '/count/{print $NF}')}
Q19="SELECT COUNT(*) FROM _db_class a, _db_class b WHERE a.class_of = b.class_of AND a.is_system_class = 1"
EXPECT_SYS=${EXPECT_SYS:-$(cd "$DBDIR" && csql -S -u dba -l -c "$Q19" "$DB" < /dev/null 2>/dev/null | awk '/count/{print $NF}')}
CASES=(
  "SELECT 1@@1"
  "SELECT COUNT(*) FROM db_class@@${EXPECT_DB_CLASS}"
  "SELECT COUNT(*) FROM _db_class a, _db_class b WHERE a.class_of = b.class_of"
  # A1: authorization resolves through the session context
  "SELECT CURRENT_USER@@'DBA'"
  # A1: deleted-class downgrade runs on the bracketed client half (else -494)
  "SELECT r IS NULL FROM a1t@@1"
  # A1: OBJECT attribute path and OBJECT comparison
  "SELECT p.o.x FROM a1p p@@5"
  "SELECT COUNT(*) FROM a1p p, a1o o WHERE p.o = o@@1"
  # A2: per-thread parser state on the tracer thread — hint table (sorted per thread) with args,
  # nested save/restore stacks, ORDERBY_NUM/INST_NUM checks, string escapes, CONNECT BY
  "SELECT /*+ ORDERED USE_NL(b) INDEX_SS(a) NO_MERGE */ COUNT(*) FROM _db_class a, _db_class b WHERE a.class_of = b.class_of AND a.class_name IN (SELECT c.class_name FROM _db_class c WHERE c.class_name = 'db_root')@@1"
  "SELECT v FROM (SELECT ROWNUM AS v FROM db_class WHERE ROWNUM <= 3 ORDER BY 1 DESC) t ORDER BY v FOR ORDERBY_NUM () = 2@@2"
  "SELECT 'it''s' || 'x'@@'it''sx'"
  "SELECT MAX(LEVEL) FROM (SELECT 1 AS id, NULL AS pid UNION ALL SELECT 2, 1 UNION ALL SELECT 3, 2) t START WITH pid IS NULL CONNECT BY PRIOR id = pid@@3"
  # A2: recursive CTE whose non-recursive part is NULL-typed (CTE NULL readers per thread)
  "WITH RECURSIVE r (n, s) AS (SELECT 1, NULL UNION ALL SELECT n + 1, 'x' FROM r WHERE n < 4) SELECT COUNT(*) FROM r@@4"
  # A2: JSON_TABLE column counter
  "SELECT COUNT(*) FROM JSON_TABLE ('[{\"a\":1},{\"a\":2}]', '\$[*]' COLUMNS (rid FOR ORDINALITY, a INT PATH '\$.a')) AS jt@@2"
  # A3: host variables cross into xqmgr_execute_query as a native DB_VALUE array
  "SELECT ? + ?@@42"
  # A3: REPEATABLE READ takes the RR transaction lock through tran_lock_rep_read / the lockhint request
  "SELECT COUNT(*) FROM a1p@@1"
  # A3: KILL runs in the folded server (the SA stub returned ER_FAILED); an unknown target is not an error
  "SELECT 1@@1"
  # A3: DDL start info on the tdes, then UPDATE STATISTICS ON ALL CLASSES progress in the event log
  "SELECT COUNT(*) FROM a3s@@0"
  # A3: DROP USER asks the server whether the user is logged in (A6: CREATE USER folded too, the set mutators)
  "SELECT COUNT(*) FROM db_user WHERE name = 'A3U'@@0"
  # A4: concurrent in-process sessions, each with its own client context (workspace, tm, sm, tr, db state)
  "${Q19}@@${EXPECT_SYS}"
  # A4: ROLLBACK decaches through the session workspace heap (A3: mspace_free abort)
  "SELECT x FROM a4r WHERE id = 1@@1"
  # A4: a session ended from inside its own bracket: the bracket exit retires the orphaned context
  "SELECT ? + ?@@42"
  # A4: REPEATABLE READ mirrors per session
  "SELECT COUNT(*) FROM a1p@@1"
  # A4: deadlock with a CS session; a victim tracer's client reaction aborts through the session workspace
  "SELECT 1"
  # A4: the session-control daemon expires the sessions and retires their contexts (teardown off any bracket)
  "SELECT COUNT(*) FROM a4r@@2"
  # A5: a client parameter of the conf reaches the folded client half (the server loads the client parameters)
  "SELECT y FROM a5u WHERE id = 1@@5"
  # A5: the client half reads the client-only session parameter it set (session read-through)
  "SELECT is_reuse_oid_class FROM db_class WHERE class_name = 'a5s'@@'NO'"
  # A5: a client-compile parameter one session set is its own (S1's ansi_quotes=no reads "id" as a string, S2's
  # default as the column)
  "SELECT \"id\" FROM a3d WHERE id = 1"
  # A5: a server-session parameter one session set is its own
  "SELECT LENGTH('a\\nb')"
  # A5: the plan-cache key prints the session's values (same text, two time zones)
  "SELECT TO_CHAR(DATETIMETZ '2026-11-07 10:00:00', 'TZH:TZM')"
  # A5: a server parameter needs a DBA (the client's scope rules in the bracket): the PRE fails with -140
  "SELECT COUNT(*) FROM a3d"
  # A5: a DBA's SET of a server parameter reaches the server (the folded server leg applies the server's rules)
  "SELECT GROUP_CONCAT('abcdefgh')@@'abcd'"
  # A5: the SHOW metadata outlives the session whose boot came first (it lives in the server boot's context)
  "SHOW HEAP HEADER OF a4r"
  # A5: the teardown frees the session's client state (savepoints, query results, triggers, schema, authorization)
  "SELECT 1@@1"
  # A6: a REVOKE committed by another session invalidates the kept plan; the recompile checks the grant again
  "SELECT COUNT(*) FROM dba.a6t@@2"
  # A6 H1 (RC): a compile that waited for the REVOKE's class lock read the grant with a statement snapshot taken
  # before the commit; its plan must not serve the kept statement in a later transaction
  "SELECT COUNT(*) FROM dba.a6o, dba.a6r"
  # A6 H1 (RR): the same with a transaction snapshot taken before the REVOKE's commit
  "SELECT COUNT(*) FROM dba.a6q"
  # A6: DROP of an indexed class with a grant revokes (and touches the class) before freeing the disk structures
  "SELECT COUNT(*) FROM db_class WHERE class_name = 'a6d'@@0"
  # A7: a PL/CSQL function with static SQL: the runtime callbacks (prepare, execute, fetch) end on the tracer thread
  "SELECT a7f (2)@@2"
  # A7: a routine catches the NO_DATA_FOUND of its callback query; the outer query must not see that error
  "SELECT a7g (2)@@-1"
  # A7: nested routines (two dispatch levels)
  "SELECT a7h (3)@@3"
  # A7: COMMIT inside a cursor loop of a procedure: the end-transaction callback runs while the outer executor and
  # the loop's query are suspended on this thread
  "SELECT COUNT(*) FROM a7l@@3"
  # A7: a routine recursing past METHOD_MAX_RECURSION_DEPTH fails cleanly (CASE_ENV replaces the statement)
  "SELECT a7f (3)"
  # A7: a builtin static method (runtime arguments, an object result back into the server executor)
  "SELECT COUNT(*) FROM db_user WHERE name = 'A7X'@@1"
  # A7: a user-defined native C method is refused before dynamic linking (-237)
  "SELECT 1"
  # A7: two sessions run routines with COMMIT at once, each with its own callback handler
  "SELECT a7f (3)@@3"
  # A7: a routine's callback query runs nested while the outer query scans in parallel
  "SELECT /*+ PARALLEL(4) */ COUNT(a7f (1)) FROM a7big@@4000"
  # A7: a routine that is not DETERMINISTIC keeps its correlated subquery out of the subquery cache: it runs once per
  # row (1 + 2 + 3), not once per key (1 + 1 + 1)
  "SELECT SUM (v) FROM (SELECT (SELECT a7n (t.k) FROM dual) AS v FROM a7k t) s@@6"
  # A7: a PARALLEL_ENABLE routine (no SQL) runs in the parallel scan's workers of a folded session
  "SELECT /*+ PARALLEL(4) */ SUM (a7p (id)) FROM a7big@@8006000"
  # A8: an expression nested past the parser's limit (16384) is a statement error, not a stack overflow
  "SELECT $(printf '1+%.0s' $(seq 1 16385))1"
  # A8: an expression nested just inside the limit compiles and runs on the server thread's stack
  "SELECT $(printf '1+%.0s' $(seq 1 16383))1@@16384"
  # A8: a 5,000-term AND chain (the regression suites' stress shape)
  "SELECT COUNT(*) FROM a7t WHERE $(printf 'id > 0 AND %.0s' $(seq 1 4999))id > 0@@3"
)
declare -A CASE_ENV CASE_EVENT CASE_COUNT CASE_OUTCOME CASE_CSQL CASE_HOLD
CASE_ENV[14]="CUBRID_M0_TRACER_BIND=30,12"
CASE_ENV[15]="CUBRID_M0_TRACER_ISOLATION=RR"
CASE_ENV[16]="CUBRID_M0_TRACER_PRE='KILL QUERY 9999'"
CASE_ENV[17]="CUBRID_M0_TRACER_PRE='CREATE TABLE a3s (x INT); UPDATE STATISTICS ON ALL CLASSES'"
CASE_EVENT[17]="progress: statistics finished"
CASE_ENV[18]="CUBRID_M0_TRACER_PRE='CREATE USER a3u; DROP USER a3u'"
CASE_ENV[19]="CUBRID_M0_TRACER_SESSIONS=8"; CASE_COUNT[19]=8
CASE_ENV[20]="CUBRID_M0_TRACER_SESSIONS=4 CUBRID_M0_TRACER_PRE='UPDATE a4r SET x = 3 WHERE id = 1; ROLLBACK'"; CASE_COUNT[20]=4
CASE_ENV[21]="CUBRID_M0_TRACER_SESSIONS=4 CUBRID_M0_TRACER_BIND=30,12 CUBRID_M0_TRACER_END=1"; CASE_COUNT[21]=4
CASE_ENV[22]="CUBRID_M0_TRACER_SESSIONS=4 CUBRID_M0_TRACER_ISOLATION=RR"; CASE_COUNT[22]=4
CASE_ENV[23]="CUBRID_M0_TRACER_PRE='UPDATE a3d SET x = 3 WHERE id = 1; SELECT SLEEP (2); UPDATE a3d SET x = 3 WHERE id = 2'"
CASE_CSQL[23]="UPDATE a3d SET x = 2 WHERE id = 2; SELECT SLEEP (4); UPDATE a3d SET x = 2 WHERE id = 1; COMMIT;"
CASE_OUTCOME[23]='M0_TRACER: (SUCCESS|S1 FAIL pre statement err=-72 )'
CASE_ENV[24]="CUBRID_M0_TRACER_SESSIONS=2"; CASE_COUNT[24]=2; CASE_HOLD[24]=130
declare -A CASE_VALUES
CASE_ENV[25]="CUBRID_M0_TRACER_PRE='UPDATE a5u SET x = 5, y = x WHERE id = 1'"
CASE_ENV[26]="CUBRID_M0_TRACER_PRE=\"SET SYSTEM PARAMETERS 'create_table_reuseoid=no'; CREATE TABLE a5s (x INT)\""
CASE_ENV[27]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_PRE_S1=\"SET SYSTEM PARAMETERS 'ansi_quotes=no'\" CUBRID_M0_TRACER_PRE_S2='SELECT SLEEP (1)'"
CASE_VALUES[27]="'id' 1"
CASE_ENV[28]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_PRE_S1=\"SET SYSTEM PARAMETERS 'no_backslash_escapes=no'\""; CASE_VALUES[28]="3 4"
CASE_ENV[29]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_PRE_S1=\"SET SYSTEM PARAMETERS 'timezone=+09:00'\" CUBRID_M0_TRACER_PRE_S2=\"SET SYSTEM PARAMETERS 'timezone=-05:00'; SELECT SLEEP (2)\""
CASE_VALUES[29]="'+09:00' '-05:00'"
CASE_ENV[30]="CUBRID_M0_TRACER_USER=A5N CUBRID_M0_TRACER_PRE=\"SET SYSTEM PARAMETERS 'group_concat_max_len=2048'\""
CASE_OUTCOME[30]='S1 FAIL pre statement err=-140 msg=\[.*DBA'
CASE_ENV[31]="CUBRID_M0_TRACER_PRE=\"SET SYSTEM PARAMETERS 'group_concat_max_len=4'\""
CASE_ENV[32]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_END=1 CUBRID_M0_TRACER_START_DELAY_S2=3"
CASE_ENV[33]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_END=1 CUBRID_M0_TRACER_PRE='SAVEPOINT a5sp; SELECT COUNT(*) FROM db_class; SELECT COUNT(*) FROM a4r'"; CASE_COUNT[33]=2
declare -A CASE_ALSO
CASE_OUTCOME[34]='M0_TRACER: SUCCESS'
CASE_ENV[34]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_USER_S1=A6U CUBRID_M0_TRACER_REEXEC_DELAY_S1=4 CUBRID_M0_TRACER_START_DELAY_S2=2 CUBRID_M0_TRACER_PRE_S2='REVOKE SELECT ON a6t FROM a6u' CUBRID_M0_TRACER_SQL_S2='SELECT 2'"
CASE_ALSO[34]='S1 kept re-execute err=-(452|494).*S1 recompile failed err=-494'
CASE_ENV[35]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_USER_S1=A6U CUBRID_M0_TRACER_START_DELAY_S1=2 CUBRID_M0_TRACER_REEXEC_DELAY_S1=4 CUBRID_M0_TRACER_PRE_S2='REVOKE SELECT ON a6r FROM a6u; SELECT SLEEP (4)' CUBRID_M0_TRACER_SQL_S2='SELECT 3'"
CASE_OUTCOME[35]='M0_TRACER: (SUCCESS|S1 FAIL db_compile_statement err=-494 )'
CASE_ALSO[35]='S1 (FAIL db_compile_statement err=-494 |kept re-execute err=-452.*S1 recompile failed err=-494)'
CASE_ENV[36]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_USER_S1=A6U CUBRID_M0_TRACER_ISOLATION_S1=RR CUBRID_M0_TRACER_PRE_S1='SELECT COUNT(*) FROM dba.a6o; SELECT SLEEP (4)' CUBRID_M0_TRACER_REEXEC_DELAY_S1=2 CUBRID_M0_TRACER_START_DELAY_S2=1 CUBRID_M0_TRACER_PRE_S2='REVOKE SELECT ON a6q FROM a6u' CUBRID_M0_TRACER_SQL_S2='SELECT 1'"
CASE_OUTCOME[36]="${CASE_OUTCOME[35]}"; CASE_ALSO[36]="${CASE_ALSO[35]}"
CASE_ENV[37]="CUBRID_M0_TRACER_PRE='DROP TABLE a6d'"
CASE_ENV[41]="CUBRID_M0_TRACER_PRE='CALL a7c ()'"
CASE_ENV[42]="CUBRID_M0_TRACER_SQL_S1='SELECT a7r (40)'"
CASE_OUTCOME[42]='S1 FAIL db_execute_statement err=-[0-9]+ '
CASE_ENV[43]="CUBRID_M0_TRACER_PRE=\"CALL add_user ('A7X', '') ON CLASS db_root\""
CASE_ENV[44]="CUBRID_M0_TRACER_PRE='CALL a7m_f () ON CLASS a7m'"
CASE_OUTCOME[44]='S1 FAIL pre statement err=-237 '
CASE_ENV[45]="CUBRID_M0_TRACER_SESSIONS=4 CUBRID_M0_TRACER_PRE='CALL a7c ()'"; CASE_COUNT[45]=4
CASE_OUTCOME[49]='S1 FAIL db_compile_statement err=-[0-9]+ msg=\[.*nested too deeply'
fail=0; n=0
for c in "${CASES[@]}"; do
  n=$((n+1)); sql="${c%%@@*}"; expect=""; [ "$sql" != "$c" ] && expect="${c#*@@}"
  [ -n "${ONLY:-}" ] && ! [[ " $ONLY " == *" $n "* ]] && continue   # ONLY="19 20": run just these cases
  out="$OUT/case$n.out"; rm -f "$out"
  errlog_lines_before=$(cat "$INST"/log/server/${DB}_2*.err 2>/dev/null | wc -l)
  event_lines_before=$(cat "$INST"/log/server/${DB}_2*.event 2>/dev/null | wc -l)
  eval "case_env=(${CASE_ENV[$n]:-})"
  [ -n "${SQLX:-}" ] && sql="$SQLX" && expect=""          # a probe: another statement, with EXTRA_ENV
  eval "case_env+=(${EXTRA_ENV:-})"
  /usr/bin/env ${ENVX:-} "$CTL" start "$DB" > "$OUT/case$n.start" 2>&1
  grep -q '^RESULT: OK' "$OUT/case$n.start" || { echo "case$n FAIL start"; fail=1; continue; }
  broker start; sleep 1
  /usr/bin/env "${case_env[@]}" CUBRID_M0_TRACER_SQL="$sql" CUBRID_M0_TRACER_OUT="$out" timeout 120 java -cp "$OUT/java:$INST/jdbc/cubrid_jdbc.jar" WireTracer 127.0.0.1 $WPORT "$DB" > "$OUT/case$n.java" 2>&1 &
  jpid=$!
  spid=""
  for p in $(pgrep -x cub_server); do
    [ "$(readlink /proc/$p/exe 2>/dev/null)" = "$(readlink -f "$INST/bin/cub_server")" ] && grep -qx "$DB" <(tr '\0' '\n' < /proc/$p/cmdline) && spid=$p
  done
  cpid=""
  if [ -n "${CASE_CSQL[$n]:-}" ]; then
    (cd "$DBDIR" && timeout 60 csql -u dba --no-auto-commit -c "${CASE_CSQL[$n]}" "$DB" > "$OUT/case$n.csql" 2>&1 < /dev/null) &
    cpid=$!
  fi
  for i in $(seq 1 60); do
    grep -qE 'M0_TRACER: (SUCCESS|FAIL)' "$out" 2>/dev/null && break; sleep 1
  done
  [ -n "$cpid" ] && wait $cpid
  wait $jpid
  [ -n "${CASE_HOLD[$n]:-}" ] && sleep "${CASE_HOLD[$n]}"
  broker stop
  "$CTL" stop "$DB" > "$OUT/case$n.stop" 2>&1
  grep -q '^RESULT: OK' "$OUT/case$n.stop" || { echo "case$n FAIL stop"; fail=1; }
  verdict=PASS
  grep -qE "${CASE_OUTCOME[$n]:-M0_TRACER: SUCCESS}" "$out" 2>/dev/null || verdict=FAIL
  [ -n "${CASE_ALSO[$n]:-}" ] && ! tr '\n' ' ' < "$out" | grep -qE "${CASE_ALSO[$n]}" && verdict="FAIL(no '${CASE_ALSO[$n]}')"
  if [ -n "$expect" ] && ! grep -qx "M0_TRACER: first value = $expect" "$out" 2>/dev/null; then verdict=FAIL; fi
  if [ -n "${CASE_COUNT[$n]:-}" ] && [ "$(grep -cx "M0_TRACER: first value = $expect" "$out" 2>/dev/null)" != "${CASE_COUNT[$n]}" ]; then verdict="FAIL(sessions)"; fi
  if [ -n "${CASE_VALUES[$n]:-}" ]; then
    got_values=$(grep '^M0_TRACER: first value = ' "$out" 2>/dev/null | sed 's/^M0_TRACER: first value = //' | sort | tr '\n' ' ')
    want_values=$(tr ' ' '\n' <<< "${CASE_VALUES[$n]}" | sort | tr '\n' ' ')
    [ "$got_values" = "$want_values" ] || verdict="FAIL(values [$got_values] != [$want_values])"
  fi
  if cat "$INST"/log/server/${DB}_2*.err 2>/dev/null | tail -n +$((errlog_lines_before+1)) | grep -qE 'Assertion|assert'; then verdict="FAIL(assert in server log)"; fi
  [ -z "$spid" ] && verdict="FAIL(no server pid)"
  if [ -n "${CASE_EVENT[$n]:-}" ] && ! cat "$INST"/log/server/${DB}_2*.event 2>/dev/null | tail -n +$((event_lines_before+1)) | grep -q "${CASE_EVENT[$n]}"; then
    verdict="FAIL(no event log line '${CASE_EVENT[$n]}')"
  fi
  ls /data/core/core.*.$spid.* >/dev/null 2>&1 && verdict="FAIL(core pid $spid)"
  echo "case$n $verdict pid=$spid [$sql] $(grep 'first value' "$out" 2>/dev/null)"
  [ "$verdict" = PASS ] || { fail=1; cat "$out" 2>/dev/null | tail -5; }
done
echo "SMOKE: $([ $fail -eq 0 ] && echo OK || echo FAILED)"
exit $fail
