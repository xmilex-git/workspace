<!-- 외부 리뷰 원문 보존본. 2026-08-15 사용자 전달(원본: 별도 환경에서 수행된 재리뷰).
     주의: 리뷰 기준 HEAD fe6816ab9는 현행 feature/columnar HEAD 795d91585보다 낡음 —
     유효성 triage는 workspace 이슈 트래커의 triage 티켓 참조. -->

# CUBRID Columnar Storage 재리뷰 기반 구현·검증 명세서

- 대상 저장소: `https://github.com/xmilex-git/cubrid`
- 대상 브랜치: `feature/columnar`
- 기준 이슈: `https://github.com/xmilex-git/workspace/issues/2`
- 재리뷰 기준 원격 HEAD: `fe6816ab9df70f5313127c47e061622ca72d8c63`
- 작성일: 2026-08-14
- 목적: 아래 결함을 구현으로 해소하고, 재현 가능한 자동화 검증 증빙을 남긴다.

---

## 1. 수행 원칙

이 문서는 단순 검토 의견이 아니라 **구현 및 검증 작업 명세서**다. 구현자는 다음 원칙을 지켜야 한다.

1. 작업 시작 시 원격 `feature/columnar` HEAD와 로컬 worktree의 HEAD를 확인하고, 검증 대상 커밋을 하나의 SHA로 고정한다.
2. 이슈 #17 등에만 기록되고 원격 브랜치에 push되지 않은 로컬 수정이 있다면 먼저 원격 브랜치에 반영한다.
3. 각 결함은 재현 테스트를 먼저 작성하거나 최소한 재현 절차를 고정한 뒤 수정한다.
4. 빌드 성공이나 단일 정상 케이스만으로 완료 처리하지 않는다.
5. 트랜잭션, WAL, crash recovery, 동시성 문제는 fault injection 또는 강제 interleaving 테스트로 입증한다.
6. 오류를 무시하거나 `assert(false)`로 막는 방식은 정합성 해결로 인정하지 않는다.
7. 모든 테스트 결과에는 실행 커맨드, 대상 SHA, DB 설정, 예상 결과, 실제 결과를 남긴다.
8. 미해결 항목은 PASS로 기록하지 않는다. timeout은 정합성 PASS가 아니라 `UNVERIFIED`로 기록한다.
9. 기존 heap 경로 회귀 테스트를 함께 수행한다.
10. 최종 산출물은 구현 커밋, 테스트 코드, 검증 리포트, 설계 변경 사항을 모두 포함해야 한다.

---

## 2. 현재 상태 요약

현재 브랜치는 다음 수직 기능 흐름까지 구현되어 있다.

```text
CREATE TABLE ... USING COLUMNAR
  → FILE_COLUMNAR 생성
  → INSERT / transaction-class write state
  → stripe flush / compression / footer
  → ACCESS_METHOD_COLUMNAR 생성
  → column projection
  → vectorized predicate bitmap
  → min/max chunk skipping
  → 기존 qexec projection·aggregation
  → derived-table materialization을 통한 join 참여
```

단일 테이블 SELECT, COUNT, 일부 수치·날짜·NUMERIC·CHAR·VARCHAR 필터, NULL·NOT, LIKE, 집계, GROUP BY, ORDER BY·LIMIT까지 기능 검증 기록이 존재한다.

그러나 현재 원격 HEAD 기준으로 storage engine 병합을 차단하는 결함이 남아 있다.

### 최종 판정

| 영역 | 판정 |
|---|---|
| DDL·카탈로그·파일 타입 분리 | 양호 |
| 단일 테이블 columnar SELECT | 상당히 구현됨 |
| projection·vector filter·min/max skip | 방향 양호, 의미론 검증 추가 필요 |
| qexec 통합 | MVP로 합리적 |
| 조인 통합 | 불완전 또는 성능 한계 존재 |
| commit·rollback·WAL | 병합 차단 |
| snapshot visibility | 병합 차단 |
| 동시 INSERT | 병합 차단 |
| savepoint·2PC | 정합성 미충족 |
| 대규모 저장 | 원격 HEAD 기준 스케일 한계 존재 |
| TPC-H 성능 개선 | 아직 유효하게 입증되지 않음 |
| `develop` 병합 | 현재 상태에서는 금지 |

---

# PART A. P0 Blocker 구현 명세

## P0-1. COMMIT 직전 columnar flush 오류 전파 및 write-state lifetime 수정

### 문제

`log_commit_local()`이 다음 반환값을 무시한다.

```c
(void) columnar_flush_all_write_states (thread_p);
```

그 결과 disk full, page allocation 실패, metapage 포화, WAL append 실패, OOM, page fix 실패 등이 발생해도 일반 commit이 계속될 수 있다.

또한 `columnar_flush_all_write_states()`가 state를 순차 flush한 직후 즉시 free하므로, 뒤쪽 state에서 실패하면 전역 head가 이미 free된 state를 가리키는 dangling pointer가 될 수 있다.

### 필수 구현

1. `columnar_flush_all_write_states()`를 **flush 단계**와 **detach/free 단계**로 분리한다.
2. 모든 state flush가 성공하기 전에는 어느 state도 free하지 않는다.
3. 하나라도 실패하면:
   - commit을 중단한다.
   - transaction을 rollback 가능한 실패 상태로 전환한다.
   - 이미 flush된 stripe는 outer transaction rollback으로 제거한다.
   - registry는 유효한 연결 상태를 유지한다.
4. 모든 flush 성공 후에만 registry head를 NULL로 변경하고 state를 일괄 free한다.
5. `log_commit_local()`은 columnar flush 오류를 반드시 확인하고, 성공 commit 상태로 진행하지 않아야 한다.
6. 오류 발생 후 `tran_index`가 재사용되어도 이전 state가 남지 않아야 한다.

### 금지 사항

- 반환값을 로그만 남기고 무시하는 방식
- 일부 state를 free한 뒤 실패하는 구조 유지
- 오류 시 commit 성공 응답

### 검증

#### TC-COMMIT-01: 단일 state flush 실패

```text
INSERT columnar
commit 시 page allocation fault injection
```

기대 결과:

- COMMIT 실패
- 재접속 후 row 0개
- coredump 없음
- 해당 transaction의 page/dir entry 잔존 없음

#### TC-COMMIT-02: 다중 class 중간 실패

```text
INSERT INTO col_a ...
INSERT INTO col_b ...
A flush 성공
B flush 실패 강제
```

기대 결과:

- transaction 전체 실패
- A와 B 모두 commit되지 않음
- abort 시 double free/use-after-free 없음
- 다음 transaction에서 동일 `tran_index` 재사용 정상

#### TC-COMMIT-03: ENOSPC

실제 작은 test volume 또는 fault injection으로 ENOSPC를 유도한다.

기대 결과:

- 사용자에게 commit 실패 반환
- commit 성공 메시지 금지
- recovery 후 row 없음

---

## P0-2. Directory entry WAL redo 형식 수정

### 문제

현재 directory append 로그의 redo에는 `COLUMNAR_METAPAGE_HEADER`만 있고 실제 `COLUMNAR_STRIPE_DIR_ENTRY` bytes가 없다. recovery 함수도 `rcv->offset`을 사용하지 않고 header만 복원한다.

### 필수 구현

redo payload에 다음을 모두 포함한다.

```text
- format/version
- 갱신된 metapage header 또는 필요한 counter/header 변경분
- directory slot index 또는 byte offset
- 전체 COLUMNAR_STRIPE_DIR_ENTRY
```

Recovery 함수는:

1. payload version을 검증한다.
2. slot offset 범위를 검증한다.
3. header와 entry를 모두 복원한다.
4. 동일 redo를 두 번 적용해도 같은 상태가 되는 idempotent 동작을 보장한다.
5. malformed payload는 assert가 아니라 corruption/error로 종료한다.

### 검증

#### TC-WAL-01: directory dirty page 미flush crash

```text
1. stripe data WAL 기록
2. directory append WAL 기록
3. metapage dirty page는 디스크 flush 전
4. commit
5. 강제 crash
6. restart recovery
```

기대 결과:

- row count와 실제 row 내용 정상
- directory entry VPID/footer/row_count 정확
- stale 또는 zero entry 없음

#### TC-WAL-02: redo 반복 적용

동일 redo record를 두 번 적용한다.

기대 결과:

- entry_count 중복 증가 없음
- 동일 slot 내용 유지
- page corruption 없음

---

## P0-3. 동시 INSERT rollback 안전한 directory publication protocol 구현

### 문제

현재 undo는 자신의 slot을 지우지 않고 `entry_count = old_count`로 복원한다. 다음 interleaving에서 다른 transaction의 committed stripe까지 사라진다.

```text
T1: slot 0 append
T2: slot 1 append + COMMIT
T1: ABORT → entry_count를 0으로 복원
```

### 필수 설계

`entry_count`를 rollback 가능한 tail pointer로 사용하지 않는다.

권장 형태:

```text
metapage high_water_mark / slot_count: 단조 증가, rollback하지 않음

각 slot:
  EMPTY 또는 RESERVED
  PUBLISHED
  ABORTED / INVALID
```

필수 조건:

1. writer는 고유 slot을 예약한다.
2. undo는 자신의 slot만 INVALID로 만든다.
3. 다른 transaction slot에는 영향을 주지 않는다.
4. reader는 INVALID/EMPTY hole을 건너뛴다.
5. stripe_id와 first_row_number gap은 허용한다.
6. slot state 변경도 WAL로 복구 가능해야 한다.
7. concurrency latch는 page latch와 transaction rollback 의미를 모두 만족해야 한다.

### 검증

#### TC-CONC-01

```text
T1 append slot A
T2 append slot B
T2 COMMIT
T1 ABORT
```

기대 결과:

- T2 row만 보임
- T1 row 안 보임
- directory에 T2 slot 유지

#### TC-CONC-02

두 transaction이 각각 여러 stripe를 교차 append한 뒤 서로 다른 순서로 commit/abort한다.

#### TC-CONC-03

metapage chain 경계를 넘는 시점에서 동일 interleaving을 반복한다.

---

## P0-4. Write-state allocator와 소유권 통일

### 문제

원격 HEAD는 growable buffer를 `db_private_alloc → realloc → db_private_free`로 관리한다. SF10 적재에서 실제 malloc metadata corruption이 발생한 것으로 기록돼 있다.

### 필수 구현

다음 객체의 allocator를 하나로 통일한다.

- `COLUMNAR_WRITE_STATE`
- `COLUMNAR_COL_BUFFER[]`
- `col->data`
- `col->exists`
- `ws->stripe_data`
- `ws->chunk_descs`
- savepoint state

권장:

1. transaction lifetime 객체는 `LOG_TDES` 또는 transaction-owned registry/context에 귀속한다.
2. worker thread가 변경되어도 안전한 allocator를 사용한다.
3. growable buffer는 `malloc/realloc/free` 또는 동일 custom allocator의 alloc/realloc/free를 일관되게 사용한다.
4. init 실패 시 부분 생성 객체를 정확히 cleanup한다.
5. transaction 종료 시 destructor 경로를 단일화한다.

### 검증

- ASAN 또는 allocator debug build에서 60M INSERT SELECT
- 여러 클라이언트가 같은 transaction index pool을 반복 재사용
- grow/shrink가 여러 번 발생하는 대형 VARCHAR 적재
- abort, commit, same-txn flush 모두에서 leak/double-free 0

---

## P0-5. 비연속 stripe page 지원

### 문제

CUBRID `file_alloc_multiple()`은 물리 VPID 연속성을 보장하지 않지만 writer와 reader는 `start_vpid.pageid + i`를 전제로 한다.

### 권장 구현: Stripe-local Page Map(SMAP)

```text
page 0:
  SMAP header
  VPID[page_count]

page 1..N:
  stripe data + footer
```

SMAP 필수 필드:

```text
magic
version
page_count
payload_page_count
reserved/checksum optional
VPID[]
```

필수 조건:

1. directory `start_vpid`는 SMAP page를 가리킨다.
2. reader는 stripe open 시 SMAP을 한 번 snapshot한다.
3. 이후 page lookup은 `stripe_vpids[index]`로 O(1) 수행한다.
4. map page capacity를 넘는 stripe는 byte cap으로 미리 flush한다.
5. map page 및 data page 모두 redo/undo 규칙이 명확해야 한다.
6. footer 위치는 물리 pageid 차이가 아닌 page-map index로 표현한다.
7. 멀티볼륨 VPID도 처리한다.

### 검증

- allocator가 의도적으로 비연속 VPID를 반환하도록 fault injection
- stripe가 volume/sector 경계를 넘도록 구성
- 200K, 1M, 60M row 적재 후 checksum/aggregate 비교
- restart recovery 후 SMAP과 data/footer 일치 확인

---

## P0-6. Metapage chain 구현

### 문제

첫 metapage에 약 255개 stripe entry만 저장 가능하며, 원격 HEAD는 포화 시 `assert(false)`와 `ER_FAILED`를 반환한다.

### 필수 구현

1. `next_metapage` chain을 writer와 reader 모두 구현한다.
2. counter ownership을 명시한다.
   - 권장: root metapage에 global counters 고정
   - tail page에는 directory entry만 append
3. tail 탐색 latch protocol을 문서화한다.
4. 새 metapage allocation·init·link의 sysop 경계를 명확히 한다.
5. transaction abort 시 dangling link가 없어야 한다.
6. 빈 chain page 재사용 정책을 정의한다.
7. reader는 전체 chain을 순회하고 visible entry를 누적한다.
8. cycle, invalid next VPID, 잘못된 magic/version을 검출한다.

### 검증

- 255, 256, 257 stripe 경계
- 400개 이상 stripe 생성
- chain 확장 직전/직후 crash
- chain page 생성 transaction abort
- chain 중간 page corruption 검출

---

## P0-7. MVCC snapshot visibility를 core 규칙과 동일하게 수정

### 문제

현재 reader는 `snapshot->m_active_mvccs.is_active(id)`만 사용한다. 이는 `lowest_active_mvccid`, `highest_completed_mvccid` 범위를 무시한다.

### 잘못된 시나리오

```text
T1 snapshot 획득
T2가 이후 MVCCID 획득 후 columnar stripe COMMIT
T1이 같은 snapshot으로 다시 columnar scan
```

T2는 T1 snapshot에서 보이면 안 되지만 active bitmap에 없다는 이유로 visible 처리될 수 있다.

### 필수 구현

1. core MVCC 모듈에 공개 helper를 추가하거나 기존 helper를 재사용한다.
2. columnar scanner가 snapshot 규칙을 자체 재구현하지 않는다.
3. own transaction stripe는 명시적으로 visible 처리한다.
4. invalid/legacy MVCCID는 format version 정책에 따라 처리하며 무조건 committed로 노출하지 않는다.
5. snapshot pointer가 NULL인 경우의 정책을 명확히 한다.

### 검증

#### TC-MVCC-01: repeatable read

```text
T1 SELECT COUNT(*) → N
T2 INSERT + COMMIT
T1 같은 transaction에서 SELECT COUNT(*)
```

기대 결과: T1 isolation semantics에 맞게 N 유지.

#### TC-MVCC-02: own write

T1 INSERT 후 commit 전 SELECT에서 own stripe visible.

#### TC-MVCC-03: uncommitted other writer

T2 uncommitted stripe는 T1에 보이지 않음.

#### TC-MVCC-04: abort

T2 abort 후 어떤 snapshot에서도 보이지 않음.

---

## P0-8. Columnar INSERT의 class lock 계약 복구

### 문제

`heap_insert_logical()`이 일반 heap 경로의 IX/BU lock 획득 전에 columnar insert로 return한다.

### 필수 구현

1. columnar insert도 heap insert와 동일한 class-level lock 계약을 지킨다.
2. prepared statement 재실행에서 이전 commit으로 lock이 해제된 경우 실행 시 재획득한다.
3. bulk insert라면 BU lock 보유를 검증한다.
4. DROP/DDL/file destroy와 충돌하지 않아야 한다.
5. lock 획득 실패 시 write state를 생성하지 않는다.

### 검증

- prepared statement: execute → commit → execute 반복
- INSERT와 DROP 동시 수행
- INSERT와 schema cache invalidation 동시 수행
- lock timeout/deadlock 시 cleanup 정상

---

## P0-9. Savepoint semantics 수정 또는 명시적 미지원 처리

### 문제

현재 savepoint marker는 `rows_at_savepoint`만 저장하며 VARCHAR/VARBIT mid-chunk rollback, savepoint 이후 새 write state, flush된 stripe 경계 등을 정확히 복원하지 못한다. OOM도 best effort로 무시한다.

### 권장 MVP 구현

1. savepoint 생성 직전에 모든 pending columnar write state를 flush한다.
2. flush 실패 시 savepoint 생성 자체를 실패시킨다.
3. write state에 savepoint generation을 부여한다.
4. savepoint 이후 생성된 state는 rollback 시 전부 폐기한다.
5. savepoint 이후 disk stripe는 기존 log rollback으로 제거한다.
6. savepoint marker allocation 실패를 무시하지 않는다.

정확한 구현이 어렵다면:

- columnar write가 존재하는 transaction에서 SAVEPOINT를 명시적으로 거절한다.
- best-effort savepoint는 제거한다.

### 검증

- fixed-width mid-chunk rollback
- VARCHAR mid-chunk rollback
- chunk boundary rollback
- stripe boundary rollback
- nested savepoint
- savepoint 이후 처음 접근한 columnar class rollback
- savepoint marker OOM

---

## P0-10. XA/2PC PREPARE 처리

### 문제

PREPARE 전에 pending columnar rows가 memory에만 남을 수 있다.

### 필수 구현 선택지

#### 선택 A: 지원

- PREPARE log 기록 전에 모든 pending columnar state flush
- 오류 발생 시 PREPARE 실패
- prepared transaction restart 후 commit/rollback 가능

#### 선택 B: MVP 미지원

- columnar DML이 포함된 XA/2PC transaction의 PREPARE를 명시적으로 거절
- 사용자에게 전용 오류 반환

### 검증

```text
columnar INSERT
XA PREPARE
server restart
XA COMMIT 또는 XA ROLLBACK
```

지원 선택 시 결과가 정확해야 하며, 미지원 선택 시 PREPARE 단계에서 일관되게 거절되어야 한다.

---

# PART B. P1 구현 명세

## P1-1. Reader on-disk metadata strict validation

다음을 반드시 검증한다.

```text
metapage magic/version
entry_count capacity
next_metapage validity/cycle
SMAP magic/version/page_count
footer 위치 범위
footer magic/version
n_columns == class representation column count
n_chunk_groups와 row_count 관계
곱셈 overflow
chunk descriptor index 범위
data_offset + data_length 범위
exists_offset + exists_length 범위
fixed-width expected decompressed bytes
variable length prefix bounds
codec enum
data_length/decompressed_length 관계
page type
VPID validity
```

Corruption 시 `assert(false)`가 아니라 명시적 corruption/error로 종료한다.

---

## P1-2. UTF-8/EUC-KR `CHAR(n)` 직렬화 수정

현재 `domain->precision`을 byte width로 사용하면 멀티바이트 문자가 잘린다.

선택지:

1. multibyte CHAR를 variable-width로 저장
2. codeset별 최대 byte width를 적용하고 정규화/padding 의미론 정의
3. MVP에서 single-byte CHAR만 허용
4. 기존 CUBRID primitive serializer 재사용

반드시 다음을 heap과 differential test한다.

```text
한글 CHAR
한글 VARCHAR
멀티바이트 최대 길이
문자 경계 절단 여부
trailing spaces
빈 문자열
```

---

## P1-3. LIKE `_` wildcard를 문자 단위로 처리

현재 raw byte matcher는 `_`가 1바이트만 소비한다. UTF-8 binary/EUC-KR binary에서도 이 동작은 잘못될 수 있다.

필수:

- 기존 codeset-aware LIKE matcher를 재사용하거나
- codepoint 단위 matcher를 구현하거나
- byte matcher 지원을 single-byte codeset으로 제한

검증:

```sql
'가' LIKE '_'
'가나' LIKE '__'
멀티바이트 prefix/suffix/contains
연속 wildcard
trailing space
```

---

## P1-4. Compression actual codec 기록

압축 함수는 다음을 반환해야 한다.

```text
actual_codec
output_buffer
output_length
```

다음 경우 `actual_codec=NONE`:

- 압축 실패
- compressed size >= raw size
- compression disabled
- empty input

Descriptor는 요청 codec이 아니라 actual codec을 기록한다.

검증:

- incompressible random payload
- empty/all-NULL chunk
- 강제 LZ4 failure
- 강제 ZSTD failure
- reader가 raw fallback 데이터를 정상 읽음

---

## P1-5. Row append와 chunk serialization 실패 원자성

### 필수 구현

- row append 전 컬럼별 cursor/bitmap state snapshot
- 중간 실패 시 정확히 rollback
- chunk serialization은 temporary buffer/descriptor에 완성 후 publish
- 또는 오류 발생 시 transaction doomed 처리하고 이후 DML/commit 금지

검증:

- N번째 컬럼에서 OOM
- 압축 중간 실패
- descriptor grow 실패
- 오류 후 재시도 또는 rollback 시 컬럼 alignment 유지

---

## P1-6. Synthetic OID 계약 수정

현재 stripe-local `current_rows` 기반 OID는 중복 가능하다.

선택:

1. stripe 시작 시 global row-number range 예약
2. 명시적 columnar row identifier 타입/encoding 도입
3. MVP에서 소비처가 없음을 증명하고 invalid OID 반환 계약 적용

상위 locator/index/trigger/supplemental log 코드가 OID uniqueness를 가정하는지 감사한다.

---

## P1-7. 메시지 카탈로그 ID 정합성

현재 메시지 파일의:

```text
1379 Expression not supported ...
1379 Last Error
```

중복을 수정한다.

```text
1379 Expression not supported ...
1380 Last Error
```

모든 locale과 `ER_LAST_ERROR`를 일치시킨다.

---

## P1-8. System parameter 연결

다음 값을 실제 시스템 파라미터로 노출한다.

```text
stripe row count
chunk row count
stripe max bytes
compression codec
compression level
writer transaction memory quota
global writer memory quota
```

기존 stripe 해석은 footer에 저장된 값만 사용해야 하며, runtime parameter 변경이 기존 데이터 해석을 바꾸면 안 된다.

---

## P1-9. Write-path per-row attrinfo overhead 개선

현재 INSERT마다 `heap_attrinfo_start/read/end`를 반복한다.

write state에 다음을 캐시하는 방안을 검토한다.

```text
class representation/reprid
attrid → storage column mapping
column serializer function pointer
domain metadata
record decoder plan
```

ALTER를 금지한 MVP 범위에서도 class cache invalidation/lifetime 계약은 지켜야 한다.

---

# PART C. 읽기 실행기 아키텍처 정리

## 1. 현재 실제 실행 모델

현재 구현은 완전한 vector expression executor가 아니라 다음 하이브리드다.

```text
chunk 단위:
  page read
  decompress
  vectorized WHERE
  min/max skip
  qualified bitmap 생성

qualified row 단위:
  DB_VALUE decode
  기존 qexec expression/projection
  기존 aggregation
  list-file tuple 생성
```

이 구조는 MVP로 합리적이다. 다만 설계 문서에서 다음 중 하나를 명확히 선택해야 한다.

1. 현재 구조를 MVP 최종 구조로 공식화
2. filter만 1차 vectorization으로 정의하고 expression/aggregate vectorization은 후속 단계로 이동
3. Q6형 SUM/COUNT 등 단순 집계를 block fast path로 추가

설계 문서에 "block 내부 식·집계 완결"이라고 쓰면서 실제 코드는 per-row qexec를 호출하는 불일치를 해소한다.

---

## 2. Derived-table join materialization

현재 조인 참여는 columnar spec을 derived table로 승격해 물질화하는 방식이다.

필수 확인:

- view merging이 다시 부모 join으로 흡수하지 않도록 NON_PUSHABLE/NO_MERGE 경계 보존
- select list trimming은 유지
- outer join, correlated subquery, CTE, nested derived table에서 의미론 유지
- materialized rows/bytes/list-file spill을 trace에 기록

장기 개선 후보:

```text
cost-based materialization
columnar block iterator를 join input으로 직접 연결
작은 결과에만 materialize
correlated result cache
```

---

# PART D. 검증 캠페인

## 1. 빌드

다음 모두 통과해야 한다.

```text
optdebug full build
release full build
standalone build
client/server build
ASAN 또는 allocator-debug build 가능 시 추가
```

빌드 로그와 버전 문자열을 보관한다.

---

## 2. 기능 differential test

동일 데이터를 heap table과 columnar table에 넣고 결과를 byte-for-byte 또는 정규화된 row 단위로 비교한다.

### 기본

- full SELECT
- COUNT(*)
- projection subset
- ORDER BY
- LIMIT/OFFSET
- GROUP BY
- SUM/COUNT/MIN/MAX/AVG
- expression projection

### Predicate

- `=, <>, <, <=, >, >=`
- BETWEEN
- IN / IN with NULL
- AND/OR/NOT Kleene 3VL
- IS NULL / IS NOT NULL
- col op col
- LIKE `%`, `_`, prefix/suffix/contains
- host variable
- correlated value

### Type

- SHORT
- INTEGER
- BIGINT
- FLOAT
- DOUBLE
- MONETARY
- DATE
- TIME
- TIMESTAMP
- DATETIME
- NUMERIC(p,s)
- CHAR(n)
- VARCHAR
- BIT
- VARBIT
- all NULL chunk
- unsupported type create/insert rejection

### String

- ASCII
- UTF-8 한글
- EUC-KR 가능 시
- trailing spaces
- empty string
- 최대 precision
- multibyte boundary

---

## 3. Transaction test matrix

| ID | 시나리오 | 기대 결과 |
|---|---|---|
| TX-01 | INSERT → COMMIT | row visible |
| TX-02 | INSERT → ABORT | row invisible |
| TX-03 | same-txn INSERT → SELECT | own row visible |
| TX-04 | T1 snapshot, T2 commit, T1 rescan | isolation semantics 유지 |
| TX-05 | T2 uncommitted stripe | T1에 invisible |
| TX-06 | T1/T2 interleaved append, T2 commit, T1 abort | T2만 유지 |
| TX-07 | commit-time flush failure | commit 실패, row 0 |
| TX-08 | 다중 class 중간 flush 실패 | 전체 rollback |
| TX-09 | nested savepoint | 정확한 rollback |
| TX-10 | XA PREPARE/restart/commit | 지원 정책에 맞게 동작 |

---

## 4. Crash recovery fault matrix

다음 각 지점 직후 강제 crash한다.

```text
file page allocation 직후
data page WAL append 직후
data page dirty 직후
SMAP WAL 직후
footer write 직후
directory slot reserve 직후
directory entry WAL 직후
slot publish 직후
commit log 직전
commit log 직후
metapage chain link 직후
```

각 케이스에서 restart 후 다음을 확인한다.

```text
committed row만 보임
aborted/uncommitted row 안 보임
orphan page 없음
invalid directory entry 없음
SMAP/footer/descriptor 범위 정상
recovery assert/coredump 없음
```

---

## 5. Scale test

### 적재량

- 200K rows
- 1M rows
- TPC-H SF1
- TPC-H SF10 lineitem 약 60M rows

### 경계

- 1 stripe
- 254/255/256/257 stripe
- 2 metapage 이상
- SMAP map capacity 직전
- stripe byte cap 직전
- multi-volume allocation 가능 시 경계 통과

### 검증

- COUNT
- SUM/MIN/MAX
- random sample checksum
- heap 대비 전체 row hash
- restart 후 재검증

---

## 6. TPC-H 정합성

22개 쿼리를 모두 수행한다.

판정 규칙:

```text
PASS: heap과 결과가 동일하고 실행 완료
FAIL: 결과 불일치 또는 오류
TIMEOUT/UNVERIFIED: 시간 내 완료되지 않아 정합성 미검증
```

다음 표현은 금지한다.

```text
19 PASS + 3 timeout을 전체 정합성 통과라고 표현
```

정확한 보고 예:

```text
19/22 verified equivalent
0 observed mismatches
3 unverified due to timeout
```

---

## 7. 성능 검증

### 공정 조건

- 동일 `data_buffer_size`
- 동일 server restart 정책
- 동일 DB volume/config
- 동일 concurrency
- 동일 query plan 조건
- heap/columnar 실행 순서 교차
- cold-cache와 warm-cache 별도
- 최소 3회, 권장 5회 median

### 측정 대상

- Q1
- Q6
- Q12
- Q14
- 단일 테이블 date range count
- projection 비율별 scan
- selectivity별 filter
- chunk skip 가능/불가능 데이터 분포

### 필수 지표

```text
elapsed time
CPU time
page-buffer ioreads
bytes decompressed
stripes read
chunk groups total/skipped
rows scanned/qualified/output
materialized list-file rows/bytes
sort/list spill pages
compression ratio
```

### 합격 기준

이 프로젝트의 기존 목표에 명시적 배수 목표가 없다면 최소 다음을 만족해야 한다.

1. 적어도 대표적인 columnar 적합 scan에서 heap 대비 유의미한 개선이 재현된다.
2. 결과는 동일하다.
3. 개선이 buffer/cache 불공정에 의한 것이 아님을 증명한다.
4. join materialization으로 인해 심각하게 느려지는 쿼리는 원인과 제한을 명시한다.

---

# PART E. 자동화 테스트 추가 요구

최소한 다음 테스트를 repository test suite에 추가한다.

```text
columnar_ddl.sql
columnar_insert_select.sql
columnar_select_types.sql
columnar_predicate_3vl.sql
columnar_utf8.sql
columnar_savepoint.sql 또는 explicit unsupported test
columnar_concurrent_insert test
columnar_commit_failure fault test
columnar_recovery fault test
columnar_metapage_chain test
columnar_noncontiguous_page test
columnar_2pc test 또는 unsupported test
```

테스트 파일이 repository에 없고 외부 `/data/...` 하네스에만 존재하면 완료로 인정하지 않는다. 외부 대규모 하네스는 추가 증빙으로 사용하되, 최소 회귀 검증은 repository에서 재실행 가능해야 한다.

---

# PART F. 구현 순서

## Phase 0. 기준점 고정

- 원격/로컬 HEAD 일치
- 미push 커밋 push
- baseline SHA 기록
- 기존 failing reproduction 실행

## Phase 1. Memory·page mapping·metapage scale

1. allocator 통일
2. SMAP 비연속 page 지원
3. metapage chain
4. strict on-disk validation

## Phase 2. Transaction correctness

1. commit error propagation
2. write-state two-phase cleanup
3. class IX lock
4. directory publication protocol
5. exact WAL redo/undo
6. snapshot helper 사용
7. savepoint
8. 2PC

## Phase 3. SQL 의미론

1. UTF-8 CHAR
2. LIKE `_`
3. compression actual codec
4. row/chunk failure atomicity
5. synthetic OID
6. message catalog

## Phase 4. Reader·join architecture 정리

1. view merge guard
2. materialization trace
3. 설계 문서와 실제 hybrid executor 일치
4. timeout query 개선 후보 분리

## Phase 5. 통합 검증

1. regression
2. concurrency
3. crash recovery
4. SF10
5. TPC-H 22Q correctness
6. fair performance

---

# PART G. 완료 조건

다음 조건을 모두 충족해야 완료다.

## 필수 correctness gate

- [ ] commit-time flush 실패가 성공 commit으로 응답되지 않는다.
- [ ] 다중 state 중간 실패 후 dangling pointer/double free가 없다.
- [ ] directory redo가 entry bytes까지 복원한다.
- [ ] concurrent writer abort가 다른 writer의 commit을 제거하지 않는다.
- [ ] 비연속 VPID stripe를 정상 읽는다.
- [ ] 256개 이상 stripe를 정상 저장·읽는다.
- [ ] core MVCC snapshot semantics와 동일하다.
- [ ] class lock 계약이 유지된다.
- [ ] savepoint 또는 명시적 미지원 정책이 정확하다.
- [ ] 2PC 또는 명시적 미지원 정책이 정확하다.
- [ ] crash recovery fault matrix 통과.
- [ ] coredump/assert/fatal 0.

## SQL semantics gate

- [ ] UTF-8 CHAR/VARCHAR heap differential 통과.
- [ ] LIKE `_` 멀티바이트 의미론 통과.
- [ ] NULL/NOT/IN 3VL 통과.
- [ ] 모든 지원 타입 round-trip 통과.
- [ ] unsupported type/expression이 명확한 오류로 거절됨.

## Scale gate

- [ ] 60M row INSERT SELECT 완료.
- [ ] restart 후 row count 및 aggregate 동일.
- [ ] metapage chain과 SMAP 경계 통과.

## TPC-H gate

- [ ] 22개 쿼리 상태를 PASS/FAIL/UNVERIFIED로 정직하게 보고.
- [ ] 결과 불일치 0.
- [ ] timeout 쿼리는 별도 미해결로 기록.

## Performance gate

- [ ] 동일 buffer/cache 조건으로 재측정.
- [ ] 대표 columnar scan의 개선 재현.
- [ ] 결과에 raw log와 설정 포함.

## 산출물 gate

- [ ] 코드 커밋 SHA.
- [ ] 자동화 테스트 커밋.
- [ ] 검증 리포트 Markdown.
- [ ] 주요 로그/JSON 결과.
- [ ] 최종 설계 문서 업데이트.
- [ ] 남은 제한과 후속 작업 목록.

---

# PART H. 최종 검증 리포트 형식

최종 리포트는 다음 형식을 사용한다.

```markdown
# CUBRID Columnar 최종 구현·검증 보고서

## 1. 대상
- Repository:
- Branch:
- Base SHA:
- Final SHA:
- Build type:
- OS/CPU/RAM/Storage:
- cubrid.conf 핵심 설정:

## 2. 구현 요약
- P0-1:
- P0-2:
...

## 3. 변경 파일
| 파일 | 변경 목적 | KLOC |

## 4. Correctness
| Test ID | 결과 | 증빙 |

## 5. Concurrency
| Interleaving | 결과 | 증빙 |

## 6. Crash Recovery
| Crash point | 결과 | 증빙 |

## 7. Scale
| Dataset | Rows | Load time | Result |

## 8. TPC-H
| Query | Heap result hash | Columnar result hash | Heap sec | Columnar sec | Status |

## 9. Performance
- cold/warm 분리
- median
- ioreads
- chunk skip
- materialization spill

## 10. 회귀
- heap CRUD
- index
- vacuum
- backup/restart

## 11. 미해결
- 정확한 제한
- 재현법
- 우선순위

## 12. 최종 판정
- MERGEABLE / NOT MERGEABLE
- 근거
```

---

# 최종 리뷰 결론

현재 구현은 초기 DDL·write-path 프로토타입을 넘어 실제 columnar vertical slice로 크게 발전했다. 특히 자체 scan path, projection, vector predicate, min/max skipping, qexec 통합, join 참여 시도, SF10 적재를 통한 scale 문제 발견은 긍정적이다.

그러나 storage engine 병합 기준에서는 다음 네 축이 최우선이다.

```text
COMMIT 원자성
WAL/Recovery 정확성
동시 rollback 안전성
MVCC snapshot 의미론
```

이 네 축이 해결되기 전에는 성능 결과가 좋아도 `develop` 병합 대상으로 보지 않는다. 모든 P0 blocker와 correctness gate를 먼저 통과시킨 뒤 SQL 의미론, scale, TPC-H 성능 검증 순으로 진행한다.
