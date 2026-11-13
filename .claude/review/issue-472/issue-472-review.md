# Issue #472 진행 리뷰

What this change does: `cubrid-fastmig`는 정상 종료한 CUBRID DB를 Rust로 직접 옮긴다. 사용자 행의 위치를 보존하면서 힙을 변환하고, 카탈로그와 인덱스를 도착 버전에 맞춰 다시 만든다.

> **판정: 수정 후 재검증 필요.** 11.4→develop과 develop→develop의 동작 근거는 쌓였다. 다만 재실행 정리에서 기존 파일을 지우는 문제, finalize 잠금 수명, 문자열 차이를 숨기는 비교기 문제를 먼저 고쳐야 한다. 디스크·메모리 한도도 아직 완료 조건을 충족하지 않는다.

## Review scope

- 확인일: 2026-10-30 KST. 대상 지도: [workspace#472](https://github.com/xmilex-git/workspace/issues/472), 구현: `/home/cubrid/dev/cubrid-fastmig`.
- 최종 코드 기준: `14079bfa666d74cdf56745f0b8454ba22759ed24`. 조사 중 들어온 버전 판독기 `022247b`와 spill 예약 `14079bf`까지 대조했다.
- 지도 본문과 하위 이슈 62개의 목록·상태를 확인했다. 본문·댓글은 계약·구현·검증에 직접 관계된 #481/#483/#484/#494/#495/#502~#506/#509/#512/#525/#526을 중심으로 읽고, 후속 버전쌍 티켓의 범위도 대조했다. #535는 #529에 합쳐 닫은 중복 이슈다.
- 소스는 plan→migrate→verify→finalize, 잠금·파일 생성·재실행 정리, 집합 비교, 자원 계산을 중점적으로 추적했다. 전체 온디스크 코덱·B-tree 빌더를 줄마다 전수 검토한 보고서는 아니다.
- 동시 세션의 미커밋 변경은 제외했다. 코드 스냅숏과 재현 자료는 [리뷰 전용 디렉터리](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030)에 보존했다.

## Progress

하위 이슈는 조회 시점에 closed 41개, open 21개였다. closed에는 중복 #535도 포함되므로 이 숫자를 완료율로 읽으면 안 된다.

| 작업 | 현재 판단 | 근거와 남은 일 |
|---|---|---|
| 온디스크 조사·계약 | 11.4→develop의 구현 기준을 마련함 | R1~R7, G1~G6, ADR 0001~0015. 로그 시작점을 vacuum 블록 경계로 맞추고 사용자 OID를 보존하는 방향이 코드와 연결돼 있다. |
| 힙·카탈로그·인덱스 통합 | 실행되는 경로가 있음 | #490~#501, #503/#504/#507/#508. same-version도 힙 patch와 전 인덱스 재빌드를 거친다. |
| 독립적인 값 대조 | 기존 T1 네 경로의 unload 결과가 현재 비교기로 일치함 | 이번 리뷰에서 보관된 엔진 unload를 다시 비교해 네 경로 모두 종료 0. 단, 아래 지적 3의 반례가 있다. |
| 포팅 TC | develop→develop의 기존 회귀 근거가 있음 | [#502](https://github.com/xmilex-git/workspace/issues/502): 고정 바이너리 `a49c9b16f054`로 30/30 PASS, DB 33개. 보고 표와 일부 원로그를 대조했으며 재실행하지 않았다. |
| 성능·최종 통합 #484 | 아직 열어 두는 것이 맞음 | unload/load 대비 개선과 cp 대비 최종 합격은 구분해야 한다. 아래 측정 표 참조. |
| 자원 한도 #526 | 구현 중 | spill arena 예약은 `14079bf`에 들어왔다. 도착 파일 공간 예약, 11.4 출발 사전 추정, 실행 가능한 최소 메모리 계산은 남았다. |
| 11.3·11.2 출발 | 아직 지원 완료 아님 | #512는 기준 DB 준비, #522는 버전 판독, #529는 실제 변환 연결이다. `source_line()`은 아직 해당 출발을 거부한다. |
| 10.2 출발 | 선행 결정·구현 필요 | #515~#524: 빈 TDE 메타데이터, LZO, 사용자 이름·소유자 참조, 같은 슬롯 시스템 행, opcode와 공백 비교 규칙. |
| 11.4 도착 | 현재 거부가 계약과 일치함 | #530~#534가 빌더·카탈로그를 맡는다. 미지원 자체를 현재 결함으로 세지 않았다. |
| 최종 릴리스 대응 | 별도 게이트 유지 필요 | #528은 기준 엔진 커밋에서 실제 11.5 릴리스까지의 차이를 반영하는 마지막 작업이다. |

오프라인 전용, 엔진 실행 의존 없음, 함수·필터 인덱스는 DDL로 이연, `migrate` 검증은 `--verify`로 선택한다는 결정을 그대로 평가 기준으로 삼았다. 이 결정들을 다시 문제로 제기하지 않았다.

## Must fix

### 1. [P1] 파일 생성이 충돌한 뒤 재실행하면 기존 파일을 삭제한다

- **역할:** 미완료 표지는 도구가 만든 파일만 기록해 다음 실행에서 정리한다.
- **문제:** 생성 전에 `marker.record(path)`를 호출하고, `create_new`가 `AlreadyExists`로 실패해도 기록이 남는다. 다음 `prepare()`는 그 경로를 그대로 삭제한다. 도착 `--log-dir`를 출발 로그 디렉터리로 지정하고 DB 이름을 유지하면 출발 `_lgat`도 이 경로에 들어간다. 별도 도착 등록 파일을 쓰면 이름 중복 검사로도 막히지 않는다.
- **근거:** [migrate.rs:451](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/cli/src/migrate.rs:451)의 로그 생성 순서, [new_log.rs:101](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/copy/src/new_log.rs:101)의 `create_new`, [incomplete_marker.rs:100](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/copy/src/incomplete_marker.rs:100)의 무조건 정리. LOB 복사와 새 spill arena도 같은 기록 순서를 쓴다.
- **재현:** 실제 `IncompleteMarker` 모듈과 운영 코드의 기록→생성 순서를 사용한 작은 실행에서 `AlreadyExists`, 재실행 전 파일 존재 `true`, 재실행 후 `false`를 확인했다. 실제 DB 파일은 사용하지 않았다.
- **수정:** 생성에 성공한 파일만 삭제 대상으로 확정하고, 출발 로그·LOB와 도착 경로의 중복도 시작 전에 거부한다. 생성 실패·강제 종료 뒤 재실행에서 기존 파일이 그대로 남는지 확인해야 한다.
- **방치 시:** 처음 실행은 기존 파일을 덮어쓰지 않고 실패하지만, 재시도가 그 파일을 지운다. 원본 보존 계약을 위반한다.

### 2. [P1] finalize는 지문을 읽은 직후 출발 DB 잠금을 놓는다

- **역할:** finalize는 출발이 바뀌지 않았고 서버가 사용 중이 아닐 때만 원본 파일을 지운다.
- **문제:** [finalize.rs:43](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/cli/src/finalize.rs:43)의 `current()` 안에서 연 `lgat`가 함수 반환 때 닫힌다. 그 뒤 LOB 검사와 [finalize.rs:219](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/cli/src/finalize.rs:219)의 삭제가 잠금 없이 진행된다.
- **근거:** [source_lock.rs](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/copy/src/source_lock.rs:1)는 열린 로그 핸들로 POSIX 잠금을 유지한다. migrate는 `OpenSource`를 끝까지 보유하지만 finalize는 그러지 않는다. 코드로 확인한 잠금 수명 결함이며 실제 서버 기동 경합은 재현하지 않았다.
- **수정:** `run()`이 로그 핸들을 보유한 상태에서 지문 대조부터 삭제·등록 해제까지 끝낸다. 그 사이 같은 로그의 다른 fd를 열고 닫아 POSIX 잠금을 풀지 않아야 한다.
- **방치 시:** 지문 검사 직후 출발 서버가 기동하면, finalize가 사용 중인 원본 볼륨·로그를 삭제할 수 있다.

### 3. [P1] 집합 비교의 정규화가 사용자 문자열 차이를 지운다

- **역할:** 엔진 unload 집합 비교는 도구와 검증기가 공유하는 코덱의 오류를 잡는 독립 기준이다.
- **문제:** [unload_normalize.rs:134](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/cli/src/unload_normalize.rs:134)는 schema 전체에서 문자열을 치환한다. LOB 정규화도 실제 LOB 토큰인지 구분하지 않고 `|file:<숫자>/ces_`를 지운다.
- **재현 A:** schema의 `DEFAULT 'national character'`와 `DEFAULT 'character'`는 기본값이 다르다. 현재 비교기는 출발 기본값의 문자열까지 치환해 `SAME`, 종료 0을 냈다.
- **재현 B:** 일반 VARCHAR 값 `'ordinary text |file:ces_1/a'`와 `'ordinary text |file:123/ces_1/a'`도 `SAME`, 종료 0을 냈다. 두 반례 모두 현재 `set_comparison`·`unload_files`·`unload_normalize` 모듈을 그대로 실행했다.
- **수정:** schema 치환을 SQL 구문 토큰으로 제한하고 문자열 리터럴·식별자 안은 보존한다. LOB 경로 정규화는 실제 `^E` LOB 값 토큰에만 적용한다.
- **방치 시:** 값이나 DEFAULT가 잘못 옮겨져도 최종 합격 기준이 통과한다. 기존 정상 fixture가 통과한 사실과 이 반례는 양립한다.

### 4. [P1] 같은 파일시스템의 별도 spill 경로는 도착 공간과 합산하지 않는다

- **역할:** plan은 도착 파일과 임시 파일이 함께 차지할 공간을 시작 전에 확인한다.
- **문제:** [temp_disk_choice.rs:30](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/cli/src/temp_disk_choice.rs:30)의 `room_for()`는 `spill.starts_with(target)`로 공간을 합산할지 정한다. 경로의 부모 관계는 파일시스템 동일 여부를 뜻하지 않는다.
- **구체적 조건:** 같은 FS의 `/data/target`과 `/data/spill`, 여유 10 GiB, 도착 필요 7 GiB, spill 7 GiB면 각 검사가 통과한다. 합계는 14 GiB다. `14079bf`의 spill 예약이 성공하면 남은 공간은 3 GiB여서 도착 쓰기는 끝나지 못한다. 실제 디스크를 채우는 실험은 하지 않았다.
- **수정:** 두 경로의 실제 장치 정보를 확인해 같은 FS에서는 필요량을 합산한다. 심볼릭 링크·마운트로 나뉜 경로도 같은 기준으로 계산한다. 도착 공간 예약은 #526의 남은 계약으로 함께 완료해야 한다.
- **방치 시:** 시작 전에 잡을 수 있는 공간 부족을 복사·재작성 도중에 만난다.

## Should fix

### 5. [P2] 표시한 최소 메모리로는 실행을 마칠 수 없다

- **역할:** #526의 최소값은 복사뿐 아니라 검증까지 실행 가능한 메모리여야 한다.
- **문제:** [resource_estimate.rs:132](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/cli/src/resource_estimate.rs:132)는 `workers × 256 KiB`만 최소값으로 낸다. 그러나 [live_row_map.rs:73](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/verify/src/live_row_map.rs:73)는 힙 페이지 수에 비례하는 메모리가 부족하면 spill 대신 오류를 낸다.
- **추가 근거:** [database.rs:44](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/source-latest/crates/verify/src/database.rs:44)는 헤더를 읽기 위해 `_lgat` 전체를 `fs::read`한다. 따라서 1 GiB 로그는 `--mem 64M`이어도 이 읽기 하나로 1 GiB 버퍼를 만든다. 워커 1개의 표시 최소값은 256 KiB다. 이번 리뷰에서 RSS를 새로 측정하지 않았다.
- **수정:** 로그는 필요한 헤더 범위만 읽는다. 최소 메모리에 live row map과 단계별 고정 버퍼를 반영하고, 실행 불가능한 조합은 도착을 쓰기 전에 거부한다. 추천값·기본값도 #526에서 요구한 `MemAvailable` 및 실제 RSS와 대조한다.
- **방치 시:** 사용자가 표의 최소 조합을 골라도 검증 단계에서 중단되거나, 한도보다 큰 메모리를 써서 OOM에 걸린다. #526은 아직 open이므로 완료된 작업의 누락으로 분류하지 않았다.

## Performance evidence

이번 리뷰는 측정을 다시 실행하지 않았다. 기존 [same.tsv](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/same.tsv), [u114.tsv](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/u114.tsv)의 계획된 회차 1~3을 집계했다. 뒤에 추가된 재측정 회차와 `--verify` 행은 섞지 않았다. 이 값은 해당 실행 바이너리의 결과이며, 새 자원 계산·arena 코드의 성능 증명은 아니다.

| 기존 큰 입력 측정 | 비교 기준 | fastmig | 해석 |
|---|---|---|---|
| develop→develop, copy 전체 | cp+sync 3.414 s | 16.325 s | 전체 migrate는 약 4.78배 오래 걸린다. |
| 같은 입력의 바이트 복사 단계만 | cp 1.562 s | volumes 0.676 s | 복사 단계는 약 2.31배 빠르다. 재빌드·patch·fsync는 제외한 값이다. |
| 11.4→develop, W=1 | CS unload/load 493.1 s | clone 109.370 s | 약 4.51배 빠르다. |
| 11.4→develop, W=4 | CS unload/load 184.7 s | clone 43.328 s | 약 4.26배 빠르다. 기준선은 깨끗한 회차 2개다. |
| 11.4→develop, W=16 | CS unload/load 148.9 s | clone 33.153 s / copy 32.522 s | 약 4.49배 / 4.58배 빠르다. |

기준선 조건과 방해받은 회차 제외는 [#484의 비교 기준선 댓글](https://github.com/xmilex-git/workspace/issues/484#issuecomment-6502508908)에 있다. fastmig 측정 스크립트는 같은 입력·CPU 집합을 지정한다. 현재 결과로는 “복사 단계가 cp보다 빠르다”는 말은 가능하지만, 지도의 “same-version 병렬 copy 모드가 cp보다 빠르다”를 전체 명령의 합격으로 적을 수 없다. #484에서 어느 실행 구간을 합격 기준으로 삼는지 기존 계약과 맞춰 명시해야 한다.

## Verification and remaining gates

이번에 직접 실행한 것은 DB를 사용하지 않는 작은 Rust 재현과 보관된 unload 파일의 비교다. 프로젝트 전체 빌드·엔진 기동·CTP·성능 측정은 하지 않았다.

| 확인 | 결과 | 범위 |
|---|---|---|
| 기존 파일 충돌 후 marker 재실행 | 기존 sentinel 파일 삭제 확인 | 실제 `IncompleteMarker`, 리뷰 전용 파일 |
| schema 기본값 차이·일반 문자열 차이 | 서로 다른 입력을 모두 SAME으로 판정 | 실제 비교 모듈, 반례 2개 |
| T1 11.4/develop × clean/dirty unload 재비교 | 네 경로 모두 SAME, 종료 0 | 보관된 엔진 unload + `14079bf` 비교 모듈. 마이그레이션 재실행 아님 |
| 기존 V1 TC 기록 | 30/30 PASS 보고와 일부 원로그 일치 | develop→develop, 엔진 `682b080b2`, 고정 바이너리 `a49c9b16f054` |
| finalize 잠금·공간 합산·메모리 계산 | 정적 결함 확인 | 서버 경합·quota·RSS 재현은 미실행 |

기존 `h920-11.4-*` e2e 기록의 set-comparison 종료 1은 당시 바이너리에 LOB 경로 정규화가 없던 결과였다. 이를 현재 실패로 다시 세지 않았다. 현재 모듈로 보관 unload를 비교하면 두 경로 모두 종료 0이다.

재현 명령과 원자료:

```sh
just --justfile /home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/review.just smoke
just --justfile /home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/review.just recompare
```

[probe.rs](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/probe.rs), [probe.log](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/issue472-review-20261030/probe.log), `recompare-*.log`에 입력·결과가 있다. 재현기는 버전 enum만 두 값으로 대체하고, 실행하는 marker·비교 모듈은 고정 스냅숏에서 그대로 가져온다. 정식 엔진 통합 게이트의 대체물이 아니다.

후속 작업은 다음 순서가 맞다.

1. 지적 1~3을 수정하고, 실패·재실행의 원본 보존과 문자열 차이의 DIFFER 판정을 확인한다. finalize는 삭제가 끝날 때까지 별도 프로세스의 로그 쓰기 잠금이 실패하는지 확인한다.
2. #526에서 지적 4~5, 도착 공간 예약, 11.4 사전 상한 추정을 완료한다. 작은 quota/제한된 FS와 kill-9 재실행에서 한도·정리·RSS를 확인한다.
3. #484는 고정된 한 바이너리로 T1 네 경로와 기존 30개 TC의 관련 경로를 다시 검증하고 측정 표를 닫는다. 유닛 테스트는 추가하지 않는다.
4. 지도에 이미 남은 vacuum data 비어 있지 않은 출발을 별도 fixture로 확인한다. 현재 샘플의 엔트리 0 통과만으로 이 경로를 승인하지 않는다.
5. 그 뒤 11.3→11.2→10.2 순서와 11.4 도착 후속을 진행하고, 실제 11.5 릴리스 대응은 #528에서 마무리한다.

**Verdict: fix 1-5 first.** 본 보고서는 코드 수정·커밋·이슈 댓글 게시·승인을 수행하지 않았다.

**Not checked:** 전체 코덱·B-tree 구현 전수, 동시 세션의 미커밋 변경, 새 엔진 빌드/CTP, 실제 서버 삭제 경합·디스크 고갈·RSS 게이트.
