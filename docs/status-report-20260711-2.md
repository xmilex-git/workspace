# Bulk Index Build 현황 보고 #2 (2026-07-11 저녁)

## 잘 돌고 있나 — 예
- 원격(.30) 방금 감사: CUBRID 프로세스 0, 잔존 임시 DB 0, /tmp 소켓 디렉토리 정리됨, 포트 free.
- 디스크 /home 47%(여유 1.9T), /data 11%(여유 9.8T), 메모리 가용 135G. 캠페인 점유 ~3G.
- 유일한 의도적 잔존물: WT의 R2-02 미커밋 diff(진행 중), 설치본 백업 `.pre-unify`(안전용).

## 오늘의 하이라이트: 첫 제품 커밋 landed
**`da822ce38` "[bulkidx] R2-01: migrate vacuum notification append to main thread"** → xmilex/bulkidx/noredo-parallel push 완료.
전 게이트를 실측 증거로 통과: debug+release 빌드 green / CCI_XA 부재 / commit·rollback·재시도·kill-중간·abort-중간(FI) / **결정적 parity 4-leg 정확 동수(1,000,000 notify 레코드, develop=후보)** / 64MiB 상한 경계± / v0 골든 PASS / 봉인·정리 완료.

### 그 과정에서 잡아낸 진짜 버그·함정 (전부 해소)
1. **제품 버그(신규 코드)**: 에러 시 `log_sysop_abort` 생략 → partial abort에서 서버 assert. 플래그 순서 재배치로 수정, FI로 재검증.
2. AF_UNIX 소켓 경로 108B 초과(긴 설치 경로) → 짧은 소켓 루트 도입.
3. `cubrid statdump`가 이 환경에서 전량 0 → **이전에 봉인된 oracle 측정치가 정크였음을 적발**, 유계 레코드-카운트 방식으로 정정.
4. parity 측정의 vacuum 경주 비결정성 → vacuum 지연 conf로 결정화(2회 반복 정확 동수 입증).
5. 설치본 이중화·databases.txt 미등록·pkill 자기참조 등 인프라 함정 다수.

## 진행 상황
| 항목 | 상태 |
|---|---|
| R0 증명 + R1 하네스/oracle + 승인체계(receipt 003, amendment 015) | ✅ |
| **R2-01** (vacuum 이관, 첫 제품 커밋) | ✅ push 완료 |
| **R2-02** (WAL/DWB policy 배선, W1 마지막 inert 슬라이스) | 🔄 구현+양모드 빌드 green. 런타임 게이트(v0 골든·parity·flush-error FI) 남음 — 게이트 전 커밋 금지 원칙대로 정지 상태, 곧 재개 |
| W2~ (R3 직렬 no-redo 5커밋 → R4 병렬 4커밋 → V1/V3/V2) | 대기 |

## 지시 반영
- **릴리즈 모드 기반 검증**: 접수. 이후 무거운 검증(v0 골든, parity, V1 matrix, V2 성능)은 release 바이너리로 수행. 예외는 성격상 debug 전용인 것만(FI 프레임워크·assert 검출 — CUBRID FI는 debug 빌드에만 존재). 운영 규칙으로 명문화한다.
- **stale 관리**: 매 단계 종료 시 프로세스/포트/temp DB 정리를 게이트에 포함해 운용 중(방금 감사 결과 깨끗).

## 사람 판단이 필요한 부분 (현재 1건, 급하지 않음)
- **W2 진입 전 closure 옵션 확정**: ALTER의 다중 flush를 단일 FORCE로 통합하는 범위 확장. (a) flush-deferral 통합(권고, 설계 완료 — 4파일·전부 기존 승인 파일 내, FEASIBLE 판정) vs (b) hierarchy/partition/FK를 bulk 비적격으로 직렬 우회(범위 축소). **기본값 (a)로 진행 예정** — 이의 있으면 알려달라. 그 외에는 사람 개입 불요; R3-04 activation 직전에 critic/architect 재심사가 한 번 더 있다.
- (참고) upstream PR/이슈 공개 여부는 캠페인 완료 후 다시 물을 것.

## 다음 액션 (자동 진행)
R2-02 런타임 게이트(release 기반) → 커밋+push → W2: R3-03(비활성 codec) → R3-01∥R3-02 → R3-04 activation(재심사 게이트) → R4 → V1/V3 → V2 성능 측정(최종 수치 보고).
