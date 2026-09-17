# PR #7866 / CircleCI 155362 — cbrd_24906_1/2 실패 원인과 처리 방안

## 결론

실패 2건(`sql/_13_issues/_23_1h/cases/cbrd_24906_1.sql`, `cbrd_24906_2.sql`)은 모두 test case 16의
`show trace`에서 hash join PROBE 아래 `(parallel workers: …)` 한 줄이 빠진 것이다. `count(*)` 값은 같다.

원인은 PR #7866이 의도한 효과 그 자체다. 튜플 포맷이 작아져 hash join **probe 입력 리스트의 페이지 수가
2 → 1**로 떨어졌고, 병렬 probe 결정은 페이지 수 기반(`hjoin_try_parallel_probe` →
`compute_parallel_degree(HASH_JOIN, probe->list_id->page_cnt, …)`)이라 임계값(2페이지) 아래로 내려가
직렬 probe가 됐다. 엔진 결함이 아니며, **`tc/pr-7866`의 answer 두 파일에서 해당 줄 4개를 제거**하는
것이 맞는 처리다.

## 증거

- CI: [job 155362](https://app.circleci.com/pipelines/github/CUBRID/cubrid/37313/workflows/d2b69ccb-35ab-45ae-a92c-8372b8057d95/jobs/155362)
  엔진 `bf3d0a727`(develop `ba88e4700` 머지 포함), TC `63adc64d`. 17,464건 중 2건 실패, shard 2.
  diff는 4곳(answer 1번 파일 541·591행, 2번 파일 607·661행) 모두 `(parallel workers: ?, …)` 한 줄 삭제.
- 같은 TC ref로 돈 다른 PR CI는 통과: job 155365(pull/7881), 155377(pull/6853). → PR #7866 고유.
- 이전 PR CI(155077 `30d57a1a0`, 155231 `6ab2bc614`)는 통과. 그 헤드에는 비용모델 PR #7622(2026-09-11 머지)가
  없어 case 16이 NESTED LOOPS였고, TC도 #3206(hash join + 병렬 PROBE 기대행 추가) 이전이었다. `bf3d0a727`
  develop 머지로 #7622가 들어오며 hash join 계획이 됐고, TC 머지로 병렬 기대행이 들어오면서 드러났다.
- 격리 재현(podman, `cubridci:test_rl8.10`, csql CS 모드, 동료 세션 `pr7866-sync-20260915-63`이 빌드한
  install-pr/install-develop 복사본, `.git_ignored_dir/scratch/ci155362/case16/`):

  | 빌드 | tbl_a 행수 | `test_mode` | case 16 PROBE |
  |---|---:|---|---|
  | develop `ba88e470` | 1000 | yes | `parallel workers: 2` |
  | PR `bf3d0a72` | 1000 | yes | 직렬 (CI와 동일) |
  | PR `bf3d0a72` | 2000 | yes | `parallel workers: 2` |

  동료 세션의 최소 재현이 양쪽 다 직렬이었던 것은 실행 당시 conf에 `test_mode=yes`가 없었기 때문이다
  (conf 수정 시각 13:17, 실행 13:12). CI sql conf는 `test_mode=yes`다.

## 메커니즘

- `system_parameter.c` `test_mode=yes`이면 `parallel_hash_join_page_threshold` 기본값 2048 → 0으로 바꾸고,
  `compute_parallel_degree`가 `MAX(threshold, 2)`로 최소 2페이지를 요구한다. `num_pages / threshold`의 MSB로
  degree를 정하므로 2~3페이지면 2, 1페이지면 0(직렬).
- probe 리스트 = 안쪽 hash join(a ⟕ b, b는 0행)의 출력 1000행. 구 포맷은 값마다 8B 헤더(+8B 정렬 값)라
  2컬럼이면 24B/행 → 24KB → 2페이지. 새 포맷(ADR 0016)은 4B 헤더 + 널비트맵 + 자연정렬 값이라 같은 행이
  12~16B → 1페이지. 트레이스의 temp SCAN `fetch`도 develop 8 / PR 4로 절반이다.
- PR은 optimizer·`px_parallel.cpp`·`query_dump.c`·`system_parameter.c`를 건드리지 않았다. 계획(HASH JOIN 2단)은
  양쪽 동일하다.

## 처리 방안

**D1. TC answer 수정(권장).** `tc/pr-7866`에서 `cbrd_24906_1.answer` 541·591행, `cbrd_24906_2.answer`
607·661행의 `(parallel workers: ?, time: ?..?, readrows: ?..?, readkeys: ?..?, rows: ?..?)` 줄을 삭제한다.
PR이 트레이스 출력을 바꾼 다른 14개 파일과 같은 처리이고, 동료 세션의 `ctp-out-pr` `.result`가 그대로
기대 결과다. 근거: 이 TC(CBRD-24906)의 목적은 항상-거짓 WHERE의 재작성 확인이며 병렬 여부는 부수 출력이다.

**엔진 변경은 하지 않는다.** 페이지 임계값을 행 기준으로 바꾸거나 포맷 압축률만큼 보정하는 것은 이 PR 범위
밖이고, 병렬 결정 로직 소유자와 별도 논의할 사안이다.

**TC 자체를 병렬 비의존으로 만드는 안(비권장).** `NO_PARALLEL_HASH_JOIN` 힌트를 넣으면 rewritten query 문구가
바뀌어 answer 전체가 흔들리고, 행 수를 늘리면 비용모델로 다른 case의 계획이 바뀔 수 있다. 실패가 17k 중
2건뿐이라 이득이 없다.

## 2차 검토: "빼지 말고 probe 입력을 2페이지 넘게 채우자"는 제안

전제 확인: 이 TC의 병렬 PROBE 기대행은 병렬 probe PR #7068(2026-05)이 넣은 것이 **아니다**. 비용모델 TC PR
#3206(2026-09-11)이 case 16 계획을 NL → HASH JOIN으로 재기준하면서 딸려 들어왔고, 작성자도 PR 본문에
"`parallel_hash_join_page_threshold=1`로 CI 환경을 맞춰 생성"했다고 적었다. 병렬 PROBE를 직접 검증하는 answer는
공개 TC에 따로 있고(`cbrd_23749`, `cbrd_25519`, `join_orderby_skip`) 이번 CI에서 모두 통과했다.

그래도 answer를 develop과 동일하게 유지하고 싶다면, 두 방식을 실측했다(격리 컨테이너, `test_mode=yes`):

| 변형 | develop | PR | 부작용 |
|---|---|---|---|
| 세 테이블 모두 4000행 | 병렬 | 병렬, 정규화 출력 develop과 **완전 동일** | case 6·7 결과 `TRUE`→`FALSE`, case 12 NL→hash, case 19·20 GROUPBY `hash: partial` + 병렬 — 다른 5개 case의 의도가 흔들려 **기각** |
| case 16만 `count(*)` → `count(*), sum(a.col_a), sum(a.col_b), sum(a.col_c)` | 병렬 3 (probe 리스트 4페이지) | 병렬 2 (2페이지) | 다른 case 무영향. 숫자는 `?`로 가려져 answer 동일. 단 PR 쪽이 임계값 2페이지에 정확히 걸려 있어(24B/행 → 24KB) 튜플이 4B 더 줄면 다시 직렬로 떨어지는 얇은 여유 |

`parallel_hash_join_page_threshold`는 `PRM_FOR_SERVER | PRM_HIDDEN`이라 세션에서 바꿀 수 없고, cubrid.conf로만
가능해 TC 안에서 임계값을 고정하는 길은 없다.

**D2. 최종 권고.** answer 4줄 삭제(D1)가 여전히 최소 변경이다. 병렬 기대행을 유지하려면 case 16만 sum 3개를
붙이는 변형(`cbrd_24906_1.sql`, `cbrd_24906_2.sql` 둘 다, 2번 파일은 prepare 문자열 안)을 쓰되, answer의 case 16
결과 블록(컬럼 헤더·sum 값)을 새로 뜨고, 위 얇은 여유를 TC 주석으로 남긴다.

## 후속 논의거리 (PR 설명에 한 줄 언급 권장)

`parallel_scan/hash_join/sort_page_threshold`는 모두 페이지 수 기준(기본 2048)이다. 임시 리스트 튜플이
절반 안팎으로 작아졌으므로 같은 행 수에서 병렬 hash join·sort가 켜지는 지점이 대략 2배 행 수로 밀린다.
probe·sort 비용은 행 단위라 기본값 재조정을 검토할 여지가 있으나, 이 PR에서 바꾸지는 않는다.
