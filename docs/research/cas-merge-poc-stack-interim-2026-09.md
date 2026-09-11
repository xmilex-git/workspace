# cas-merge PoC 중간 스택(닫힌 4건) — YCSB C×3·A×3 vs develop·cas-merge 기준 (2026-09-11)

workspace [#253](https://github.com/xmilex-git/workspace/issues/253) 중간 산출물. 사용자 지시: 지도 계속 여부 판단 입력으로 **성공한 PoC를 전부 합친 빌드**를 develop([#255](https://github.com/xmilex-git/workspace/issues/255))과 같은 형식으로 잰다. 열린 PoC 4건(N1 #247·메모리 #250/#251·P6 #252)은 미포함 — 최종 스택은 별도.

## 1. 대상·조건

| 항목 | 값 |
|---|---|
| 스택 브랜치 | `poc/stack` tip `ad795c5fc5b9f7c958cf7e47f3a8eb7d3ca54047` = cas-merge 기준 `d533969e4` + 6커밋 cherry-pick(충돌 0): t23 `a5f379a11`·`5c66cb080` → t23b `ea2c775eb` → u1 `69339c6f3` → u23 `a1aeecf83` → t1r7 `ad795c5fc` |
| 포함 후보 | [T2/T3+T2/T3-b #245/#254](https://github.com/xmilex-git/workspace/issues/254), [U1 #246](https://github.com/xmilex-git/workspace/issues/246), [U2/U3 #248](https://github.com/xmilex-git/workspace/issues/248), [T1/R7 #249](https://github.com/xmilex-git/workspace/issues/249) |
| 빌드 | fresh `release` preset(RelWithDebInfo), `CUBRID 11.5.0 (11.5.0.2841-ad795c5)`, 설치 `/home/cubrid/release/CUBRID-wf-poc-stack`, 워크트리 `~/dev/worktrees/wf-poc-stack`. `libcubrid.so.11.5` sha256 `499aba9e…3dbc34d`, `cub_server` `8d16c756…5707211`. 빌드 3m14s(warm ccache) |
| smoke | `smoke.sh smk` 14/14 PASS, `smoke_jdbc.sh smk 33000` SUCCESS(plain·SSL·read-only) |
| 측정 | #244 runbook 축자: 같은 호스트(podman 컨테이너, SMT OFF nproc 32)·하네스·JDBC 0076·golden DB copydb·conf 100(G2 체크포인트-조용)·threads 100·zipfian·20M ops. 유휴 게이트 **D10 loadavg1<10**(develop 캠페인과 동일; #244 cas-merge 기준은 <4) |
| A 교차 | runbook "A drifts day to day" 규칙대로 스택 A와 base A를 같은 세션에 교차(stack a1 → base a5 → stack a2 → base a6 → stack a3 → base a7) |
| 유효성 | 9레그 전부 checkpoints 0·nonzero_returns 0·smt_check 통과. 무효·대체 레그 없음 |

## 2. 레그 표 (p50/p99 = HDR µs, loadavg = 레그 직전 1분값)

| leg | cand | WL | ops/s | READ p50 | READ p99 | UPD p50 | UPD p99 | loadavg1 | 시작(KST) |
|---|---|---|---|---|---|---|---|---|---|
| c1 | stack | C | 203,566 | 453 | 1,255 | – | – | 5.26 | 18:52 |
| c2 | stack | C | 203,254 | 438 | 1,260 | – | – | 4.25 | 19:01 |
| c3 | stack | C | 208,444 | 432 | 1,193 | – | – | 3.41 | 19:09 |
| a1 | stack | A | 31,513 | 365 | 10,607 | 4,079 | 21,375 | 7.60 | 19:17 |
| a5 | base | A | 28,522 | 410 | 7,731 | 4,875 | 24,655 | 17.29¹ | 19:40 |
| a2 | stack | A | 31,185 | 265 | 6,019 | 4,655 | 23,199 | 4.83 | 19:54 |
| a6 | base | A | 28,453 | 352 | 6,079 | 5,239 | 25,311 | 5.99 | 20:07 |
| a3 | stack | A | 29,052 | 281 | 6,751 | 4,967 | 25,087 | 5.58 | 20:21 |
| a7 | base | A | 27,165 | 411 | 9,047 | 5,207 | 25,583 | 10.37¹ | 20:40 |

¹ 게이트는 <10에서 통과했고 copydb·기동 뒤 레그 직전 값이 올라간 경우(develop c1과 같은 유형). 20M 완료·오류 0·체크포인트 0으로 유효 처리, 삭제하지 않음.

## 3. median + raw MAD

| 대상 | ops/s median (MAD) | READ p50 / p99 | UPD p50 / p99 |
|---|---|---|---|
| **stack C** | **203,566** (312) | 438 / 1,255 | – |
| **stack A** | **31,185** (328) | 281 / 6,751 | 4,655 / 23,199 |
| base A (같은 세션 a5–a7) | 28,453 (69) | 410 / 7,731 | 5,207 / 25,311 |
| develop (#255) | C 93,883 (5,977) · A 27,726 (1,486) | C 980 / 2,569 · A 521 / 4,843 | A 5,207 / 24,959 |
| cas-merge 기준 (#244, 09-10) | C 118,374 (1,545) · A 31,423 (24) | C 750 / 2,299 · A 351 / 5,507 | A 4,687 / 22,927 |

## 4. 비율

| 비교 | ops/s | READ p50 | READ p99 | UPD p50 | UPD p99 |
|---|---|---|---|---|---|
| **stack C vs develop** | **×2.169 (+116.8 %)** | −55.3 % | −51.1 % | – | – |
| stack C vs cas-merge 기준 | ×1.720 (+72.0 %) | −41.6 % | −45.4 % | – | – |
| **stack A vs develop** | **+12.5 %** | −46.1 % | **+39.4 %** | −10.6 % | −7.1 % |
| stack A vs base A(같은 세션) | **+9.6 %** | −31.5 % | −12.7 % | −10.6 % | −8.3 % |
| base A(같은 세션) vs develop | +2.6 % | | | | |
| stack A vs 09-10 base median | −0.8 % | | | | |

## 5. 읽는 법·한계

- **C**: 개별 PoC 최대치 U1 단독 +32 %(156,669)를 훨씬 넘는 +72 %. 후보들이 서로 다른 심볼(락·memmove·malloc·mht_clear·classrepr)을 소거해 이득이 실제로 합산·증폭됐다. p50 438 µs, p99 1,255 µs로 지연도 절반 이하. develop 대비 2.17배.
- **A**: 같은 세션 base 대비 +9.6 %(MAD 밖), develop 대비 +12.5 %. 09-10 base median(31,423)과는 같은 대역 — A는 일간 드리프트가 후보 효과와 같은 크기이므로 **같은 세션 교차값만** 스택 효과로 인용한다. A는 로그 커밋·pgbuf victim 등 서버 선존 비용이 지배해 폴드 측 PoC로는 10 %대가 상한(설계 예상과 일치).
- **A READ p99는 여전히 develop보다 높다**(6,751 vs 4,843, +39 %). 같은 세션 base(7,731)보다는 12.7 % 낮아 스택이 악화시킨 것은 아니며, cas-merge 계열 공통의 tail 문제(a1의 10,607 outlier 포함). 귀속은 최종 스택의 G2 hold 절차로.
- 게이트 규약: develop·스택은 <10, cas-merge 기준(#244)은 <4. 스택 C 레그의 실제 시작값은 3.4~5.3으로 #244 대역과 겹친다.
- develop sha는 cas-merge 기준의 merge-base보다 17커밋 앞선다("두 빌드 간 비교").
- 이번 회차 생략(최종 스택으로 이월): perf hot-symbol 위상 diff, G5 메모리 `51_smaps_pss_leg.sh`, 후보별 처분표.

## 6. 원자료

`/home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf-poc/results/stack/{smoke,c1,c2,c3,a1,a2,a3}/`, `results/base/{a5,a6,a7}/`, `/home/cubrid/release/CUBRID-wf-poc-stack/WF_POC_BUILD_INFO.txt`.
