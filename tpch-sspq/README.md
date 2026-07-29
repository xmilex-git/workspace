# TPCH-SSPQ

CUBRID와 PostgreSQL의 **TPC-H single-session parallel query** 동작을 같은 장비·같은 데이터셋 위에서
비교 분석하는 프로젝트다. 다중 사용자 처리량(QphH)이 아니라, **세션 하나가 쿼리 하나를 실행할 때
엔진이 확보하는 병렬성과 그 확장 한계**가 관심 대상이다.

이 폴더는 workspace 저장소의 기존 single-context 규칙에서 **의도적으로 분리된 독립 컨텍스트**다.
프로젝트 문서와 ADR은 모두 이 폴더 안에 둔다(ADR 0001).

## 다음 세션 시작점 (컨텍스트 없이 시작해도 이것만 읽으면 된다)

**`contract_revision: 2`** (원칙 v2 = ADR 0020, 2026-07-29 채택). 용어가 전면 치환됐다 —
`G2` → **`PER_QUERY_CONNECTION_DIAG`**, `실행 단위 파리티` → **`configured-cap parity`**,
`규명 완료` → **`measured, correctness-unverified`**.

**상태: `PER_QUERY_CONNECTION_DIAG` 완주. Q1·Q21·Q9·Q8·Q18·Q15·Q3 측정 완료
(전부 `measured, correctness-unverified` — SF1 reference correctness 미수행, ADR 0020 §7).**

**순위 표기 규칙 (ADR 0020 §3)** — complete-case와 censored를 섞지 않는다.

| 구분 | 쿼리 | 값 |
|---|---|---|
| **전체 22개 최상위 (censored lower-bound)** | **q22** | CUBRID `timeout_ext` **≥300.008 s** / PG **0.971 s** → 격차 **≥299.03 s**, 배수 **≥309x**. **다음 대상**(ADR 0020 §6) |
| censored — 양쪽 | q17, q20 | 양쪽 ≥300 s → 격차 판정 불가, 순위 제외 |
| **complete-case Pareto (완주 19개)** | q1~q16, q18, q19, q21 | 아래 표. `positive_pareto` 누적 **84.1 %** (complete-case 분모) |

| Q | complete-case 순위 | 배수 [wall] (configured-cap parity) | 형상 일치 배수 [wall] | 곱 분해 (이벤트 단위 명시) | IPC (C/P) | 지배 버킷 [cycles] | 보고서 |
|---|---|---|---|---|---|---|---|
| **Q21** | **1위** | **14.32x** (single-query-repeat) | 3.23x | 플랜 **4.436x** [wall] × 행당 **3.228x** [CPU-초] | 1.807/1.563 | 인덱스 탐색·키 비교(B-tree) 35.9 % (42.4x) | `docs/report-q21-gap-20260729.md` |
| **Q1** | 2위 | **3.070x** | (미측정) | (플랜 축 미측정) | 2.339/2.357 | (cycles 미측정) instr 식 평가 31.2 % + 값/도메인 22.0 % + 수치 16.3 % = **69.5 %** | `docs/report-q1-symmetric-profile-20260728.md` |
| **Q9** | 3위 | **2.741x** (single-query-repeat) | 2.79x | 플랜 **0.984x** [wall] × 행당 **2.785x** [CPU-초] | 1.929/1.378 | **지배 버킷 없음** — 상위 6개가 89.5 %를 나눈다 | `docs/report-q9-gap-20260729.md` |
| **Q8** | 4위 | **3.960x** (single-query-repeat, PG read-light) | 3.96x | **`0.999x × 0.9314x × 4.2559x`** 또는 **`3.508x × 1.129x`** (이 두 표기만 허용, ADR 0020 §5) | 2.132/1.374 | 정본형상 B-tree 35.1 % / **형상 일치 시 B-tree 0 %**, Q1형 3버킷 46.8 % | `docs/report-q8-gap-20260729.md` |
| **Q18** | 5위 | **1.247x** (single-query-repeat) | **1.877x** | 플랜 **0.664x** [wall] × 실행단위 **1.541x** [units 비] × 행당 **1.218x** [CPU-초] | **1.811/2.447** | **instructions 비 0.858x — CUBRID가 더 적다.** cycles 1위 식 평가/튜플 구성 101.9 %, 2위 버퍼 고정·래치 94.2 % (leader 23.2 %) | `docs/report-q18-gap-20260729.md` |
| **Q15** | 6위 | **2.179x** (single-query-repeat) | **2.179x** (네이티브 형상 일치) | 플랜 **1.000x** [wall] × 실행단위 **1.262x** [units 비] × 행당 **1.716x** [CPU-초] | **2.29/1.94** | **술어 평가 47.7 % (22.0x)** — 스캔·디코드는 **0.97x 동률** | `docs/report-q15-gap-20260729.md` |
| **Q3** | **7위** | **2.2573x** (single-query-repeat) | **1.8109x** (PG 형상) ↔ **1.1826x** (CUBRID 형상) | 플랜 **1.2465x** [wall] × 실행단위 **0.7986x** [units 비] × 행당 **2.2676x** [CPU-초], 검산 **0.00 %** | **1.55/1.94** | **B-tree 49.3 % (∞) + 버퍼 고정·래치 47.5 % (12.3x) = 96.8 %** — 스캔·디코드는 **0.95x 동률** | `docs/report-q3-gap-20260729.md` |

**Q3의 결론: 새 범주 `플랜형(옵티마이저 오선택형)`.** Q21의 `플랜형`과 다르다 —
**플랜 축이 CPU를 바꾸지 않는다.** CUBRID의 질의실행분 CPU-초는 idx-NL 47.30 s ↔ USE_HASH 47.60 s로
**0.6 % 동률**이고, 플랜 축 1.2465x는 전부 `time-weighted active units` 5.61 → **7.05**(노드 cap 6의
**117.5 %**)에서 나온다. **Q3에서 새로 확정된 것 6건**:
(a) **`parallelism`은 쿼리 단위 상한이 아니라 노드 단위 상한**이고 전역 예산은
`max_parallel_workers`(CUBRID **100** ↔ PG **8**, `px_worker_manager_global.cpp:57-78`)다 —
현행 `configured-cap parity`는 노드 cap만 맞추고 **전역 예산 12.5배 비대칭을 방치**한다.
cubH가 동시 활성 **12단위**까지 올라간 것이 그 비대칭이 물린 첫 사례이며 라벨은
**`configured-cap 초과`**(신규)다.
(b) **형상 일치 배수가 둘로 갈리는 첫 쿼리** — PG 형상 1.8109x ↔ CUBRID 형상 1.1826x.
CUBRID의 인덱스 NL 경로는 cycles 1.234x로 PG와 거의 대등하다(버퍼 1.19x / B-tree 1.10x).
따라서 **정본 버킷 표의 "B-tree 49.3 %"는 플랜 형상의 부산물**이고 형상을 맞추면 13.6 %로 떨어진다
(Q8에서 확정한 성질의 강한 재현).
(c) **`instructions` 비가 두 번째로 하한**이다(1.9522x < wall 2.2771x, IPC 비 **0.799**) —
`instructions` 기반 서술 금지. `cycles` 2.4397x가 wall보다 7.1 % 큰 잔차는 유효 클럭 비
2.476/2.289 = 1.0817과 units 비 1.0098로 **0.04 %** 내에 닫힌다.
(d) **버퍼 고정·래치 역전이 다섯 번째로 재현**되되 형태가 다르다 — 순위는 2위로 같고
**절대 델타가 instr 28.31 G → cycles 33.57 G로 커져** 1위와의 격차가 47.9 %p → **1.8 %p로 붕괴**한다
(그 버킷 IPC **0.83**, B-tree는 2.06). 뿌리는 **플랜이 페이지를 27.79배 더 만지는 것**이다 —
CUBRID 39,538,926 page fix ↔ PG 1,422,457 buffer access, **fix 1회에 659 cycles**
(`page_buffer.c:2211`, lock-free fast path `:7670`이 이미 있는데도).
(e) **`perf record -a -C`의 심볼 해석 함정 등재** — perf 4.18은 레코드 시작 전 존재하던 sibling
스레드의 map group을 연결하지 못해 CUBRID 정본 프로파일의 **99.95 %가 `[unknown]`**이 됐다
(워커 풀 재사용). 오프라인 심볼라이저 `q3/scratch/resolve.py`로 보정하고 perf 해석분과
**95.68 % / 96.42 % 일치**를 검산했다. **이전 라운드 CUBRID 프로파일은 재검증 대상**이다.
(f) **ADR 0019 §4-c leader 클럭 이득이 재현되지 않는다**(leader 2.378 GHz < worker 2.513 GHz,
직렬 0.50 s) → 조항을 **"직렬 구간이 wall의 20 % 이상일 때만"**으로 좁혔다(ADR 0020 §5).
또한 **ADR 0016 민감도 판정도 좁혔다** — PG Q3는 잔존율이 30.2 → 66.6 %(**+36.4 %p**, Q8의 3.6배)로
움직이는데 `Execution Time`은 −1.86 %다(미스 단가 **0.175 µs**) → 판정 기준은 잔존율 이동이 아니라
**"미스 감소량 × 단가가 wall에서 관측되는가"**다.
**개선 후보 5개** 제시(A NL probe 비용 재교정 = 신규 / B `pgbuf_fix_release` hit 경로 단축 = 기존 ③ 확장,
**A+B 동시 착지 시 1.722x** / C 힙 튜플 디코드 특화 = ①, 형상 일치 시 1위 / D 전역 병렬 예산 쿼리 단위화
= 신규, **성능이 아니라 계약 정합 후보** / E B-tree descent 캐시 = ④, 형상 의존).
**기존 후보 중 ②⑤⑥⑦⑧⑬ 정본 배제, ⑫⑭ 부분 해당, ⑮ 채증**(전부 채증).

**Q15의 결론: 새 범주 `필터 지배형`이고, 양쪽이 동시에 단위 붕괴한다.**
`2.1650x = 플랜 1.0000x × 실행단위 1.2620x × 행당 1.7155x`(검산 오차 **0.00 %**).
**플랜 축이 네이티브로 1인 첫 쿼리**다 — 형상이 계열까지 일치하고 노드별 실제 행수도 일치해
(스캔 통과 2,265,714 / 그룹 100,000 / 최종 1) 강제할 형상 차가 없다.
**Q15에서 새로 확정된 것 5건**: (a) **세 문장 정의 문제는 닫혔다** — `PER_QUERY_CONNECTION_DIAG` 하네스는 `create view`/`select`/
`drop view` **세 문장 전체를 한 호출로** 쟀고(정의 A = 정본·헤드라인), 정의 B(select만)와 차이가
**0.01 %**다. DDL이 **양쪽 정확히 4 ms**여서 뷰 생성 비용의 격차 기여는 **0.0000 s**다.
(b) **양쪽 모두 뷰를 실체화하지 않고 인라인 확장해 lineitem을 2회 스캔한다** — CSE가 어느 엔진에도 없다.
양쪽을 단일 평가(CTE 실체화)로 바꾸면 CUBRID −49.2 % / PG −54.2 %이고 **배수는 2.165x → 2.400x로
악화**한다(양쪽 공통 구조 문제). (c) **술어 평가가 격차 1위인 첫 쿼리** — cycles 격차의 **47.7 %**(22.0x),
행당 **CUBRID 150.5 vs PG 6.8 cycles**. 반대로 **스캔·레코드 디코드는 0.97x 완전 동률**이고
(`heap_attrinfo_read_dbvalues` 90 cycles/행 vs PG `tts_buffer_heap_getsomeattrs` **174 cycles/행**)
Q1형 3버킷은 죽는다(식 평가 **1.00x**, 수치 **0.62x로 CUBRID가 적다**). 뿌리는
`query_evaluator.c:1666 eval_pred`가 `A AND B`에 대해 **행당 3회 재귀** 호출되고 `:152-279`가 행마다
상수·타입 판정을 재수행한 뒤 도메인 일반 비교로 내려가는 것 — 스캔에 융합된 상수 범위 검사가 없다.
(d) **양쪽 동시 `단위 붕괴`가 Q18에 이어 두 번째** — CUBRID **59.3 %**(wall의 **50.1 %가 leader 단독
GROUP BY**), PG **74.8 %**. CUBRID 뿌리는 **Q18과 같은 한 줄** `external_sort.c:5232`
`if (px == NULL || px->hash_eligible) return 1;`이고, 뷰가 2회 평가되므로 **직렬 구간도 2회** 온다.
PG 뿌리는 **코드가 아니라 클러스터 상한**이다 — 외곽 `Gather Merge`가 워커 5개를 쥔 채 `InitPlan`이
트리거되어 `bgworker.c:1105`에서 8−5=3만 등록된다(`Workers Launched: [3 5]`, 5회 반복 결정적,
표본화로 **8워커 공존을 pid 단위 확인**). **`max_parallel_workers=8` 기본값을 유지**하고 상한을 올린
보조 통제 런은 하지 않았다 — 이 손실은 실행 단위 축에 포함해 별도 기록하며, **배수 인용 시
"PG InitPlan 3워커(클러스터 상한 8) 포함"을 명기**한다. 단일 평가 A/B가 이를 확증한다(PG 74.8 →
**86.7 %** 복귀, CUBRID 59.0 %로 **불변**). (e) **직렬 구간은 클럭 이득을 받는다** — 행위자별 역산
클럭이 CUBRID leader **2.81 GHz** > worker 2.21 GHz다(직렬 구간엔 코어 1개만 바빠 turbo가 더 붙는다).
**병렬화 상한 계산에 클럭 하락을 반영해야 한다** — 반영하지 않으면 후보 A의 상한이 1.26x로 과대평가된다.
**개선 후보 5개** 제시(A GROUP BY 최종화 병렬화 = 기존 ⑦, 상한 **1.31~1.53x** / B 술어 평가 스캔 융합,
**1.91~2.05x** / C 반복 뷰 CSE / D MVCC 페이지 단위화 / E 적재 밀도 대칭화)이고 **A+B 동시 착지 시 1.05x**.
**기존 후보 8개 중 ②③④⑤⑥ 배제, ⑧ 사실상 배제, ①은 유지하되 격차 설명력 ≈ 0**(전부 채증).
**Q15 PG는 io worker pid가 런 중 2 → 6개로 동적 증가**해 그 열을 **2.207 s/런(PG SUT CPU의 9.9 %)**로
정정했다. **PG 귀속 검증에 새 방법을 썼다** — `perf stat -p <postmaster>` + 새 psql 세션이면 leader가
런 중 fork되어 상속되므로 **leader+워커를 정확히** 센다(instructions 귀속 **100.10 %**). 이번 회차
`-a -C` idle 감산법은 idle 6 s 창이 배경 부하 **75.12 G instructions**를 담아 성립하지 않았다.

**Q18의 결론: 낮은 배수는 작은 격차가 아니다 (ADR 0019).** 1.247x는 **두 플랜 오류의 상쇄값**이고,
형상을 맞추면 **1.877x**, 집계 서브쿼리만 떼면 **1.958x**다. PG는
`pg_stats.n_distinct(l_orderkey)`가 **397,034**(실제 15,000,000, **37.8x 과소**)라서 상위 조인을
오선택해 **wall의 34.6 %(10.59 s)**를 버린다 — CUBRID의 NDV 추정은 오차 0.47 %로 정확했고
인덱스 NL을 골랐다. **Q18에서 새로 확정된 것 3건**: (a) **`instructions` 비가 처음으로 1 미만**
(**0.858x** — CUBRID가 명령을 더 적게 쓰고도 느리다). IPC가 **역전**됐고(1.811 vs 2.447 = 0.740x)
"instructions 비는 상한"이라는 규칙이 깨진다 → **정본 비교축을 `cycles`로 격하**(ADR 0019 §2).
(b) **양쪽이 동시에 `단위 붕괴`인 첫 쿼리** — 이용률 CUBRID **41.1 %** / PG **46.9 %**, 실행 단위 축이
처음으로 **주축(1.541x)**이고 행당 비용 축은 처음으로 1에 근접한다(1.218x). 0.05 s 표본화로
**격차 7.56 s의 86.3 %가 1단위 구간**(CUBRID 26.67 s = wall의 69.8 %, PG 20.15 s = 65.8 %)임을
채증했다. (c) **CUBRID의 직렬 구간은 코드 상수다** — `external_sort.c:5232`
`if (px == NULL || px->hash_eligible) return 1;` 때문에 GROUP BY 외부 정렬이 **항상 직렬**이다
(`input_list->page_cnt` 423,552가 문턱 2048을 207배 넘지만 그 계산에 도달하지 못한다).
`/*+ NO_HASH_AGGREGATE */`로 조항을 끄면 정렬은 실제로 6워커가 되지만 입력이 15 M→60 M로 4배가 되고
병합·최종화(`:5829`, `:5841`)가 여전히 직렬이라 **53.07 s로 더 느려진다.** 그 직렬 26.67 s의
**cycles 23.2 %가 버퍼 고정·래치**다 — 단일 스레드인데 BCB 뮤텍스를 잡는다.
**Q18 PG는 ADR 0016 하위 레짐에 무감하다**(`hit+read` 2,552,611 완전 동일, 미스 −18.0 %에 wall +0.68 %) —
비용이 shared buffer 미스가 아니라 임시파일 스필(temp 6.9 GB read / 9.0 GB written)에 있기 때문이다.

**Q9의 결론: 플랜 축은 격차를 만들지 않는다.** CUBRID에 PG 형상을 강제하면 1.6 % **느려지고**,
PG에 CUBRID 조인 순서를 강제하면 35 % 느려진다 — 두 옵티마이저가 각자 옳았다. **실행 단위 축도
0.23 %로 닫혔다**(이용률 CUBRID 98.8 % / PG 96.4 %). Q9는 **Q1형 + Q21의 B-tree 하이브리드**다.
**Q9에서 새로 확정된 것 2건**: (a) **instructions 비 4.233x가 wall 2.741x를 과장한다** — IPC가
CUBRID 1.929 vs PG 1.378(1.40x)이고 **cycles 비 3.022x**가 시간 비에 가깝다. Q1(IPC 사실상 동일)과
다르므로 **앞으로 프로파일 배수를 인용할 때 이벤트를 명기한다.** (b) **cycles에서 순위가 뒤집힌다** —
버퍼 고정·래치가 instr 3위(13.3 %) → **cycles 1위(27.8 %)**, 집계·해시는 기여 부호가 역전
(+2.2 % → −4.7 %, PG `ExecParallelScanHashBucket` IPC 0.27).

**Q8의 결론: Q1형이되, 실행 단위 축이 처음으로 닫히지 않았다.** 플랜 축 **0.999x**(CUBRID에 PG 형상을
강제해도 0.1 % 차)이고 역방향은 **1.870x**(PG에 CUBRID 형상 강제) — CUBRID 행당 비용이 워낙 커서
**어느 플랜을 골랐는지가 관측되지 않는다.** 실행 단위 축은 **1.129x**(이용률 CUBRID **86.5 %** vs PG 97.6 %)
이고, 원인은 스레드 표본화로 특정됐다 — **wall의 15.1 %(1.37 s)가 실행 단위 1**로 도는 직렬 꼬리이며,
그 구간은 gather 위의 중간 리스트 스캔(668페이지)이 `parallel_scan_page_threshold=2048` 문턱에 걸려
직렬로 떨어진 뒤 그 위 `customer` PK 인덱스 NL이 통째로 직렬화된 것이다
(`px_scan.cpp:885`, `px_parallel.cpp:118-122`, `system_parameter.c:5135-5140`). 제거 시 3.960x → **3.47x**.
**정본 형상의 B-tree 39.2 %는 플랜 축이 아니라 플랜 형상의 부산물**이다 — 형상을 맞추면 B-tree는
**0 %**가 되고 Q1형 3버킷이 **53.3 %(instr) / 46.8 %(cycles)**로 그 자리를 그대로 차지한다.
**Q8 PG는 ADR 0016 하위 레짐 축에 민감하다**(`hit+read` 1,465,669 완전 동일, 분할만 이동 →
미스 −17.5 %에 wall −10.6 %, 단가 2.62 µs/미스). 그래서 같은 single-query-repeat 안에서도
배수가 **3.43x(read-heavy) ↔ 3.96x(read-light)**로 갈린다. CUBRID는 무감.

**여러 쿼리에 걸치는 최우선 개선 후보 (Q18에서 2개 신규 등재, 기존 6개 유지)**:
① **힙 튜플 디코드 인터프리테이션 제거**(`heap_file.c:10255-10302/10315-10358/10464-10525`,
`object_primitive.c:8968-8978`; Q1 9.9 % + Q9 23.8 % + Q8 26.1 %; **Q18 레버 아님** — 병렬 구간
전용이라 wall 환산 −0.55 s) —
② **노드 경계 튜플 재구성 제거**(`query_opfunc.c:625/356/6327`, `fetch.c:4852`;
Q1 31.2 % + Q9 23.6 % + Q8 30.6 %, cycles 11.5x; **Q18 cycles 1위 +36.23 G — 총 cycles 격차
+35.55 G보다 크다**) —
③ BCB 뮤텍스 → 원자 연산 + per-thread pin 캐시
(`page_buffer.c:950-957`; Q9 cycles 1위 27.8 % + Q21 23.67 % + Q8 19.8 % +
**Q18 직렬 leader cycles 23.2 % — 경합이 없는 단일 스레드에서 뮤텍스를 잡는다**) —
④ B-tree descent 페이지 캐시 + midxkey 비교 특화 (`btree.c:5190`, `object_primitive.c:7731`;
Q21 51.5 % + Q8 정본 39.2 % + Q9 11.6 %; **Q18 0.0 % — 해당 없음**) —
⑤ **중간 리스트 스캔 병렬화 문턱을 비용 기반으로**(`px_scan.cpp:885`; Q8 단독 12.9 %,
Q5·Q11 미확인; **Q18 해당 없음** — Q18의 직렬 노드는 리스트 스캔이 아니라 GROUP BY 정렬이다) —
⑥ NUMERIC pass-through(`object_primitive.c:8743-8800`; Q1 16.3 % + Q9 8.0 % + Q8 9.2 %;
**Q18 cycles 1.00x 완전 동률 — 해당 없음**) —
⑦ **[신규] GROUP BY 병합·최종화의 병렬화**(`external_sort.c:5232` 선반환 / `:5829` 직렬 fan-in /
`:5841-5848` 직렬 final run, `query_executor.c:5657/5662`, `xasl_generation.c:16563`;
**Q18 단독 wall의 69.8 %**, 3단위 시 1.247x → **0.67x**, 6단위 시 **0.52x**. 난이도 높음 —
`qexec_gby_put_next`가 그룹 상태를 공유한다) —
⑧ **[신규] `px_scan_result_handler::write()`의 `thread_local` 호이스팅**
(`px_scan_result_handler.cpp:49`/`:787-925`, `hpp:80`; 이미 있는 해법 패턴 `:939-940`;
Q18 워커 instructions 7.6 % / cycles 5.2 %, 전체 cycles 3.6 %. **난이도·위험 최저, 비용/효과 비 최상**).
⑨ **[Q3 신규] NL 인덱스 probe 비용 재교정** — `ISCAN_IO_HIT_RATIO 0.5` 하드코드 제거,
`HJ_MEM_ALLOC_CONSTANT`의 NL 선호 오프셋 폐기, probe 비용에 인덱스 높이 × page fix 단가 반영
(`query_planner.c:98`/`:3411`/`:87`/`:3650-3658`; Q3 플랜 축 **1.2465x** 전량. 모델은 probe:row를
0.91:1로 보는데 실측은 **4.49:1** = 4.9배 역방향 오차. **위험 높음** — 22쿼리 전체 플랜이 바뀐다) —
⑩ **[Q3 신규] 전역 병렬 예산을 쿼리 단위로** — `parallelism`은 노드 cap이고 전역 예산은
`max_parallel_workers`(CUBRID 100 ↔ PG 8)다 (`px_parallel.cpp:172`,
`px_worker_manager_global.cpp:57-78`; **성능 개선이 아니라 `configured-cap parity` 정합 후보**.
Q3 cubH가 동시 활성 12단위로 cap 6을 117.5 % 초과했다).
**구현은 아직 없다.** 다음 대상은 **q22**(censored lower-bound ≥309x, bounded profile + 플랜 규명,
ADR 0020 §6 — 새 세션으로 별도 지시). 그 밖의 미측정 항목: ADR 0018·0019가 남긴 Q5·Q11의 **양쪽**
`time-weighted active units`, 백로그 3건(`TRUE_SINGLE_CONNECTION`, `SF1_CORRECTNESS`, rev 1 raw 백업 tar).

### 측정 계약 요약 (전문은 아래 "확정 결정"과 `docs/adr/`)

| 항목 | 값 |
|---|---|
| **`contract_revision`** | **2** (ADR 0020). rev 1은 ADR 0001~0019까지의 계약이며 과거 결과의 실행 계약으로 보존한다. rev 1 결과를 rev 2 용어로 다시 쓸 때는 `실행 계약 rev 1 / 기술 rev 2`를 명기한다 |
| **정본 트랙** | **`configured-cap parity`** — 노드 단위 cap을 CUBRID `parallelism=6` ↔ PG `max_parallel_workers_per_gather=5`(+leader)로 맞춘다. **전역 예산은 맞추지 않는다**(CUBRID `max_parallel_workers=100` ↔ PG `8`, 12.5배 비대칭 — 기록 대상). "6 실행 단위 파리티"라는 표현은 폐기됐다 (ADR 0014+0020 §4) |
| **run metadata 의무** | 모든 run 디렉터리에 `meta.json`: `contract_revision`, `track`, `connection_mode`, `protocol`, `cpuset`, `timeout_method`, `sut_boundary`, `configured_cap`, `build`(commit+Build ID), `config_deviations`, `correctness`, `artifacts`(sha256). 표준 스크립트 `q3/scratch/meta.sh`. **계약≠실행이면 `CONTRACT_MISMATCH` + 중단.** metadata 없는 run은 표에 올리지 않는다 (ADR 0020 §2) |
| **상태 라벨** | **`measured, correctness-unverified`**. SF1 reference correctness 미수행이므로 **"완료"를 쓰지 않는다**. 대체 채증(엔진 간 결과 동일성·노드별 행수 일치)은 하위 증거일 뿐이다 (ADR 0020 §7) |
| **순위 표기** | **complete-case(완주 19개) Pareto와 censored lower-bound를 분리**한다. 전체 22개 최상위는 **q22**(≥309x), Q21은 **"완주 19개 complete-case Pareto 1위"**로만 표기 (ADR 0020 §3) |
| **트랙 명칭** | 구 `G2` = **`PER_QUERY_CONNECTION_DIAG`** (쿼리마다 클라이언트를 새로 띄운다 → 단일 connection 결과로 표현 금지). `TRUE_SINGLE_CONNECTION`은 백로그 (ADR 0020 §1) |
| **기준선 (Q1)** | CUBRID **31.612 s** / PG **10.296 s** = **3.070x** (mmap 기준. ADR 0010+0015) |
| **WARM 규칙** | 세트 전 warmup 1회 미집계 + **엔진 전환 직후 재수행**, 집계 런 physical read≈0 채증(문턱 1 % / 100 MiB), 실패 런 무효 (ADR 0006). **하위 레짐 표기 의무** — `stream` ↔ `single-query-repeat`을 같은 표에 섞지 않는다. PG는 **쿼리 조건부로** 민감(Q21 12.72x ↔ 14.32x, Q8 3.43x ↔ 3.96x / **Q9·Q18 무감**), CUBRID는 무감 (ADR 0016) |
| **timeout** | 쿼리당 **300초**. PG는 세션 GUC `statement_timeout`(엔진 취소), **CUBRID는 기제가 없어 외부 `timeout 300`으로 클라이언트를 감싼다** → 그래서 CUBRID는 쿼리별 개별 호출이 필요하다 (CONTEXT.md 비대칭 항) |
| **격리** | 양쪽 서버 node0 `0-15` 핀, **클라이언트도 SUT cpuset 공유**, 수집기만 밖(20-23) (ADR 0012) |
| **PG DSM** | **`dynamic_shared_memory_type=mmap`** — 기본값 `posix` 이탈. `/dev/shm`이 64000k 고정이라 Parallel Hash 쿼리가 기본값에서 실패했다 (ADR 0015) |
| **CPU 회계** | 주 지표 `cub_server` ↔ backend+workers. `broker+CAS`(=클라이언트측 처리 역할)와 **파싱·플랜 시간**은 별개 열 필수, 합산 단일 숫자 금지 (ADR 0009+0011). PG **`io worker`도 별개 열**(Q21 실측 SUT의 +4.99 %), PG worker CPU는 **N회+settle 브래킷**으로 재야 회수 누수가 없다 (ADR 0017) |
| **대외 인용 단서 3건** | (1) PG 개발 스냅샷 핀 (2) CUBRID 히스토그램 on (3) PG mmap — 어느 엔진도 "출시 기본 설정 성능"이 아니다 |
| **병렬 라벨** | 노드별 워커 분포는 **플랜 채증으로만** 인용. 모든 표에 `planned` / `launched` / `동시 활성(표본 최대)` / `time-weighted active units` / `serial tail`을 **따로** 적는다. 라벨은 노드 cap 대비 `time-weighted active units`로 판정 — **80 % 미만 `단위 붕괴` / 100 % 초과 `configured-cap 초과`(Q3 신규) / 그 사이 `병렬 유지`**, **PG에도 같이 적용**한다 (ADR 0018+0019+0020 §4). 직렬 구간이 wall의 20 % 이상이면 **행위자별 프로파일** 필수이고, **클럭 이득 가정도 그때만** 한다 (ADR 0019 §4, 0020 §5) |
| **프로파일 정본 축** | **`cycles`**. `instructions` 비는 상한도 하한도 아니다(Q8 5.796x ≫ wall 3.960x, **Q18 0.858x ≪ 1.247x, Q3 1.9522x ≪ 2.2771x**). **IPC 비를 표에 항상 넣고**, 1에서 ±20 % 벗어나면 `instructions` 기반 서술을 금지한다 (ADR 0019 §2). **모든 배수·기여도에 이벤트 단위를 붙이고 혼용하지 않는다** — `[wall]`/`[질의실행분 CPU-초]`/`[cycles]`/`[instructions]`/`[time-weighted active units]` (ADR 0020 §5) |
| **프로파일 채증 함정** | `perf record -a -C`(perf 4.18)는 **레코드 시작 전 존재하던 sibling 스레드**의 심볼을 해석하지 못한다 — CUBRID 워커 풀 재사용 시 최대 **99.95 %가 `[unknown]`**. 오프라인 심볼라이저 `q3/scratch/resolve.py`로 보정하고 perf 해석분과의 일치율을 검산한다(Q3 95.68 % / 96.42 %). 이전 라운드 CUBRID 프로파일은 재검증 대상 (Q3 §3.1) |
| **배수 표기** | 정본 플랜 배수와 **형상 일치 배수를 같은 줄에 병기**한다. 20 % 이상 벌어지면 그 배수는 "두 옵티마이저 선택의 차"를 포함한 값이다(Q18 1.247x ↔ **1.877x**). **형상 일치 배수가 둘일 수 있다** — Q3는 PG 형상 1.8109x ↔ CUBRID 형상 1.1826x이며 둘 다 적는다 (ADR 0019 §1) |
| **Q8 분해 표기** | **`0.999x × 0.9314x × 4.2559x` 또는 `3.508x × 1.129x`만 허용.** 두 표기를 섞거나 다른 인자 조합으로 재배열하지 않는다 (ADR 0020 §5) |

### 좌표 (절대경로)

| 대상 | 경로 |
|---|---|
| 환경 변수 (**먼저 source**) | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/scratch/env.sh` |
| 프로젝트 문서 | `/home/cubrid/dev/workspace/tpch-sspq/{README,CONTEXT,ENVIRONMENT}.md`, `docs/adr/0001`~`0020`, `docs/report-*.md`, **`docs/MANIFEST-raw-evidence.md`** |
| 쿼리 — CUBRID 정본 / PG 파생본 | `/home/cubrid/dev/workspace/tpch-sspq/queries/q{1..22}-{cubrid,pg}.sql` (+ `q15_{create_view,select,drop_view}-*.sql`, 변환 diff `queries/diff/`) |
| 스키마 | `/home/cubrid/dev/workspace/tpch-sspq/schema/` |
| `PER_QUERY_CONNECTION_DIAG` raw 산출물 (구 `G2`) | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/g2-stream/raw/` (`g2-times.tsv` 220행, `blocks/`, `plans/`, `plans2/`, `cubplan/`) — `contract_revision: 1`, metadata 없음 |
| `PER_QUERY_CONNECTION_DIAG` 하네스 | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/g2-stream/scratch/run-g2.sh` (단계 1~5) — **쿼리마다 클라이언트를 새로 띄운다**(재명명 근거) |
| **Q21 raw 산출물** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q21/raw/` (`s1/`, `s1-times.tsv`, `s1b-cpu.tsv`, `s2/`, `pgcpu/`, `prof/`) |
| **Q21 하네스** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q21/scratch/` (`run-s1.sh`, `run-s1b.sh`, `run-pgcpu.sh`, `run-prof.sh`, `run-stat.sh`, `symbols2.sh`, `classify.py`, `subgroup.py`, `show_threads.py`) |
| **Q9 raw 산출물** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q9/raw/` (`s1-times.tsv`, `s1/`, `s1p/`, `s2a-cpu.tsv`, `s2a/`, `s2b/`, `pgcpu/`, `s2c-times.tsv`, `s2c/`, `s2d/`, `prof/`, `s4/`) |
| **Q9 하네스** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q9/scratch/` (`run-s1.sh`, `run-s1p.sh`, `run-s2a.sh`, `run-pgcpu.sh`, `run-s2c.sh`, `run-prof.sh`, `run-stat.sh`, `symbols2.sh`, `classify.py`(**Q1∪Q21 UNION 버킷 규칙 — 세 쿼리 재분류용**), `subgroup.py`, `show_threads.py`, `sample-threads.py`) |
| **Q8 raw 산출물** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q8/raw/` (`s1-times.tsv`, `s1r-times.tsv`, `s1/`, `s1r/`, `s1p/`, `s2/`, `s2-times.tsv`, `cpu/`, `cpu2/`, **`final/`(정본 세트)**, `thr/`, `prof/`) |
| **Q8 하네스** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q8/scratch/` (`run-s1.sh`, `run-s1p.sh`, `run-s2ab.sh`, `run-cpu.sh`, **`run-final.sh`**, `run-prof.sh`, `run-stat.sh`, `symbols2.sh`, `classify.py`(**Q1∪Q21∪Q9 UNION 규칙 무변경 + `Q8`/`Q8s` 두 세트 추가**), `sample-threads.py`) |
| **Q18 raw 산출물** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q18/raw/` (`s1/`(wall.tsv·플랜·trace), `s2/`(형상 A/B·집계 단독), `s3/`(레짐·민감도), `cpu/`, `cpu2/`, `thr/`, `prof/`) |
| **Q18 하네스** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q18/scratch/` (`run-s1.sh`, `run-s2.sh`, `run-cpu.sh`, `run-cpu2.sh`, `run-thr.sh`, `run-prof.sh`, `run-stat18.sh`, `symbols2.sh`, **`actors.sh`·`actor-buckets.sh`(행위자별 프로파일 — 신규)**, `classify.py`(**Q1∪Q21∪Q9∪Q8 규칙 + Q18 확장 6심볼 + `Q18`/`Q18m` 세트 추가**), `sample-threads.py`, **`sample-pg.py`(PG 프로세스 동시성 표본화 — 신규)**) |
| **Q15 raw 산출물** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q15/raw/` (`s1/`, `s2/`, `cpu/`, `cte/`, `thr/`, `prof/`) |
| **Q15 하네스** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q15/scratch/` (`run-s1.sh`, `run-cpu.sh`, `run-cpu-cte.sh`, `run-thr.sh`, `run-prof.sh`, `run-stat.sh`, `symbols2.sh`, `classify.py`, `actors.sh`, `actor-classify.py`) |
| **Q3 raw 산출물** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q3/raw/` (`s1/`, `s2/`, `s2b/`, **`final/`(정본 세트)**, `pair/`, `cpu/`, `cpu2/`, `cpu3/`, `thr/`, `prof/`) — **각 세트에 `meta.json`(`contract_revision: 2`)** |
| **Q3 하네스** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/q3/scratch/` (`run-s1.sh`, `run-s2.sh`, `run-s2b.sh`, **`run-final.sh`**, `run-pair.sh`(인접 쌍 A/B), `run-cpu.sh`(`SUB`/`QC`/`QP` 파라미터화), `run-thr.sh`, `run-prof.sh`, `run-stat.sh`, **`meta.sh`(metadata 표준 — 신규)**, `symbols2.sh`, `classify.py`(UNION 규칙 + `Q3`/`Q3h`/`Q3n`), **`resolve.py`(perf 심볼 해석 보정 — 신규)**, **`actors.py`(행위자별 분해 — 신규)**, `actor-classify.py`) |
| **raw 백업** | `/home/cubrid/dev/workspace/tpch-sspq/.git_ignored_dir/backup/` (`q3-raw-20260729.tar.gz`) — 목록은 `docs/MANIFEST-raw-evidence.md` |
| A~D·프로파일 하네스 | `.../g1-abcd/scratch/{run-a.sh,run-a-unitparity.sh,run-b2.sh,run-c.sh,snap.py,reduce_a.py}`, `.../g1-prof/scratch/{run-prof.sh,classify.py}` |
| CUBRID 측정 빌드 / DB | `/home/cubrid/tpch-sspq-install/cubrid-f30f1c260` / `/home/cubrid/dev/workspace/.git_ignored_dir/tpch-sspq/cubrid-databases/tpch_sf10_q1` (전용 `databases.txt`) |
| CUBRID 핀 소스 워크트리 | `/home/cubrid/dev/wt-tpch-sspq` @ `f30f1c260` |
| PG 측정 빌드 / PGDATA | `/home/cubrid/pg/pg20devel-5713b437` / `/home/cubrid/pg/pgdata-tpch-sspq` (port 5442) |
| PG 핀 소스 | `/home/cubrid/dev/postgres` @ `5713b437` |
| CUBRID 서버 기동/정지 | `/home/cubrid/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh` (**이것만 사용**) |

**불가침**: `~/CUBRID` 심링크(`jdbc-direct-poc-release/CUBRID-jdbc-direct-v3-r1`), 공용
`~/databases`, 적재된 8테이블(재적재 금지), `/tmp` 사용 금지, push 금지.

## 상태 이력

**G1 선행 조건 완료 →** 양쪽 엔진에 8개 테이블이 모두 적재됐고 q1~q22가 양쪽
방언으로 준비됐다. 이후 Q1 파일럿·A~D 카운터·대칭 프로파일·소스 규명·`PER_QUERY_CONNECTION_DIAG`(구 `G2`) 완주까지 진행됐다.

- 인벤토리 조사 완료(2026-07-28, 읽기 전용) → `ENVIRONMENT.md`.
- CUBRID `f30f1c260` release 빌드 설치 완료 — `~/tpch-sspq-install/cubrid-f30f1c260`,
  `cubrid_rel` = `11.5.0 (11.5.0.2374-f30f1c2)`. `~/CUBRID` 심링크 불변.
- PostgreSQL `5713b437a`(20devel) 빌드·설치 완료 — `~/pg/pg20devel-5713b437`,
  `initdb -D ~/pg/pgdata-tpch-sspq` 성공. **기동 완료**(port 5442), `shared_buffers=8GB`.
- `-g` 무해성 `.text` 검증 통과(ADR 0003).
- **Q1 한정 파일럿 완료(2026-07-28)** → `docs/report-g1-q1-pilot-20260728.md`.
  warm 3회 평균 **CUBRID 34.699 s vs PostgreSQL 8.974 s (3.867x)**, 양쪽 4행 결과 일치,
  양쪽 목표 DOP 6 실제 적용 확인(CUBRID `parallel workers: 6` / PG `Workers Launched: 6`).
- **`tpch_sf10_v2`는 pin 빌드로 열리지 않는다** — CBRD-26956(`a9fca9002`)의 CHAR/VARCHAR
  저장 포맷 revert 때문이다. DB를 은퇴시키고 pin 빌드로 재적재한다. (ADR 0007)
- **G1 자산 완성(2026-07-28)** → `docs/report-g1-assets-20260728.md`. 나머지 7테이블을
  양쪽에 적재(8테이블 행수 3자 일치, 합계 86,586,077), 인덱스는 양쪽 PK 8개만(FK 0),
  통계 양쪽 갱신, q2~q22 PG 방언 파생(11파일 11줄 변경, 22개 전부 `EXPLAIN` 통과).
  자료형 파리티는 `schema/README-type-parity.md`, 쿼리 방언은
  `queries/README-q2-q22-dialect.md`.
- **CUBRID 통계에는 히스토그램·MCV·min/max·null 비율이 없다 (사실, 2026-07-28 채증)** →
  `docs/report-cubrid-statistics-content-20260728.md`. 컬럼당 저장되는 것은 **NDV 하나**뿐이고
  (`src/storage/statistics.h:87-95`), 인덱스당 keys/부분키/pages/leafs/height가 추가된다.
  히스토그램 서브시스템은 이 pin에 **존재하지만**(`src/optimizer/histogram/`, `_db_histogram`,
  CBRD-26202 이후) `update_statistics_update_histogram` 기본값이 `n`이라 2단계
  `UPDATE STATISTICS ... WITH FULLSCAN`은 히스토그램을 **0개** 만들었다(`db_histogram` 0행).
  따라서 2단계의 "통계 파리티"는 **"양쪽 다 stale이 아니다"(freshness)로만** 읽어야 하며
  정보량 동등을 뜻하지 않는다. 히스토그램이 없을 때 `<`/`<=`/`>`/`>=`는 상수
  `DEFAULT_COMP_SELECTIVITY 0.1`, `BETWEEN`은 `DEFAULT_BETWEEN_SELECTIVITY 0.01`을 쓰고
  (`query_planner.c:10624`, `10645`), 등식만 `1/NDV`로 데이터에 반응한다. **G4는 이 비대칭을
  자기 산출물의 전제로 명시해야 한다.**
- **CUBRID 히스토그램 활성화 완료 — 기본값 이탈 (2026-07-28, ADR 0008)** →
  `docs/report-cubrid-histogram-enabled-20260728.md`. 측정 install `cubrid.conf`에
  `update_statistics_update_histogram=yes`를 넣고 래퍼로 재기동, `paramdump`에서
  `[C*]`/`[S*]` 양쪽 `y` 채증. `db_histogram` **0 → 283행**, 8테이블 **61컬럼 전부**
  300버킷·`full scan`. 히스토그램이 실제로 소비된다 — `l_shipdate < date` 추정이
  실제의 **0.232배 → 1.004배**로 교정됐다. **함정**: `UPDATE STATISTICS ... WITH FULLSCAN`
  만으로는 안 된다(`bucket_count=-1`이 기본값 300 대신 **최소 4**로 클램프되고
  `ON ALL CLASSES`가 `WITH FULLSCAN`을 버린다). 테이블별
  `ANALYZE TABLE <t> DROP HISTOGRAM` → `UPDATE HISTOGRAM WITH FULLSCAN`을 쓴다
  (`.git_ignored_dir/g1-assets/scratch/rebuild-hist.sh`, 8테이블 39.7s).
  **그래도 여전히 없는 것**: 물리 correlation, avg_width(소스에 개념 없음), 정확한
  도메인 min/max(최저 버킷이 `(-inf, hi]`로 열림), `attr op attr` 히스토그램 경로
  (`query_planner.c:10523-10525`, 상수 0.1 유지). 버킷 수도 미정렬(CUBRID 300 vs
  PG 100, 의미도 다름 — 정렬 비용 3.2s로 값싸게 가역적).
- **대외 인용 단서 (필수, 3개)**: 이 프로젝트 수치는 **어느 엔진에 대해서도 "출시 기본
  설정 제품의 성능"이 아니다.**
  1. **PostgreSQL은 개발 스냅샷 핀**(`5713b437`, `20devel`) — 릴리스 PostgreSQL 성능이
     아니다. (ADR 0002)
  2. **CUBRID는 `update_statistics_update_histogram=yes`**(기본값 `no`) — 기본 설정
     CUBRID가 아니다. (ADR 0008)
  3. **PostgreSQL은 `dynamic_shared_memory_type=mmap`**(기본값 `posix`) — 호스트
     `/dev/shm`이 64000k 고정이고 확장 권한이 없어 Parallel Hash 쿼리가 기본값에서
     실행되지 않았기 때문이다. 전환 비용 실측은 PG가 **1.40 % 빨라진** 것이었고(예상된
     보수적 방향과 반대), 무변경 CUBRID 대조군의 −0.72 % 드리프트를 감안하면 mmap
     귀속분은 최대 ~0.7 %p다. (ADR 0015)
- **Q1 DOP6 재측정 — CUBRID 재현 안 됨 (2026-07-28)** →
  `docs/report-q1-dop6-reproduction-20260728.md`. warm 3회 AB/BA 교차:
  **CUBRID 31.511 s (sd 0.301) / PG 8.908 s (sd 0.008) = 3.537x**.
  PG는 파일럿 대비 −0.74 %로 재현됐고, **CUBRID는 −9.19 %(파일럿 sd의 26.6배)로
  재현되지 않았다** — 비율이 3.867x → 3.537x로 내려갔다. 플랜 형상은 양쪽 다 파일럿과
  동일하고 worker도 6/6이며, 바뀐 것은 CUBRID 추정 카디널리티뿐이다
  (`sel 0.1 → 0.9868`, `card 5,998,605 → 59,194,236`, 실제 59,142,609). 4행 결과는
  양쪽 다 파일럿과 바이트 단위 동일, 집계 6런 물리 read 전부 0.0 MiB.
  파일럿 이후 달라진 것은 7테이블 적재·히스토그램 활성화·**서버 코어핀 실제 적용**·
  배경 부하 차이다. **원인은 지목하지 않는다**(ADR 0005).
  DOP 스윕(1/2/3/4)은 취소됐다.
- **Q1 DOP6 A~D 카운터 측정 (2026-07-28)** → `docs/report-q1-abcd-counters-20260728.md`.
  프로파일러 미부착, 카운터만. **CPU 작업량 비 3.035x vs wall 비 3.555x**
  (CUBRID SUT CPU 188.673s / PG 62.163s). **instructions 비 3.021x, IPC는 사실상 동일**
  (2.485 vs 2.520) — 명령 수 자체가 3배다. 평균 병렬 활용도 CUBRID 5.926(워커 6개,
  리더 스레드 0.47s) / PG 6.940(리더 8.87s가 스캔 참여 + 워커 53.29s). 버퍼 fetch
  CUBRID 683,137×16KiB=10,674MiB / PG 1,125,170×8KiB=8,791MiB, 물리 디스크 read 양쪽 0.
  **바이트 1.214x는 전부 컬럼 저장 표현**: CHAR +21.91 B/행, DECIMAL +12.53,
  VARCHAR +7.89, DATE +1.50, INTEGER ±0이고 행 구조 오버헤드는 CUBRID가 10.96 B **작다**.
  8테이블 합계도 1.188x로 lineitem 특유가 아니다. **해석·원인 지목 없음**(ADR 0005).
- **계약 결정 4건 확정 (2026-07-28, ADR 0010~0013)**
  - **기준선 교체**: **CUBRID 31.511 s / PG 8.908 s / 3.537x**(8테이블 + 히스토그램
    활성화)가 현 기준선이다. 파일럿 값(34.699 / 8.974 / 3.867x)은 **폐기하지 않고 이력
    보존**하며 인용 시 구성이 다르다는 단서를 붙인다. 9.19 % 드리프트는 **원인 미규명으로
    종결**하고 더 추적하지 않는다. 용어 분리: **런 내 재현성(within-set sd)**과
    **세션 간 드리프트(between-session drift)**는 다르며, **런 내 sd를 세션 간 비교의
    유의성 문턱으로 쓰지 않는다**. (ADR 0010)
  - **정본 접속 경로 = `csql -C` 직결**. 기존 "broker/CAS 경유(CCI)" 조항은 대체된다.
    기존 측정(파일럿·기준선 포함)은 **전부 유효**하다 — 이미 직결로 측정됐다. 의무 조항:
    모든 측정 표에 **쿼리별 클라이언트측 파싱·플랜 생성 시간**을 별도 열로 채증하고
    크기를 잰다. Q1 실측 **CUBRID 3.0 ms(클라이언트측) / PG 0.640 ms(backend 내부)**.
    (ADR 0011)
  - **cpuset은 공유 유지**: `cub_server`와 클라이언트측 처리(csql/psql)가 계속 node0
    `0-15`를 같이 쓴다(분리 권고 **기각**). 근거 — 클라이언트 CPU는 `cub_server`가
    아니라서 SUT CPU 열에 안 잡히므로 회계 불변, wall이 end-to-end라 CUBRID 클라이언트측
    플랜 시간은 이미 포함, PG가 파싱·플랜을 SUT 코어에서 하므로 같은 코어 경합이 대칭.
    **cpuset은 SUT CPU 회계 경계와 독립된 축**이다. 수집기만 SUT 밖. (ADR 0012)
  - **기준선 전용 재측정 라운드 없음** — A~D 라운드가 새 표 형식의 기준선을 겸한다.
    (ADR 0013)
- **Q1 DOP6 A~D 확정판 (2026-07-28)** → `docs/report-q1-abcd-counters-round2-20260728.md`.
  (A) CPU 3.035x vs wall 3.555x, 리더/워커 분리(CUBRID 0.470 s / 워커 188.0 s,
  PG 8.870 s / 53.293 s). (A) 게이트 = 클라이언트측 CPU가 SUT의 0.045 %/0.113 %로 1 %
  미만 → (B)를 `perf -a -C 0-15`로 측정. instructions 비 2.960x, IPC 2.339 vs 2.357.
  **오염률 각주: instructions 2.6 %/4.1 %, cycles 7.3 %/10.5 %, branch-misses
  11.7 %/11.2 %, LLC-load-misses 44.8 %/93.9 %** — 캐시 이벤트는 SUT 부착값을 쓴다.
  (C) 버퍼 fetch 683,137×16 KiB vs 1,125,170×8 KiB = 1.214x, 물리 read 양쪽 0.
  (D) 1.214x는 전부 컬럼 저장 표현(CHAR +21.91, DECIMAL +12.53, VARCHAR +7.89,
  DATE +1.50, INTEGER ±0), 행 구조 오버헤드는 CUBRID가 10.96 B 작다.
  **정정**: 직전 라운드에 적은 "`perf -a -C` 신뢰 불가"는 **내 오류**였다 — 통제 워크로드
  대조로 0.12 % 일치를 확인했고, 그때 본 이상값은 배경 부하 변동(1.9~52 G instr/s)이었다.
- **`configured-cap parity` 교정 (2026-07-28, ADR 0014; rev 2에서 재명명, ADR 0020 §4)** →
  `docs/report-q1-unit-parity-20260728.md`. "목표 DOP 6" 파리티가 실제로는 **CUBRID
  6단위 vs PG 7단위**로 어긋나 있었다 — PG는 `parallel_leader_participation`이 기본 `on`
  이라 leader가 worker와 동등 참여한다(leader CPU 8.870 s ≈ worker 평균 8.88 s). 병렬
  효율은 사실상 같았고(98.8 % vs 99.1 %) 단위 수만 달랐다. **교정: CUBRID
  `parallelism=6` ↔ PG `max_parallel_workers_per_gather=5`(+leader) = 양쪽 6단위.**
  `parallel_leader_participation`은 기본 `on` 유지(끄면 PG 사용자가 안 쓰는 구성).
  **결과 — 형님 예측대로 wall 비가 3.555x → 3.049x로 SUT CPU 비 3.056x와 0.2 % 차로
  수렴**했다. PG 총 CPU는 −0.12 %로 불변이고 wall만 8.957 → 10.442 s(7/6 배 예측치
  10.450 s와 −0.07 %). 4행 결과 양쪽 바이트 동일. **헤드라인 배수는 단위 파리티 트랙
  3.049x**를 쓰고, 자연 구성값 3.555x를 두 번째 트랙으로 함께 낸다.
- **Q1 대칭 프로파일링 — 증거 기반 원인 후보 도출 (2026-07-28)** →
  `docs/report-q1-symmetric-profile-20260728.md`. 단위 파리티 트랙, `perf record -a -C 0-15`
  + report 단계 SUT 귀속(비율 CUBRID 90.9 % / PG 96.7 %), 플랫 프로파일만(콜그래프 미부착 —
  fp 언와인딩 비대칭, 그리고 `__mem*`류가 1.32 %/2.82 %뿐이라 필요 없었다).
  **귀속 검증: instructions 1,278.53 G / 424.61 G로 (B) 실측과 99.97 % / 99.80 % 일치.**
  질의 구간 오버헤드 +0.61 % / −1.29 %(문턱 5 % 내).
  **총 격차 853.92 G instructions(3.011x)의 기여도** — 식 평가/튜플 구성 **28.8 %**(5.57x),
  값/도메인 변환 **22.9 %**(CUBRID 195.6 G vs **PG 0**), 수치 연산 16.3 %(**1.77x**로 평균
  이하), 집계·해시 11.4 %(4.53x), 스캔/레코드 디코드 9.5 %(2.27x).
  **배제**: DECIMAL 산술이 주 동인이라는 설명(1.77x, PG 비중이 42.43 %로 더 큼),
  메모리 할당(0.82x로 CUBRID가 **적다**, 기여 −1.5 %), 버퍼·래치(양쪽 0.2 % 미만),
  정렬(양쪽 0 %). ADR 0005 해제 범위대로 근거 숫자를 붙인 원인 후보 3개를 냈다.
- **`PER_QUERY_CONNECTION_DIAG`(게이트 G2) 완주 (2026-07-28)** → `docs/report-g2-stream-20260728.md`.
  **rev 1 실행 계약 / rev 2 기술**. `configured-cap parity` 트랙,
  AB/BA 3블록 10스트림. **Q1은 대표가 아니다** — 격차의 **43.5 %가 Q21 단독**(12.72x),
  Q1은 15.3 %(2.87x)로 2위이고 배수 중앙값은 2.15x다. **Q2는 CUBRID가 이긴다**(0.10x,
  signed 기여 −2.00 %). **PG-only Parallel subset은 비어 있다** — 완주 19개 전부 CUBRID가
  병렬을 타고, 유일한 비대칭은 반대 방향인 **Q13(CUBRID 6단위 / PG 완전 직렬, 1.03x)**.
  ~~**CUBRID의 6단위는 단일 스캔 쿼리에서만 유지된다**~~ — 다중 조인 쿼리는 노드 대부분이
  2워커(Q21 `4×2 1×3 1×6`, Q5·Q8·Q11 동일 양상)이고 PG는 모든 노드가 leader+5로 균일하다.
  **→ 성능 해석으로는 정정됨 (ADR 0018)**: 플랜 형상 서술로는 유효하지만 Q21 실측에서
  CUBRID 이용률은 `CPU/wall 5.818 = 6단위의 96.97 %`이고 2/3워커 노드의 자기 시간 합은
  **0.83 %**다. `N×2`는 `parallel_type::SUBQUERY`의 **코드 상수 1**
  (`px_parallel.cpp:85-109`)이며 데이터·`parallelism`·힌트와 무관하다.
  Q5·Q8·Q11은 이용률을 재지 않았으므로 "붕괴" 라벨을 붙이지 않는다.
  timeout 3개: Q17·Q20 양쪽 초과, **Q22는 CUBRID만**(PG 0.971 s, 1500 s 프로브도 미완주 →
  하한 ≥309x). positive_pareto 80 %는 상위 6쿼리(Q21·Q1·Q9·Q8·Q18·Q15). 결과 19개 행수
  완전 일치, 수치 차이는 전부 기존 등재된 십진 스케일 범주.
- **PG DSM 백엔드를 `mmap`으로 이탈 (ADR 0015)** — 호스트 `/dev/shm`이 64000k 고정이고
  uid 340001에 확장 권한이 없어 Parallel Hash 쿼리(Q5·Q8·Q10)가 기본값 `posix`에서
  실행되지 않았다(피크 48,412k/64,000k, 결정론적). 전환 후 3개 전부 정상.
  **전환 비용 실측: PG가 1.40 % 빨라졌다** — 예상된 "mmap이 느려 배수를 축소한다"는
  보수적 방향은 **성립하지 않았다**. 무변경 CUBRID 대조군이 같은 세션쌍에서 −0.72 %
  드리프트했으므로 mmap 귀속분은 최대 ~0.7 %p, 배수 영향 3.049x → 3.070x.
  **대외 인용 단서가 3개로 늘었다.**
- **Q21 측정 — `measured, correctness-unverified` (2026-07-29)** → `docs/report-q21-gap-20260729.md`. 4단계 전부 완주.
  **격차가 곱으로 정확히 갈렸다: 14.319x = 플랜·조인 전략 4.436x × 행당 실행 비용 3.228x**
  (검산 오차 0.00 %). 앞 항은 같은 엔진 A/B(질의 재작성으로 PG 플랜 형상 강제, 플랜 형상
  일치를 노드 단위로 채증: supplier⋈nation 4,010 / 날짜필터 37,929,348 / l1⋈supplier
  1,522,366 / 최종 39,448 전부 양쪽 일치), 뒤 항은 형상 일치 상태의 엔진 간 비.
  **행당 축 3.228x는 Q1의 3.070x와 같은 크기** — Q21의 초과분 4.4x는 전부 플랜이 만든다.
  **실행 단위 축은 0.2~1.6 %**로 닫혔다(ADR 0018).
  **뿌리는 비용 비교가 아니라 탐색 공간**: 상관 서브쿼리가 `query_planner.c:9094-9106`에서
  조인 열거 **이전에** 단일 노드 스캔 플랜에 못박히고, `grep -rniE "semi.?join|anti.?join"
  src/optimizer src/parser` = **0건**이다. 힌트로 조인 순서를 강제해도 sarg가 l1 노드를
  떠나지 않으며(추정 cost 125.67 M → 488.00 M), 옵티마이저는 **볼 수 있는 대안 중 최선을
  정확히 골랐다**. 선택도 3개가 상수다 — `attr op attr` 0.1(실측 0.632),
  `EXISTS` 0.1(≈0.99), `NOT EXISTS` 0.9(0.0557).
  대칭 프로파일: **인덱스 탐색·키 비교(B-tree)가 격차의 51.5 %**(CUBRID 856.17 G vs
  PG 12.28 G = 69.72x, `pr_midxkey_compare` 단독 12.46 %). **Q1의 1~3위 버킷(식 평가·값
  도메인 변환·수치 연산, 합 68.0 %)은 Q21에서 5.9 %**이고 수치 연산은 **양쪽 0**이다.
  귀속 검증 CUBRID **100.03 %**(`perf stat -p`) / PG 96.2 %(잔차는 `io worker` 4.88 G와
  일치, 합 101.0 %), 오버헤드 −0.58~+2.58 %(문턱 5 %). 개선 후보 5개 제시, **구현 없음.**
- **계약 결정 3건 확정 (2026-07-29, ADR 0016~0018)**
  - **WARM에 하위 레짐이 둘 있다** — `stream` ↔ `single-query-repeat`. 물리 read≈0을 둘 다
    통과하는데 PG Q21 wall이 **12 % 다르다**(총 버퍼 접근은 11,833,091 ↔ 11,833,092로
    1블록 차이 동일, `shared read`만 1,275,875 → 580,522). **CUBRID는 무감**(trace fetch
    카운터 자릿수까지 불변). 두 레짐을 같은 표에 섞지 않고 표기를 의무화한다. (ADR 0016)
  - **PG `io worker`는 SUT 밖이되 별개 열로 기록**(Q21 실측 SUT instructions의 +4.99 %) —
    CUBRID에 대응물이 없다. **PG worker CPU는 회수 시점 가산**이라 질의 직후 스냅샷은
    `CPU/wall = 6.86`(6단위 초과, 물리적 불가)을 만든다 → **N회 연속 + settle 2 s 브래킷**
    으로 재고 N으로 나눈다. CUBRID는 단일 프로세스라 이 문제가 없다. (ADR 0017)
  - **노드별 워커 분포는 시간 가중으로 읽는다** — 개수만 세는 `N×2` 라벨을 쓰지 않는다.
    판정은 `time-weighted active units ÷ 노드 cap`이고 **80 % 미만 `단위 붕괴` / 100 % 초과 `configured-cap 초과`**. `PER_QUERY_CONNECTION_DIAG` 결론 4번의
    성능 해석을 정정한다(플랜 채증으로는 유효). (ADR 0018)
- **Q9 측정 — `measured, correctness-unverified` (2026-07-29)** → `docs/report-q9-gap-20260729.md`. 4단계 전부 완주.
  **격차가 곱으로 갈렸다: 2.741x = 플랜·조인 전략 0.984x × 행당 실행 비용 2.785x**(검산 오차 0.00 %).
  **플랜 축의 기여는 0이다 — Q21과 정반대다.** CUBRID에 PG 형상을 강제(`/*+ ORDERED USE_HASH(partsupp) */`,
  주 노드 5개 행수 완전 일치)하면 19.542 → 19.852 s로 **1.6 % 느려지고**, PG에 CUBRID 조인 순서를
  강제(`join_collapse_limit=1`)하면 7.253 → 9.798 s로 **35 % 느려진다.** 유일한 플랜 차이는
  partsupp가 들어오는 자리이고, 그 교환(인덱스 NL 3.26 M회 제거 −5.2 s ↔ 분할 해시 조인 degree 4
  +4.9 s)이 상쇄된다. **실행 단위 축도 0.23 %로 닫혔다** — wall 비 2.741x ≈ SUT CPU 비 2.735x,
  시간 가중 이용률 CUBRID **98.8 %**(질의 실행분 5.927/6) / PG 96.4 %. `CPU/wall = 6.306 > 6`은
  `pgbuf-page-flush` 0.354단위(SUT CPU의 5.6 %) 때문이고 **PG는 그 대응물이 SUT 경계 밖**이다.
  **지배 버킷이 없다** — 스캔·디코드 23.8 % / 식 평가·튜플 구성 23.6 % / 버퍼 고정·래치 13.3 % /
  B-tree 11.6 % / 값·도메인 9.2 % / 수치 8.0 %로 상위 6개가 89.5 %를 나눈다. **Q1형(3버킷 40.8 %)
  + Q21형 B-tree(11.6 %)의 하이브리드**이고 제3의 축은 없다. 최대 단일 사실은 **해시 조인 프로브
  측 lineitem 59,986,052행 전량이 QFILE 리스트 파일 튜플로 물질화된다**는 것(생존 5.44 %,
  `px_scan_result_type.hpp:28-34`에 프로브 융합 `RESULT_TYPE`이 없다). 절제 실험으로
  **프로젝션 NUMERIC 컬럼당 −0.97 s**를 측정했다. 귀속 검증 CUBRID **100.05 %** / PG 98.38 %,
  오버헤드 −0.79 %/+0.48 %. 개선 후보 5개 제시, **구현 없음.**
- **Q9가 프로파일 인용 규칙에 추가한 것 (2026-07-29, 계약 사실)**
  - **프로파일 배수는 이벤트를 명기한다.** Q9 실측 **instructions 4.233x vs cycles 3.022x vs
    wall 2.741x** — IPC가 CUBRID 1.929 / PG 1.378(**1.40x**)로 갈리기 때문이다. Q1은 IPC가
    사실상 같았고(2.339 vs 2.357) Q21은 IPC를 재지 않았다. **instructions 비는 시간 격차의
    상한이며, cycles 비가 시간 비에 가깝다.**
  - **cycles에서 버킷 순위가 뒤집힌다.** 버퍼 고정·래치 instr 3위(13.3 %) → **cycles 1위(27.8 %)**,
    집계·해시는 기여 **부호가 역전**(+2.2 % → −4.7 %). 원인은 PG `ExecParallelScanHashBucket`
    (instr 6.08 G / cycles 22.34 G = **IPC 0.27**, PG cycles의 21.2 %)의 메모리 지연이다.
    **주 표는 instructions로 두되 cycles 표를 반드시 같이 낸다.**
  - **버킷 규칙 정정 1건**: PG `ExecParallelScanHashBucket`은 `^ExecParallel`에 걸려 `병렬 인프라`로
    갔었는데 `nodeHash.c`의 버킷 체인 탐색이므로 **`집계·해시·해시조인`이 맞다**. Q21 재분류에도
    같은 정정을 적용했다(`.git_ignored_dir/q9/scratch/classify.py`).
- **Q15 측정 — `measured, correctness-unverified` (2026-07-29)** → `docs/report-q15-gap-20260729.md`. 4단계 전부 완주.
  **`2.1650x = 플랜 1.0000x × 실행단위 1.2620x × 행당 1.7155x`(검산 오차 0.00 %)** — 플랜 축이
  **네이티브로 1**인 첫 쿼리. 세 문장(create view/select/drop view) 정의 문제를 먼저 닫았다:
  G2는 세 문장 전체를 한 호출로 쟀고(정의 A = 헤드라인), 정의 B와 차 0.01 %, **DDL 양쪽 4 ms로
  격차 기여 0.0000 s**. **양쪽이 뷰를 인라인 확장해 lineitem을 2회 스캔**하고 CSE가 없다
  (단일 평가로 CUBRID −49.2 % / PG −54.2 %, **배수는 2.400x로 악화** = 양쪽 공통 구조 문제).
  **술어 평가가 cycles 격차의 47.7 %(22.0x)**로 1위이고 **스캔·디코드는 0.97x 동률**이라
  **새 범주 `필터 지배형`**이다. **양쪽 동시 `단위 붕괴`**(CUBRID 59.3 % / PG 74.8 %)이고 CUBRID
  뿌리는 **Q18과 같은 `external_sort.c:5232`**, PG 뿌리는 `bgworker.c:1105`의 클러스터 상한 8
  (외곽 gather 5 + InitPlan 3). `max_parallel_workers` 기본값 유지, 실행 단위 축으로만 분해 기록.
  귀속 검증 instructions CUBRID **100.22 %** / PG **100.10 %**(신규: `perf stat -p <postmaster>` 부착),
  오버헤드 −0.05 %/+0.56 %. 개선 후보 5개, **기존 후보 8개 중 5개 배제(채증)**. **구현 없음.**
- **Q18 측정 — `measured, correctness-unverified` (2026-07-29)** → `docs/report-q18-gap-20260729.md`, ADR 0019.
  **`1.247x`(single-query-repeat; G2 stream 1.214x)는 두 플랜 오류의 상쇄값이다** — 형상을 맞추면
  **1.877x**, 집계 서브쿼리만 떼면 **1.958x**다. 3축 분해
  **`1.2468x = 플랜 0.6643x × 실행단위 1.5409x × 행당 1.2180x`**(검산 오차 **0.014 %**).
  - **플랜 축이 처음으로 1보다 작다(0.664x = PG가 자기 플랜으로 1.505x 잃는다).** 사유는
    `pg_stats.n_distinct(lineitem.l_orderkey)` = **397,034**(실제 15,000,000, **37.8x 과소**,
    `default_statistics_target`=100, MCV 없음) — PG는 상위 조인을 오선택해 lineitem을 **두 번째로
    전체 순차 스캔(직렬)**하고 orders 해시를 128배치로 스필한다(합 **10.59 s = wall의 34.6 %**).
    **CUBRID NDV 추정은 14,929,885(오차 0.47 %)로 정확했고** 624행 드라이버 인덱스 NL을 골랐다.
    **이 프로젝트가 기록한 통계 비대칭의 부호가 뒤집힌 첫 사례다.**
  - **양쪽이 동시에 `단위 붕괴`인 첫 쿼리** — 이용률 CUBRID **41.1 %** / PG **46.9 %**.
    0.05 s 표본화(CUBRID 761표본 / PG 634표본, 단위-초 검산 −0.9 % / +0.2 %)로 구간을 갈랐다:
    **6단위 구간은 CUBRID 11.38 s(29.8 %) / PG 10.72 s(34.2 %)뿐이고 격차 7.56 s의 86.3 %가
    1단위 구간에서 난다**(CUBRID 26.67 s = 69.8 %, PG 20.15 s = 65.8 %).
  - **CUBRID 직렬 구간은 코드 상수다** — `external_sort.c:5232`
    `if (px == NULL || px->hash_eligible) return 1;`로 GROUP BY 외부 정렬이 **항상 직렬**이다
    (`input_list->page_cnt` 423,552가 문턱 2048을 **207배** 넘지만 도달하지 못한다;
    사슬 `xasl_generation.c:16563` → `query_executor.c:5657/5662` → `external_sort.c:5232`).
    `/*+ NO_HASH_AGGREGATE */`로 조항을 끄면 정렬이 실제로 `(parallel workers: 6)`가 되지만
    입력이 15 M→60 M로 4배가 되고 병합·최종화(`:5829` 직렬 fan-in, `:5841-5848` 직렬 final run)가
    여전히 직렬이라 **53.07 s로 더 느려진다.** `max_agg_hash_size` 상한 **128 MB**
    (`system_parameter.c:3472-3483`)로는 15 M 그룹(≈600 MB+)이 구조적으로 못 들어간다.
    `sort_buffer_size` 2M→64M은 스필을 −49.6 % 줄이지만 wall은 **−4.2 %**뿐이다.
  - **`instructions` 비가 처음으로 1 미만이다: 0.858x**(CUBRID 468.26 G vs PG 545.68 G).
    `cycles` 1.159x, wall 1.247x, **IPC 역전 1.811 vs 2.447 = 0.740x**. 귀속 검증
    CUBRID **+0.07 %/−0.15 %**(`perf stat -p`), PG −2.7 %/−4.8 %(system-wide − idle 기준선),
    오버헤드 PG −0.2 % / CUBRID +1.5 %. → **정본 비교축을 `cycles`로 격하**(ADR 0019 §2).
  - **행위자별 프로파일이 새 필수 산출물이다**(ADR 0019 §4). CUBRID 직렬 leader의 **cycles 23.2 %가
    버퍼 고정·래치**(16.41 G; `pgbuf_fix_release`·`pgbuf_unfix`·`__pthread_mutex_*`) — **경합이 없는
    단일 스레드인데 BCB 뮤텍스를 잡는다.** 워커는 **TLS/런타임 5.2 %**(`__tls_get_addr`/`__tls_init`,
    `px_scan_result_handler.cpp:49`의 `thread_local tl`을 `write()`에서 튜플마다 15+회 참조).
    PG는 leader·worker 둘 다 "스캔·디코드 + 집계·해시"가 절반 이상이고 워커 instructions의 ~40 %가
    해시집계 스필 경로다(`nodeAgg.c:3042-3076`).
  - **PG는 ADR 0016 하위 레짐에 무감**(`hit+read` 2,552,611 완전 동일, 미스 −18.0 %에 wall +0.68 %) —
    비용이 shared buffer 미스가 아니라 임시파일 스필(temp 6.9 GB read / 9.0 GB written)이기 때문이다.
    CUBRID도 무감. **PG `work_mem`을 4 MB→64 MB로 올리면 플랜이 `Finalize HashAggregate`로 바뀌어
    leader가 1,251 MB를 직렬 스필하고 20.40 s → 32.78 s로 느려진다 — 기본 4 MB가 우연히 최적이다.**
  - 개선 후보 5개(신규 2 + 기존 3), 기존 후보 중 **④ B-tree·⑤ 리스트 스캔 문턱·⑥ NUMERIC은
    Q18에 해당 없음**(각 0.0 % / 미해당 / cycles 1.00x 동률)임을 채증. **구현 없음.**
- **Q3 측정 — `measured, correctness-unverified` (2026-07-29)** → `docs/report-q3-gap-20260729.md`, ADR 0020.
  **`contract_revision: 2` 첫 보고서.** 4단계 전부 완주, `raw/*/meta.json` 10세트.
  **`2.2573x [wall] = 플랜 1.2465x [wall] × 실행단위 0.7986x [units 비] × 행당 2.2676x [CPU-초 비]`**
  (검산 오차 **0.00 %**). **새 범주 `플랜형(옵티마이저 오선택형)`**.
  - **플랜 축이 CPU를 바꾸지 않는 첫 사례** — CUBRID 질의실행분 CPU-초가 idx-NL 47.30 s ↔
    `USE_HASH` 47.60 s로 **0.6 % 동률**이고, 플랜 축 전량이 `time-weighted active units`
    5.61 → **7.05**(노드 cap 6의 **117.5 %**, 동시 활성 **12단위**)에서 온다. 노드 cap 6 정규화 시
    두 형상이 7.88 s ↔ 7.93 s로 동률 → **CUBRID에게 플랜 선택은 시간을 바꾸고 일은 바꾸지 않는다.**
  - **`configured-cap parity`의 구멍을 찾았다** — `parallelism`은 `px_parallel.cpp:172`에서
    **노드마다** 적용되고 전역 예산은 `px_worker_manager_global.cpp:57-78`의
    `max_parallel_workers`(**CUBRID 100 ↔ PG 8, 12.5배 비대칭**)다. 라벨 **`configured-cap 초과`** 신설.
  - **형상 일치 배수가 둘로 갈리는 첫 쿼리** — PG 형상 **1.8109x** ↔ CUBRID 형상 **1.1826x**.
    양방향 A/B 성공(`/*+ USE_HASH */` ↔ `enable_hashjoin/mergejoin/memoize/incremental_sort=off`
    + `join_collapse_limit=1` + 명시 조인 순서), 노드 6지점 실제 행수 일치 채증.
    역방향 `pgNL/pgN` **1.9088x** — PG는 CUBRID 형상으로 1.91배 잃는다.
  - **`instructions` 비가 두 번째로 하한**(1.9522x < wall 2.2771x, IPC 비 **0.799**). `cycles`
    2.4397x이고 wall 대비 +7.1 % 잔차는 유효 클럭 비 1.0817과 units 비 1.0098로 **0.04 %** 내에 닫힌다.
  - **cycles 버킷: B-tree 49.3 %(∞) + 버퍼 고정·래치 47.5 %(12.30x) = 격차의 96.8 %.**
    버퍼 역전이 다섯 번째 재현이되 **절대 델타가 instr 28.31 G → cycles 33.57 G로 커져** 1위와
    1.8 %p 차로 동률화한다(버킷 IPC **0.83**). 뿌리는 **페이지를 27.79배 더 만지는 것**
    (CUBRID **39,538,926** page fix ↔ PG **1,422,457** buffer access)과 **fix 1회 659 cycles**다
    (`page_buffer.c:2211`, lock-free fast path `:7670`이 이미 있는데도). **형상을 맞추면
    39.54 M ↔ 36.13 M(1.094x)로 붙고 B-tree는 1.10x·버퍼는 1.19x가 된다** — 정본 버킷의
    "B-tree 49.3 %"는 **플랜 형상의 부산물**이다(Q8 성질의 강한 재현).
  - **플랜 축의 소스 뿌리**: `query_planner.c:98 ISCAN_IO_HIT_RATIO 0.5` + `:3411`
    (probe IO를 절반으로 깎는다) + `:87 HJ_MEM_ALLOC_CONSTANT 1500`(주석이
    **"Heuristic offset to prefer NL join over hash join"**) + `:3650-3658` 스필 IO
    `(inner+outer)×0.5`. hash-join 2단 추가 비용 18,671,467의 **90.5 %(16,902,174)가 스필 항**이고
    모델은 probe:row를 **0.91:1**로 보는데 실측은 **4.49:1**(probe 13,660 cycles / row 3,041 cycles)
    = **4.9배 역방향 오차**. 스필 예측 자체는 맞았고(trace `SPLIT partitions: 12`) 틀린 것은 단가다.
  - **채증 함정 2건 등재**: (i) `perf record -a -C`(perf 4.18)가 **레코드 시작 전 존재하던 sibling
    스레드**를 해석하지 못해 CUBRID 정본 프로파일이 **99.95 % `[unknown]`**이었다 → 오프라인
    심볼라이저 `q3/scratch/resolve.py`(일치율 검산 95.68 % / 96.42 %). (ii) ADR 0019 §4-c leader
    클럭 이득 **미재현**(leader 2.378 GHz < worker 2.513 GHz, 직렬 0.50 s) → 조항을
    "직렬 20 % 이상일 때만"으로 좁혔다. **ADR 0016 민감도 판정도 좁혔다** — PG 잔존율이
    30.2 → 66.6 %(**+36.4 %p**)로 크게 움직이는데 `Execution Time` **−1.86 %**(단가 **0.175 µs**).
  - **배경 부하로 무효 처리한 run 3건**(삭제 없이 기록): `final` 블록 6(loadavg **33.15**),
    `s2 pg-nl R1`(sda 1,551 MiB), `s2b cubH B2`. 같은 장비의 다른 세션이 코어 0-31을 쓴다.
  - 개선 후보 5개(신규 2 = ⑨ NL probe 비용 재교정 / ⑩ 전역 병렬 예산 쿼리 단위화, 기존 3),
    **A+B 동시 착지 시 1.722x**(절대 격차 −42.6 %). 기존 후보 **②⑤⑥⑦⑧⑬ 정본 배제**. **구현 없음.**
- 남은 것: **G1(R0 재현)이 다음 행동**이고 선행 조건은 모두 닫혔다. 아래 pending 중
  게이트 진행을 막는 항목만 그 전에 닫는다.

## 확정 결정

1. **독립 컨텍스트** — 저장소 루트 `CONTEXT.md` / `docs/adr/`에 이 프로젝트 항목을 추가하지 않는다.
   용어는 `tpch-sspq/CONTEXT.md`, 결정은 `tpch-sspq/docs/adr/`에 둔다. (ADR 0001)
2. **PostgreSQL은 개발 스냅샷을 그대로 pin** — `~/dev/postgres` master
   `5713b437abed7085e7d59849c6e9e0f4f469633d` (**20devel**, `git describe` = `REL_19_BETA1-472-g5713b437abe`).
   안정 릴리스가 아니므로, 이 프로젝트의 수치는 **릴리스 PostgreSQL의 성능이라고 인용할 수 없다**. (ADR 0002)
3. **CUBRID는 `f30f1c26003e5aa8e93182648e06cad76fc77064` pin** — clean 워크트리 `~/dev/wt-tpch-sspq`에서
   빌드해 전용 prefix에 설치했다. `~/CUBRID`의 JDBC-direct PoC 빌드는 사용하지 않으며 심링크도
   건드리지 않는다. (ADR 0002)
4. **release 단일 빌드로 절대 성능과 VTune을 함께 측정** — CUBRID `release`(RelWithDebInfo,
   `-O2 -g -DNDEBUG`), PG `--enable-debug`(→ `-g -O2`, cassert off, JIT off). `--enable-debug`가
   `-g`만 추가한다는 것과 `.text` 코드 동일성은 실측으로 확인했다. (ADR 0003)
5. **쿼리·스키마 정본은 기존 자산 재사용, CUBRID 데이터는 pin 빌드로 재적재** —
   `scale10/queries/q1~q22`와 `create_tpch_{table,index}.sql`이 CUBRID 정본이다.
   TPC-H kit 부재로 dbgen seed·kit 버전은 확정 불가이며 그 한계를 수용한다(ADR 0004).
   반면 `~/databases/tpch_sf10_v2`는 **pin 빌드로 열리지 않아 은퇴**시켰다 — CBRD-26956
   (`a9fca9002`)이 CHAR/VARCHAR on-disk 포맷을 revert했고 그 DB는 revert 이전 빌드
   `4cfc837`이 썼다. 데이터는 `scale10/load_data/*.load`에서 pin 빌드로 다시 적재하며
   전용 `databases.txt`를 쓴다(공용 `~/databases` 불변). PG 적재·PG판 쿼리 파생과 함께
   **G1 선행 조건**이다. (ADR 0004, 0005, 0007)
6. **`perf`/`numactl`은 사용자가 직접 sudo 설치** — 정확한 `dnf` 명령은 `ENVIRONMENT.md` 4절.
7. **실행 전략은 얇은 경로(게이트 기반)** — R1~R8 전체 매트릭스를 순서대로 돌지 않고 G1~G5를
   차례로 통과시키며, 각 게이트의 증거로 다음 게이트의 대상 범위를 좁힌다. multi-seed(R4)와
   POWER-SHAPED는 삭제하고, 전용 C driver와 네트워크 실험(N1~N4)은 연기한다. (ADR 0005)
8. ~~**목표 DOP는 양쪽 6으로 고정** — CUBRID `parallelism=6` ↔ PG `max_parallel_workers_per_gather=6`~~
   → **ADR 0014가 대체.** 그 설정은 실제로 CUBRID 6단위 vs PG 7단위였다. 파리티는
   **실행 단위 수**로 맞추며 확정값은 CUBRID `parallelism=6` ↔ PG
   `max_parallel_workers_per_gather=5`(+leader) = **양쪽 6단위**다. PG
   `max_parallel_workers`(및 `max_worker_processes`)는 6 이상을 확보한다. CUBRID 서버 풀
   `max_parallel_workers`는 기본값 100이라 제약이 되지 않는다. DOP sweep을 다시 열면
   축은 worker 수가 아니라 **실행 단위 수**다. (ADR 0005 → 0014)
9. **단일 쿼리 timeout은 양쪽 300초** — 초과한 쿼리는 값을 대체하거나 보간하지 않고 **별도 상태
   `timeout`으로 기록**하며, 스트림은 다음 쿼리로 계속한다. 하네스 필수 요구사항이다. (ADR 0005)
10. **캐시 레짐은 WARM이 주 레짐** — 측정 세트마다 warmup 스트림 1회를 돌려 집계에서 빼고, AB/BA
    엔진 전환 직후에는 warmup을 재수행한다(CUBRID 46GB + PG ~25GB vs available ~91Gi — 상대 엔진
    런이 page cache를 밀어낼 수 있다). 측정 런의 물리 read 카운터로 warm임을 채증하며 **검증 실패
    런은 무효**다. cold는 주 축이 아니라 **I/O 진단 트랙 전용**이고 warm과 같은 표에 합치지 않는다.
    (ADR 0006)
11. **CUBRID 옵티마이저 히스토그램을 활성화한다 — 기본값 이탈** —
    `update_statistics_update_histogram=yes`(출시 기본값 `no`)를 측정 install
    `cubrid.conf`에 넣는다. 목적은 양쪽 옵티마이저의 카디널리티 추정 정보량을 맞춘 뒤
    **실행 엔진 차이를 보는 것**이다. 버킷 수는 각 엔진 기본값(CUBRID 300 /
    PG `default_statistics_target` 100)을 쓰고 정렬하지 않는다. 통계 재구축은
    `UPDATE STATISTICS`가 아니라 테이블별 `ANALYZE TABLE <t> DROP HISTOGRAM` →
    `UPDATE HISTOGRAM WITH FULLSCAN`으로 한다(전자는 버킷을 4로 클램프하고
    `WITH FULLSCAN`을 버린다). **이 구성의 수치는 기본 설정 CUBRID의 성능으로 인용할
    수 없다.** (ADR 0008)
12. **Comparison Contract — SUT CPU 경계는 "플랜을 실행하는 프로세스"** —
    주 지표는 CUBRID `cub_server` ↔ PG backend + parallel workers다. CUBRID의
    클라이언트측 질의 처리(파싱·플랜 생성·결과 마샬링)는 **주 지표에서 빼되
    `broker+CAS` 열로 항상 같이 기록**하며, PG는 그 열이 `N/A (backend 내부)`다
    (CUBRID 옵티마이저는 클라이언트측 — `src/optimizer/AGENTS.md:3,55`). 두 열을
    합산한 단일 숫자는 내지 않는다. 하네스·수집기(perf/VTune/모니터링)는 SUT와 다른
    cpuset. **wall time은 종전대로 end-to-end이고 이 변경의 영향을 받지 않는다** —
    worker 합산 CPU를 wall time에서 감산·직접 비교하지 않는 규칙도 유지된다.
    현재 하네스에는 broker/CAS가 **존재하지 않는다**(`csql -C`는 `cub_server` 직결,
    `cubrid broker status` → not running)이므로 그 열은 `csql` 자신을 뜻한다.
    (ADR 0009. 코어핀 권고는 ADR 0012가 기각·대체했고, `broker+CAS` 열 정의와
    파싱·플랜 열 의무화는 ADR 0011이 확장했다.)
13. **기준선** (8테이블 + 히스토그램 활성화, 2트랙) —
    **헤드라인: 단위 파리티 트랙 CUBRID 31.842 s / PG 10.442 s / 3.049x**(양쪽 6 실행 단위),
    자연 구성 트랙 CUBRID 31.511 s / PG 8.908 s / 3.537x(PG 7 실행 단위).
    파일럿 값은 이력 보존, 인용 시 구성 단서 필수. 9.19 % 드리프트는 원인 미규명 종결.
    **런 내 재현성(within-set sd)과 세션 간 드리프트(between-session drift)를 구분하고,
    런 내 sd를 세션 간 유의성 문턱으로 쓰지 않는다.** (ADR 0010, 0014)
14. **정본 접속 경로는 `csql -C` 직결** ↔ `psql` 직결. broker/CAS 경유 조항은 대체됐고
    기존 측정은 전부 유효하다. **모든 측정 표에 쿼리별 파싱·플랜 생성 시간 열을 채증**한다
    (CUBRID는 클라이언트측이라 SUT 밖, PG는 backend 안이라는 비대칭 때문). (ADR 0011)
15. **cpuset 공유 유지** — `cub_server`·PG backend·클라이언트측 처리(csql/psql) 모두
    node0 `0-15`, 수집기만 SUT 밖. **cpuset은 SUT CPU 회계 경계와 독립된 축이다.**
    (ADR 0012)
16. **기준선 전용 재측정 라운드를 만들지 않는다** — 해당 구성에서 처음 돌리는 측정
    라운드가 기준선을 겸한다. (ADR 0013)
17. **파리티는 실행 단위 수로 맞춘다** — 실행 단위 = 실제로 튜플을 처리하는 동시 실행
    주체 수이며 worker 수와 다르다(CUBRID = worker 수, PG = worker 수 + 1). 확정값은
    CUBRID `parallelism=6` ↔ PG `max_parallel_workers_per_gather=5` = **양쪽 6단위**.
    `parallel_leader_participation`은 기본 `on` 유지. 지표는 **(1) 자연 구성값 /
    (2) 단위 파리티 통제값 2트랙**으로 내고 **헤드라인 배수는 (2)**를 쓴다. 모든 표에
    **실행 단위 수 행**을 넣는다. (ADR 0014)
18. **WARM에는 하위 레짐이 둘 있다** — `stream` ↔ `single-query-repeat`을 같은 표에 섞지 않고
    모든 표에 하위 레짐 필드를 적는다. PG 민감도는 **쿼리 조건부**이고(Q21·Q8 민감 / Q9·Q18 무감)
    판정 기준은 워킹셋 크기가 아니라 **버퍼 잔존율이 상태에 따라 움직이는가**다.
    PG 표에는 `shared hit`/`read` 분할을 같이 적는다. (ADR 0016)
19. **PG `io worker`는 별개 열** — ADR 0009 경계에서 주 지표에 넣지 않고, PG worker CPU는
    N회+settle 브래킷으로 재야 회수 누수가 없다. (ADR 0017)
20. **노드별 워커 분포는 시간 가중으로만 읽는다** — 분포 표기는 플랜 채증이고 판정은
    `CPU/wall ÷ 목표 단위 수`(80 % 미만일 때만 `단위 붕괴`)다. 분포 표기는 **직렬 노드를 세지
    않으므로 직렬 구간을 따로 채증한다.** (ADR 0018)
21. **낮은 배수는 작은 격차가 아니다** — 정본 플랜 배수와 **형상 일치 배수를 같은 줄에 병기**하고
    (Q18 1.247x ↔ 1.877x), **`instructions` 비는 상한도 하한도 아니므로 정본 비교축은 `cycles`**이며
    **IPC 비를 표에 항상 넣는다**(±20 % 벗어나면 instructions 기반 서술 금지). 이용률 라벨 규칙은
    **PG에도 같이 적용**하고, 직렬 구간이 wall의 20 % 이상이면 **행위자별 프로파일**을 필수
    산출물로 낸다. 분류 규칙 확장은 **호출지점 확인 후에만** 하고 되돌릴 방법을 적는다. (ADR 0019)
22. **측정 원칙 v2 — `contract_revision: 2`** (사용자 지시, ADR 0020). ① 구 `G2`는 단일 세션이
    아니므로 **`PER_QUERY_CONNECTION_DIAG`**로 재명명하고 단일 connection 결과로 표현하지 않는다
    (`TRUE_SINGLE_CONNECTION`은 백로그 B1, 실행 금지). ② 모든 run에 `meta.json`으로
    `contract_revision`·`connection_mode`·`protocol`·`cpuset`·`timeout_method`·`sut_boundary`·
    `configured_cap`·`build`(commit+Build ID)·`artifacts`(sha256)를 남기고, **계약≠실행이면 즉시
    중단**한다(`meta.sh`가 `CONTRACT_MISMATCH`로 집행). ③ **complete-case(완주 19개) Pareto와
    censored lower-bound를 분리**하고 Q21은 "완주 19개 complete-case Pareto 1위"로만 표기한다
    (전체 22개 최상위는 **q22 ≥309x**). ④ "6 실행 단위 파리티" → **`configured-cap parity`**,
    `planned`/`launched`/`동시 활성`/`time-weighted active units`/`serial tail`을 따로 적는다.
    ⑤ 배수·기여도에 **이벤트 단위를 명시**하고 혼용하지 않으며 **Q8 분해는 두 표기만 허용**한다.
    ⑥ 다음 대상은 **q22**(bounded profile + 플랜 규명, 새 세션). ⑦ **SF1 correctness 미수행이므로
    어떤 항목도 "완료"가 아니다** — 전부 `measured, correctness-unverified`, SF1은 백로그 B2.
    ⑧ 기존 결과는 **삭제 금지·재분류만**, raw evidence는 `docs/MANIFEST-raw-evidence.md`에
    manifest와 백업 위치를 남긴다. (ADR 0020)

## 실행 전략(얇은 경로)

전체 매트릭스를 순회하지 않는다. **게이트를 하나 통과할 때마다 그 게이트의 증거로 다음 게이트의
대상 범위를 좁히는 얇은 경로**로 진행한다. 각 게이트는 통과 조건과 산출물이 정해져 있고, 조건을
채우지 못하면 다음 게이트를 열지 않는다. (ADR 0005)

| 게이트 | 하는 일 | 통과 조건 / 산출물 |
|---|---|---|
| **G1** | R0 재현 — 기존 하네스를 그대로 쓰고, 새 pinned 빌드 2개(CUBRID `f30f1c260`, PG `5713b437a`) 위에서 AB/BA interleaved 3회. **세트 시작 전과 엔진 전환 직후마다 warmup 스트림 1회(미집계)** | 양쪽 22개 쿼리 완주(또는 `timeout` 상태 기록), 집계 런 전부 warm 검증 통과, paired 차이의 sd 실측치 확보 |
| **G2** (트랙 명칭 = **`PER_QUERY_CONNECTION_DIAG`**) | 절대격차 Pareto + 22개 쿼리 양쪽 plan **병렬 여부 분류표**. **complete-case 19개만 순위**, q22는 censored lower-bound, q17·q20은 양쪽 censored (ADR 0020 §3) | **PG-only Parallel subset 식별이 최우선 통과 조건**, 절대격차 상위 목록 확정 |
| **G3** | top5만 DOP 1 vs 목표 DOP(6) 분해 | 쿼리별 병렬 이득/무이득 구분, 필요한 쿼리에만 DOP sweep 1~6 |
| **G4** | top3~5 plan diff + actual rows | **선행 조건: 통계 파리티** — 충족(2.6단계, ADR 0008). 양쪽 다 히스토그램·MCV·null 비율 보유, 범위 술어 추정이 양쪽 다 데이터에 반응한다. 단 CUBRID에 **여전히 없는 4항목**(물리 correlation, avg_width, 정확한 도메인 min/max, `attr op attr` 히스토그램 경로)과 **버킷 수 미정렬**(300 vs 100)을 산출물에 **전제로 명기**한 뒤 plan 형상 차이와 추정/실측 행수 괴리를 기록 |
| **G5** | 증거가 가리키는 **한 트랙만** 오픈 — optimizer 트랙 또는 VTune DIAG-PREFIX 트랙 | 증거로 확정된 영역에만 계측 패치. 두 트랙 동시 오픈 금지 |

**원인 후보는 측정 증거에서만 도출한다.** 어떤 연산자·코드 경로·서브시스템도 게이트를 통과하기 전에
병목 후보로 지목하지 않는다. 사전 지목은 G2~G4의 분류와 비교를 편향시키므로 문서·하네스·보고서
어디에도 넣지 않는다.

**환경 대체**: cgroup v2·HugePages·`chrt`(RT 우선순위)가 이 장비에서 불가하므로 `taskset`+`numactl`
바인딩으로 격리하고, CV 3% 절대 기준 대신 **paired AB/BA + 신뢰구간**으로 판정한다. (ADR 0005)

## Pending decisions

- ~~CUBRID 히스토그램을 켤지 여부~~ → **해결: (b) 켜고 재실행** (2026-07-28, ADR 0008,
  `docs/report-cubrid-histogram-enabled-20260728.md`). 잔여 판단은 **버킷 수 정렬 여부**
  뿐이다 — CUBRID 300 vs PG 100이고 두 파라미터의 의미 범위가 다르다(PG `default_statistics_target`은
  표본 크기 300×target까지 좌우). 지금은 각 엔진 기본값을 쓰며, 정렬 비용은 실측
  3.2s(8테이블 재구축 39.7s → 36.5s)로 값싸게 가역적이므로 G4 증거를 보고 정한다.
- 양측 파라미터 공정 대응 규칙(CUBRID `data_buffer_size`/`sort_buffer_size` ↔ PG `shared_buffers`/`work_mem`).
  Q1 파일럿은 **잠정으로 buffer 8G ↔ 8GB**를 썼다 — `tpch_sf10_v2`를 운용한 실측값
  (`paramdump`: `data_buffer_size=8.0G`)을 PG `shared_buffers`에 그대로 미러링했다. 규칙 자체는 미확정.
  `sort_buffer_size`/`work_mem`은 기본값이며 Q1에서는 무의미했다(CUBRID `GROUPBY … page: 0, ioread: 0`,
  PG 4행 quicksort 26kB).
- ~~병렬 여부 분류표의 라벨 규칙~~ → **해결 (2026-07-29, ADR 0018)**: 노드별 워커 분포는
  **플랜 채증으로만** 인용하고, 판정 라벨은 `CPU/wall ÷ 목표 실행 단위 수`로 붙인다.
  **80 % 미만일 때만** `단위 붕괴`를 쓰고, 그때 어느 노드가 붕괴 시간을 쥐는지 자기 시간
  비중과 함께 적는다. `Workers Launched < 목표 DOP`(PG Q22의 `Planned 5 / Launched 4`)도
  같은 규칙을 적용한다 — 개수 불일치가 아니라 이용률이 판정한다. **Q9는 측정해 라벨을 붙였다**
  (`1×2 2×5 2×6` → 질의 실행분 `CPU/wall` 5.927 = 6의 **98.8 %** → `병렬 유지`; `SUBQUERY` 2워커는
  gather 래퍼이고 그 아래가 5·6워커임을 스레드 표본화로 확정). **잔여: Q5·Q8·Q11의 이용률
  미측정(라벨 미부여 상태).** `CPU/wall > 6`이 나오는 경우의 읽는 법(내부 배경 스레드 분리)도
  ADR 0018에 추가됐다.
- 게이트 마진 — 판정 방식은 paired AB/BA + 신뢰구간으로 확정됐고, `PER_QUERY_CONNECTION_DIAG` 절대격차 컷 마진 수치만
  G1의 paired sd 실측치로 정한다. Q1 파일럿의 sd(CUBRID 0.120s / PG 0.018s)는 **엔진 내부 반복 노이즈**일
  뿐 paired AB/BA sd가 아니므로 마진 근거로 쓰지 않는다.
- ~~cold/warm 캐시 레짐 고정 방식~~ → **해결**: WARM 주 레짐 + cold 진단 트랙(ADR 0006). 잔여는
  컨테이너 안에서 `sudo /home/cubrid/bin/drop_caches.sh`가 동작하는지 **1회 실측**뿐이며, cold 트랙을
  여는 시점에 확인한다. warm 검증 문턱(1% / 100MiB)은 G1 실측 분포로 확정한다. Q1 파일럿의 집계 6개
  스트림은 최악값이 11.8MiB(스캔 대상의 0.13%)로 잠정 문턱을 충족했다(표본 6개로는 확정 불가).
- 측정 격리 — `taskset`+`numactl` 바인딩으로 확정. Q1 파일럿에서 `taskset -c 0-15`(node0 16코어)가
  PG 7개 프로세스·CUBRID 7개 스레드를 worker 부족 없이 수용했다. stray `cub_master`는 **0개**였고
  `ENVIRONMENT.md`의 4개는 stale이다. 상주 프로세스 정리 범위만 남았다.
- ~~PG 데이터 적재와 PG판 쿼리 파생 규칙~~ → **해결**(2026-07-28,
  `docs/report-g1-assets-20260728.md`). 양쪽 8테이블 적재 완료, q1~q22 양쪽 방언 확보.
  잔여로 넘어간 것은 **Q14/Q17/Q22의 결과 비교 시 십진 스케일 정규화**뿐이다 —
  CUBRID의 나눗셈/`AVG`이 PG `numeric`보다 소수 자릿수를 더 많이 남긴다
  (`schema/README-type-parity.md` §3).

## 백로그 (등재만, 실행은 별도 지시 — ADR 0020)

| # | 트랙 | 내용 | 선행 조건 |
|---|---|---|---|
| B1 | **`TRUE_SINGLE_CONNECTION`** | 한 연결에서 완주 19개를 순서대로 실행하고 연결 내 상태(CUBRID `xcache`·세션 통계, PG plan cache·`work_mem` 재사용) 효과를 분리한다. 현행 `PER_QUERY_CONNECTION_DIAG`는 쿼리마다 연결을 새로 만들므로 이 축이 미측정이다 | 없음. **실행은 별도 지시 전까지 금지** (ADR 0020 §1) |
| B2 | **`SF1_CORRECTNESS`** | SF1 데이터셋 + TPC-H reference answer 대조. **미수행이므로 모든 항목이 `measured, correctness-unverified`다** | (1) 재적재 금지 예외 승인 또는 별도 DB 승인 (2) TPC-H kit 확보(ADR 0004의 미해결 한계) |
| B3 | **q22 bounded profile + 플랜 규명** | censored lower-bound ≥309x. CUBRID 300 s 절단이므로 bound 확정(외부 timeout 연장 = 계약 변경) 또는 timeout 안에 끝나는 축소 변형으로 플랜 규명 | **다음 대상** (ADR 0020 §6) — 새 세션으로 별도 지시 |
| B4 | rev 1 raw 백업 tar | `g2-stream`·`q21`·`q9`·`q8`·`q18`·`q15`의 백업 tar가 아직 없다(Q3만 있다) | 없음 |
| B5 | 이전 라운드 CUBRID 프로파일 재검증 | `perf record -a -C` 심볼 해석 함정(Q3 §3.1)의 영향 여부를 `[unknown]` 비율로 확인하고 필요 시 `resolve.py`로 재해석 | 없음 |
| B6 | Q8·Q18 PG 귀속 재검증 | `-a -C` idle 감산법 → `perf stat -p <postmaster>` + 새 psql 세션으로 재검증 | 없음 (Q15에서 등재) |
| B7 | 전역 병렬 예산 비대칭 | CUBRID `max_parallel_workers=100` ↔ PG `8`. 계약을 어떻게 다룰지 미결 — 후보 ⑩이 코드 축 | 사용자 결정 |

## 산출물 배치 원칙

- **대용량 결과는 git 밖.** raw 측정치, 생성 데이터, 적재 로그, VTune 결과는
  `.git_ignored_dir/tpch-sspq/`에 두고 이 폴더에는 **결론과 그 근거 포인터만** 커밋한다.
- 스크래치는 `/tmp`·`$TMPDIR` 금지(저장소 house rule). `.git_ignored_dir/` 사용.
- 서버 기동/정지는 예외 없이
  `.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh` 래퍼 경유
  (raw `cubrid server start|stop`은 파이프에서 무한 hang).
