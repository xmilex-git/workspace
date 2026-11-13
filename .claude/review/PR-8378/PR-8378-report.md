# PR #8378 코드 리뷰 보고서 (재리뷰)

**PR:** [CUBRID/cubrid#8378](https://github.com/CUBRID/cubrid/pull/8378)
**제목:** [CBRD-27847] Store a string value that exactly matches the column without casting it
**작성자:** soheejung-cs
**HEAD SHA:** `c45aac991` (develop `e98bdd885` 머지; 이전 리뷰 `f3bac6bdc`, merge-base `226352283`)
**JIRA:** CBRD-27847 (Improve Function/Performance) / 연관: CBRD-27583(#8213, 원인 변경)
**TC PR:** CUBRID/cubrid-testcases#4007 (ready, `c3c88d5ab`, xmilex-git 리뷰 요청) / CUBRID/cubrid-testcases-private-ex#4710 (빈 draft)
**리뷰 일시:** 2026-11-06 (1차 2026-11-05)
**리뷰 결정:** 엔진 추가 게시 없음(11-05 Approve 5779594721 유지, reviewDecision APPROVED). TC #4007 Approve(본문 없음). TLA+ 관찰 2건은 게시하지 않음. private-ex #4710 리뷰 없음(변경 0)

> **TL;DR** (Non-blocking): 새 head는 develop 머지 한 번뿐이다. 두 커밋의 패치는 `git range-diff`로 1차 리뷰 때와 같다(`=`). 새 head에서 optdebug CI(sql 17,747 / medium / shell)가 전부 통과했다. TLA+ 모델은 지름길 판정이 모든 입력 조합에서 캐스트와 같은 값과 같은 오류를 내는지, 빌린 버퍼가 레코드를 만들 때까지 사는지 검증했다. 계측 빌드에서 TC를 실행한 trace도 모델과 맞았다. TC #4007은 공유 경로를 167번 실제로 태운다.

## Summary

- **변경 요약**: `heap_attrinfo_can_share_string ()` (CHAR, VARCHAR, BIT, BIT VARYING 공유 판정)이 참이면 `heap_attrinfo_set_converted ()`가 값을 캐스트 없이 `setval (copy=false)`로 빌려 넣는다.
- **1차 리뷰 이후 바뀐 것**: develop 머지(`c45aac991`). 이 경로에 닿는 develop 커밋은 없다. CBRD-27464(#8026)는 `locator_sr.c`의 FK 경로만 바꾸고 `heap_attrinfo_set` 대입 값은 NULL뿐이며, `heap_attrinfo_set_converted ()`의 호출자 7곳은 그대로다.
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음 (Codex 스레드 4463663921에는 작성자가 11-05에 답을 달았다. 재평가는 꺼져 있어 도달할 수 없다고 했고, gdb로 진입 0회를 확인했다)

---

## Findings

없음

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 문자열 열 1개당 행당 명령 수가 머지 전 수준(약 1,130)으로 돌아옴 | 본문 측정: 기울기 1,738 -> 824 (develop 1802aa581 대비, release, instructions:u). TLA+ C4: 정확히 맞는 값은 모두 공유된다 | 충족 |
| 정밀도 초과, 코드셋이나 콜레이션이 다른 값의 오류와 결과가 develop과 같음 | TC #4007 Case 4, 5, 6 (CI optdebug ok). TLA+ C1, C3: 모든 입력 조합에서 공유 결과 = 캐스트 결과 | 충족 |
| Implementation: 지름길을 정확히 맞는 문자열과 BIT까지 넓힘 | `heap_attrinfo_can_share_string`. guard마다 TLA+ mutant가 위반을 잡는다 | 충족 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| INSERT, UPDATE, MERGE, ODKU, REPLACE에서 같은 도메인 값 저장 | #4007 Case 1-3. 계측 빌드 trace에서 공유 대입 167건 | 통과 |
| 캐스트를 유지하는 값(정밀도, 콜레이션, 코드셋, 짧은 CHAR, 기본값, 호스트 변수) | Case 4. trace에서 캐스트 경로 294건 (오류 5건 포함) | 통과 |
| 열보다 긴 값은 오류 | Case 5. -427 5건, trace에서도 er=1 5건 | 통과 |
| pad 문자가 공백이 아닌 CHAR (euckr, binary) | Case 6. trace에서 꽉 찬 euckr/binary CHAR 공유 확인 | 통과 |

- #4007: 바뀐 케이스(`cbrd_27847.sql`)에 답안이 있다. 헤더 주석에 `;`가 없다. 본문의 실행 주장(release 91465a14a와 develop 1802aa581에서 OK)은 CI(optdebug, `c45aac991` + tc `c3c88d5ab`, case ok 188 ms)와 어긋나지 않는다. 본문의 "단위 suite"는 엔진 PR 본문이 말하는 작성자의 판정 함수 계약 suite를 가리킨다.
- develop과 PR의 출력이 같은 것은 성능 변경이라 의도된 것이다. 이 TC가 공유 경로를 실제로 타는지는 아래 trace가 보여 준다.
- private-ex #4710: 바뀐 파일 0개. 리뷰 대상이 아니다.

## TLA+ Verification

```
TLA+ 검증: 통과 - .claude/review/PR-8378/tla/str-share/
- 속성: C1 equivalence(공유 값의 레코드 바이트와 도메인 = 캐스트 결과) TLC 통과 TLAPS 요청 없음 (PR 본문 TO-BE, 함수 주석, JIRA 기대 결과 2)
        C2 safety(빌린 버퍼가 레코드 생성까지 산다) TLC 통과 (함수 주석, Codex 스레드와 작성자 답)
        C3 equivalence(공유 경로의 오류 = 캐스트의 오류) TLC 통과 (PR 본문, JIRA 기대 결과 2)
        C4 safety(정확히 맞고 길이가 맞고 소유하지 않는 값은 공유) TLC 통과 (PR 본문 TO-BE, JIRA 기대 결과 1)
- 결함: 없음
- mutant: 12개 모두 위반 검출 (develop=merge-base는 C4, 첫 커밋 규칙 "CHAR 아무 길이"는 C1) / 살아남은 mutant: 없음
- 경계: MaxPrec 3, 열 정밀도 {2,3}, 값 정밀도 0..4, 길이 0..4, 2열 x 2행; scale MaxPrec 4, 3열; IndInv 귀납성은 Apalache(열과 행 수 전 범위, MaxPrec 3 고정)
- trace validation: 수용 1건(TC cbrd_27847, 이벤트 600개), 거부 2건(sh 뒤집기 76번, er 뒤집기 554번)
- 반례: 재평가를 켠 cfg에서만 Codex 경로(witness-reev-page)가 나온다. 코드는 재평가를 끈다(pt_to_update_xasl, pt_to_delete_xasl)
- RESULT: OK (str-share-20261106-113209-3713579)
```

- `DB_NEED_CLEAR` guard (`need_clear`, 값이 자기 버퍼를 가지는지)는 재평가를 켠 모델에서만 mutant가 위반을 낸다. 재평가가 꺼진 지금은 소유 값을 쥔 쪽이 모두 레코드 생성 뒤에 값을 놓는다. 그래서 이 guard는 재평가 경로를 막고, develop처럼 소유 값을 복사하게 남겨 두는 역할이다. 함수 주석과 같다.
- 코드셋 비교는 콜레이션이 다른 코드셋에 속한 값이 들어올 때만 결과를 바꾼다. 비교 한 번이라 지적하지 않는다.

## Runtime Verification

- gha-ci run 42006007241: head `c45aac991`, optdebug("debug" 슬롯), tc `tc/pr-8378` `c3c88d5ab`. sql verdict pass (total 17,747), `sql/_36_guava/cbrd_27847` ok, medium pass, shell pass. 빌드 debug/release 모두 pass.
- 계측 빌드: `~/optdebug/CUBRID-pr8378-tla` (optdebug, `c45aac991` + 리뷰 전용 TLATRACE 패치, libcubrid `3466009e56aa3388`, libcubridsa `1fc1a4a83c6ff2db`). SA 모드로 TC 케이스를 그대로 실행했다(csql rc=0, ERROR 5건은 Case 5의 기대 오류). 이벤트 600개(Assign 461, Build 139).
- 1차 리뷰의 근거: gha-ci 41631057774 (`f3bac6bdc`). 1차 보고서는 `.git_ignored_dir/scratch/pr8378/PR-8378-report.1105.md`에 있다.
