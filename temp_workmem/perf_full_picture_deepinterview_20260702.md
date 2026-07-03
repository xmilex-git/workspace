# temp-workmem 성능 전체 그림 — deep interview 시드 (2026-07-02 밤)

> 용도: 오너가 "성능을 접은 결정 전부"를 한눈에 보고 deep interview를 다시 하기 위한 단일 문서.
> 구성: A 원설계 → B 성능 현실(실측) → C 성능을 접은 결정 전수 목록(감사) → D 회수 경로 → E **오너 결정이 필요한 애매한 지점(인터뷰 안건)** → F "다 성능 좋게 하면 안 되나"에 대한 직답 → G #99 직렬 가드 정밀 분석.
> 근거 정본: SSOT #75 본문, 성능 감사 보고(2026-07-02, 이슈 #110~#112의 출처), #98 측정, #107 Phase 1 보고.

---

## A. 원설계 (tape design — 불변 목표, SSOT §1)

CUBRID temp/spill 경로를 **PostgreSQL work_mem 철학**(BufFile / logtape / SharedFileSet)으로 전면 개편(#60→#78).

- **축1 (생명주기/백킹)**: 처리 중 데이터 = per-worker work_mem 버퍼 + 오버플로는 per-worker private append-only **BufFile**(pgbuf BCB 우회, 전역 레지스트리·per-page 락 없음, offset 산술 주소). transient는 질의 종료 시 폐기. 질의 수명을 넘는 것은 정확히 2클래스 — holdable(세션 이관), cached-persist(결과캐시 copy-out).
- **축2 (연결구조)**: `qfile_connect_list`(cross-file next_vpid 재링크) 폐기 → `QFILE_LIST_ID`에 **Tapeset**(순서 있는 Tape 벡터). 워커가 자기 Tape을 생산·freeze(불변), 리더/세션이 논리 import. 스캔 좌표 = (tape_idx, page_offset, tuple_offset). 병렬 read = 64-page Chunk atomic work-stealing.
- **성능 논리**: 옛 구조의 비용 = 전역 페이지 레지스트리 + per-tuple dirty-mark 락 + pgbuf BCB 경유 + connect 재링크. 새 구조 = 락 없는 private append + zero-copy freeze + 산술 주소. **병렬화 해금(PHJ 5×)이 첫 이득, spill I/O 효율이 두 번째 이득**이어야 했다.
- holdable은 materialize(복사)로 **일단** 통일 착지(#94) — zero-copy reparent는 후속(ADR 0001 개정, 이제 #111이 추적).
- e21917cfd의 raw-fd 레거시(전역 레지스트리+per-tuple 락+VPID connect)는 Phase3(#74)에서 삭제.

## B. 성능 현실 (실측 — 좋은 것과 나쁜 것)

**좋은 것 (#98 44-leg, N=5 CoV≤0.15):**
- PHJ: 게이트 ON이 develop까지 능가 (695.9 vs 876.5ms @2000k). 게이트 설계 자체는 무죄.
- wide-row 전컬럼 확장모드: 회귀 없음 (ON/OFF 0.78~1.02, 한 케이스 -22% 개선). HYBRID 창 마이크로스윕 전 구간 ON 우세.
- #91 착지로 PHJ 추가 -21%.

**나쁜 것 (캠페인 최대 사실):**
- **branch 전체가 narrow 정렬/집계에서 develop 대비 1.9~3.1× 열세** — 게이트 ON/OFF 무관(base 문제).
- 원인 확정(#107 Phase 1): `qfile_put_next_sort_item`(list_file.c)의 **use_original=1 원본 재조회가 raw-fd 백킹 위에서 행당 ~0.8회 실제 pread**(develop 7.3만 vs branch 406만, 0.3GB 정렬에 62GB 읽기). develop은 같은 재조회를 하지만 pgbuf 512M가 공짜로 흡수. 재조회 접근 패턴이 순환(stride ~7.6p)이라 **readahead/캐싱으로는 못 구함 → re-fetch 제거(D1)가 정공법**.
- 완화장치였을 SortCache는 develop부터 `#if 0`으로 죽어 있음(list_file.c:4648) — pgbuf가 가려주던 결함이 raw-fd에서 노출된 구조.
- **D1(#107 Phase 2)은 현재 .30에서 구현 중 — 착지 전까지 캠페인의 성능 약속은 미실현 상태.**

## C. 성능을 접은 결정 — 전수 감사 결과 (11건, 숨긴 것 0건)

판정: **A** = 타당+회수 경로 추적됨 / **B** = 타당하나 미추적이었음(→ 오늘 이슈화 완료) / **C** = 과잉보수(해당 없음).

| # | 결정 | 무엇을 잃나 | 왜 | 회수 경로 | 판정 |
|---|---|---|---|---|---|
| 1 | #99(a) raw-fd 오버플로 입력 정렬 직렬 강제 (`9acdc6150`) | 해당 입력의 병렬 정렬 | px chunk_distributor가 raw-fd 페이지 열거 불가(절단 4.19M→349k의 원인) | 게이트 ON+NEW 입력이면 자동 해소, Phase3에서 raw-fd 자체 소멸 | A |
| 2 | #99(b) FILE_QUERY_AREA 출력 정렬 직렬 안전망 + sort-then-move 복사 1회 | 게이트 ON에서 대형 QUERY_CACHE 정렬 직렬 고정 + 결과 전량 복사 | px 워커의 query-area 쓰기는 same-tran-unsafe | **#110 (신규)** | B→해소 |
| 3 | #85 NEW 리스트 hash list scan HYBRID/HASH_FILE 비활성(non-hash 폴백) | NEW build 리스트의 해시 스캔 최적화 | synthetic curr_vpid의 tape_idx 소실(VPID punning 오답) | **#101** (use_original=1 복원과 함께) | A |
| 4 | #85 partial-key 정렬 use_original=1 차단 → 전컬럼 복사 정렬 | key-only 정렬 대비 넓은 temp 레코드 | 동일 punning | **#101** — 단 E-1 긴장 관계 참조 | A |
| 5 | #100/#103 NEW 입력 GROUP BY/ORDER BY/ANALYTIC 전컬럼 payload 운반 | 정렬/스필 바이트 증가 | key-only A_sort_key가 비키 컬럼 손상(SIGABRT 실물) | #98이 비용 무회귀 실측(0.78~1.02). #101이 좌표 정합 복원 | A |
| 6 | #105 CONNECT BY parent-pos 리스트 **영구** OLD 강제 | CONNECT BY-heavy 워크로드의 NEW 이득 영구 포기 | `QFILE_TUPLE_POSITION_DB` 직렬화 포맷에 TAPE 좌표 자리가 없음 | **없음(설계상 영구)** — E-2 인터뷰 안건 | A(단 영구 천장) |
| 7 | #94 holdable/Class-B materialize 전체 복사 통일 | 대형 holdable 결과 복사 1회 | 3싱크 tapeset-blind(release 0행)의 단일 착지 우선 | **#111 (신규)** — zero-copy reparent 복원 | B→해소 |
| 8 | #84 PHJ split: OLD 입력 또는 게이트 OFF면 직렬 | OLD 입력 split 병렬성 | OLD sector_page_iterator 행유실 실버그 | 게이트 ON+NEW면 병렬 복원. 단 **중첩 HJ는 HJ 출력 미이주 탓 게이트 ON에도 직렬** → **#112 (신규)** | B→해소 |
| 9 | P2 미이주 7사이트(머지조인/UNION/CTE/analytic/HJ ST) OLD 유지 + membuf 강제OFF(H-4) Phase3 이연 | 해당 연산자의 work_mem/BufFile 이득 전무 | 점진 이주(correctness-first) | #78 인벤토리 + #74 | A — E-5 안건 |
| 10 | #91 pool 바이트 상한 = work_mem cap의 1/4 | 상한 근접 시 조기 스필 | 무계정 RSS 증폭(degree×work_mem) 방지 | golden ±10% 무회귀 실측. 1/4은 매직넘버 — E-7 안건 | A |
| 11 | #107 D2(same-page 캐싱)/D3(readahead) 조건부 보류 (supervisor 결정) | D1 잔여 pread가 크면 추가 지연 | 순환 패턴이라 효과 의문 + 범위 최소화 | D1 재측정이 자동 판별 | A |

## D. 회수 경로 요약 (이슈 맵)

```
[진행 중] #107 D1 (.30) ──→ narrow 재측정 ≤ develop×1.10 ──→ #80 게이트 기본 ON
[게이트 ON 후 자동 해소] C-1(raw-fd 입력 직렬), C-8 일부(split 병렬 복원)
[#101] C-3/C-4 가드 해제 + 좌표 1급화  ← 단 E-1 긴장 관계 먼저 결정
[신규 #110] C-2 FILE_QUERY_AREA 직렬 해제
[신규 #111] C-7 zero-copy reparent 복원 (ADR 0001 개정 동반)
[신규 #112] C-8 중첩 HJ 직렬 — HJ 출력 이주(C-15)의 acceptance로 명시
[#78→#74] C-9 미이주 7사이트 + H-4 + raw-fd 삭제(C-1 근본 소멸)
[영구/결정 필요] C-6 CONNECT BY (E-2)
```

## E. "애매한 부분" = 오너 결정이 필요한 지점 (deep interview 안건)

이게 질문하신 "애매한 부분"의 실체입니다. 기술적으로 막힌 게 아니라 **방향 선택이 열려 있는 곳**들입니다:

- **E-1. #101 vs #107 D1의 방향 긴장 (가장 중요)**: D1은 "재조회를 없애기 위해 **전컬럼 운반을 확대**"하는 방향이고, #101의 절반(use_original=1 복원)은 "**운반을 줄이고 재조회로 회귀**"하는 방향 — 서로 반대다. #98은 운반 비용이 무회귀라 실측했고, D1이 착지하면 재조회 자체가 사라지므로 **use_original=1 복원의 성능 근거는 소멸할 수 있다**. 질문: D1 착지 후 #101을 "hash list scan 복원 + 좌표 정합성"으로 축소하고 use_original 복원은 폐기할 것인가? (Batch B 슬롯 2의 좌표 조사가 판단 자료를 만드는 중)
- **E-2. CONNECT BY 영구 천장 수용 여부**: 진짜 해제는 `QFILE_TUPLE_POSITION_DB` 직렬화 포맷에 TAPE 좌표를 추가하는 것 = 저장 포맷 변경. CONNECT BY-heavy 워크로드가 중요하지 않다면 영구 수용이 맞고, 중요하다면 Phase3 전에 포맷 확장을 설계해야 한다.
- **E-3. FILE_QUERY_AREA(#110)의 해법 선택**: (a) sort-then-move 전면화 — 단순하지만 복사 1회 상존 / (b) px-safe query-area 할당 설계 — 복사 0이지만 file_manager 동시성 설계 필요. 어느 쪽?
- **E-4. zero-copy reparent(#111) 우선순위**: holdable 대형 결과가 실워크로드에 얼마나 있나? 없으면 영원히 후순위가 맞다.
- **E-5. P2 미이주 7사이트의 이주 순서**: Phase3(#74)는 비가역 삭제라 그 전에 어디까지 이주할지 결정 필요. 머지조인/UNION/CTE 중 실워크로드 비중 기준 우선순위를 오너가 줘야 한다.
- **E-6. membuf 강제OFF(H-4) 제거 시점**: Phase3 이연이 맞나, 아니면 #80 전에 풀어 측정에 포함하나.
- **E-7. #91 pool 상한 1/4**: 검증은 됐지만 매직넘버. tunable로 노출할 가치가 있나(운영 복잡도 vs 튜닝 여지).
- **E-8. #80 전환 조건 "median ≤ develop×1.10"**: 1.10이 맞는 기준인가? PHJ처럼 이기는 축이 있으니 워크로드 가중 기준으로 바꿀 여지.

## F. "걍 다 성능 좋게 하는 게 어려워?"에 대한 직답

**아니오, 대부분 어렵지 않고 — 순서와 뿌리의 문제입니다.**

1. 성능 후퇴의 **뿌리는 단 2개**입니다: ① base spill 계층의 재조회 증폭(#107 — 지금 수정 중, 이게 1.9~3.1× 열세의 전부) ② TAPE 좌표가 2급 시민이라는 것(VPID punning — #85/#100/#103/#99 가드 전부의 공통 뿌리, #101이 1급화하면 한꺼번에 풀림). 나머지 가드들은 이 2개의 그림자입니다.
2. 순서가 강제되는 이유: 가드를 먼저 풀면(성능 먼저) 무음 오답 — 이 캠페인은 **70만 vs 248만 행 무음 절단, 4.19M→349k 절단, 힙오염, UAF**를 이미 실물로 냈습니다. 그래서 correctness 가드 → 병목 수정(#107) → 게이트 ON(#80) → 가드 해제(#101 등) → 레거시 삭제(#74) 순서입니다. 지금은 그 3단계째입니다.
3. 진짜로 "어려운"(= 공짜가 아닌) 것은 **1건뿐**: CONNECT BY(E-2, 저장 포맷). 나머지는 전부 경로가 있고 이슈로 추적됩니다(#107, #101, #110~#112, #78).

## G. #99 직렬 가드 정밀 분석 (완료 — 판정: 가드 유지 옳음, 한시적)

**G-1. 발동 반경은 QUERY_CACHE 전용이 아니다**: raw-fd 입력 가드(`external_sort.c:5206-5210`)는 병렬 예측이 서는 **모든 ORDER BY/ORDER WITH LIMIT**에서, 입력이 work_mem을 초과해 raw-fd로 스필했으면 무조건 발동한다. work_mem 중간 리스트는 초과 시 반드시 raw-fd로 가므로(`temp_page_store.cpp:3109-3162`, file_manager 폴백 없음) 일반 대형 ORDER BY도 걸린다. QUERY_CACHE 힌트는 흔한 사례였을 뿐.

**G-2. 그런데 잃는 병렬성이 사실상 없다 (핵심 발견)**: work_mem 아키텍처에서 OLD backing 병렬 정렬은 **가드 이전에도 실효 직렬이었다** — px sector scan은 membuf 전체를 CAS 승자 워커 1명이 통째로 가져가고(`list_file.c:4199-4247`), work_mem 리스트는 `temp_vfid=NULL`이라 나머지 워커가 가져갈 file_manager 섹터가 없다. 스필한 경우엔 membuf prefix만 정렬 = **오답(절단)**. 즉 가드 이전 세계는 "실효 직렬(정확)" 아니면 "빠른 오답" 둘뿐이었고, 가드는 후자를 전자로 바꾼 것이다. GROUP BY/DISTINCT/ANALYTIC 정렬은 애초에 `sort_check_parallelism`이 직렬로만 돌려서 절단 위험 자체가 없었다.

**G-3. 진짜 병렬 경로는 이미 존재한다**: 입력이 NEW(Tapeset) backing이면 sector scan 대신 `chunk_distributor`가 스필 포함 전체를 정확히 병렬 열거한다(`external_sort.c:5446-5456`). 즉 **진짜 수정 = 입력 리스트를 NEW backing으로 생산(#78 이주/#74 raw-fd 삭제)이고, 그러면 이 가드는 자연 소멸(죽은 코드)**. raw-fd sector scan을 별도로 병렬화하는 것(offset 산술이라 열거는 쉬우나 소유권/동시성 계약 신설 필요)은 곧 삭제될 코드에 대한 투자라 **하지 말 것**.

**G-4. sort-then-move 복사 비용은 좁다**: RESULT_FILE 제거는 "캐시 등록 ORDER BY + 병렬 예측 + raw-fd 미스필(membuf 내)"에서만 발동. 흔한 경우 전량 복사 1회, 결과가 스필한 경우 최대 2회(materialize+duplicate). 회피책(px-safe query-area 할당)은 file_manager 동시성 재설계라 독립 투자 비효율 — NEW backing 결과 생산이 함께 해소(#110에서 이 방향으로 판단).

**최종 판정**: ① 직렬 가드 유지는 옳다 — 포기한 "동작하던 병렬성"이 없고, 대안은 오답이었다. ② 단 "고전(pre-workmem) CUBRID 대비"로는 대형 스필 ORDER BY 병렬 정렬 손실이 실재한다 — 이 회복은 #99가 아니라 **workmem 캠페인 완성(#78 NEW 이주 + #80 게이트 ON)** 그 자체가 담당한다. ③ 후속 추적 2건: 가드를 "Phase3 완료 시 제거 항목"으로 #74 계약에 명시(완료), #110은 px-safe 할당이 아니라 NEW backing 결과 생산 방향으로 스코프 확정(완료). ④ 성능 캠페인에서 가드 발동 er_log 집계로 "고전 대비 손실이 실측 유의한가"를 데이터로 닫을 것(#97/#107 재측정에 편입).
