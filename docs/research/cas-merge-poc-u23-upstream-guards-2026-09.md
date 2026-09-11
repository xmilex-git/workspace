# PoC U2/U3 — mht_clear 빈 가드 + classrepr 엔트리 캐시라인 분리 + 스레드 소유 classrepr pin — C×1 + 상류 보고 근거

- 티켓: [workspace#248](https://github.com/xmilex-git/workspace/issues/248) (맵 #207, 기준선 #244 상속, 후보 정의 [브레인스토밍 2 #218](https://github.com/xmilex-git/workspace/issues/218) U2/U3 — 상류급 G7)
- 일자: 2026-09-11 · 측정 환경: #244 runbook 그대로(SMT off·nproc 32·idle 게이트·G2 체크포인트-조용 conf·golden→copydb)
- 기준 sha `d533969e4` 위 1커밋 `8d44e2fc1` · PoC 브랜치 `poc/u23-upstream-guards` (xmilex-git/cubrid, 워크트리 `~/dev/worktrees/wf-poc-u23`) · 설치본 `/home/cubrid/release/CUBRID-wf-poc-u23`
- 원자료: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/results/u23/{smoke,c1,perfC,c2c}` · diff `patches/u23-upstream-guards.diff`(4파일 +261/−8)

## 0. 왜 — 기준선·U1 perf가 말하는 것

두 후보 모두 **폴드와 무관한 서버 선존 비용**(G7)이며, 티켓의 프로브 수치(#218: `mht_clear` 1.32 %/1.04 %, classrepr 뮤텍스 0.54~1.17 %, c2c HITM 라인 #1)를 #244 기준선과 U1 perf.data에서 inclusive(children)로 다시 읽으면:

| cycles, cub_server, C 워크로드 | 기준선 #244 children / self | U1 #246 children / self |
|---|---|---|
| `heap_classrepr_get` | 1.13 % / 0.09 % | **3.18 %** / 0.19 % |
| `heap_classrepr_free` | 0.45 % / 0.03 % | **1.74 %** / 0.07 % |
| └ 호출자 `heap_attrinfo_start`·`heap_attrinfo_end` | 1.06 % · 0.53 % | 2.22 % · 1.45 % |
| └ 호출자 `heap_get_indexinfo_of_btid` | 0.74 % | 2.12 % |
| `__pthread_mutex_lock` self 중 classrepr 귀속 | 0.32 + 0.17 = 0.49 % | 0.48 + 0.25 = 0.73 % |
| `mht_clear` (self ≈ children) | 0.80 % | 0.74 % |
| **U2+U3 합계(inclusive)** | **≈2.4 %** | **≈5.7 %** |

A 워크로드 기준선: `heap_classrepr_get` 1.34 % · `heap_classrepr_free` 0.61 % · `mht_clear` 0.55 %.

실체:
- **U3** — autocommit READ 1문장이 `usertable` 표현을 **2번 fix/unfix** 한다: 스캔의 `heap_attrinfo_start/end`와 인덱스 스캔 준비의 `heap_get_indexinfo_of_btid`. 한 쌍 = `hash_mutex` 1회 + 엔트리 `mutex` 2회(get의 trylock→lock, free의 lock), 100 커넥션이 **같은 엔트리 한 개**(단일 핫 클래스)를 두드리므로 c2c HITM 라인 #1(#218 L4: 엔트리 뮤텍스 0x10~0x20 + `heap_classrepr_get`이 읽는 필드 0x38)이 된다. U1이 락 매니저 왕복(15.4 %)을 걷어내자 classrepr 왕복이 **다음 직렬화 지점**으로 떠올랐다(1.6 % → 4.9 %).
- **U2** — `logtb_tran_clear_update_stats`가 **매 커밋** `mht_clear`를 2회(`Tran_unique_stats`·`Tran_classes_cos`, 각 101버킷) 호출하고, `mht_clear`는 `nentries`를 보지 않고 101버킷을 전부 순회·NULL 재기록한다. 읽기 전용 트랜잭션(C 100 %, A의 READ 절반)은 두 테이블이 항상 비어 있다.

## 1. 무엇을 바꿨나 (throwaway, 4파일 +261/−8)

### U2 — `mht_clear` 빈 테이블 단락 (`memory_hash.c` +12)
`nentries == 0`이면 act/lru 리스트가 이미 비어 있고 모든 버킷이 NULL임이 `mht_put*/mht_rem`의 부기로 보장되므로 `ncollisions = 0`만 하고 즉시 반환(BR-07/A60). 모든 `mht_clear` 호출자에 적용되는 일반 가드 — 비어 있지 않은 테이블은 기존 경로 그대로.

### U3(a) — 엔트리·해시 앵커 캐시라인 분리 (`heap_file.c`, MEM-03/COH-04)
`HEAP_CLASSREPR_ENTRY`(112 B, malloc 16 B 정렬 → 엔트리 2개가 한 라인 공유)를 **64 B × 2 라인**으로 재배치: 라인 0 = fix/unfix마다 쓰는 `mutex`·`fcnt`·`zone`·`force_decache`·`next_wait_thrd`, 라인 1 = 해시 체인 워커가 **엔트리 뮤텍스 없이** 읽는 `class_oid`·`hash_next`·`repr`·`idx`·LRU 링크·reprid. `HEAP_CLASSREPR_HASH`(64 B)도 `aligned(64)`. 두 배열은 `posix_memalign(64)`으로 할당(선언만 정렬하면 malloc이 깨뜨림).

### U3(b) — 스레드 소유 classrepr pin (`heap_file.c` + `thread_entry.hpp/.cpp`, PAR-10/COH-12/COH-10)
티켓 (b)안 "문장당 get/free 쌍을 트랜잭션 로컬 pin으로"를 **스레드 로컬·트랜잭션 경계 무관**으로 넓혔다(autocommit에서 트랜잭션-로컬 pin은 문장당 2쌍 → 1쌍만 줄이지만, 스레드 pin은 0쌍으로 만든다).
- `THREAD_ENTRY.classrepr_pins[4]` — 슬롯 = {`idx`, `nref`, `gen`, `reprid`, `oid_key`, `repr`}. pin은 엔트리 `fcnt` 참조 1개를 **소유**한다.
- `heap_classrepr_get`: 진입 시 pin 조회(TLS 스레드 엔트리 기준) — OID·reprid(NULL_REPRID 또는 pin의 last reprid) 일치면 `nref++` 후 반환. **공유 메모리 쓰기 0**. 미스면 기존 경로, 캐시 히트/삽입 시 `cache_entry->mutex`를 쥔 채 `fcnt++` 한 번 더 하고 빈 슬롯에 채택(라운드로빈 축출, 축출은 어떤 캐시 락도 쥐지 않은 진입부에서만).
- `heap_classrepr_free`: `nref > 0 && idx == pin.idx`면 `nref--`로 끝(공유 접촉 없음). 아니면 기존 경로(`heap_classrepr_free_internal`). 참조는 fcnt 위에서 fungible하므로 pin-경유 참조와 일반 참조가 섞여도 총량이 맞는다(pin-경유 get 수 = nref 감소 수, 나머지 free는 일반 경로).
- **무효화** = 프로세스 전역 `heap_Classrepr_pin_gen`(atomic int). `heap_classrepr_decache_guessed_last`가 해시 체인 **언링크 후**(hash_mutex 해제 후) release로 +1, get은 체인 조회 **전**에 acquire로 스냅샷 → 언링크 이전에 엔트리를 찾은 get은 반드시 구세대를 저장하고 다음 get에서 불일치를 본다(COH-10). 불일치 + `nref == 0`이면 일반 free로 참조 반환(→ `force_decache`면 그 자리에서 재활용).
- **DDL 비차단**: `heap_classrepr_decache`는 fcnt를 기다리지 않는다(`force_decache` 마킹 후 마지막 unfix가 재활용). 유휴 커넥션의 pin은 DDL을 막지 못하고 엔트리 재활용만 그 스레드의 다음 get까지 늦춘다. 문장 수준 안전성은 기존과 동일: IS/IX 클래스 락을 잡은 뒤에야 `heap_attrinfo_start`가 pin을 보고, DDL은 SCH_M 획득 뒤에만 decache한다.

| 변경 지점 | 내용 | 규칙 |
|---|---|---|
| `mht_clear` | `nentries == 0` 단락 | BR-07, A60 |
| `HEAP_CLASSREPR_ENTRY`/`HEAP_CLASSREPR_HASH` | 2라인 분리·`aligned(64)`·`posix_memalign` | MEM-03, COH-04 |
| `heap_Classrepr_pin_gen` | decache 세대(release/acquire) | COH-10 |
| `heap_classrepr_pin_lookup/adopt/release` | 스레드 슬롯 4개, 라운드로빈 축출, 중첩 get 채택 충돌은 채택 생략 | PAR-10, COH-12 |
| `heap_classrepr_free` → `_internal` 분리 | pin 경유 참조 단락 | — |
| SA/CS 빌드 | pin 코드는 `SERVER_MODE` 한정, 레이아웃 변경만 공유 | — |
| 사전 컴파일 검사 | U1 빌드 트리 compile_commands로 SERVER/SA `-Werror` 단일 TU 통과(3 TU) | — |

## 2. 게이트 — fresh release 빌드 + smoke

- fresh `release`(RelWithDebInfo) 빌드 성공(`CUBRID 11.5.0 (11.5.0.2836-8d44e2f)`, 08:37 KST). 설치본 `CUBRID-wf-poc-u23`: `libcubrid.so.11.5` sha256 `df7d67cc…`, `cub_server` `1143b921…`, JDBC 0076 동일(`3e876fb1…`).
- 캠페인 conf 적용 후 `smoke.sh smk` **14/14 PASS**(DDL·GRANT/REVOKE·PL/CSQL·동시 4세션·RR 포함 — DDL 케이스가 pin 무효화 경로를 실제로 통과), `smoke_jdbc.sh smk 33000` **SMOKE_JDBC: SUCCESS**. 서버 .err에 error/assert/fatal 0, core 0. SMT off 확인(`control=off active=0 nproc=32`).

## 3. 측정 — C×1 (기록용, #244 7항)

| leg | ops/s | READ p50 | READ p99 | checkpoints | errors | loadavg_before |
|---|---|---|---|---|---|---|
| base c1/c2/c3 (#244) | 115,550 / 118,374 / 119,919 | 766/750/742 | 2,433/2,299/2,293 | 0 | 0 | 4.97/4.67/5.05 |
| **u23 c1** | **128,066** | **680** | 2,295 | 0 | 0 | 3.65 |

- 기준 median 118,374(MAD 1,545) 대비 **+8.19 %(+6.3 MAD)**, p50 **−9.3 %**, p99 −0.2 %(hold 2,529 미달 — G2 hold 없음). floor 113,739 위 → **회귀 아님, 크래시 없음 → 스택 포함**.
- 참고: U1 단독 C×1은 +32.4 %였다. U23은 U1 위에서 더 커질 후보다(U1 프로파일에서 classrepr 왕복이 4.9 %로 3배 불어난 것이 §0 표) — 정식 판정은 스택(#253).

## 4. perf — 계수 소거 여부 (C, 5M ops, cycles 커널 포함, 30 s)

| 심볼 (cub_server cycles) | 기준선 #244 | **u23** | 비고 |
|---|---|---|---|
| `mht_clear` self | 0.77 % | **0.07 %** | 잔여는 가드 자체(호출+분기) — 목표 "self→0" 달성 |
| `heap_classrepr_get` children / self | 1.13 % / 0.09 % | **0.09 % / 0.07 %** | 잔여 = pin 조회(TLS 읽기+슬롯 4개 스캔) |
| `heap_classrepr_free` children / self | 0.45 % / 0.03 % | **0.03 % / 0.02 %** | |
| `heap_attrinfo_start` / `heap_attrinfo_end` children | 1.06 % / 0.53 % | 0.66 % / 0.22 % | 남은 것은 attrinfo 자체 작업 |
| `heap_get_indexinfo_of_btid` children | 0.74 % | 0.19 % | |
| `__pthread_mutex_lock` self | 2.42 % | **1.97 %** | 호출자 목록에서 `heap_classrepr_*` **소멸**(기준선 0.49 %) |
| `__lll_lock_wait` self | — | 0.38 % | |
| `__tls_get_addr` self | 1.16 % | 1.19 % | pin의 TLS 읽기 2회/문장이 더해졌으나 총량은 노이즈 안(N1 #247의 대상) |
| `log_commit_local` children | 8.72 % | 8.80 % | U2가 뺀 0.7 %p는 락 매니저 unlock(U1 미적용 설치본)에 가려짐 |

`perf c2c`(시스템 전역 20 s, `perf c2c record -a`): Load Local HITM 127,051 / Remote 83,258, LLC miss→remote HITM 33.2 %, 공유 라인 49,502(#218 프로브 C: 129,376 / 78,120 / 34.0 % / 47,032 — 총량은 같은 대역). **상위 HITM 라인에서 classrepr 엔트리 라인 소멸**(`c2c_top.txt`에 `heap_file.c`/`classrepr` 심볼 0건). 상위는 이제 #0 QMGR 질의 엔트리 상태+뮤텍스(1,446 HITM, #218 F3 선존), #1 pgbuf BCB(`pgbuf_fix_release`/`pgbuf_unfix`, 1,005), #2 QMGR 임시파일 뮤텍스(`qmgr_create_new_temp_file`, 788) — 전부 #218 라인 #0/#2/#4 그대로 한 칸씩 올라온 것.

## 5. PoC가 단순화한 지점 (후속 구현·상류 보고의 정확성 증명 항목)

1. **pin 미회수** — 스레드 엔트리 소멸·커넥션 종료 시 pin을 반환하지 않는다(엔트리 풀 재사용 시 다음 스레드가 세대 검사로 이어받음). 1,000+ 유휴 커넥션이 각 4엔트리까지 1024-엔트리 캐시를 점유할 수 있어 미스 시 "캐시 만원 → 디스크 repr 반환" 절벽 가능. 제품판은 커넥션/스레드 종료 훅에서 `heap_classrepr_pin_release` 전수 호출 + 슬롯 수 조정.
2. **decache 세대가 전역** — 어느 클래스의 DDL이든 모든 스레드의 모든 pin을 무효화한다(다음 get에서 1회 재채택 비용). DDL 빈도가 높은 워크로드에서 per-class 세대(엔트리 라인 1의 필드)로 정밀화 가능.
3. **`heap_classrepr_restart_cache`(크래시 리커버리)가 pin을 리셋하지 않음** — 부트 시점이라 활성 pin이 없다는 가정. 제품판은 finalize/restart에서 전 스레드 pin 무효화(세대 +1로 충분치 않음: idx가 새 area를 가리키게 되므로 슬롯 자체를 비워야 한다).
4. **중첩 get 채택 충돌은 채택 생략** — 클래스 레코드 읽기 중 재귀 get이 같은 빈 슬롯을 먼저 채우면 바깥 get은 pin하지 않는다(두 엔트리 뮤텍스 동시 보유를 피하기 위해). 성능 영향만, 정확성 무관.
5. **TLS 기준 pin** — `heap_classrepr_free`에 thread_p가 없어 get도 TLS 스레드 엔트리를 쓴다(문장당 `__tls_get_addr` 2회 추가). `heap_classrepr_free`에 thread_p 인자를 더하는 시그니처 변경(호출자 100+)은 제품판 몫.
6. **reprid 지정 get은 pin 대상 아님** — `reprid != last_reprid`(구 표현으로 레코드 읽기)는 기존 경로. YCSB엔 없음.
7. **fungible 참조 회계의 증명** — pin-경유 참조와 일반 참조가 같은 fcnt 위에 섞이는 불변식(`nref` 감소 수 = pin-경유 get 수, 나머지 free는 일반 경로)은 문서상 논증만; 제품판은 DEBUG_CLASSREPR_CACHE 아래 스레드별 카운터 assert 추가.
8. **U3(a) 레이아웃의 단독 효과 미분리** — (a)와 (b)를 한 설치본에 넣었다. pin이 핫패스의 엔트리 접촉을 없앴으므로 c2c 소거의 주역은 (b); (a)는 미스 경로·다중 클래스 워크로드용. 상류 보고 시 (a)는 독립 소형 패치로 분리 가능.
9. **U2 `assert(act_head == NULL && lru_head == NULL)`** — release에서 꺼짐. `mht_put*/mht_rem` 부기 신뢰가 전제(mht_rem은 act/lru 양 리스트에서 언링크 확인).
10. unit·CTP·정확성 증명 생략(throwaway 규약).

## 6. 처분

- **스택 포함**(#244 7항: 회귀·크래시 아님, p99 hold 없음). 스택 티켓 #253이 U1과 함께 정식 C×3·A×3으로 판정.
- **상류(CBRD) 보고 초안 근거** — 둘 다 폴드 무관 서버 선존 비용(G7, 폴드 성과에 미합산):
  - **U2**: `mht_clear`가 `nentries`를 보지 않고 전 버킷을 순회 — 매 커밋 2×101버킷 NULL 재기록, C 워크로드 cub_server 사이클 0.77 %. 12줄 일반 가드, 의미론 변화 없음 → 독립 소형 PR 후보(가장 낮은 위험).
  - **U3(a)**: `HEAP_CLASSREPR_ENTRY` 112 B·16 B 정렬로 뮤텍스+fcnt와 체인 워커가 읽는 `class_oid`/`hash_next`가 한 라인, 이웃 엔트리와도 공유 — #218 c2c 라인 #1. 재배치+`posix_memalign` 만으로 독립 패치 가능.
  - **U3(b)**: 문장당 classrepr fix/unfix 2쌍(스캔 attrinfo + 인덱스 info)이 100 커넥션에서 한 엔트리 뮤텍스를 두드림 — 기준선 1.6 %, U1 적용 후 4.9 %(다음 직렬화 지점). 스레드 pin + decache 세대로 핫패스 공유 접촉 0. 보고에는 §5의 1·3·5·7 증명 항목을 함께 올린다. 상류 CAS 구성에서는 세션당 CAS 프로세스가 각자 서버 스레드에 붙으므로 같은 경합 밀도가 재현되며(엔트리 뮤텍스는 서버 내부), U1과 달리 vanilla 재측정 없이도 방향은 유효 — 수치만 재채집.
- **스택 포함 여부**: 포함. 후속 구현 채택 순위는 스택 결과 뒤(단독 +8.2 %는 U1 +32.4 %·T2/T3 +5.3 % 다음).
- 파생: 45_c2c_leg.sh를 runbook에 추가(선택 레그). c2c 상위 라인이 QMGR 질의 엔트리·pgbuf BCB·임시파일 뮤텍스로 정리됨 — F3(QMGR 엔트리 스레드 로컬 캐시) fog의 계수 갱신.
