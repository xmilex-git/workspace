# fold-v2 — the smoke, gate and trace harness of the CAS fold re-port (CBRD-27430)

A tracked copy of the scripts the map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618)
runs at every stage gate. The scripts run from `.git_ignored_dir/scratch/fold-v2/` (their paths are written out);
this directory exists so a cleanup of the scratch disk cannot lose them again (2026-11-24 it did).

- `harness/` — the scratch tree's scripts as of `cas-fold-v2` `16916de659` (B4 gate, 2026-11-26): per-stage smokes
  (`smoke/`, `b1a/smoke/` … `b4/smoke/`), gate runners (`b*/gate-*.sh`, `b4/gate-all.sh`), TLA+ trace tooling per
  stage (`instrument.py`, `events*.py`, `trace/run.sh`, `trace/mk.py`, `trace/instrumented.diff`) and the commit
  attribution tables (`commit-stage.tsv`, `stage-range.tsv`, `overrides.tsv`).
- `recover/` — the tools that rebuilt the scratch tree from old session transcripts: `extract.py` (tool calls in
  time order), `replay.py` (each Bash call in a bwrap sandbox: read-only /, no network, own pid namespace, runtime
  binaries stubbed), `diverge.py` and `audit.py` (replay failures against the original runs' output).

## Restore

```bash
rsync -a tools/fold-v2/harness/ .git_ignored_dir/scratch/fold-v2/
```

Not in the copy, made again after a restore:

- installs `~/optdebug/CUBRID-cas-fold-v2`, `~/release/CUBRID-cas-fold-v2` (`cubrid-build`, `INSTALL_PREFIX`);
- the port claim and session conf: `just port-claim foldv2s0 <effort>`, then append `session_state_timeout=60`,
  `update_use_attribute_references=yes`, `test_mode=yes` to `.git_ignored_dir/conf/foldv2s0.conf`; the memory-check
  confs are that file plus `use_system_malloc=yes` (`b2/foldv2s0-mc.conf`, `b4/foldv2s0-mc.conf`,
  `.git_ignored_dir/conf/foldv2s0-mc.conf`); the broker ports in the smokes (36701–36704, shm 3679x) are the
  claimed block's;
- install conf backups `b1a|b1b|b2/confbak/<mode>/{cubrid.conf,cubrid_broker.conf}`, copied from the fresh installs;
- the smoke databases: `bash b4/mkdb.sh` (`smoke/db`: foldv2s0; `b4/db`: foldv2s0 + foldv2b).

## Gate of the current head

```bash
bash .git_ignored_dir/scratch/fold-v2/b4/gate-all.sh <tag>
```

Both builds: wire 51, B1a 5, B1b 5, B2 13, login 4, B3 5, B4 11, thread-entry repro 3; then the memory check on
optdebug (B4, login, repro). A script changed in scratch is copied back here in the same commit as its stage's
MAP.md.
