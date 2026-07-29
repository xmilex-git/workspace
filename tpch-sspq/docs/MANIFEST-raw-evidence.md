# raw evidence manifest

원칙 v2 §8(ADR 0020) — **기존 결과는 삭제하지 않는다.** 이 파일이 raw 산출물의 단일 목록이며,
세트별 파일 해시는 각 run 디렉터리의 `meta.json`(`artifacts[].sha256_16`)에 있다.

프로젝트 루트: `/home/cubrid/dev/workspace/tpch-sspq`
raw 루트: `<root>/.git_ignored_dir/` (git 밖)

## 트랙별 산출물

| 트랙 | 경로 | contract_revision | connection_mode | metadata | 상태 |
|---|---|---|---|---|---|
| `PER_QUERY_CONNECTION_DIAG` (구 `G2`) | `.git_ignored_dir/g2-stream/raw/` (`g2-times.tsv` 220행, `blocks/`, `plans/`, `plans2/`, `cubplan/`, `summary.json`) | 1 | per-query-connection (**재명명 근거**: `scratch/run-g2.sh`가 쿼리마다 클라이언트를 새로 띄운다) | 없음 (rev 1) | 보존, 재분류만 |
| Q1 파일럿·A~D·프로파일 | `.git_ignored_dir/g1-abcd/`, `.git_ignored_dir/g1-prof/`, `.git_ignored_dir/g1-dop/`, `.git_ignored_dir/g1-assets/` | 1 | 혼합 (미기록) | 없음 (rev 1) | 보존 |
| Q21 | `.git_ignored_dir/q21/raw/` (`s1/`, `s1-times.tsv`, `s1b-cpu.tsv`, `s2/`, `pgcpu/`, `prof/`) | 1 | 미기록 | 없음 (rev 1) | 보존 |
| Q9 | `.git_ignored_dir/q9/raw/` | 1 | 미기록 | 없음 (rev 1) | 보존 |
| Q8 | `.git_ignored_dir/q8/raw/` (`final/`이 정본 세트) | 1 | 미기록 | 없음 (rev 1) | 보존 |
| Q18 | `.git_ignored_dir/q18/raw/` (`s1/`, `s2/`, `s3/`, `cpu/`, `cpu2/`, `thr/`, `prof/`) | 1 | 미기록 | 없음 (rev 1) | 보존 |
| Q15 | `.git_ignored_dir/q15/raw/` (`s1/`, `s2/`, `cpu/`, `cte/`, `thr/`, `prof/`) | 1 | 미기록 | 없음 (rev 1) | 보존 |
| **Q3** | `.git_ignored_dir/q3/raw/` (`s1/`, `s2/`, `s2b/`, `final/`, `pair/`, `cpu/`, `cpu2/`, `cpu3/`, `thr/`, `prof/`) | **2** | wall 세트 `per-query-connection` / CPU·프로파일 세트 `single-connection-n-statements` | **10개 `meta.json`** | 현행 |

## 백업

| 대상 | 백업 위치 | 크기 | sha256 (앞 24자) |
|---|---|---|---|
| Q3 raw + scratch 전체 | `.git_ignored_dir/backup/q3-raw-20260729.tar.gz` | 1,822,917 B | `f5b4f7d9874f062a720156b9` |

* 백업은 `/tmp`를 쓰지 않으며 `tpch-sspq/` 밖으로 나가지 않는다(계약).
* rev 1 트랙의 백업 tar는 아직 없다 — **다음 라운드의 선행 작업으로 등재**한다.

## 무효 run (삭제 금지, 무효 사유 기록)

| 세트 | run | 사유 |
|---|---|---|
| `q3/raw/final` | 블록 6 전체 (`*-B6`, `*-w6`) | 배경 부하 loadavg 9.9 → **33.15**(다른 세션 `bun /home/cubrid/.bun/bin/gjc`, affinity 0-31) |
| `q3/raw/s2` | `pg-nl-R1` | WARM 실패 — 구간 sda read **1,551.5 MiB** (문턱 100 MiB) |
| `q3/raw/s2` | `pg-nl-warmup` | WARM 실패 — sda 4,936.2 MiB (warmup이므로 애초에 미집계) |
| `q3/raw/s2b` | `cubH-B2` | 배경 부하로 10.339 s (같은 세트 중위 6.76 s) |
| `q3/raw/s2b` | `wall2.tsv` 반복 1~3 | 배경 부하 + `cubH` sda 83~110 MiB |

## 재검증 대상 (Q3에서 발견한 채증 함정)

`perf record -a -C`(perf 4.18)가 **레코드 시작 전 존재하던 sibling 스레드**의 심볼을 해석하지 못한다
(Q3 보고서 §3.1). CUBRID는 `parallel-query` 워커를 풀로 재사용하므로 영향을 받는다.

| 대상 | 확인 방법 | 상태 |
|---|---|---|
| `q21/raw/prof`, `q9/raw/prof`, `q8/raw/prof`, `q18/raw/prof`, `q15/raw/prof`의 CUBRID `.symbols` | `[unknown]` 비율 확인 → 5 % 초과면 `q3/scratch/resolve.py`로 재해석 | **미확인** |
| Q8·Q18의 `-a -C` idle 감산 기반 PG 귀속 | `perf stat -p <postmaster>` + 새 psql 세션으로 재검증(CONTEXT.md) | **미확인** (Q15에서 등재된 항목) |
