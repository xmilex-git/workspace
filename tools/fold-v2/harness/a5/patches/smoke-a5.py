p='smoke.sh'
s=open(p).read()
def rep(old,new,cnt=1):
    global s
    assert s.count(old)==cnt, (old[:120], s.count(old))
    s=s.replace(old,new)
rep('''in the session conf).
set -u''','''in the session conf).
# A5: CASE_VALUES[<n>] = first values (one per session, space-separated, in any order) the case must print; the
# session conf carries update_use_attribute_references=yes (case 25, a client parameter loaded from the conf).
set -u''')
rep('''FIXTURE="drop table if exists a1t, a1ref, a1p, a1o, a3s, a3d, a4r;''','''FIXTURE="drop table if exists a1t, a1ref, a1p, a1o, a3s, a3d, a4r, a5u, a5s;
create table a5u (id int primary key, x int, y int); insert into a5u values (1, 1, 0);''')
rep('''(cd "$DBDIR" && csql -S -u dba -c "create user a3u" "$DB" < /dev/null >> "$OUT/fixture.out" 2>&1) || { echo "ABORT: fixture user"; exit 2; }''','''(cd "$DBDIR" && csql -S -u dba -c "create user a3u" "$DB" < /dev/null >> "$OUT/fixture.out" 2>&1) || { echo "ABORT: fixture user"; exit 2; }
# A5: a user who is not a DBA (SET of a server parameter)
(cd "$DBDIR" && csql -S -u dba -c "drop user a5n" "$DB" < /dev/null > /dev/null 2>&1)
(cd "$DBDIR" && csql -S -u dba -c "create user a5n; grant select on a3d to a5n" "$DB" < /dev/null >> "$OUT/fixture.out" 2>&1) || { echo "ABORT: fixture user a5n"; exit 2; }''')
rep('''  "SELECT COUNT(*) FROM a4r@@2"
)''','''  "SELECT COUNT(*) FROM a4r@@2"
  # A5: a client parameter of the conf reaches the folded client half (the server loads the client parameters)
  "SELECT y FROM a5u WHERE id = 1@@5"
  # A5: the client half reads the client-only session parameter it set (session read-through)
  "SELECT is_reuse_oid_class FROM db_class WHERE class_name = 'a5s'@@'NO'"
  # A5: a client-compile parameter one session set is its own (S2 does not see S1's oracle_style_outerjoin)
  "SELECT COUNT(*) FROM a3d a, a4r b WHERE a.id = b.id(+)@@2"
  # A5: a server-session parameter one session set is its own
  "SELECT LENGTH('a\\\\nb')"
  # A5: the plan-cache key prints the session's values (same text, two time zones)
  "SELECT TO_CHAR(CAST(DATETIME '2026-11-07 10:00:00' AS DATETIMETZ), 'TZH:TZM')"
  # A5: a server parameter needs a DBA (the client's scope rules in the bracket)
  "SELECT COUNT(*) FROM a3d@@2"
  # A5: a DBA's SET of a server parameter reaches the server (the folded server leg applies the server's rules)
  "SELECT GROUP_CONCAT('abcdefgh')@@'abcd'"
  # A5: the SHOW metadata outlives the session whose boot came first (it lives in the server boot's context)
  "SHOW HEAP HEADER OF a4r"
  # A5: the teardown frees the session's client state (savepoints, query results, triggers, schema, authorization)
  "SELECT 1@@1"
)''')
rep('''CASE_ENV[24]="CUBRID_M0_TRACER_SESSIONS=2"; CASE_COUNT[24]=2; CASE_HOLD[24]=130
''','''CASE_ENV[24]="CUBRID_M0_TRACER_SESSIONS=2"; CASE_COUNT[24]=2; CASE_HOLD[24]=130
declare -A CASE_VALUES
CASE_ENV[25]="CUBRID_M0_TRACER_PRE='UPDATE a5u SET x = 5, y = x WHERE id = 1'"
CASE_ENV[26]="CUBRID_M0_TRACER_PRE=\\"SET SYSTEM PARAMETERS 'create_table_reuseoid=no'; CREATE TABLE a5s (x INT)\\""
CASE_ENV[27]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_PRE_S1=\\"SET SYSTEM PARAMETERS 'oracle_style_outerjoin=yes'; SELECT SLEEP (3)\\" CUBRID_M0_TRACER_PRE_S2='SELECT SLEEP (1)'"
CASE_OUTCOME[27]='S2 FAIL db_compile_statement err=-[0-9]+'
CASE_ENV[28]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_PRE_S1=\\"SET SYSTEM PARAMETERS 'no_backslash_escapes=no'\\""; CASE_VALUES[28]="3 4"
CASE_ENV[29]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_PRE_S1=\\"SET SYSTEM PARAMETERS 'timezone=+09:00'\\" CUBRID_M0_TRACER_PRE_S2=\\"SET SYSTEM PARAMETERS 'timezone=-05:00'; SELECT SLEEP (2)\\""
CASE_VALUES[29]="'+09:00' '-05:00'"
CASE_ENV[30]="CUBRID_M0_TRACER_USER=A5N CUBRID_M0_TRACER_PRE=\\"SET SYSTEM PARAMETERS 'group_concat_max_len=2048'\\""
CASE_OUTCOME[30]='S1 FAIL pre statement err=-[0-9]+ msg=\\[.*DBA'
CASE_ENV[31]="CUBRID_M0_TRACER_PRE=\\"SET SYSTEM PARAMETERS 'group_concat_max_len=4'\\""
CASE_ENV[32]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_END=1 CUBRID_M0_TRACER_START_DELAY_S2=3"
CASE_ENV[33]="CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_END=1 CUBRID_M0_TRACER_PRE='SAVEPOINT a5sp; SELECT COUNT(*) FROM db_class; SELECT COUNT(*) FROM a4r'"; CASE_COUNT[33]=2
''')
rep('''  if [ -n "${CASE_COUNT[$n]:-}" ] && [ "$(grep -cx "M0_TRACER: first value = $expect" "$out" 2>/dev/null)" != "${CASE_COUNT[$n]}" ]; then verdict="FAIL(sessions)"; fi''','''  if [ -n "${CASE_COUNT[$n]:-}" ] && [ "$(grep -cx "M0_TRACER: first value = $expect" "$out" 2>/dev/null)" != "${CASE_COUNT[$n]}" ]; then verdict="FAIL(sessions)"; fi
  if [ -n "${CASE_VALUES[$n]:-}" ]; then
    got_values=$(grep '^M0_TRACER: first value = ' "$out" 2>/dev/null | sed 's/^M0_TRACER: first value = //' | sort | tr '\\n' ' ')
    want_values=$(tr ' ' '\\n' <<< "${CASE_VALUES[$n]}" | sort | tr '\\n' ' ')
    [ "$got_values" = "$want_values" ] || verdict="FAIL(values [$got_values] != [$want_values])"
  fi''')
open(p,'w').write(s)
