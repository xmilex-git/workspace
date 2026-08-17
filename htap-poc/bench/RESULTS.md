# #61 안전 스모크 측정 결과 — logging overhead · extraction throughput · RMT amplification

티켓: [#61](https://github.com/xmilex-git/workspace/issues/61) · 측정일 2026-08-17 ·
근거: [#50](https://github.com/xmilex-git/workspace/issues/50) 결정(안전 확인 ①·②·⑥만, 상대 비교로 충분)

## 측정 환경

- 단일 노드 (rootless podman 스택 `htap-poc/infra/`: Kafka 3.8.1 KRaft · Debezium Connect 3.0.0 · ClickHouse 24.8), Linux 6.9.4, 공유 개발 서버(전용 아님 — 절대 수치가 아니라 상대 비교 목적)
- CUBRID 11.5.0, **#47 엔진 패치 빌드** (`56afad65a`, 설치본 `~/htap-cdc/CUBRID-11.5-htapcdc-prv`, 2026-08-17 14:57 빌드), DB `htapdb`, 기본 `cubrid.conf` + `supplemental_log` 토글
- 커넥터: `debezium-connector-cubrid` fork `ae5f38f`(#60 포함), 소스만 측정 대상 토픽 구독(②는 sink 미관여), ⑥은 공식 ClickHouse sink 경유
- 워크로드 생성기: `gen_workload.py`(seed 고정 — off/on 동일 SQL 재사용) · 러너 `run_write_bench.sh` · 단일 csql 클라이언트
- 재현: 아래 각 절의 절차. 워크로드 파일은 scratch 생성물(커밋 안 함), 생성기는 이 디렉토리에 커밋

## ① supplemental logging overhead — **bulk +2.4%, single-row +0.5%** (한 자릿수)

같은 SQL 파일을 `supplemental_log=0/1`로 서버 재시작만 바꿔 실행. 각 구성 warmup 1회 + 본측정 3회, 중앙값. CDC 클라이언트 미접속(순수 로깅 비용).

| 페이즈 | 내용 | off 중앙값 | on 중앙값 | overhead |
|---|---|---|---|---|
| bulk | 2,000 txn × 100행 multi-row INSERT + 2,000 txn × 100행 UPDATE (40만 row-ops) | 12.108 s | 12.405 s | **+2.45 %** |
| single | 10,000 txn × 단일행 INSERT/UPDATE 교대 (커밋 지연 성향) | 4.912 s | 4.934 s | **+0.45 %** |

- on 기준 처리율: bulk ≈ 32.2k row-ops/s, single ≈ 2.0k txn/s (단일 클라이언트).
- run 간 편차 < 1 %. pre-#47 엔진(08-15 빌드)에서도 같은 프로토콜로 +3.1 %/+0.7 % — 패치 전후 동급.
- **완료 조건 판정: 두 자릿수 % 아님 → 후속 결정 티켓 불요.**

## ② extraction throughput — **정상 상태 ~26–28k events/s, 지속 부하 3k events/s에서 lag ≤ ~1.2 s**

- **스냅샷(보너스)**: 205,000행 t_bench JDBC export 2.824 s ≈ **72.6k rows/s** (Kafka publish는 별도 수 초).
- **버스트 catch-up**: 200,000 update 이벤트를 3.25 s에 기록(쓰기측 61.5k events/s). 토픽 end-offset 2 s 샘플링 결과 커넥터가 **~26–28k events/s** 정상 상태로 드레인, 쓰기 종료 8.3 s 후 완전 catch-up (burst 시작 기준 t=11.6 s).
- **지속 keep-up**: 3,000 events/s × 60 s 페이싱 부하에서 최대 lag **3,644 events(≈1.2 s분)**, 쓰기 종료 2 s 내 드레인 — 상한(26k/s) 아래 지속 부하는 안정적으로 따라간다.
- 판정: 단일 태스크 extraction 상한이 이 스택의 단일 클라이언트 쓰기 상한(~60k events/s 버스트)보다 낮지만, 버스트는 유한 lag로 흡수되고 지속 부하 기준으론 여유가 크다.

## ⑥ RMT physical amplification (best-effort) — **hot-key 갱신은 물리 팽창이 사실상 없음**

update-heavy 극단(5개 PK에 20,000 UPDATE, 4,000 txn) 실측:

| 단계 | 행 수 | 디스크 |
|---|---|---|
| CDC 이벤트 (토픽) | 20,005 | — |
| sink가 CH에 실제 insert한 raw 행 (part_log NewPart 누적) | **279** (= poll batch 57 × 배치당 유니크 키 ~5) | 37.7 KB 누적 |
| RMT 자동 머지 후 active | 10 | 1.3 KB |
| `OPTIMIZE FINAL` 후 | 5 | 0.7 KB |

- 공식 ClickHouse sink가 **poll batch 내 same-key 이벤트를 최종본으로 collapse**(RMT 의미론상 안전 — 최종 `_version`만 유효)해 이벤트 수 대비 1.4 %만 물리 기록됐고, RMT 머지가 나머지를 즉시 수렴시켰다.
- 최종 상태는 CUBRID와 정확 일치(qty 4012/4079/4001/4001/4004), 종료 후 `diff-check.sh` **0 mismatch**.
- 한계: hot-key 극단 워크로드다. 키가 넓게 분산된 update는 batch collapse 이득이 없어 raw 행 ≈ 이벤트 수(머지 전)로 팽창한다 — 디스크 상한은 머지 케이던스에 좌우되며, 이 측정은 "갱신 폭주가 무한 팽창으로 이어지지 않는다"는 안전 확인까지만 말한다.

## 측정 중 발견 (별도 후속)

**cubrid_log 클라이언트-서버 버전 skew → native SIGSEGV.** #47 패치가 CDC API 구조체 레이아웃을 바꿨는데(`CUBRID_LOG_ITEM`에 `rec_lsa` 추가 등, `cubrid_log.h` diff 확인), 프로토콜/ABI 버전 검증이 없어 구버전 서버↔신버전 클라이언트(또는 그 역) 조합이 명시적 에러가 아니라 **`or_unpack_int` SIGSEGV로 Connect 워커 JVM 전체를 죽인다** (이 세션에서 2회 실증 — 워커 native crash는 JNA 격리 결정 #57의 직접 증거). 기술지원 관점에서 "서버와 커넥터 번들 lib 버전 불일치 = 프로세스 사망"은 매뉴얼 제약 절 + 엔진 하드닝 후보. → 신규 티켓으로 재단.
