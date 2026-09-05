# wf220 D5 verification report

Engine: d8cbe2ddc531192cd8258b71f348cde4eed2d7e9; optdebug/release cubrid_rel 11.5.0.2770-d8cbe2d.
Fresh dedicated builds: optdebug PASS; release PASS; shared ~/CUBRID directory untouched.
Direct test_server_compile: optdebug 18/18 PASS; release 18/18 PASS.
Smoke optdebug CS: in-process 14/14 PASS; JDBC/thin/csql/gate 4/4 PASS.
Fail-before-fix idempotence: baseline cd6ab1b double-init area_dump=10; candidate=5, one each.
Candidate lifecycle: 20 module init/final cycles, residual areas=0; actual CS expected failed restart=-677 then 5 restart/shutdown cycles PASS.
HA candidate command: BUILD=~/optdebug/CUBRID-wf220-area-lifetime PR=7837 just ctp ha_shell _22_ha
HA candidate run: /home/cubrid/dev/workspace/.git_ignored_dir/scratch/ctp-run-out/ha_shell-20260905T200118Z-3892632; CTP 8cb1b9b; TC develop 21122e4fe033; directory 10 PASS/18 FAIL (runner rc1), assertions 38 OK/25 NOK, cores 0.
HA baseline representative command: BUILD=~/optdebug/CUBRID-wf210-lru PR=7837 just ctp ha_shell _22_ha/bug_3196
HA baseline representative: /home/cubrid/dev/workspace/.git_ignored_dir/scratch/ctp-run-out/ha_shell-20260905T205630Z-4011866; bug_3196 FAIL with identical two broker-connect errors, cores 0.
Classification: 16 candidate failures contain literal ERROR cannot connect to broker with CUBRID_CSQL_BROKER_PORT unset vs configured 10090/13091; bug_bts_5243 is the same class by captured activeCount=4 vs expected16 (standbyCount=18); bug_4027 is prior classified TC fold incompatibility.
Cleanup: candidate/baseline CTP containers absent; wf220 server/master absent; port claim released. Engine checkout only cubrid-cci submodule worktree marker from standard initialization; no source modifications.
Evidence checksum manifest: /home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf220/sha256-manifest.txt
