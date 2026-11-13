# PR #4597 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4597](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4597)
**제목:** [CUBRIDQA-1136] Fix the timing-dependent verdicts of check_option, temp_enc_06 and oper03, and move cbrd_21506_backupdb to _25_unstable
**작성자:** tw-kang
**HEAD SHA:** `ffbf729f8` (develop merge-base `a4e12efc7`, develop tip `edc9b1fd3`)
**JIRA:** CUBRIDQA-1136 / 연관: CBRD-27635 (Develop, cbrd_21506_backupdb 의 restrack_assert core)
**TC PR:** TC-only PR (엔진 PR 없음)
**리뷰 일시:** 2026-10-28
**리뷰 결정:** Approve (2026-10-28 게시, review 5679453202, commit ffbf729f8). grill 은 사용자 지시로 생략

> **TL;DR** (Non-blocking): 세 케이스의 수정이 보고한 원인을 엔진 소스 기준으로 정확히 막는다. 판정식은 그대로이고, 실패 조건을 일부러 만든 A/B(temp_enc_06, check_option)도 PR 에 있다. 머지를 막을 결함은 없다.

## Summary

- **변경 요약**: temp_enc_06 은 에러 로그 파일 전체를 읽고, oper03 은 잘못된 LSA 를 `lsa1 + 2^48`(같은 페이지 offset+1)로 만들고, check_option 은 csql 이 schema lock 을 쥔 동안 unloaddb 11개를 띄운다. cbrd_21506_backupdb 는 CBRD-27635 수정 전까지 `_25_unstable` 로 옮긴다.
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음 (QA 회신의 "CBRD 등록 부탁"은 이미 있는 CBRD-27635 로 충족)

---

## Findings

없음

검토했으나 남기지 않은 것:
- check_option: lock 확인용 `cubrid lockdb`(관리 도구 client) 의 마지막 연결을 서버가 아직 반환하지 않은 상태에서 11번째 unloaddb 가 접속하면 실패가 2건이 될 수 있다. 서버는 소켓 종료를 본 뒤 `css_free_conn` 에서 슬롯을 돌려주므로 창은 있지만, 재현 근거가 없어 지적하지 않는다(P15).
- temp_enc_06: 새 glob `${db_name}_[0-9]*.err` 가 이전 실행의 로그를 함께 읽을 위험은 없다. CTP 가 케이스마다 `resetCUBRID_linux` 에서 `$CUBRID/log` 의 파일을 모두 지운다.

## 정적 검증 (엔진 develop `2d925cb86`)

| 케이스 | PR 의 주장 | 소스 근거 | 판정 |
|---|---|---|---|
| check_option | 관리 도구 client 는 일반 `max_clients` 슬롯을 먼저 쓰고, 없으면 예약 1개를 쓴다 | `connection_globals.c` `css_get_admin_client_max_conn` = 1, `CR_NORMAL_FIRST` (`connection_sr.c` `css_increment_num_conn_internal`) | 맞음 |
| check_option | 접속한 unloaddb 는 tbl_a lock 에서 멈춘다 | `unloaddb.c` 316-318: `unload_lock_timeout` 기본 -1(무한) 뒤 `locator_get_all_mops`. `--process=i/N` 은 클래스별이 아니라 heap 페이지를 나누므로 11개 모두 tbl_a 를 읽는다 | 맞음 |
| check_option | 슬롯 9(일반) + 1(예약) = 10, 11개 중 1건 실패 | 위 두 줄 | 맞음 |
| oper03 | LSA 하위 48비트 pageid, 상위 16비트 offset | `log_lsa.hpp` `pageid:48`, `offset:16`; `cubrid_log.c` memcpy; `test.c` `atoll` | 맞음 |
| oper03 | offset+1 은 레코드 시작점이 될 수 없다 | `log_prior_lsa_append_align` 8바이트 정렬; `cdc_validate_lsa` 는 페이지 안 레코드 시작점 체인과 `LSA_EQ` 만 본다 | 맞음 |
| temp_enc_06 | 두 번의 서버 시작이 분이 바뀌면 다른 `.err` 파일에 쓴다 | #4427 의 file_enc_05/07 과 같은 수정(같은 glob) | 맞음 |
| cbrd_21506_backupdb | CBRD-27635 가 같은 core 를 다룬다 | CBRD-27635 본문: 이 케이스, `resource_tracker.hpp:455`, 상태 Develop | 맞음 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| check_option 44번: 실패 1건, 덤프 30000행 미만 | PR 본문: 5/5 OK, unloaddb 1초 간격 강제 판 develop NOK 2/2 -> PR OK 2/2 | 충족 |
| temp_enc_06 1번: TDE 줄 2개 | PR 본문: 5/5 OK, 두 번째 시작을 다음 분으로 미룬 판 develop NOK 2/2 -> PR OK 2/2 | 충족 |
| oper03 3번: API 오류 1줄 | PR 본문: 5/5 OK. 강제 판은 없음, 위 소스 근거로 결정적 | 충족 |
| cbrd_21506_backupdb 격리 | readme 사유 줄, 파일 rename 100% | 충족 |

- answer 파일 변경 없음(판정식 그대로). 헤더 주석 `;` 없음. 이동 케이스는 디렉터리 밖 파일을 참조하지 않는다(`$init_path/init.sh` 만).
- PR 본문의 주장(실패 횟수, 검사 번호, 소스 위치)은 위 표와 일치한다.
- 판정: Approve 가능.

## Runtime Verification

- 이번 리뷰에서 새로 돌린 실행 없음. 근거는 PR 본문의 pod 실행(develop `2d925cb868` debug, CTP `47026a17a3`, `shell_ci.conf`)과 위 정적 검증.
- gha-ci 증거 없음: fork lane dispatch 가 HTTP 422 로 막혔다고 PR 이 적고 있다.
