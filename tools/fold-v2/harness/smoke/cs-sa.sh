#!/bin/bash
# regular CS and SA paths on a fold install (no tracer): cs-sa.sh <install> <dbdir> <db>
INST=$1; export CUBRID=$INST CUBRID_DATABASES=$2 PATH=$INST/bin:$PATH; DB=$3
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
SQL="drop table if exists s0t, s0o; create table s0o (a int) dont_reuse_oid; insert into s0o values (1),(2);
create table s0t (id int primary key, o s0o, s set(int)); insert into s0t select a, s0o, {a, a+1} from s0o;
select count(*), sum(id) from s0t t, s0o o where t.o = o;
select id, s from s0t order by id;
select /*+ use_hash */ count(*) from db_class a, db_class b where a.class_name = b.class_name;
drop table s0t; drop table s0o;"
cd $2
echo "-- SA"; csql -S -u dba -c "$SQL" $DB < /dev/null 2>&1 | grep -vE '^$|^=+$|^Execute OK|Current transaction|row(s)? (selected|affected)' | head -30
$CTL start $DB | grep '^RESULT'
echo "-- CS"; csql -u dba -c "$SQL" $DB < /dev/null 2>&1 | grep -vE '^$|^=+$|^Execute OK|Current transaction|row(s)? (selected|affected)' | head -30
$CTL stop $DB | grep '^RESULT'
