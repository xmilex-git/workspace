# PROTOTYPE #485 (G4) — new log start after the source log end, volumes untouched

Throwaway. Question: what must a fresh sparse `_lgat` contain so that develop **release** boots volumes whose page LSAs
were left as the source wrote them (choice (B), fixed by the user)? Script: `fm485_proto.py` (hdr / scan / mklog).

## Setup
- Engine: develop release `~/release/CUBRID-cbrd27819-s0` (develop 4f1a68c1e + a NUMERIC-only refactor) for CS runs;
  cross-check in SA on `~/release/CUBRID-fastmig-dev` (origin/develop 682b080b2, T1 #479).
- Source DB `fm485` made by that engine: 3 volumes (64M each), 200k-row table + PK + index, update/delete, serial,
  7 archives; normal shutdown. Source log: `append_lsa=(10061,14992)`, `fpageid=8953`, `mvcc_next_id=9`.
  Page scan: max page LSA `(10061,14824)` < append_lsa, no LSA/watermark mismatch.
- Writer check: mode A output == `cubrid copydb` header byte for byte except db_creation/vol_creation/prefix/padding;
  CRC (zlib crc32 over 16B head + 16B tail of each 4 KiB block, checksum field zeroed) reproduces copydb's checksums.
- Each run: reflink copy of the pristine dir, delete `_lgat _lgar* _lgar_t _lginf`, write a new `_lgat`; volumes,
  `_vinf`, `_keys` byte-identical to the source (cmp).

## Runs
| run | F (new fpageid) | result |
|---|---|---|
| B1 | append.pageid+1 = 10062 | boot, queries, 150k insert/update/delete match a Python oracle; but **FATAL -97 "unable to find log page 10044 in log archives"** in `logpb_remove_archive_logs_exceed_limit`, and after restart **"VACUUM ERROR: cannot prefetch log page 10044"**. 10044 = 324×31: the first vacuum block (`vacuum_log_block_pages`=31) starts before F, so vacuum and archive removal look for a page that never existed. |
| B2 (CS) | ceil(10062/31)×31 = 10075 | boot, same workload, results match the oracle; 5 archives created from 10075; no ERROR/FATAL. `kill -9` → master relaunch → recovery: redo from chkpt 10075 over 6814 log pages / 1,017,707 records, undo 11 trans, checkpoint, values match oracle (incl. serial and JSON table). Clean stop + restart: values match, 0 ERROR lines. vacuumdb dump: first referenced log page 16957 (vacuum advanced past F). |
| B3 (SA) | 10075 | `csql -S` workload + reboot: values match; header `vacuum_last_blockid=451` after SA shutdown; CS boot afterwards clean. |
| B4 (SA, fastmig-dev 682b080b2) | 10075 | same as B3, values match. |

11.4 base DB (T1 pristine `fm114_clean`, read only): `append_lsa=(9070,4712)`, max page LSA `(9070,4656)` (vol 0 page 641,
VACUUM_DATA) — page LSA ≤ append_lsa holds; F would be ceil(9071/31)×31 = 9083.

## Rule (header of the new `_lgat`)
- `N` = `BOOT_DB_PARM.vacuum_log_block_npages` of the source DB (31 by default).
- `F = ceil((src append_lsa.pageid + 1) / N) × N` — must be a vacuum block boundary.
- `fpageid = nxarv_pageid = F`, `append_lsa = chkpt_lsa = (F, 0)`, `nxarv_phy_pageid = 1`, `nxarv_num = 0`,
  `last_arv_num_for_syscrashes = last_deleted_arv_num = -1`, `vacuum_last_blockid = 0` (copydb value; works in CS and SA).
- `db_creation` = the source log's value (volume headers keep theirs; no volume write). Volume header `chkpt_lsa` left
  stale (older than F) — accepted.
- Physical page 1: `logical_pageid = F`, offset -1, LOG_END_OF_LOG record. Rest of the file sparse.
- Other fields as copydb (`logpb_initialize_header` + `was_copied=1`, source `mvcc_next_id`), develop
  `db_release`/`db_compatibility`/`sysmeta_version=1`.
- Precondition: source normally shut down; page LSA ≤ source append_lsa (held on both DBs above without exception).
