# PR #4394 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4394](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4394)
**제목:** [CBRD-27401] Add shell case for ALTER INDEX ... COMPACT on overflow OID chains
**작성자:** shparkcubrid
**HEAD SHA:** `757f19019` (base develop)
**JIRA:** CBRD-27401 (Improve Function/Performance, Resolved; 엔진 CUBRID/cubrid#7899, merge `0c310e25c`, 2026-09-29) / 연관: CBRD-24094 (오버플로 디렉터리 포맷), CBRD-27324
**TC PR:** 이 PR 자체 (엔진 머지 뒤의 후속 TC PR, shell 1건 `shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh`). 엔진 PR 의 봇 draft (cubrid-testcases#3460, private-ex#4106) 는 변경 없이 닫힘
**리뷰 일시:** 2026-10-12
**리뷰 결정:** #4394 Comment (인라인 5건 + 본문; 1, 2, 3, 6 제안/질문, 5 는 번호 NIT 만 게시)

> **TL;DR** (Non-blocking): 케이스는 맞고 결정적이다. 직전 빌드 NOK, 직후 빌드 OK x3, 최신 develop OK, 코어 0. 다만 페이지 수 검사가 "줄었다" 만 봐서 일부 키만 컴팩션하는 회귀를 놓치고, 개발자 테스트 리포트가 1순위로 꼽은 "스캔 중 COMPACT" 와 결정적으로 넣을 수 있는 권한, 경계값, 직후 kill -9 복구가 빠져 있다.

## Summary

- **변경 요약**: 4키 x 5,000행 인덱스에서 60% 삭제 + `vacuumdb` 후 COMPACT 를 실행해 페이지 감소, 키별 idx = heap 건수, 멱등성, FILL_FACTOR 문법, 유니크 no-op, 식별자 사용, DML 경합, `checkdb` 를 검사하는 shell 케이스 1건 추가
- **주요 이슈**: check 6 의 "감소" 판정이 데이터가 정하는 값 (36 -> 20) 보다 약함 / 스캔 경합 미포함
- **확인 필요 사항**: 동반 변경 (키 중간 스캔 재개) 을 검사하지 않는 이유, PR 본문 검증 내용

---

## Findings

### Non-blocking (should consider)

1. `cbrd_27401.sh:170` -- check 6 (와 check 5) 은 `[ "$ovf_after" -lt "$ovf_before" ]` 만 본다. `Num_ovf_page` (`SHOW INDEX CAPACITY` 의 오버플로 페이지 수, 디렉터리 페이지 포함) 는 데이터로 정해진다: 키당 5,000 OID = 데이터 8 + 디렉터리 1 페이지 -> 4 x 9 = 36, 컴팩션 뒤 2,000 OID / (680 x 0.9) = 4 + 1 -> 4 x 5 = 20. 직후 x3, 최신 develop 4번 모두 36 -> 20, 39 -> 23 으로 같았다. 지금 판정은 키 1개만 컴팩션해도 (36 -> 32) OK 다 -> 드라이버가 키를 건너뛰는 회귀를 못 잡는다. `[ "$ovf_before" -ge 32 ] && [ "$ovf_after" -le 20 ]` 로 바꾸면 positive control (검사 경로 도달 확인) 도 겸하고 AC1 ("이론값 +-5%") 에 맞는다. 헤더 29행 "~7 overflow pages" 는 실측상 8.
2. `cbrd_27401.sh:246-249` -- 경합 단계의 COMPACT 30회와 `wait $bg_pid` 에 `timeout` 이 없다. check 13 이 겨냥하는 래치 교착이 실제로 나면 케이스가 CTP 가 끊을 때까지 멈추고, 서버 정리 (`deletedb`) 도 안 된다. `timeout 300 csql ...` 와 제한 있는 대기로 감싸면 교착이 NOK 한 줄로 남는다.
3. 커버리지 -- 개발자 테스트 리포트 (`CBRD-27401_test_report.md` 6절) 와 AC 중 결정적으로 넣을 수 있는 항목이 케이스에도, 제외 사유로도 없다. 최신 develop 에서 프로브로 확인한 동작:
   - FILL_FACTOR 경계: `= 50` 허용 (현재 49/100/101 만), `= 4294967386` -> "FILL_FACTOR argument must be between 50 and 100." (이 PR 이 고친 int 절단 결함, 리포트 4절 #3), `= -1` / `= 90.5` -> Syntax error.
   - 권한: SELECT 만 가진 사용자 -> "INDEX authorization failure.", `grant index` 뒤 성공.
   - 복구: COMPACT 직후 `kill -9` -> 1초 뒤 자동 재기동, 키별 2000 idx = heap, `Num_ovf_page` 20 유지, `checkdb` rc=0 (AC4 의 결정적 부분, 리포트 6절 #9).
   - 파티션 (`ON t` / `ON ONLY t`, 엔진 PR 본문 72 -> 47) 은 미확인.
4. PR 본문 -- "답지는 develop 58b49b39f 빌드에서 CTP로 생성" 은 shell 케이스라 답지가 없고, 직전/직후/최신 결과와 빌드 종류가 없다. "대부분의 COMPACT는 no-op" 은 최신 develop 프로브에서 30회 모두 DML 세션이 살아 있는 동안 시작했고 23회가 1-5 페이지를 반납했다. 제외한 시나리오 (killtran 중단, 잠금 관찰, HA, 성능) 와 이유도 본문에 없다.
5. NIT: check 14 가 `write_ok/nok` 를 두 번 써서 `.result` 는 16줄인데 헤더 번호는 15까지다 (16번 NOK 를 헤더에서 찾을 수 없음). 헤더 블록은 `init test` 뒤 `:<<'END'` 48줄이다 (tc-author 형식: 맨 앞 `:<<'DESCRIPTION'`, 40줄 이하; 팀 공통 규칙이 아니라 게시하지 않음).

### Questions for the author

6. `cbrd_27401.sh:23-26` -- 헤더가 동반 변경 (`btree_ovf_scan_locate_resume`, 키 중간에서 멈춘 범위 스캔을 마지막 OID 기준으로 재개) 을 설명하지만, COMPACT 와 동시에 도는 SELECT 가 없어 이 변경의 목적 ("동시 스캔이 행을 잃지 않음") 은 검사되지 않는다. 개발자 리포트 3.1절, 6절 #1 이 최우선으로 꼽은 시나리오다. check 13 경합에 같은 키를 읽는 SELECT 세션 (리포트 1절의 한 문장 idx/heap 비교) 을 넣을지, 넣지 않는다면 본문에 제외 이유를 적을지.

## JIRA -> TC

AC 7개와 개발자 리포트 6절 권고 11개를 케이스에 대응시켰다.

| 항목 | TC 상태 | 판정 |
|---|---|---|
| AC1 `Num_ovf_page` 이론값 +-5% 감소, 디렉터리 엔트리 = 데이터 페이지 | check 6 (감소만), check 15 (`btree_ovf_dir_check` 가 엔트리 수 검사) | 부분 (1) |
| AC2 전후 count, `checkdb` btree / entries | check 2, 3, 7, 14, 15 (기본 `checkdb` = `CHECKDB_ALL_CHECK_EXCEPT_PREV_LINK`, entries 포함) | 충족 |
| AC3 동시 INSERT/DELETE/SELECT, 잠금 대기 없음 | check 13 (INSERT/DELETE 만) | 부분 (6) |
| AC4 kill -9 후 복구 | 없음 | 미충족 (3) |
| AC5 유니크, 1페이지 체인 no-op | check 11 (유니크, 오류 없음만) | 부분 |
| AC6/AC7 실행 시간, split 완화 | 시간 측정 (tc-author 규칙 23) | 제외 타당, 본문 미기재 (4) |
| 리포트 #1 스캔 중 COMPACT | 없음 | 미충족 (6) |
| 리포트 #2 DML 동시 | check 13-15 | 충족 |
| 리포트 #3 killtran 중단, #5 잠금 | 큰 체인 + 타이밍 의존 | 제외 타당, 본문 미기재 (4) |
| 리포트 #4 FILL_FACTOR 경계 | 49/95/100/101 | 부분 (3) |
| 리포트 #6 권한 | 없음 | 미충족 (3) |
| 리포트 #7 대상 오류 | 유니크만 | 부분 |
| 리포트 #8 파티션 | 없음 | 미충족 (3) |
| 리포트 #9 직후 비정상 종료 | 없음 | 미충족 (3) |
| 리포트 #10 HA, #11 REBUILD 대비 | ha_shell / 성능 | 제외 타당, 본문 미기재 (4) |

TC 파일 검토 (tc-author shell 규칙): `bash -n` 통과, CTP 전역 (`result_file`, `case_no` 등) 재할당 없음, 결과 줄은 매번 한 번에 기록, 시간 검사 없음, `finish` 가 마지막. check 10 은 두 문장의 범위 오류가 한 번의 파싱에서 둘 다 출력되어 (`pt_cat_error` 후 파싱 계속) `-eq 2` 가 성립한다 (실행 `'[' 2 -eq 2 ']'`). 판단 규칙: 페이지 수 관찰이 필요해 shell (R2), 배치는 Improve 이므로 `_40_guava` 로 맞다.

판정: 케이스 자체는 직후/최신에서 결정적으로 통과하고 직전에서 실패한다. 커버리지 부족 (1, 3, 6) 은 회귀 검출력 문제이며 머지를 막지는 않는다.

## Runtime Verification

로컬 컨테이너 CTP (`just ctp shell _40_guava/cbrd_27401`, `--testcases-as-is`, TC `757f19019`, gha-ci optdebug 아카이브, 6개 동시 실행):

| 지점 | 커밋 | 결과 |
|---|---|---|
| 직전 | `453da49c8` (`0c310e25c^`) | NOK -- 4-6, 8-11, 13 (`Syntax error: unexpected 'compact', expecting REBUILD`), CTP 재실행 1회 포함, 코어 0 |
| 직후 | `0c310e25c` | OK x3 (16/16), 코어 0, 매번 `Total pages 39 -> 23`, `Num_ovf_page 36 -> 20` |
| 최신 develop | `fd540db0c` | OK (16/16), 코어 0, 같은 값 |

- 프로브 (최신 develop, 커밋 안 함): 경합 COMPACT 30회 전부 DML 생존 중 시작, 23회가 페이지 반납 (`er_log_debug` 의 "overflow pages freed"), `dml_errors=0`. FILL_FACTOR, 권한, 복구 결과는 Finding 3.
- 케이스 실행 시간 173초 (6개 동시, 본문은 약 15초). 시간 검사는 없으므로 판정에 영향 없음.
- gha-ci: 실행 안 함 (TC 단독 PR, 사용자 결정 2026-10-12).
- 증거: `.git_ignored_dir/scratch/pr4394/runtime/results.md`.

## Existing Comments

swi0110 Approve (본문 없음, 2026-10-12). 미답 코멘트 없음.
