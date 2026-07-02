# 워크스페이스 위생 분류 보고서 — 스트레이(비추적) 파일

- 작성일: 2026-07-02
- 대상: `~/dev/workspace` 루트의 비추적(untracked) 파일
- 성격: **READ-ONLY 분류**. 어떤 파일도 삭제/이동/수정하지 않음. supervisor 승인 대기.
- 방법: `git status --porcelain` 목록 + `ls -la`(크기/mtime) + `file`(코어에 임베드된 실행 커맨드) + 이슈/문서 grep. gdb `bt` 는 사용하지 않음(파일명 PID/타임스탬프 + `file` 임베드 커맨드로만 추정).

---

## 요약

- 분류 대상 스트레이 파일(루트, 이번 스코프): **코어 20건 + `csql.err` + `csql.access` + `mutex` + `wmg003*` 9건 = 32건**
  - 코어 20건 apparent 크기 합 ≈ **25.9 GiB** (on-disk `du` < apparent — 코어가 sparse)
  - `wmg003*` DB 볼륨셋 합 ≈ **1.7 GiB**
  - 코어 20건 = 초기 git snapshot 17건 + 이 세션이 fail-before-fix 재채증으로 신규 생성한 `core.parallel-query.*` 3건(7/2 20:15~20:16, snapshot 이후 생성)
- 판정 집계 (32건 기준):
  - **보존 (preserve): 6건** — 이슈 #109 증적 core 3건(§1a) + 이 세션 신규 증적 `core.parallel-query.*` 3건(§1b)
  - **삭제가능 (deletable): 10건** — tpch_sf10 코어 5건 + wmg003 liveness csql 코어 2건 + `csql.err` + `csql.access` + `mutex`
  - **보류 (hold): 16건** — wmloc 서버 코어 7건(동일 캠페인, sibling 이슈 증적 가능성) + `wmg003*` DB 볼륨셋 9건(실 DB, 삭제=파괴적; 이 중 `wmg003_lgar.removed`는 hold 내 우선-삭제 안전)
- 별도(디렉터리, 스코프 밖이나 용량 큼): `vtune/` ≈ **4.7 GiB**, `CBRD-26900-review/` ≈ **577 MiB** → §5 참고.

> 공간 회수 관점: 확실 삭제가능(10건) ≈ 4.2 GiB, 보류 승인 시 추가 회수 wmloc 코어 ≈ 12 GiB + wmg003 DB 1.7 GiB + vtune 4.7 GiB. 보존(6건) ≈ 9.7 GiB 는 유지.

---

## 1a. 보존 필수 — 이슈 #109 증적 core (3건) ✅ 존재 확인

이슈 #109 본문:
- 대표 백트레이스 core: **`core.transaction.3261892.*`** (`9acdc6150` release, `px_hash_join.cpp:196 build_partitions` 힙손상 SIGABRT)
- 동일 시그니처 추가 2건: **`core.transaction.3224593.*`**, **`core.transaction.3226337.*`** (fa199a742+패치 빌드)

실제 파일 대조 — 3건 모두 루트에 존재하며 `file` 상 `cub_server wmloc` 서버 코어로 확인:

| 파일 | 크기(byte) | mtime | 임베드 커맨드 | 판정 |
|---|---|---|---|---|
| core.transaction.3261892.ilhansong_data2.1782989351 | 1,426,001,920 | 7/2 19:49 | cub_server wmloc | **보존 (#109 대표 bt)** |
| core.transaction.3224593.ilhansong_data2.1782988505 | 1,417,080,832 | 7/2 19:35 | cub_server wmloc | **보존 (#109 동일 시그니처)** |
| core.transaction.3226337.ilhansong_data2.1782988554 | 1,410,043,904 | 7/2 19:35 | cub_server wmloc | **보존 (#109 동일 시그니처)** |

**삭제 금지.** 이슈 close 및 supervisor 명시 승인 전까지 유지.

---

## 1b. 보존 필수 — 이 세션 신규 증적 core (`core.parallel-query.*`, 3건) ✅ 존재 확인

이 세션이 fail-before-fix 재채증(재현 후 fix 이전 상태 재확보)으로 **신규 생성**한 코어. 초기 git snapshot(작업 시작 시점) 이후 7/2 20:15~20:16 에 생성되어 원본 목록에는 없었음. 3건 모두 루트에 실존, `file` 상 `cub_server wmloc` 서버 코어로 확인. team-lead 지시에 따라 **신규 증적 → 보존**.

| 파일 | 크기(byte) | mtime | 임베드 커맨드 | 판정 |
|---|---|---|---|---|
| core.parallel-query.3311439.ilhansong_data2.1782990907 | 1,494,650,880 | 7/2 20:15 | cub_server wmloc | **보존 (신규 재채증)** |
| core.parallel-query.3314095.ilhansong_data2.1782990965 | 2,333,753,344 | 7/2 20:16 | cub_server wmloc | **보존 (신규 재채증)** |
| core.parallel-query.3314946.ilhansong_data2.1782990982 | 2,333,757,440 | 7/2 20:16 | cub_server wmloc | **보존 (신규 재채증)** |

**삭제 금지.**

---

## 2. 코어 덤프 — 나머지 14건 분류

임베드 커맨드(`file`)로 출처를 확정. 어떤 워크스페이스 문서(temp_workmem/*, issues.md 등)도 코어 PID 를 직접 참조하지 않음(grep 결과 0건) → 파일명/커맨드 기반 추정.

### 2a. tpch_sf10 캠페인 코어 (5건) → **삭제가능**
다른 DB(`tpch_sf10`), 다른 빌드(develop-69e73b47 / 11.5.develop), 7/1 이전. 현재 활성 캠페인(#109 wmloc)과 무관. 참조 문서 없음.

| 파일 | 크기(byte) | mtime | 임베드 커맨드(요약) | 빌드 | 판정 |
|---|---|---|---|---|---|
| core.csql.1168137.* | 2,990,080 | 7/1 00:37 | csql dba tpch_sf10 -c "count(*), SUM(CAST(c AS NUMERIC))" | develop-69e73b47 | 삭제가능 |
| core.csql.1168743.* | 2,990,080 | 7/1 00:38 | csql dba tpch_sf10 -c "count(*) FROM (SELECT l_orderkey ...)" | 11.5.develop | 삭제가능 |
| core.csql.1168774.* | 2,990,080 | 7/1 00:38 | csql dba tpch_sf10 (동일 쿼리) | 11.5.develop | 삭제가능 |
| core.csql.1168805.* | 2,990,080 | 7/1 00:38 | csql dba tpch_sf10 -c "/*+ NO_PARALLEL */ count(*) ..." | 11.5.develop | 삭제가능 |
| core.transaction.1311076.* | 2,273,091,584 | 7/1 13:23 | cub_server tpch_sf10 | 11.5.develop | 삭제가능 |

### 2b. wmg003 liveness csql 코어 (2건) → **삭제가능**
`SELECT count(*) FROM db_class` / `SELECT 1 FROM db_root` — DB 접속 smoke 쿼리 클라이언트 크래시. 진단 가치 낮음, 각 ~1 GiB 로 용량만 큼.

| 파일 | 크기(byte) | mtime | 임베드 커맨드 | 판정 |
|---|---|---|---|---|
| core.csql.4126943.* | 1,093,459,968 | 6/30 00:24 | csql -S dba wmg003 -c "count(*) FROM db_class" | 삭제가능 |
| core.csql.4127265.* | 1,093,459,968 | 6/30 00:25 | csql -S dba wmg003 -c "SELECT 1 FROM db_root" | 삭제가능 |

### 2c. wmloc 서버 코어 — #109 과 동일 캠페인 (7건) → **보류**
전부 `cub_server wmloc`, `~/CUBRID/bin`, 7/2 당일. #109 이 재현 중이던 hash-join/work_mem 캠페인(#75/#77/#78 계열)의 **반복 재현 크래시**. #109 은 이 중 대표 3건만 인용(§1). 나머지 7건은 어떤 문서/이슈에서도 파일명으로 인용되지 않으나, sibling 오픈 이슈(#75/#77/#78)가 백트레이스로 참조할 가능성을 배제할 수 없어 **보류(supervisor 확인 후 삭제)**. #109 상 재현은 결정적(3/3)이라 재생성 가능.

| 파일 | 크기(byte) | mtime | 임베드 커맨드 | 판정 |
|---|---|---|---|---|
| core.transaction.2264355.* | 1,801,478,144 | 7/2 11:40 | cub_server wmloc | 보류 |
| core.transaction.2267323.* | 1,444,626,432 | 7/2 11:41 | cub_server wmloc | 보류 |
| core.transaction.2270333.* | 1,452,736,512 | 7/2 11:42 | cub_server wmloc | 보류 |
| core.transaction.2615139.* | 2,267,176,960 | 7/2 14:12 | cub_server wmloc | 보류 |
| core.transaction.2663808.* | 2,258,173,952 | 7/2 14:36 | cub_server wmloc | 보류 |
| core.transaction.2857685.* | 1,399,746,560 | 7/2 16:20 | cub_server wmloc | 보류 |
| core.transaction.3138308.* | 2,334,584,832 | 7/2 18:49 | cub_server wmloc | 보류 |

---

## 3. 기타 루트 스트레이 파일

| 파일 | 크기 | mtime | 추정 출처 | 판정 |
|---|---|---|---|---|
| csql.err | 2,032,011 | 7/2 19:45 | csql 에러 로그(hash-join 캠페인 중 생성) | 삭제가능 |
| csql.access | 4,636 | 7/2 11:13 | csql 접속 로그 | 삭제가능 |
| mutex | 0 | 7/2 17:54 | 빈 파일 — 오타/리다이렉션(`> mutex`) 사고 추정 | 삭제가능 |

---

## 4. `wmg003*` — CUBRID DB 볼륨셋 (9건, ≈1.7 GiB) → **보류**

`wmg003` 는 스트레이 아티팩트가 아니라 **CUBRID 데이터베이스 하나의 볼륨/로그 셋**(루트에 생성됨). §2b 의 csql 코어가 이 DB 를 대상으로 함. 현재 `cub_server`/`cub_master` 프로세스 미기동(pgrep 0건). DB 삭제는 파괴적이므로 owner 확인 필요 → **보류**.

| 파일 | 크기(byte) | mtime | 역할(추정) | 판정 |
|---|---|---|---|---|
| wmg003 | 805,306,368 | 7/2 17:26 | 데이터 볼륨 | 보류 |
| wmg003_lgat | 268,435,456 | 7/2 17:26 | active log | 보류 |
| wmg003_lgar_t | 268,435,456 | 7/2 17:20 | log archive(temp) | 보류 |
| wmg003_lgar002 | 268,435,456 | 7/2 14:03 | log archive #002 | 보류 |
| wmg003_lginf | 1,062 | 7/2 14:13 | log info | 보류 |
| wmg003_vinf | 218 | 6/24 22:36 | volume info(ASCII) | 보류 |
| wmg003_keys | 65 | 6/24 22:36 | TDE keys | 보류 |
| wmg003_lgat__lock | 41 | 7/2 17:20 | active-log lock | 보류 |
| wmg003_lgar.removed | 268,419,072 | 6/24 22:39 | 제거표시된 옛 log archive | **삭제가능(hold 내 우선)** — `.removed` 접미사, 6/24 stale |

> `wmg003_lgar.removed` 는 CUBRID 가 이미 제거 대상으로 표시한 옛 archive 로, DB 무결성과 무관하여 단독 삭제 안전. 나머지 8건은 DB 일체이므로 함께만 처리 권장.

---

## 5. 스코프 밖 참고 (루트 비추적 디렉터리 — 삭제 판단 유보, 용량만 보고)

| 항목 | 크기 | 성격 | 비고 |
|---|---|---|---|
| vtune/ | ≈4.7 GiB | Intel VTune 프로파일링 결과 | 최대 용량. 완료된 프로파일이면 회수 후보 — owner 확인 |
| CBRD-26900-review/ | ≈577 MiB | 리뷰 작업 디렉터리 | 진행 상태 확인 필요 |
| temp_workmem/(문서/artifacts/docs) | 소~중 | 활성 workmem/이슈 문서 | 유지 |
| sampling_backport/, cubrid-rawfd-workmem/, .codex/, .agents/skills/tmux-control/, vtune 외 | 소 | 작업/설정 | 유지 |
| 루트 *.md (CBRD-26931-handoff, backport_plan, issue78_plan, issues, issue65*, CONTEXT-MAP 등) | 소 | 이슈/핸드오프 문서 | 유지 |

---

## 6. `.gitignore` 보강 제안 (적용 금지 — 제안만)

현재 `.gitignore` 에 코어/DB/로그 패턴 없음. 아래 추가 시 재발 방지:

```gitignore
# core dumps
core.*

# csql local logs
csql.err
csql.access

# stray empty artifact
/mutex

# local scratch DB volume sets (never commit)
/wmg003*

# profiler output
/vtune/
```

> 주의: `core.*` 는 광범위. `.claude/CLAUDE.md` 등 정상 파일과 충돌 없음(루트 `core.` 접두 파일만 매치). 필요 시 `/core.*` 로 루트 한정 가능.

---

## 7. supervisor 조치 요청 (승인 시)

1. **즉시 삭제 안전(10건, ≈4.2 GiB)**: §2a(5) + §2b(2) + `csql.err` + `csql.access` + `mutex`.
2. **보류 → 확인 후 삭제**: §2c wmloc 서버 코어 7건(≈12 GiB, sibling 이슈 미참조 확인 후) + §4 `wmg003_lgar.removed`(단독 안전).
3. **보존 유지(6건)**: §1a #109 증적 3건 + §1b 신규 재채증 `core.parallel-query.*` 3건 — 삭제 금지.
4. **DB 처리 별도 결정**: §4 `wmg003` 볼륨셋(활성/폐기 여부 owner 판단).
5. **`.gitignore` 보강**: §6 제안 반영 여부 결정.

---

## 처분 기록 (2026-07-02 밤)

supervisor 승인에 따라 **삭제가능 10건 삭제 완료**(≈3.3GiB 회수): tpch 코어 5 + wmg003 csql 코어 2 + csql.err/csql.access/mutex.
보존 6건(#109 원본 3 + fail-before-fix 3) 및 보류 16건(wmloc 코어 7 + wmg003 볼륨 9)은 그대로 유지.
