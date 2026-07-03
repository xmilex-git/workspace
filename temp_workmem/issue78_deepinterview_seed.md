# deep-interview 시드 — 병렬 SORT/DISTINCT perf 회귀 (#78/#73)

> 이 노트는 VTune 분석(`~/dev/workspace/vtune/ANALYSIS_KR.md`) 직후 작성된 deep-interview 출발 질문 모음.
> 권위: SSOT #75 §0 P2/§2.1·2.2, ADR 0003·0005. product code 수정 금지(deep-interview = 요구사항).

---

## 0. 유저 핵심 코멘트 (verbatim, deep-interview에서 함께 고려)

> "다 각자 다른 tape에 결과를 적는데, 한번에 한 스레드에서만 쓰기가 가능한데,
>  왜 더티를 남길때 mutex를 잡아야하지..? 이따 deep interview 때 같이 고려해보자."

---

## 1. 코드 사실로 본 그 코멘트 (grounding)

- `rawfd_find_and_mark_dirty(page_p)`의 mutex는 **dirty 비트 자체를 보호하는 게 아니라**,
  **서버 전역 공유 레지스트리** `g_rawfd_state.fixed_primary_shards[(page_p>>6)&63].map`
  (= `unordered_map<PAGE_PTR, rawfd_fixed_page>`)를 보호한다. (`temp_page_store.cpp:1205~`, `:145~149`)
- 즉 **write는 per-worker(자기 tape) 단일 스레드**가 맞지만, **페이지 추적 bookkeeping(맵)은 서버 전역 1개**라서
  concurrent find/insert/erase/rehash를 막으려고 락이 붙는다.
- 그러므로 **락은 "per-tape 쓰기" 때문에 필요한 게 아니라, "전역 레지스트리"라는 OLD 아키텍처 선택의 산물**이다.
  → 유저 직관이 맞다: 데이터가 per-worker로 분할돼 있으면 추적도 per-worker여야 하고, 그러면 락은 불필요.
- 한발 더: NEW 설계(ADR0003/0005)는 fix→dirty-mark→나중에 flush 라는 **간접층(전역 맵 경유)** 자체를 없애고
  **owner가 자기 버퍼/파일에 직접 append + batch flush + freeze**. 그러면 **dirty 마킹 자체가 사라질 수 있다**
  (pgbuf의 fix/dirty/flush를 raw-fd로 흉내 낸 게 OLD의 구조적 부채).

## 2. 측정으로 본 영향 (왜 이게 회귀의 본질인가)
- 이 전역-레지스트리 락이 병렬 스캔 생산자(`parallel_scan::result_handler::write → qfile_generate_tuple_into_list`)에서
  **페이지당 3.3~3.4M회** 잡힘 → 8워커 직렬화 → 평균 0.87코어(develop 4.16코어) → ~3.7× 회귀.
- 64샤딩(PHASE A.3)으로도 빈도+충돌 때문에 누적 wait 110~117s. 샤딩은 self-CPU만 줄였지 병렬성 회복 못함.

## 3. deep-interview에서 결정할 질문
1. **NEW 백킹은 dirty-mark를 "아예 제거"(owner 직접 append)인가, 아니면 "per-worker dirty 유지(락만 제거)"인가?**
   - 전자가 ADR 정합(간접층 제거). 후자면 왜 dirty가 여전히 필요한지.
2. **전역 레지스트리가 OLD에서 꼭 필요했던 책무**(reaper liveness/abnormal-term page free, eviction, write-back 추적)를
   per-worker **소유권 + 결정적 teardown**(ADR0001 reaper `(tran,query) OR session-held`)으로 어떻게 1:1 대체하나? 누락 책무 없나?
3. **lock0 불변식 보장**: NEW 생산 경로가 "공유 atomic chunk 커서 1개 외 mutex 0"(ADR0005)인지 — 즉
   NEW-backed list의 `qfile_set_dirty_page`가 rawfd 전역 경로를 **short-circuit** 하는가? (현 2A-1b NEW에서도 scan 생산자는 OLD 경유 → 미이주)
4. **이주 범위/순서**: 이 워크로드 병목 생산자 = 병렬 스캔 result_handler(2A-2). SORT만 옮긴 2A-1b가 무이득인 이유.
   read/consumer 경로(`result_handler::read`)·Phase3(OLD 레지스트리 삭제) 순서.
5. **금지**: §0 P2 "방안E(락 스킵)"는 증상 패치 → 채택 금지. 해법 = 구조(전역 레지스트리) 제거.

## 4. 참고 산출물
- 분석서: `~/dev/workspace/vtune/ANALYSIS_KR.md`
- VTune 결과: `~/dev/workspace/vtune/results/{develop,redesign_old,redesign_new}{,_thr}/`

---

## 5. "전역 레지스트리가 왜 필요한가" 추적 결과 (root cause) + 유저 stance

### 유저 stance (verbatim, deep-interview 함께 고려)
> "현재 설계에서 필요없을 부분은 가차없이 쳐내는것도 맞지. 같이 고려해보자."
> (= 이 hot 전역 per-page 레지스트리는 현 설계의 load-bearing 필수가 아니라 dead weight일 가능성 → 적극 제거 검토.)

### 왜 생겼나 (코드 사실)
- raw-fd 페이지 버퍼 = **naked `malloc(DB_PAGESIZE)`**(`alloc_db_page_buffer`). **identity 없음**(자기 file/page_index 역참조 없음).
- 그래서 PAGE_PTR만으로 flush/release하려면 `rawfd_fixed_page{file,page_index,dirty,ref_count}`를
  **전역 `unordered_map<PAGE_PTR,…>`** 에서 lookup → 락 필요.
- **결정적 모순**: dirty 마킹 호출자는 **이미 tfile을 넘긴다**(`qmgr_set_dirty_page(…,tfile_vfid_p)` → `rawfd_flush_page(thread_p,tfile_p,…)`),
  그런데 `rawfd_flush_page`는 `(void) tfile_p;` 로 **버리고** 전역 맵에서 file을 다시 찾는다(`rawfd_release_fixed_page`도 동일).
- 즉 hot 전역 per-page 맵 = **"raw pointer → (file,page_index)" 번역 계층**일 뿐. pgbuf의 *opaque PAGE_PTR* 페이지 모델에
  raw-fd를 억지로 끼운 산물. per-worker 단일쓰기 tape가 offset 산술로 자기 페이지를 알면(NEW) **맵도 락도 불필요**.

### 두 개의 "global"을 구분 (스코프 핵심)
| 구조 | 키 | 접근 빈도 | global인 이유 | perf 역할 |
|---|---|---|---|---|
| `fixed_primary/secondary_shards` | **PAGE_PTR** | **per-page (3.3M회)** | 버퍼에 identity가 없어서 | **병목 (제거 대상)** |
| `registry` | file_seq | open/close/reap (cold) | 서버 전역 abnormal-term reaping + 소유권 이전 | 병목 아님 |

→ hot한 per-page 맵은 제거 가능. cold한 per-file reaper만이 유일하게 "global" 정당성(crash 정리) — 그것도 per-worker 소유권+결정적 teardown(ADR0001)로 대체 검토.

### 스코프 옵션 (effort/복잡성 weigh — deep-interview 결정)
- **L0 (최소/증상)**: `rawfd_flush_page`/`release`가 넘겨받은 tfile 사용 + page_index를 버퍼/per-tfile에 담아 전역 per-page 맵 제거. 변경 최소지만 §0 P2 증상패치 경계(raw-fd+reaper 잔존, ref_count/secondary/read-cache 상호작용 리스크).
- **L1 (타깃 이주 — 권장)**: 병렬 스캔 생산자를 **이미 빌드된 NEW per-worker 백킹**(Phase1 `80f2bf810`)으로 이주(2A-2). 자기 tape에 offset 직접 → 전역 맵/락 소멸. 이 워크로드 해결, SSOT 정합. OLD 즉시삭제 불요.
- **L2 (full contract)**: 모든 생산/소비 NEW 후 raw-fd 레지스트리/락 전체 삭제(§5.4 Phase3). 구조적 종결.
- 결론 방향: **perf 버그 해소엔 설계 전반 flip 불필요**(L1로 충분); "필요없는 부분 가차없이 제거"는 L2(레지스트리/dirty-mark 간접층 자체)에서 실현.
