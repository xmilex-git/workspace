# 주 캐시 레짐은 WARM으로 고정하고, cold는 I/O 진단 트랙으로 강등한다

CUBRID 데이터 볼륨은 46GB(`tpch_sf10_v2_x001` 35G + `x002` 10G + generic 256M, 로그 8.9G 제외)이고
PG 적재분은 같은 SF10에서 25GB 안팎이 될 전망이다. 이 장비의 available은 ~91Gi라 **한쪽만 warm이면
여유롭게 들어가지만 양쪽이 동시에 완전히 상주하지는 못한다**. 즉 레짐을 고정하지 않으면 AB/BA
교차 배치 자체가 캐시 축을 흔든다.

cold를 주 레짐으로 두는 선택지는 이 환경에서 정의부터 성립하지 않는다. 서버 재시작은 **DB 버퍼만**
비우고 OS page cache는 그대로 남기므로, 결과는 cold도 warm도 아닌 "DB 버퍼 cold + OS 캐시 warm"이라는
이름 없는 혼합 상태가 된다. 진짜 cold를 만들려면 page cache까지 버려야 하고 그것은 sudo 경유
`drop_caches`를 요구한다. 반면 warm은 warmup 스트림 한 번으로 재현 가능하고, 비용은 스트림 1회다.

이 프로젝트의 판정 축은 단일 세션이 확보하는 병렬성이다. 스토리지 대역이 지배하는 구간에서는 양쪽
엔진의 병렬 실행 차이가 I/O 대기에 묻히므로, **주 레짐을 warm으로 두는 것이 판정 축과도 맞는다.**

## Decision

### 주 레짐: WARM

- **각 측정 세트 시작 전에 warmup 스트림을 1회 돌린다.** warmup 스트림은 집계에 포함하지 않으며,
  그 뒤의 런만 집계 대상이다.
- **AB/BA 엔진 전환 직후에는 warmup을 재수행한다.** 상대 엔진의 런이 page cache를 밀어낼 수 있다
  (CUBRID 46GB + PG ~25GB > available ~91Gi의 여유 폭). 전환 후 첫 스트림을 그대로 집계하면
  그 쌍만 캐시 상태가 다른 값이 된다.
- warmup 스트림도 측정 스트림과 같은 쿼리 집합·같은 DOP·같은 바인딩으로 돈다. 다른 조건의 warmup은
  warm 상태를 만들지 못한다.

### WARM 검증은 측정 계약의 일부다

warmup을 "돌렸다"는 사실이 아니라 **물리 read가 실제로 사라졌다는 채증**이 통과 조건이다.

- 채증 수단: 측정 런 구간의 **`/proc/<서버 pid>/io`의 `read_bytes` 델타**(= 스토리지에서 실제로 올라온
  바이트)를 1차 근거로 쓰고, 같은 구간의 `iostat -x` sda1 `kB_read` 델타를 교차 확인으로 쓴다.
  CUBRID는 서버 프로세스, PG는 백엔드 + 병렬 워커의 델타를 합산한다.
- 판정: 델타가 **잠정 기준 — 그 런이 읽은 논리 데이터량의 1% 미만이면서 절대값 100MiB 미만** 이면
  warm으로 인정한다. 두 수치는 G1의 실측 분포를 보고 확정하며, 그때 이 ADR을 개정한다.
- **검증에 실패한 런은 무효다.** 값을 보정하거나 "warm에 가까움"으로 표에 올리지 않고, 폐기 후
  warmup부터 다시 시작한다. 무효 런의 발생 횟수와 사유는 보고서에 남긴다.
- 보조 근거(선택): PG `EXPLAIN (ANALYZE, BUFFERS)`의 `shared read`, CUBRID `statdump`의 data page
  fetch/ioread. 엔진 내부 카운터는 OS 레벨 채증을 대체하지 않고 보강만 한다.

### cold는 I/O 진단 트랙 전용

cold는 주 축이 아니다. **스토리지 경로가 결과를 지배하는지 확인해야 할 때만** 여는 별도 트랙이며,
warm 결과와 같은 표에 합치지 않는다(`CONTEXT.md`의 Query Stream 정의: 다른 캐시 레짐의 스트림은
같은 표에 합치지 않는다).

절차:

1. 서버 재시작으로 DB 버퍼를 비운다(CUBRID는 `cubrid-server-ctl.sh` 래퍼 경유, PG는 `pg_ctl`).
2. OS page cache를 버린다 — 사용자가 세팅한 NOPASSWD 스크립트
   `sudo /home/cubrid/bin/drop_caches.sh` (내용: `sync` 후 `echo 3 > /proc/sys/vm/drop_caches`).
   컨테이너 안에서 `/proc/sys/vm/drop_caches` 쓰기가 막혀 있으면 **호스트에서 실행**한다.
3. 측정 런의 물리 read 카운터로 **진짜 cold였는지 검증한다.** warm 판정과 같은 카운터를 반대 방향으로
   읽어, read_bytes 델타가 그 런의 논리 읽기량 규모로 관측되어야 한다. 관측되지 않으면 캐시가 남은
   것이므로 그 런은 무효다.
4. cold 런은 항상 자기 트랙의 표에만 올리고, 레짐 표기(`cold`)를 Comparison Snapshot에 적는다.

서버 재시작만 하고 page cache를 남긴 상태는 **cold가 아니다.** 그 상태의 수치는 어느 표에도 올리지
않는다.

## Consequences

- 모든 측정 세트의 비용에 warmup 스트림 1회가 상수로 붙고, AB/BA 전환마다 한 번 더 붙는다. G1의
  interleaved 3회는 그만큼 길어진다.
- 하네스는 런 경계에서 `read_bytes`/`iostat` 스냅샷을 찍고 델타를 런 레코드에 함께 저장해야 한다.
  timeout 상태 기록과 마찬가지로 **하네스 필수 요구사항**이다. 카운터 없이 나온 런은 warm 여부를
  사후에 증명할 수 없으므로 집계에 쓰지 않는다.
- Comparison Snapshot에 캐시 레짐(`warm`/`cold`)과 warm 검증 결과(카운터 델타)를 기록한다. 레짐
  필드가 빈 측정치는 표에 올리지 않는다.
- 1% / 100MiB 문턱은 잠정값이다. G1에서 실제 델타 분포를 보고 확정하며, 문턱을 바꾸면 그 전에 warm으로
  인정한 런을 새 문턱으로 재판정한다.
- 남은 실측 1건: **컨테이너 안에서 `sudo /home/cubrid/bin/drop_caches.sh`가 실제로 동작하는지**.
  `/proc`는 rw로 마운트돼 있지만 `/proc/sys/vm/drop_caches`는 비-root로 읽히지 않아 컨테이너 정책까지는
  확인되지 않았다. cold 트랙을 여는 시점에 1회 실측하고 실패하면 호스트 실행으로 전환한다.
  drop_caches는 장비 전체의 page cache를 버리므로 다른 작업과 겹치지 않는 시점에 실행한다.
- cold를 주 레짐으로 되돌리려면 이 ADR을 supersede한다. warm 트랙과 cold 트랙의 수치를 한 표에 합치는
  것은 어느 경우에도 유효하지 않다.
