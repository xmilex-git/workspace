# ADR-0006: no-redo 빌드를 CS loaddb로 한정하고, marker를 replay 차단벽으로 격하한다

날짜: 2026-07-20. 상태: 승인(보스, grilling 세션). 대체: ADR-0003(identity 기계 전체),
ADR-0004(잔여부), ADR-0005(복원 안내 정책). 유지: ADR-0001, ADR-0002(빌드 경로 원리).

## 맥락

리뷰 대응을 거치며 일반 CREATE INDEX/ALTER 표면에서 no-redo를 지원하기 위한 기계(서버 발급
create LSA identity, pending 등록부, 발행 결합 marker, 복구의 suppression/청소 walk/repair,
클라이언트 deferral/descriptor 배선)가 비대해졌고, 복원 후 불완전 인덱스가 남는 경로(운영자
안내 의존)는 기술지원 실수 시 장애 표면이 된다. 이 규모의 스펙은 머지 불가 판정.

## 결정

1. **적용 표면을 CS 모드 loaddb로 한정한다.** unloaddb 산출물의 표준 플로우(CREATE TABLE →
   데이터 로드 → ALTER로 PK/인덱스 생성)에서 인덱스 생성 단계만 no-redo 병렬 빌드를 탄다.
   일반 CREATE INDEX/ALTER(csql, 응용)는 기존 전체-로깅으로 동작한다.
2. **활성 판정은 전부 서버측이다.** sbtree_load_index에서
   `BOOT_IS_LOADDB_CLIENT_TYPE (logtb_find_client_type (tran_index))`(LOADDB_UTILITY +
   ADMIN_LOADDB_COMPAT_UNDER_11_2/11_4 — compat 모드는 구버전 unload 파일 이관용으로 이름
   해석만 다름) && `index_status != OR_ONLINE_INDEX_BUILDING_IN_PROGRESS`로 계산한다.
   UNIQUE/PK 포함. SA 모드는 SERVER_MODE 게이트로 구조적 배제. loaddb 옵션 신설 없음
   (비상 우회 = SA 모드 loaddb). 클라이언트는 아무것도 모른다 — wire·클라이언트 코드 불변.
3. **marker는 payload 없는 replay 차단벽 레코드다.** 빌드가 no-redo로 완주하면 커밋 전
   durability flush 관문 직후 서버가 단독 발급한다. 발행(publication)과의 결합, identity,
   pending 등록부, 커밋/2PC 가드는 모두 삭제한다.
4. **미디어 복구는 차단벽을 넘지 않는다.** restoredb 계열의 redo가 이 레코드를 만나면 전용
   에러(영/한 메시지)로 즉시 실패한다: "이 백업 체인은 loaddb의 no-redo 인덱스 빌드 구간을
   포함하여 재생 복원할 수 없습니다. loaddb 이후 백업을 사용하거나 시점 복원으로 그 이전까지만
   복원하십시오." 재기동(crash recovery)은 차단하지 않는다(커밋 전 flush 관문으로 페이지가
   이미 디스크에 있어 무해 통과). 시점 복원(-d, 백업 자체 복원)은 차단벽 이전까지 정상 동작.
   결과: 불완전 인덱스가 존재하는 DB 상태는 어떤 경로로도 생성 불가.
5. **커밋 전 flush 관문은 전역 flush로 단순화한다**(별도 커밋, 성능 회귀 시 단독 revert).
   loaddb 한정 세계에서는 동시 트래픽 부재가 전제라 파일 범위 한정(scoped) 관문의 존재
   이유가 사라진다. 빌드 중 워커 unfix-후 flush는 유지(말미 flush 폭풍 방지).
6. **운영 계약**: loaddb 수행 후 전체 백업 필수(기존 표준 지침과 동일). rollback/크래시된
   빌드의 차단벽도 로그에 남아 보수적으로 거부될 수 있다(안전 방향, 동일 지침으로 해소).

## 기각한 대안

- 일반 DDL 표면 유지 + 자동 정리/안내(기존 ADR-0003~0005 체계): 머지 불가 규모 + 안내 의존
  리스크. 본 결정으로 대체.
- marker 직전까지 부분 복원 후 정상 종료: 잘린 시점을 성공처럼 보이게 함 — 기각.
- 커밋 시점 barrier 발급: 상태기계 잔존 대비 이득 미미 — 기각(빌드 시점 발급, false-positive
  거부는 수용).
- 헤더 플래그로 차단: 디스크 포맷 변경 유발 — 기각(로그 레코드가 최소형).

## 결과

잔존 diff ≈ 빌드 경로(btree_load/external_sort: 병렬+강등+워커 flush+전역 관문, 데드락·고아
파일·retire·ovf 픽스 포함) + boot.h 매크로 1개 + 서버 술어 몇 줄 + barrier 레코드 1종 +
복구 거부 수십 줄 + msgcat 2건. 클라이언트·wire·connection·locator·schema_manager·
execute_schema·file_manager·log_2pc·page_buffer diff 0. HA/2PC/혼합버전 제약은 "loaddb
한정"이라는 표면 정의로 흡수된다.
