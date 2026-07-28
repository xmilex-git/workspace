# PostgreSQL의 DSM 백엔드를 `mmap`으로 바꾼다 (기본값 `posix` 이탈)

G2(q1~q22 완주) 첫 워밍업 스트림에서 PostgreSQL이 **Q5·Q8·Q10에서 결정론적으로
실패**했다.

```
ERROR:  could not resize shared memory segment "/PostgreSQL.4293141524"
        to 16777216 bytes: No space left on device
```

원인은 호스트 `/dev/shm` 크기다. 측정으로 확정했다.

| 사실 | 값 |
|---|---|
| `/dev/shm` 마운트 | `shm on /dev/shm type tmpfs (rw,nosuid,nodev,noexec,relatime,**size=64000k**)` |
| Q5 단독 실행 중 피크 사용량 | **48,412 KB** / 총 64,000 KB |
| 실패 요청 | 세그먼트를 16,777,216 B로 확장 → 47 MB + 16 MB > 62.5 MB |
| 재현성 | Q5 단독 2/2회 동일 실패 |
| 실행 계정 | uid **340001**, `/dev/shm` 확장 권한 없음 |
| 실패 쿼리의 공통점 | Parallel Hash 노드 수 최다군 — Q5=6, Q8=8, Q10=4 (EXPLAIN 채증) |

## Decision

`postgresql.conf`에 **`dynamic_shared_memory_type = mmap`** 을 추가하고 재기동한다.
**PostgreSQL 기본값 `posix`에서 의도적으로 이탈하는 것이다.** CUBRID는 무변경.

| 항목 | 값 |
|---|---|
| 적용 파일 | `~/pg/pgdata-tpch-sspq/postgresql.conf` (원본 백업: `.git_ignored_dir/g2-stream/raw/postgresql.conf.before-mmap`) |
| 컨텍스트 | `postmaster` — 세션 GUC로 불가하므로 conf 수정 + 재기동이 유일한 경로 |
| 채증 | `pg_settings` → `dynamic_shared_memory_type | mmap | postmaster`; `$PGDATA/pg_dynshmem/`에 세그먼트 생성 확인 |
| 재기동 | `taskset -c 0-15 pg_ctl restart` — node0 핀 유지 |
| 효과 | Q5 **6.508 s**, Q8 **2.040 s**, Q10 **3.446 s** 로 3개 전부 정상 실행 |

### 왜 다른 선택지가 아닌가

| 대안 | 기각 사유 |
|---|---|
| `/dev/shm` 확장 | uid 340001에 마운트 변경 권한이 없다. 또한 컨테이너 공용 자원이라 다른 작업에 영향을 준다 |
| `sysv` | 커널 `shmmax`/`shmall`에 의존하므로 천장을 옮기는 것일 뿐 또 다른 한계에 걸릴 수 있다 |
| `work_mem` / `hash_mem_multiplier` 축소 (세션 GUC 가능) | DSM 수요는 줄지만 **플랜과 배치 수가 바뀐다** — 측정 조건 변경 |
| `enable_parallel_hash=off` (세션 GUC 가능) | Parallel Hash를 없애 DSM을 회피하지만 **플랜 패밀리를 바꾼다** |
| 19쿼리로 축소 | 지시가 q1~q22 완주다. 3쿼리 누락은 Pareto를 왜곡한다 |

## 편향 방향 — 예상과 실측이 다르다 (실측대로 기록한다)

PostgreSQL 문서는 `mmap`이 느릴 수 있다고 적고 있으므로 **이 이탈이 PG에 불리하게
작용해 CUBRID/PG 배수를 축소(보수적)시킬 것**이라는 예상이 있었다.
**측정 결과는 그 반대다.**

전환 직후, 다른 작업을 하기 전에 Q1을 단위 파리티 트랙(양쪽 6 실행 단위)으로 WARM 규칙
그대로 3회 재측정했다. **CUBRID를 무변경 대조군으로 같이 돌렸다.**

| | posix 기준선 | mmap 측정 | 델타 | 판정 근거 |
|---|---|---|---|---|
| PostgreSQL Q1 wall | 10.442 s (within-set sd 0.008) | **10.296 s** (sd 0.057) | **−0.146 s (−1.40 %)** | posix sd의 18.2배 |
| **CUBRID Q1 wall (대조군, 무변경)** | 31.842 s (sd 0.093) | **31.612 s** (sd 0.215) | **−0.230 s (−0.72 %)** | 자기 sd의 2.5배 |
| 배수 | **3.049x** | **3.070x** | +0.021 (+0.7 %) | |

읽는 법:

* **PG는 느려지지 않고 1.40 % 빨라졌다.** 따라서 이 이탈은 배수를 축소하지 않고
  오히려 **3.049x → 3.070x로 소폭 확대**한다. "보수적 방향"이라는 예상은
  **성립하지 않았다** — 이 문서는 예상이 아니라 실측을 채택한다.
* 다만 **아무것도 바꾸지 않은 CUBRID 대조군이 같은 방향으로 −0.72 % 움직였다.**
  즉 두 세션 사이에 그 정도의 세션 간 드리프트가 실재한다. PG의 −1.40 % 중
  mmap에 귀속할 수 있는 몫은 **최대 약 0.7 %p**다.
* ADR 0010이 정한 대로 **런 내 sd(0.008 s)를 세션 간 비교의 유의성 문턱으로 쓰지
  않는다.** 18.2배라는 수치는 그 오용의 예시일 뿐이고, 정직한 척도는 대조군이 보여준
  드리프트다.

**결론(판정)**: 델타는 작고, 배수에 미치는 영향(+0.7 %)이 무변경 대조군이 보인
드리프트와 같은 크기다. 따라서 **posix 값과 mmap 값을 같은 축에서 읽어도 된다**고
판정한다. 단 Q1 기준선은 앞으로의 모든 PG 측정이 mmap에서 나오므로 **mmap 값으로
갱신한다**.

### 갱신된 Q1 기준선 (단위 파리티 트랙)

| | CUBRID | PostgreSQL | 배수 |
|---|---|---|---|
| ~~posix (구)~~ | ~~31.842 s (sd 0.093)~~ | ~~10.442 s (sd 0.008)~~ | ~~3.049x~~ |
| **mmap (현)** | **31.612 s (sd 0.215)** | **10.296 s (sd 0.057)** | **3.070x** |

## 모든 PG 표에 붙일 각주 (의무)

> PostgreSQL 수치는 `dynamic_shared_memory_type=mmap` 구성에서 측정됐다(기본값
> `posix`에서 이탈). 전환 비용을 Q1으로 실측한 결과 PG가 1.40 % **빨라졌고**,
> 같은 세션쌍에서 무변경 CUBRID 대조군이 −0.72 % 드리프트했으므로 mmap 귀속분은
> 최대 약 0.7 %p이며 배수에 미치는 영향은 3.049x → 3.070x다. posix에서 측정된 값과
> mmap에서 측정된 값은 표에 명시적으로 구분 표기한다.

## 대외 인용 단서 — 세 번째 항목

이 프로젝트 수치에 붙는 단서가 이제 **3개**다.

1. **PostgreSQL은 개발 스냅샷 핀**(`5713b437`, `20devel`) — 릴리스 PostgreSQL 성능이
   아니다. (ADR 0002)
2. **CUBRID는 `update_statistics_update_histogram=yes`** — 기본 설정 CUBRID가 아니다.
   (ADR 0008)
3. **PostgreSQL은 `dynamic_shared_memory_type=mmap`** — 기본 설정 PostgreSQL이 아니다.
   호스트 `/dev/shm`이 64 MB로 고정돼 있고 확장 권한이 없어 Parallel Hash 쿼리가
   기본값에서 실행되지 않았기 때문이다. (이 ADR)

즉 이 프로젝트의 수치는 **어느 엔진에 대해서도 "출시 기본 설정 제품의 성능"이 아니다.**

## Consequences

* PG의 모든 Gather가 DSM 경로를 바꾸므로 **posix에서 측정된 기존 PG 수치는 표에서
  `posix`로 표시**하고 mmap 수치와 섞지 않는다. G2 이전의 PG 수치(파일럿, 자연 구성
  트랙, A~D 카운터, 5·6단계 프로파일)는 전부 posix에서 측정됐다.
* `$PGDATA/pg_dynshmem/`에 파일이 쌓이므로 디스크가 /home(1.4 T 여유)으로 옮겨간다.
  `/dev/shm` 64 MB 제약은 사라진다.
* CUBRID에는 대응하는 변경이 없다 — CUBRID는 DSM을 쓰지 않고 단일 프로세스 내
  스레드로 병렬을 구현한다(5단계에서 확인: `parallel-query` 스레드 6개, 같은 tgid).

## Status

Accepted (2026-07-28). 적용·채증 완료. 편향 방향은 **예상(보수적)과 반대로 측정됐고
실측을 채택했다.**
