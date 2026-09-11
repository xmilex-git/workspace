# PoC T1/R7 — 바인드 clone 축소 + 요청 body/argv 스크래치 malloc 제거 — 계수 분해 후 C×1·A×1

- 티켓: [workspace#249](https://github.com/xmilex-git/workspace/issues/249) (맵 #207, 기준선 #244 상속). 후보 정의: [브레인스토밍 1 #216](https://github.com/xmilex-git/workspace/issues/216) `optimization-brainstorm.md` T1(execute 입력 DB_VALUE 배열 전량 clone 후 clear → 동기 borrow) · R7(매 요청 body malloc·인자마다 argv realloc → bounded request scratch / inline argv); [브레인스토밍 2 #218](https://github.com/xmilex-git/workspace/issues/218) `perf-rules-review.md` N7(=R7 흡수, ALLOC-01/02·PAR-11) · N8(=T1 흡수, ALLOC-01·MEM-01·COH-12).
- 일자: 2026-09-11 · 측정 환경: #244 runbook 그대로(SMT off·nproc 32·idle 게이트·G2 체크포인트-조용 conf·golden→copydb)
- 기준 sha `d533969e4` 위 1커밋 `ded65d100` · PoC 브랜치 `poc/t1r7-alloc-cut` (xmilex-git/cubrid, 워크트리 `~/dev/worktrees/wf-poc-t1r7`) · 설치본 `/home/cubrid/release/CUBRID-wf-poc-t1r7`
- 원자료: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/results/t1r7/{smoke,c1,a1,a2,perfC,perfA}` · 호스트 대조 `results/base/a4ref` · 기준선 재분해 `results/base/perf{C,A}/t1r7_*.txt` · diff `patches/t1r7-alloc-cut.diff`(6파일 +201/−23) · 분류기 `scripts/t1r7_classify.py`

## 0. 왜 — 기준선 perf의 계수 분해 (티켓이 요구한 선행 작업)

티켓은 "N7은 계수 미확정, N8은 `db_value_clone` 지분 — 구현 전에 기준선 perf에서 두 계수를 분해해 적고, 합쳐 0.5 % 미만이면 PoC 규모를 줄인다"고 했다. #244 기준선 `perf.data`(C 285K·A 149K 샘플, cycles 커널 포함, dwarf)를 다시 읽었다. 기준선 표의 self 값(`db_value_clone` 0.03 %, `malloc` 2.53 %)만으로는 두 후보가 보이지 않고, **inclusive(children) + 할당자 호출 사슬의 경로별 분류**로 읽어야 한다.

### 0.1 경로 루트의 inclusive 지분 (cub_server cycles, children / self)

| 루트 | C children / self | A children / self | 실체 |
|---|---|---|---|
| `cas_process_request` | 94.62 / 0.48 | 73.48 / 0.33 | 폴드된 CAS 스피커 전체 |
| **R7-argv** `net_decode_str` | **1.16** / 0.05 | **0.98** / 0.03 | 인자마다 `REALLOC(argv, 8·argc)` — `realloc` self 0.27 %(100 % 이 경로), `_int_malloc` 0.28, `_int_free` 0.14, `malloc` 0.07, 나머지 ≈0.4는 루프·memcpy·ntohl |
| **R7-body** `read_msg` MALLOC/FREE (`cas_process_request` 직접) | **≈0.54** (malloc 0.20 + cfree 0.10 + `_int_free` 0.24) | ≈0.33 (0.10 + 0.07 + 0.16) | 요청당 body 1 malloc + 1 free |
| **T1** `make_bind_value` | **1.26** / 0.07 | **1.15** / 0.05 | value_list malloc/free ≈0.05 + `netval_to_dbval` |
| └ `netval_to_dbval` | 1.14 / 0.11 | 1.04 / 0.08 | 문자열 바인드: `intl_check_string` 0.05·`lang_get_client_charset` 0.08·`db_value_domain_init` 0.09·`db_value_clone`→`pr_clone_value`→`db_private_alloc`/`hl_lea_alloc` 0.04+0.03 … (clone은 glibc malloc이 아니라 **private heap**이라 #177의 malloc 지분에 들어 있지 않았다) |
| └ value_list clear (`ux_execute`) | ≈0.04 (`pr_clear_value` 0.03 + `db_private_free` 0.01) | — | T1-clear1 |
| (유지) `pt_set_host_variables` | 0.78 / 0.09 | 0.73 / 0.10 | **파서 보유용 2차 복사** — `tp_value_cast_internal` 0.13(100 % 이 경로)·`pr_clear_value` 0.07·`pr_clone_value`. PoC 범위 밖(티켓: "history/result-cache 보유용 복사는 별도") |

- **PoC가 겨누는 합계(inclusive): C ≈ 3.0 % (R7 1.7 + T1 1.3), A ≈ 2.5 % (R7 1.3 + T1 1.2)** — 티켓의 0.5 % 하한을 크게 넘으므로 **PoC 규모 축소 없이 전량 구현**. 단, 이 3 %는 inclusive라 실제 소거 가능한 self 사이클은 그중 일부(할당자 self 합 ≈1.0 %: realloc 0.27 + R7 malloc/free 0.54 + argv `_int_*` 0.42 …)이고, 나머지는 디코드 루프·문자열 검사처럼 남는 비용이다. 기대 상한 ≈ C 사이클 1.5~2 %.
- `#177 malloc 6.7~9.1 %` 중 R7 지분 = `malloc`+`realloc`+`free` 계열 self 7.1 % 가운데 **≈1.2 %p**(R7-body 0.54 + R7-argv 0.27+0.28+0.14+0.07). 나머지 malloc 파편의 최대 단일 소비자는 여전히 결과당 `db_cp_query_type`(#254 fog).
- T1의 `db_value_clone` 지분은 self 0.03 %가 아니라 `netval_to_dbval` inclusive 1.14 %로 읽어야 한다. 또 **문자열 바인드 1개가 2번 deep-copy 된다**: ① CAS 래퍼 `netval_to_dbval`(`db_make_char`로 wire 버퍼를 가리킨 뒤 `db_value_clone`) ② 파서 `pt_set_host_variables`(`pr_clear_value(hv)` 후 `tp_value_cast_preserve_domain`/`pr_clone_value`). ①만 PoC 대상.

### 0.2 실행 모델 확인(설계 전제)
- `driver_session.cpp`: 폴드된 CAS 스피커는 **채택 커넥션당 전용 스레드 1개**(`request_loop` → `cas_process_request` 반복). CAS 전역은 `CAS_TLS`(=`thread_local`)로 세션-로컬. 따라서 "세션 소유 bounded 버퍼"는 스레드 로컬로 구현하면 정확히 세션 소유가 된다.
- `read_msg`(요청 body)는 `cas_process_request` 끝에서 free 되고, `argv`·바인드 값은 그 안에서만 소비된다 — 기존 코드의 소유권 계약이 이미 "요청 끝까지"라 alias 전환에 새 계약이 필요 없다.

## 1. 무엇을 바꿨나 (throwaway, 6파일 +201/−23)

### R7 — 요청 body 스레드 스크래치 + inline argv (`cas_dispatch.c` +80, `cas_network.c/.h` +60, `driver_session.cpp` +1; ALLOC-02/ALLOC-05)
- `cas_req_body_acquire(size)`: `thread_local` 스크래치(`cas_req_body_scratch`, cap은 1 KiB에서 2배씩 성장, **상한 64 KiB**)를 요청 간 재사용. 상한 초과 또는 재진입(`busy`) 시 기존 `MALLOC` 경로. `cas_req_body_release`는 스크래치면 busy 해제, 아니면 `FREE_MEM`. 스레드가 요청 루프를 떠날 때 `cas_request_scratch_release_thread()`로 반납(`driver_session.cpp request_loop` 끝) — 세션당 누수 없음.
- `net_decode_str_into(msg, size, &fc, &argv, inline_argv, 16)`: 디스패처 스택의 `void *argv_inline[16]`에 채우고 17번째 인자부터만 heap(1회 MALLOC 후 2배 REALLOC). 기존 `net_decode_str`는 `(NULL, 0)` 래퍼로 의미 보존(cgw·shard proxy 호출자 무변경). free는 `argv != argv_inline`일 때만.
- YCSB execute 요청(fn_execute: srv_h_id·flag·max_col_size·max_row·… + 바인드 2·argc) 인자 수 ≈ 10~12 → 전부 inline.

### T1 — inline 바인드 배열 + 문자열 바인드 wire alias (`cas_execute.c` +45; ALLOC-01/ALLOC-02)
- `make_bind_value_into(..., inline_buf, cap, ...)`: `ux_execute` 스택의 `DB_VALUE bind_inline[8]`를 쓰고 9개 이상만 MALLOC. 기존 `make_bind_value`는 `(NULL, 0)` 래퍼(`ux_execute_all`·array·batch 경로 무변경). 정상·오류 두 해제 지점 모두 `value_list != bind_inline`일 때만 FREE.
- `netval_to_dbval` 꼬리: `desired_type == DB_TYPE_NULL || !coercion_flag`이고 **`!db_val.need_clear && TP_IS_CHAR_TYPE`** 이면 `*out_val = db_val`(구조체 복사 = wire 버퍼 alias)로 끝. 소유 payload(유니코드 compose된 문자열·JSON·set·LOB·수치 계열)는 기존 `db_value_clone` 그대로. alias 값은 `set_host_variables`→`pt_set_host_variables`가 파서 소유로 deep-copy 하므로 하류 계약 불변이고, `ux_execute`의 `db_value_clear`는 need_clear=false에서 no-op.
- 하지 않은 것: 파서 2차 복사(`pt_set_host_variables`)의 borrow 전환 — 티켓 범위 밖(보유용 복사). §5·§6에 후속 후보로 적는다.

## 2. 게이트 — fresh release 빌드 + smoke

- fresh `release`(RelWithDebInfo) 빌드 성공(`CUBRID 11.5.0 (11.5.0.2836-ded65d1)`, 10:51 KST, 3분 10초). 설치본 `CUBRID-wf-poc-t1r7`: `libcubrid.so.11.5` sha256 `849ec5ef…`, `cub_server` `f67a18a7…`, JDBC 0076 동일(`3e876fb1…`). 변경 4 TU에 warning 0.
- 캠페인 conf 적용 후 `smoke.sh smk` **14/14 PASS**(DDL·GRANT/REVOKE·PL/CSQL·동시 4세션·RR — 다중 인자 요청과 문자열·수치 바인드가 새 디코드·바인드 경로를 실제로 통과), `smoke_jdbc.sh smk 33000` **SMOKE_JDBC: SUCCESS**. 서버 .err는 smoke 자체의 의도적 오류 케이스(-494/-294/-4)만, ycsb 레그 .err는 ER -380(benign) 외 0, core 0. SMT off 확인(`control=off active=0 nproc=32`).

## 3. 측정 — C×1·A×1 (기록용, #244 7항)

| leg | ops/s | READ p50 | READ p99 | UPD p50 | UPD p99 | checkpoints | errors | loadavg_before |
|---|---|---|---|---|---|---|---|---|
| base c1/c2/c3 (#244) | 115,550 / 118,374 / 119,919 | 766/750/742 | 2,433/2,299/2,293 | – | – | 0 | 0 | 4.97/4.67/5.05 |
| **t1r7 c1** | **124,334** | **707** | 2,307 | – | – | 0 | 0 | 3.84 |
| base a1/a2/a3 (#244) | 31,423 / 31,447 / 26,944 | 372/351/328 | 6,107/5,507/5,291 | 4,559/4,687/5,679 | 22,927/22,735/26,383 | 0 | 0 | ≈5 |
| **t1r7 a1** | **30,008** | 362 | 6,435 | 4,711 | 23,855 | 0 | 0 | 4.23 |
| **t1r7 a2** (a1이 floor 아래라 1회 추가) | **29,709** | 365 | 6,411 | 4,855 | 24,191 | 0 | 0 | 3.66 |
| **base a4ref** (12:33, 같은 시간대 기준선 설치본 `d533969` 재측정 — 호스트 대조) | **28,662** | 361 | 8,535 | 5,035 | 24,719 | 0 | 0 | 3.88 |

- **C**: 기준 median 118,374(MAD 1,545) 대비 **+5.03 %(+3.9 MAD)**, READ p50 **−5.7 %**, p99 +0.35 %(hold 2,529 미달). floor 113,739 위 → **회귀 아님, 크래시 없음 → 스택 포함**(#244 7항의 선별 기준은 C×1).
- **A**: 두 레그 모두 기준 median 31,423 대비 **−4.5 % / −5.5 %**, D4 클램프 floor 30,481 아래(−473 / −772). READ p99 +16.9 %/+16.4 %(hold 6,058 초과 → G2/호스트 hold 표기), UPD p99 +4.0 %/+5.5 %(hold 25,220 미달). READ·UPDATE·p50·p99가 **모두 같은 방향으로 3~5 % 느려진 균일한 형상**이라 바인드 경로(UPDATE에 더 노출) 특이 변화로 보이지 않는다 — A는 `pgbuf_get_victim_from_lru_list`·커널 spinlock·로그 flush가 지배하는 IO/락 워크로드이고, 기준선 자체가 a3 26,944(−14 %)를 포함할 만큼 산포가 크다. perf A 레그(5M, perf 부착)는 32,688 ops/s로 기준 median보다 높았다. 판별을 위해 같은 시간대에 기준선 설치본으로 A×1을 재측정했다(a4ref, 아래).
- **판정: A의 floor 이탈은 호스트 시간대 변동.** 같은 시간대(12:33)의 기준선 설치본이 28,662 ops/s(09-10 median 대비 **−8.8 %**, READ p99 8,535)로 t1r7의 두 레그보다 낮다. 같은 시간대 대조로 읽으면 t1r7 A = **+4.7 % / +3.7 %**(a1/a2 vs a4ref), READ p99 −25 %. 즉 코드 회귀 신호는 없고 오히려 C와 같은 방향의 소폭 이득이다(단일 대조 레그라 기록용). 09-10 기준 median 31,423에 대한 hold 표기는 **호스트 귀속**으로 남긴다.
- 파생: **A 기준선은 하루 단위로 ±9 % 움직인다**(09-10 a3 26,944, 09-11 12:33 base 28,662). #253 스택 정식 게이트는 base A×3을 **같은 세션에서 교차(interleave) 재채집**해 비교해야 하며, 09-10 표를 그대로 기준으로 쓰면 오판한다 — runbook·맵 fog에 기록.

## 4. perf — 계수 소거 여부 (C·A, 5M ops, cycles 커널 포함, 30 s; 기준선 #244 perf.data를 §0과 같은 방법으로 재분해한 값과 비교)

| cycles, cub_server | C base → t1r7 | A base → t1r7 | 읽기 |
|---|---|---|---|
| `realloc` self (100 % R7-argv) | 0.27 → **0.00** | 0.21 → **0.00** | argv REALLOC 소멸 |
| `net_decode_str` → `net_decode_str_into` children | 1.16 → **0.08** | 0.98 → **0.08** | 디코드 경로 = 루프 자체만 남음(−1.1 %p) |
| R7-body(read_msg malloc/free 직접 귀속) | ≈0.54 → **0** | ≈0.33 → **0** | 분류기에서 R7-body·R7-argv 클래스 소멸 |
| `make_bind_value` → `_into` children | 1.26 → **0.75** | 1.15 → **0.65** | value_list malloc/free + wire clone 소멸 |
| └ `netval_to_dbval` children | 1.14 → 0.69 | 1.04 → 0.60 | 잔여 = self 0.11 + `lang_get_client_charset` 0.12 + `db_value_domain_init` 0.08 + `intl_check_string` 0.03 + inlined `db_make_char`/compose 검사 |
| └ T1-clone1 private heap(`hl_lea_alloc`+`db_private_alloc`) | 0.07 → **0** | — → 0 | CAS측 deep copy 소멸 |
| (유지) `pt_set_host_variables` children | 0.78 → 1.03 | 0.73 → 1.17 | 파서 보유용 복사 — 이제 **바인드 경로에 남은 유일한 deep copy** |
| `malloc` self | 2.53 → 1.96 | 1.46 → 1.54 | |
| `_int_malloc` self | 1.44 → 1.16 | 1.01 → 0.92 | |
| `malloc_consolidate` self | 2.11 → 1.66 | 0.95 → 0.86 | 잔여 100 % `qmgr_attach_first_page_copy`(#254 fog) |
| `_int_free` / `cfree` self | 1.03 / 0.45 → 0.79 / 0.34 | 0.73 / 0.36 → 0.56 / 0.34 | |
| **malloc 계열 합(realloc 포함)** | **7.83 → 5.91 (−1.9 %p)** | 4.72 → 4.22 (−0.5 %p) | 남은 최대 단일 소비자 = 결과당 `db_cp_query_type`(C children 3.18 → 2.73) |
| 후보 무관 대조: `__memmove` / `mutex_lock` / `lock_internal_perform_lock_object` / `__tls_get_addr` / `mht_clear` | 2.89/2.42/1.72/1.16/0.77 → 2.83/2.48/1.72/1.17/0.76 | | 프로파일 형상 동일 — 변화가 겨눈 경로에 국한됨 |

- 두 계수 모두 **가설대로 소거**됐다: R7은 realloc 0 + 디코드 inclusive 1.16→0.08, T1은 CAS측 clone과 배열 malloc 0. §0의 기대 상한(C self 1.5~2 %)과 C 실측 −1.9 %p(malloc 계열)가 일치한다.
- 관찰: `pt_set_host_variables` 지분이 0.78→1.03 %(C)로 **늘어** 보이는데, 분모(총 사이클/op) 감소분(≈5 %)만으로는 설명이 안 된다(기대 ≈0.82). 30 s 단일 샘플의 산포일 수도, alias 값(CHAR precision −1)이 `tp_value_cast_preserve_domain`에서 clone 대신 cast 경로를 타는 차이일 수도 있다 — 후속 T1-b(파서 borrow) 후보의 첫 확인 항목으로 §6에 적는다.
- perf 레그 소요가 17~27분으로 늘었다(YCSB+record는 수 분; 이 티켓이 `40_perf_leg.sh`에 추가한 15개 심볼 × flat 호출 사슬 `perf report`가 dwarf 5 GB perf.data에서 각 1~2분). 다음 티켓은 필요 심볼만 남기거나 `--percent-limit`을 올릴 것 — runbook에 메모.

## 5. PoC가 단순화한 지점 (후속 구현의 정확성 증명 항목)

1. **스크래치 상한 64 KiB·성장 정책은 임의값** — 상한 이상 body는 legacy malloc. #237 M3(요청 body/argv scratch 80 KiB+α)와 수치를 맞추는 것은 #237 몫. trim(축소) 없음 — 한 번 커진 스크래치는 세션 종료까지 유지(연결당 최대 64 KiB retained; G5 기울기 영향은 스택 #253에서 확인).
2. **재진입 가드는 busy 플래그 1개** — 같은 스레드에서 `cas_process_request`가 중첩되면 안쪽은 malloc. 현재 코드 경로에 중첩은 없다고 보지만 증명하지 않았다.
3. **alias 값의 생존 계약을 컴파일 타임/런타임으로 강제하지 않음** — `value_list[i]`가 `read_msg`를 가리키는 동안 `read_msg`가 살아 있어야 한다는 것은 기존 free 지점(요청 끝)에 의존. 제품판은 `T_REQ_INFO`에 body 소유권을 두고 `ux_execute` 계열이 그 수명 안에서만 alias 하도록 assert(또는 alias 값에 표식) 추가.
4. **alias 대상은 CHAR/VARCHAR만** — BIT/VARBIT·NCHAR 계열도 alias 가능하지만 YCSB 노출이 없어 제외. OBJECT(`ux_str_to_obj`)·LOB·JSON·set·수치는 기존 clone/coerce 경로.
5. **`ux_execute`만 inline 배열** — `ux_execute_all`(prepare+execute 통합)·`ux_execute_array`·batch·`ux_get/put_attr`는 래퍼를 통해 기존 heap 경로. 제품판은 동일 패턴 확장.
6. **`net_decode_str_into` 오버플로 경로 미검증** — 17개 이상 인자(다중 바인드 execute, array 실행)는 heap 성장 경로를 타지만 YCSB로는 타지 않는다. smoke 14건 중 다중 바인드 케이스가 있으면 통과 근거가 된다(§2).
7. **cgw·shard proxy 이진은 무변경** — `cas_cgw.c`는 기존 `net_decode_str`(래퍼) 호출, `shard_proxy_io.c`는 자체 복제본.
8. **SQL_LOG=OFF에서 측정** — 바인드 값 로깅(`cas_log_write_value_string`)이 alias 값을 읽는 경로는 요청 안이라 안전하지만 실측하지 않았다.
9. unit·CTP·정확성 증명 생략(throwaway 규약).

## 6. 처분

- **스택 포함**(#244 7항: C×1 +5.0 %, 회귀·크래시 없음, C p99 hold 없음). A×1은 09-10 median 기준 −4.5/−5.5 %로 클램프 floor 아래지만 같은 시간대 기준선 대조(a4ref 28,662)로 **호스트 변동으로 판정** — 코드 회귀 아님. 스택 티켓 #253이 정식 C×3·A×3으로 판정한다(A는 base 교차 재채집 필수).
- **후속 구현 채택: 채택 후보(소형·저위험).** 두 변경 모두 소유권 계약이 기존과 동일("요청 끝까지")하고 폴백 경로(상한 초과·재진입·9개 이상 바인드·소유 payload)가 legacy 코드 그대로라 정확성 증명 항목이 §5의 9개로 좁다. 이득은 C 사이클 ≈2 %p(malloc 계열 −1.9 %p + 디코드 −1.1 %p)·처리량 +5 %로, U1(+32 %)·U2/U3(+8 %)·T2/T3(+5 %) 다음 순위. 제품 반영 경로(7837 합류 vs 별도 PR)는 스택 처분표 뒤.
- **T1의 소유권 계약 초안(티켓 요구 산출)**:
  1. 요청 body(`read_msg`)의 소유자는 디스패처(`cas_process_request`)이며 수명은 "그 요청의 `server_fn` 반환까지". 스크래치/heap 어느 쪽이든 동일.
  2. `argv[]`·`value_list[]`의 alias 값(need_clear=false, payload가 body를 가리킴)은 body의 **차용자**로, 해제 의무가 없고 body보다 오래 살 수 없다. 이를 넘겨 보관하려는 쪽(파서 `host_variables`, 결과 캐시, SQL 로그 지연 기록 등)이 **자기 소유 복사**를 만든다 — 현재 `pt_set_host_variables`가 그 역할.
  3. `ux_execute` 계열은 alias든 clone이든 `db_value_clear`를 호출한다(alias면 no-op) — 호출자가 두 경우를 구분하지 않는 것이 계약.
  4. 제품판은 (a) body 스크래치를 `T_REQ_INFO`(세션 상태)에 두고 acquire/release를 요청 브래킷에 묶는다, (b) alias 여부를 DB_VALUE 표식 없이 need_clear로만 판별하므로 "need_clear=false인 문자열은 요청 body 또는 불변 메모리를 가리킨다"를 assert 가능한 불변식으로 승격(디버그 빌드에서 payload 주소가 body 범위 안인지 검사).
- **후속 PoC 후보 T1-b(파서 borrow)** — 바인드 경로에 남은 유일한 deep copy `pt_set_host_variables`(C 1.03 %·A 1.17 %). 파서 `host_variables`를 요청 수명 borrow로 바꾸려면 "실행 후 host_variables를 읽는 곳"(SQL 로그·query info·`db_get_hostvars`·재컴파일)의 수명 감사가 필요해 이 티켓 범위 밖. 스택 처분표(#253)에서 기존 P6·#254 소형 할당 군 후보와 함께 판정.
- 파생 fog: A 기준선의 일간 변동(±9 %) — #253 게이트 규약 보완(base 교차 재채집). perf 레그 후처리 27분 — runbook 메모.
