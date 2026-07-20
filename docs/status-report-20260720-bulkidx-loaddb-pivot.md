# Status Report — bulkidx loaddb 피벗 완결 (2026-07-20)

CBRD-27071 no-redo 병렬 인덱스 빌드의 스펙 축소 피벗(ADR-0006) 구현·검증·push·JIRA 갱신 완료.
이전 세션(grill 승인 + 수술 WIP, context 소진으로 중단)의 인계를 이어받아 완결한 기록이다.

## 결과물

| 항목 | 값 |
|---|---|
| 커밋 A | `587c8236e` — loaddb 한정 피벗 + 기계 삭제 (32파일 +221/−5,059) |
| 커밋 B | `88f74c4a2` — scoped barrier → 전역 flush 승격 (+37/−310, 단독 revert 가능) |
| push | xmilex `bulkidx/noredo-parallel-r304-wip` (7d0a58740..88f74c4a2) |
| merge-base 대비 최종 | 17파일 +4,211/−926 — 빌드 경로 + boot.h 매크로 1 + 서버 술어 + barrier 1종 + 복구 거부 + msgcat 2 |
| diff 0 확인 축 | client/wire/connection/locator/schema_manager/execute_schema/file_manager/log_2pc/vacuum/log_writer/system_parameter |
| JIRA | Summary → "Support no logging-per-page parallel index build", 본문 전면 교체, 첨부 3종 교체(analysis/verification/tc-bundle), 코멘트 4775284 |

## 인계 시점 대비 새로 해결한 것

1. **LOADDB_MARKER=0 미스터리 규명** — 코드 결함이 아니라 계측 사고 2중첩:
   - `cubrid diagdb -d 8` 정방향 전체 덤프가 중간 레코드에서 조용히 중단(rc=254, develop
     바이너리도 동일 지점 재현 = upstream 기존 결함). 계수는 역방향 덤프로 교정.
   - `just build`가 설치본 conf를 초기화 → `parallel_sort_page_threshold` 소실 → 소형 픽스처
     직렬 강등 → 발화 자체가 안 됨. 빌드 후 conf 재적용을 절차화.
2. **시점 복원(-d) 결함 수정** — 시간 기반 stop은 완결 레코드에서만 멈추므로 redo가 barrier를
   물리적으로 지나간다. 거부 기준을 "조우"에서 "**빌드 트랜잭션이 replay 창 안에서 완결**"로
   교정(analysis가 완결 트랜잭션을 테이블에서 제거하는 기존 불변식 사용). ADR-0006 §4 갱신.
3. **운영자 메시지 결함 수정** — `er_set(ER_GENERIC_ERROR)`가 포맷 인자를 버려 "Internal system
   failure"로 나오던 것을 fatal 포맷에 안내문+barrier LSA 직접 탑재로 교체(콘솔 실측 확인).
4. **compat loaddb 발화 확인** — `-u dba --no-user-specified-name`(구버전 이관 모드)도 정상 발화.

## 검증 (release, 최종 바이너리)

- 기능 표면: utility/compat loaddb 발화(barrier=빌드당 1, COPYPAGE=root 계열 소수), csql/SA
  비발화, 직렬 강등 시 barrier 0. 전부 PASS.
- 재기동: 빌드 중 kill -9(흔적 0·재시도 성공) / 완료 후 kill -9(barrier 무해 통과·인덱스 생존).
- 복원: full replay 거부(전용 메시지, barrier LSA 포함) / -d 시점복원 성공(인덱스 부재="문장
  미실행", 데이터 보존) / loaddb 이후 백업 full 복원 성공. checkdb 전부 0.
- 실패 주입(loaddb 재구성): 빌드 중 client kill -9 → 서버 트랜잭션 잔존 0·카탈로그 잔재 0·
  재시도 성공 / mid-sort 실패(temp_file_max_size_in_pages=16) → 즉시 깨끗한 오류(rc=3, 0초,
  hang 없음)·잔존 0·재시도 성공·checkdb 0.
- 빌드 게이트: release+debug green (커밋 A·B 각각).

## 성능 (20GB, 3.41억 행 flat key, loaddb 인덱스 로드 단계, cold 교대)

| 대상 | 유효 중앙값 | 배율 |
|---|---|---|
| develop | 669.2s (2회) | 1.00× |
| 커밋 A (scoped 관문) | 231.6s (3회) | 2.89× |
| 커밋 B (전역 관문) | **196.0s (3회)** | **3.41×** |

**B가 A보다 15% 빠름 → B 유지 확정, revert 불요.** (probe 순회 없이 flusher가 병렬로 미는
구조가 유리. 증거: `bkx-review-response/evidence/perf-20g-pivot/measurements.tsv`)

## TC (JIRA 첨부 tc-bundle 전면 교체, 전 스크립트 실행 완료)

loaddb 주도 v2: `tc-loaddb-basic.sh`(발화 P1 + 비발화 N1 csql/N2 SA), `tc-crash-restart.sh`
(C1 빌드 중 kill / C2 완료 후 kill), `tc-replay-barrier.sh`(R3 사후백업 복원 → R1 full replay
거부 → R2 시점복원 — 시점복원의 resetlog가 체인을 절단하므로 반드시 마지막). 오라클은 역방향
덤프 계수(lib-oracle.sh). 함정 2건 README 명문화: threshold 오버라이드 필수(아니면 직렬 강등
상태로 무의미 PASS), 정방향 전체 덤프 금지.

## 문서

- ADR-0006 §4 완결 기준 갱신, ADR-0003/0004/0005 superseded 표기.
- `docs/review-response-bulkidx-decisions.md` ADR-0006 이행 절 추가(전 항목 체크).

## 미결/후속

- diagdb 로그 덤프 중도사(upstream, develop서도 재현)는 이 브랜치 범위 밖 — 별도 이슈 후보.
- PR 7487(page_buffer waiter_exists) develop 머지 시 rebase로 3-hunk 자연 소멸 예정.
- 정식 TC 레포(cubrid-testcases-private-ex) 등재는 QA 단계 워크플로우로 이월.
