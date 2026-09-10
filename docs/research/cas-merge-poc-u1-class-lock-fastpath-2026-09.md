# PoC U1 — 클래스 IS 락 PG식 fastpath(약한 락 슬롯 + 강한 락 카운터, 보유 목록 O(n) 제거) — C×1·A×1 + 락 계수

- 티켓: [workspace#246](https://github.com/xmilex-git/workspace/issues/246) (맵 #207, 기준선 #244 상속, 후보 정의 [브레인스토밍 2 #218](https://github.com/xmilex-git/workspace/issues/218) G6/G7)
- 일자: 2026-09-11 · 측정 환경: #244 runbook 그대로(SMT off·nproc 32·idle 게이트·G2 체크포인트-조용 conf·golden→copydb)
- 기준 sha `d533969e4` 위 1커밋 `b086f17ae` · PoC 브랜치 `poc/u1-class-lock-fastpath` (xmilex-git/cubrid, 워크트리 `~/dev/worktrees/wf-poc-u1`) · 설치본 `/home/cubrid/release/CUBRID-wf-poc-u1`
- 원자료: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/results/u1/{smoke,c1,a1,perfC,perfA}` · diff `patches/u1-class-lock-fastpath.diff` · 패치 스크립트 `patches/u1_apply.py`

## 0. 왜 — 기준선 perf가 말하는 것

#218 프로브의 "lock 2.95 %"는 self 계수였다. 기준선(#244) perf.data를 **inclusive(children)** 로 다시 읽으면 락 왕복은 C 워크로드 cub_server 사이클의 **≈15 %** 다:

| 기준선 C (cycles, inclusive) | children | self |
|---|---|---|
| `xcache_find_xasl_id_for_execute` | 8.96 % | 0.31 % |
| └ `lock_object` → `lock_internal_perform_lock_object` | 7.90 % / 7.82 % | 1.72 % |
| &nbsp;&nbsp;└ `lf_hash_insert_internal`(find_or_insert + `res_mutex`) | 3.63 % | 0.29 % |
| `log_commit_local` | 8.72 % | 0.04 % |
| └ `lock_unlock_all` → `lock_internal_perform_unlock_object` | 7.46 % / 5.16 % | 1.54 % |

A 워크로드는 `lock_object` 4.02 % + `lock_unlock_all` 3.10 %(pgbuf victim 9.7 %가 지배).

실체: autocommit 문장마다 xcache가 `lock_object(class, root, IS|IX)` 를 부르고, 이는 (1) **root class 자원**에 IS/IX, (2) **usertable 클래스 자원**에 IS/IX를 잡는다. 두 자원 모두 100 커넥션이 공유하는 단일 `LK_RES`라 `find_or_insert`가 매번 같은 `res_mutex`를 잡고, holder 리스트(≈100 엔트리)를 `lock_find_my_holder_entry`·`lock_position_holder_entry`·unlock의 `total_holders_mode` 재계산에서 O(n) 으로 걷는다. 커밋의 `lock_unlock_all`이 같은 두 자원의 `res_mutex`를 다시 잡는다. 트랜잭션-로컬 `lock_find_class_entry` 우회는 **같은 트랜잭션 안의 재요청**만 돕고 autocommit엔 무력하다(#218 G6 사실).

## 1. 무엇을 바꿨나 (throwaway, 2파일 +620/−60)

PostgreSQL의 relation fastpath(`FP_LOCK_SLOTS_PER_BACKEND`=16, `FastPathStrongRelationLocks` 1024 파티션)를 CUBRID 락 매니저에 옮겼다.

**약한 클래스 락 = {IS, IX, SCH_S}** — 서로 전부 호환. 이 모드의 클래스 락(ROOT_CLASS 포함)은 **공유 `LK_RES` holder 리스트에 넣지 않고** 소유 트랜잭션의 `class_hold_list`/`root_class_hold`에만 둔다(`LK_ENTRY.is_fastpath`, `res_head == NULL`). 획득은 자기 `hold_mutex` 아래 O(1) 링크, 커밋의 `lock_unlock_all`은 O(슬롯) 언링크 — 공유 테이블 미접촉.

**강한 락 카운터** — 비약한 모드(S, SIX, X, SCH_M, BU) 요청자는 공유 테이블을 건드리기 **전에** `lk_Fp_strong_count[hash(class_oid)]`(1024 파티션, `std::atomic<int>`)를 올리고, `find_or_insert`로 `res_mutex`를 잡은 뒤 **모든 트랜잭션의 `hold_mutex`를 순서대로 잡아** 해당 OID의 fastpath 엔트리를 `LK_RES` holder 리스트로 이전한다(`lock_fp_transfer_all`; 엔트리 객체는 그대로 두고 `res_head`/`next`만 채움 → 소유자가 들고 있는 포인터(인스턴스 락의 `class_entry`, `lock_object` 지역변수)가 전부 유효). 그 뒤는 기존 호환성 검사 그대로. 약한 요청자는 **자기 `hold_mutex` 안에서** 카운터를 읽는다: 0을 봤으면 링크가 강한 요청자의 스캔 이전에 끝나 스캔에 잡히고, 스캔이 먼저 끝났으면 뮤텍스 핸드오프(acquire/release)로 증가가 보인다. 카운터는 강한 엔트리가 `lock_free_entry`로 죽을 때 내린다(`holds_strong_count`).

**락 순서** `res_mutex → hold_mutex` 로 기존(`lock_insert_into_tran_hold_list`)과 동일. fastpath 자체는 `hold_mutex` 안에서 어떤 `res_mutex`도 잡지 않는다.

| 변경 지점 (`lock_manager.c/.h`) | 내용 | 규칙 |
|---|---|---|
| `LK_ENTRY` | `key_oid`/`key_type`(자원 키 사본 — `res_head` 없이 클래스 엔트리 식별) · `is_fastpath` · `holds_strong_count` | — |
| `LK_TRAN_LOCK.fp_count` | 트랜잭션당 fastpath 엔트리 수, 상한 `LK_FP_SLOTS_PER_TRAN`=16(초과는 slow path) | PG 동일 |
| `lk_Fp_strong_count[1024]` | 강한 락 보유·대기 카운터. **읽기 지배**(문장마다 load, 쓰기는 DDL급)라 파티션별 패딩 없음 | PAR-10(read-mostly), GLOB-09 의도적 미적용(핫 writer 부재) |
| `lock_internal_perform_lock_object` 클래스 분기 | `lock_fp_find_class_entry`(hold_mutex 아래 is_fastpath/res 동시 판독) → 신규 약한 요청 `lock_fp_try_grant_new` / 자기 fastpath 엔트리 재요청·IS→IX 전환 `lock_fp_try_regrant` / 강한 요청 카운터↑ → `find_or_insert` 뒤 `lock_fp_transfer_all`(자기 엔트리 포함) → 기존 상태기계 | COH-12(공유 대신 소유 분할) |
| `lock_internal_perform_unlock_object` | fastpath 엔트리 → `lock_fp_release_entry`(O(1), 공유 테이블 미접촉). `move_to_non2pl` 요청이면 `lock_fp_self_transfer_slow`로 공유 테이블에 먼저 이전 후 기존 경로(non2pl 의미론 보존) | — |
| `is_fastpath` 판독 | unlock 경로의 무뮤텍스 판독은 `__atomic_load_n(ACQUIRE)`, 이전 측 클리어는 `__atomic_store_n(RELEASE)` — `res_head` 게시가 먼저 보이도록 | COH-10 |
| `lock_free_entry` | `holds_strong_count`면 카운터↓(강한 락의 유일 퇴장 지점) | — |
| `res_head->key` 참조 7곳 | `key_oid`/`key_type` 사본으로 교체(tran hold list insert/delete·`lock_find_class_entry`·escalation 2·`lock_object` 상위클래스·granule 증감·2PC prepare `lock_fp_entry_key`) | — |
| 사전 컴파일 검사 | 기준 빌드 트리 compile_commands로 SERVER/SA 두 모드 `-Werror` 단일 TU 컴파일 통과 | — |

## 2. 게이트 — fresh release 빌드 + smoke

- fresh `release`(RelWithDebInfo) 빌드 **3 m 56 s**, `lock_manager` 경고 0(빌드 전체 198건은 기존 파일). 설치본 `CUBRID-wf-poc-u1`: `libcubrid.so.11.5` sha256 `8389b1c4…`, `cub_server` `f6fb9bd4…`, JDBC 0076 동일.
- 캠페인 conf 적용 후 `smoke.sh smk` **14/14 PASS**(DDL·GRANT/REVOKE·PL/CSQL·동시 4세션·RR 포함), `smoke_jdbc.sh smk 33000` **SMOKE_JDBC: SUCCESS**(B1 전 단계, 3× SUCCESS). 서버 .err에 segfault/fatal/assert 0, core 0.
- 운용 메모(하네스): 첫 smoke 시도 14/14 FAIL은 엔진이 아니라 레시피 — `CUBRID_DATABASES`를 **unset**하면 엔진이 `databases.txt`를 **프로세스 cwd 기준**으로 찾는다(`databases_file.c:227`). `createdb`는 `$CUBRID/databases` 안에서 실행돼 성공했고 `smoke.sh`는 결과 디렉터리에서 실행돼 서버가 못 떴다(-174/-113). `CUBRID_DATABASES=$CUBRID/databases`를 명시해 재실행 → 통과. 실패 로그는 `smoke/smoke_sh.attempt1_cwd_mismatch.log`로 보존. runbook에 smoke 절 추가.

## 3. 측정 — C×1 · A×1 (기록용)

| leg | ops/s | READ p50 | READ p99 | UPD p50 | UPD p99 | checkpoints | errors | loadavg_before |
|---|---|---|---|---|---|---|---|---|
| base c1/c2/c3 (#244) | 115,550 / 118,374 / 119,919 | 766/750/742 | 2,433/2,299/2,293 | – | – | 0 | 0 | 4.97/4.67/5.05 |
| **u1 c1** | **156,669** | **564** | **1,551** | – | – | 0 | 0 | 3.14 |
| base a1/a2/a3 (#244) | 31,423 / 31,447 / 26,944 | 372/351/328 | 6,107/5,507/5,291 | 4,559/4,687/5,679 | 22,927/22,735/26,383 | 0 | 0 | – |
| **u1 a1** | **32,216** | 329 | 6,795 | 4,295 | 22,655 | 0 | 0 | 3.66 (5분 12.02) |

- **C: +32.35 %**(+24.8 base-MAD; 트랙 최대 — t23 +5.3 %, t23b +4.9 %). p50 **−24.8 %**, p99 **−32.5 %**(hold 2,529 미달 → G2 hold 없음). 회귀·크래시·오류 없음 → **스택 포함**.
- **A: +2.52 %**(+2.5 클램프-MAD, floor 30,481 통과). UPDATE p50/p99 −8 %/−1 %, READ p50 −6 %. **READ p99 6,795 > hold 6,058(+23 %) → #244 7항대로 G2 귀속 hold 표기**. 단서: a1은 idle 게이트 통과 직후 5분 loadavg 12.0(타 테넌트 감쇠 중)에서 기동됐고, A의 perf에서 `pgbuf_get_victim_from_lru_list` 9.71 → 1.77 %로 지배 심볼이 바뀌어 tail의 귀속은 스택 A×3에서 다시 본다. A는 pgbuf victim·로그 커밋(`log_commit_local` 12 % 유지)이 지배해 락 왕복 소거의 처리량 효과가 작다(설계 예상과 일치).

## 4. perf — 락 계수 소거 여부

cycles(커널 포함)·dwarf·30 s @ t=20 s·5M ops·게이트 통과 후 기동. **inclusive(children)** 비교:

| symbol (children / self) | base C | **u1 C** | base A | **u1 A** |
|---|---|---|---|---|
| `xcache_find_xasl_id_for_execute` | 8.96 / 0.31 | **1.85** / 0.26 | 4.06 / 0.18 | **1.14** / 0.16 |
| `lock_object` | 7.90 / 0.09 | **0.49** / 0.04 | 4.02 / 0.07 | **1.10** / 0.09 |
| `lock_internal_perform_lock_object` | 7.82 / 1.72 | **0.41** / 0.17 | 3.98 / 1.08 | **1.07** / 0.22 |
| └ `lf_hash_insert_internal`(find_or_insert) | 3.63 / 0.29 | 0.24 / 0.08 | 1.87 / 0.39 | 0.67 / 0.28 |
| `log_commit_local` | 8.72 / 0.04 | **1.52** / 0.02 | 12.94 / 0.07 | 12.17 / 0.06 |
| `lock_unlock_all` | 7.46 / 0.06 | **0.23** / 0.04 | 3.10 / 0.03 | **0.62** / 0.03 |
| `lock_internal_perform_unlock_object` | 5.16 / 1.54 | 0.13 / 0.06 | 2.17 / 0.90 | 0.52 / 0.08 |
| **락 왕복 합(lock_object + lock_unlock_all)** | **15.4 %** | **0.7 %** | **7.1 %** | **1.7 %** |
| `__pthread_mutex_lock` self | 2.42 | 2.28 | 2.34 | 2.45 |
| `__lll_lock_wait` / `futex_wake` self | 0.41 / 0.68 | 0.21 / 0.49 | – / 0.50 | – / 0.69 |

- **가설 검증**: C에서 락 왕복 inclusive 15.4 % → 0.7 %(−14.7 pp), A 7.1 → 1.7 %. 남은 `lock_object` 0.5 %는 인스턴스 락 경로(A의 UPDATE X 락)와 fastpath 자체 비용(`hold_mutex` 3쌍/문장). `lock_fp_*`·`lock_find_my_holder_entry`는 static 단일 호출자라 **인라인돼 심볼로 안 나온다**(`nm` 확인; 기준선의 `lock_find_my_holder_entry`도 "(inlined)"로만 보였음).
- **`__pthread_mutex_lock` self는 그대로**(2.4 → 2.3 %): 락 매니저 res_mutex가 빠진 자리를 `heap_classrepr_get`/`heap_classrepr_free`의 버킷 뮤텍스(0.48 + 0.31 %)가 최상위 caller로 채웠다 → **U3(classrepr 엔트리 뮤텍스 캐시라인 분리, #248)의 직접 근거**. 커널 `native_queued_spin_lock_slowpath`는 C 0.84 → 1.16 %, A 1.65 → 3.06 %로 늘었다(처리량 증가에 따른 futex/스케줄러 경합 상승; A의 tail 표기와 함께 스택에서 재확인).
- C top-10 self에서 `lock_internal_perform_lock_object`(1.72)·`lock_internal_perform_unlock_object`(1.54)가 사라지고 `pgbuf_fix_release` 1.24 → 1.64, memmove 2.89 → 3.08, malloc 2.53 → 2.55 — 일반 경로가 더 많은 문장을 처리한 결과(비율은 유지). 남은 상위는 t23/t23b·T1/R7·N1의 대상과 겹친다.

## 5. PoC가 단순화한 지점 (후속 구현의 정확성 증명 항목)

YCSB에는 DDL이 없어 강한 락 경로는 **연결만 하고 미검증**이다(컴파일·smoke 14케이스에는 CREATE/DROP/GRANT/REVOKE·PL/CSQL이 포함되어 크래시 여부만 확인). 제품 구현이 증명·보완해야 할 것:

1. **non2pl 미재생.** 이전(`lock_fp_transfer_one_locked`)은 `lock_update_non2pl_list`를 재생하지 않는다 — RR 트랜잭션이 클래스 S 락을 풀어 non2pl로 남긴 뒤 다른 트랜잭션이 fastpath IX를 잡으면 "inconsistent non2pl" 표시가 빠진다. 제품판: 클래스 자원에 non2pl 엔트리가 생기는 순간 강한 카운터처럼 fastpath를 닫거나(non2pl 카운터), 이전 시 재생.
2. **lockdb(`xlock_dump`)·`lock_get_number_object_locks`** 는 자원 해시만 걷어 fastpath 엔트리를 보여주지 않는다(PG는 `pg_locks.fastpath` 열로 노출). 이벤트 로그의 `lock_event_log_lock_info`만 "fastpath class lock" 한 줄 처리.
3. **강한 카운터의 강등 비대칭.** `lock_internal_demote_class_lock`(X→IS 등)은 카운터를 내리지 않는다(엔트리가 죽을 때만). 보수적(fastpath가 더 오래 닫힘)이며 정확성 무해.
4. **데드락 탐지·타임아웃 로그**는 자원 홀더 리스트 기준 — fastpath 홀더는 누구도 막지 못하므로(강한 요청자가 먼저 이전) WFG 누락 없음. 단 `lock_event_log_tran_locks`류가 fastpath 클래스 엔트리를 만나는 경로는 실행되지 않아 미검증.
5. **`lock_fp_transfer_all` 비용** O(num_trans) 뮤텍스 쌍 — DDL급 요청에만 발생. 트랜잭션 수 수천에서의 지연은 미측정.
6. **fp_count 상한 16 초과·엔트리 할당 실패** 시 slow path 폴백 — 미검증(YCSB는 클래스 2개).
7. **`lock_fp_is_weak_mode`에 SCH_S 포함** — SCH_S는 SCH_M과만 비호환이므로 안전하나, SCH_S를 요구한 뒤 `lock_unlock_object(force)`로 푸는 경로가 non2pl을 요구하면 self-transfer slow path를 탄다(비용만, 의미론 동일). 빈도 미측정.
8. **2PC prepare(`lock_unlock_all_shared_get_all_exclusive`)** 는 fastpath IX 엔트리의 키를 `lock_fp_entry_key`로 합성 — 복구 재획득(`lock_reacquire_crash_locks`)까지 미검증.
9. **인스턴스 락의 `class_entry` 포인터** 는 fastpath 클래스 엔트리를 가리켜도 유효(객체 이동 없음). escalation(`lock_escalate_if_needed`)은 fastpath IS/IX 엔트리에서 S/X 강한 요청으로 이어져 self-transfer → 정상 전환; 미검증.
10. **약한→약한 전환(IS→IX) 의 정당성**은 "카운터 0 ⇒ 이 클래스에 강한 보유자·대기자 없음 ⇒ 모든 홀더가 약한 모드 ⇒ IX 호환" 논증에 의존한다. 모든 강한 획득이 `lock_internal_perform_lock_object` 클래스 분기를 통과한다는 전제(복구·loaddb BU 포함) 를 제품판이 감사해야 한다.

## 6. 처분

- **처분 제안: 스택 포함(#253) + 후속 구현 채택 1순위 + 상류 보고(CBRD 후보).** C×1 +32 %·p99 −33 %는 이 트랙의 다른 후보 합계보다 크고, 락 왕복 inclusive 계수가 15 % → 0.7 %로 소거돼 귀속이 명확하다. 회귀·크래시 없음. A는 +2.5 %로 floor 통과, READ p99만 G2/호스트 hold 표기(스택 A×3에서 판정).
- **G7 적용**: 락 매니저는 폴드가 건드리지 않은 서버 선존 코드라 **상류급** — 폴드 성과에 미합산하고 CBRD 후보로 표기한다. 단서: 상류(브로커/CAS 경유) 배치에서는 CAS hop이 문장 간 간격을 벌려 res_mutex 경합 밀도가 낮으므로 절대 이득은 이보다 작을 수 있다(폴드가 경합을 응축한 뒤에 가장 크게 드러난 항목). 상류 보고 시 vanilla 기준선 재측정이 필요하다.
- **제품 반영 전 필수**: §5의 10개 항목 증명 + 강한 락 경로 TC(DDL 동시성·escalation·2PC·RR non2pl)·CTP sql/medium 전건·lockdb 노출. 구현 자체는 PG 설계의 직역이라 PoC 코드(2파일 +620/−60)가 초안으로 쓰일 수 있다. 정정 후보: `lock_fp_find_class_entry`와 `lock_fp_try_grant_new`의 `hold_mutex` 2회를 1회로 합치기(문장당 뮤텍스 3쌍 → 2쌍).
- **파생 입력**: `__pthread_mutex_lock` 최상위 caller가 `heap_classrepr_get/free`로 바뀜 → U2/U3(#248) 우선순위 유지·근거 보강. A 워크로드의 `native_queued_spin_lock_slowpath` 3 %·`pgbuf_get_victim` 지배 변화는 스택 A×3 perf에서 귀속.

운용 메모: 워커 셸이 zsh라 `${PIPESTATUS[0]}`가 비어 종료코드 캡처가 한 곳 빠졌다(PASS/FAIL 집계로 대체 확인). 이후 위임 프롬프트는 `bash -c` 래핑 또는 `$pipestatus`(zsh)를 명시할 것.
