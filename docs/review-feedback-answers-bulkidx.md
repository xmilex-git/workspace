# bulkidx 리뷰 피드백 답변 (develop...bulkidx/noredo-parallel-r304-wip)

기준: merge-base 39bdc0a77, tip 86d581d4f. 질문 순서대로 append.

## 1. system parameter를 이용한 구현 — 저 파라미터의 역할은?

브랜치가 추가한 파라미터는 2개다.

- `bulk_build_worker_flush` (btree_load.c:2571): no-redo 빌드에서 워커가 leaf 페이지를 unfix한 직후
  그 페이지를 flush 큐에 태울지 여부. 커밋 전 durability 관문의 부하를 빌드 진행 중에 분산시키는
  스위치.
- `bulk_build_scoped_barrier` (btree_load.c:1608): 커밋 전 durability 관문을 "그 인덱스 파일이
  차지한 페이지/볼륨 범위 한정 flush+sync"로 할지(on), 전역 flush로 할지(off) 선택하는 스위치.

둘 다 캠페인 중 A/B 검증용 kill-switch였다(4조합 매트릭스로 양쪽 모두 정합 검증 완료). 기능
정체성과 무관하므로 **지시대로 전부 제거하고 무조건 on 동작으로 고정한다** — no-redo 빌드는
항상 워커 flush + scoped barrier로 수행. (조치: 파라미터 정의/기본값/게이트 삭제, 실행 중.)

## 2. xlocator_force_validate_bulk_tail의 역할은?

FORCE(publication) 요청 꼬리에 붙는 bulk 인덱스 descriptor의 서버측 검증 게이트다(locator_sr.c:7027).
빈 꼬리 = 기존 FORCE 그대로. 꼬리가 있으면 정확히 1개의 versioned descriptor만 허용하고(잉여
바이트 거부), unpack 결과(BTID, create LSA, 클래스 집합, constraint/owner 이름)를 caller-owned
버퍼로 뽑아준다. 이후 xlocator_force가 이 값을 서버측 pending-build 등록부와 대조해 정확 일치할
때만 marker를 발행한다 — "클라이언트가 보낸 값은 힌트, 판정은 서버 등록부"라는 identity 원칙의
입구다. develop 반영 관점에선 이 함수 자체는 얇고(순수 unpack+검증), 최소수정 원칙에 부합한다.
살 뺄 여지는 이 함수가 아니라 그 아래 계층(문항 4·5·7)의 협상/이중 layout 분기다 — 7번 조치로
함께 얇아진다.

## 3. NET_CAP_BULK_NO_REDO의 역할은?

접속 핸드셰이크에서 협상되는 capability 비트다(network.h:315). 클라이언트가 이 비트를 광고하면
서버가 BTREE_LOADINDEX 요청/응답의 확장 layout(요청에 eligible 플래그, 응답에 create LSA)을
사용하고, 없으면 양쪽 다 기존 layout으로 동작한다. 즉 구/신 버전 클라·서버 혼용을 위한 wire
게이트였다. → 7번 지시로 폐기.

## 4. locator_bulk_force_tail_compute_size는 왜 클라이언트에서?

FORCE 요청을 만들어 보내는 쪽이 클라이언트이기 때문이다. descriptor는 가변 길이(클래스 개수,
이름 길이)라 요청 버퍼를 할당하기 전에 packed 크기를 알아야 하고, 직렬화(pack)와 크기 계산은
같은 곳(송신측)에 있어야 포맷이 한 벌로 유지된다. 서버는 대응하는 unpack만 가진다. 이건 기존
CUBRID 요청 직렬화 관례(or_pack류) 그대로다.

## 5. network_interface_cl.c가 바뀌어야 하는 이유는?

클라이언트가 서버와 주고받는 두 요청의 payload가 바뀌었기 때문이다.
- BTREE_LOADINDEX: 요청에 eligible 플래그 추가, 응답에서 서버 발급 create LSA 수신.
- FORCE: bulk descriptor 꼬리 pack/전송, 응답 unpack(모두 caller-owned 버퍼, 리뷰 P2-15 반영).
이 파일이 클라이언트측 요청 직렬화의 표준 위치다. 7번 조치 후에는 capability 분기(구 layout
폴백)가 사라져 파일 변경량이 줄어든다.

## 6. locator_force_bulk는 뭐야?

클라이언트측 FORCE의 bulk 변형이다(locator_cl.c). 일반 locator_force와 같은 flush 경로를 타되
(1) bulk descriptor 꼬리를 함께 보내고, (2) ignore-error 목록을 보내지 않으며(P1-10), (3) 응답의
create LSA 검증 실패 시 savepoint rollback으로 물러난다. 주변의 flush-deferral 기제는 CREATE
INDEX 문 중간의 부수 flush들이 marker 없이 publication돼 버리는 것을 막고, 최종 FORCE 한 번에
descriptor가 실리도록 미룬다.

## 7. NET_CAP_BULK_NO_REDO 삭제

동의한다. cas/서버 버전 불일치는 지원 시나리오가 아니므로(접속 시 버전 검사로 거부) capability
협상과 구-layout 폴백 분기는 죽은 무게다. **삭제 실행 중**: 비트 정의, 광고/판독 함수, 클라·서버
양쪽의 이중 layout 분기 제거 → 확장 layout 단일화. `CSS_CONN_ENTRY.client_capabilities`도 다른
용처가 없으면 함께 제거. 단, ADR-0004의 log 소비자 게이트(구버전 standby가 marker 레코드를 못
읽는 문제)는 wire와 별개의 축(HA rolling upgrade)이므로 유지한다.

## 8. sm_bulk_index_provenance_is_eligible은?

디버깅용이 아니다. "이 CREATE INDEX가 no-redo를 요청해도 되는가"의 클라이언트측 적격성 술어다
(schema_manager.c:10699): 새로 할당된 BTID + heap 로드 경로 + 인스턴스 존재 + WITH ONLINE 아님 +
서버 모드. allocate_index의 실제 판정(10897)에서 사용 중이다. 서버가 최종 판정(병렬 관여, log
호환)을 하므로 이 값은 힌트지만, 부적격 표면(빈 테이블, online 등)에서 요청 자체를 안 보내게
하는 필터라 제거하면 서버 왕복 후 강등만 늘어난다. 유지 권고. 조건부 지시("디버깅용도라면")에
해당하지 않아 유지한다 — 대신 불필요한 unused 속성만 정리.

## 9. update_class 관련 변경들은?

CREATE/ALTER INDEX의 카탈로그 publication을 "marker 동반 FORCE 한 번"으로 만드는 클라이언트측
배선이다(schema_manager.c). 구체적으로 (1) allocate_index가 서버 응답의 create LSA를 받아
descriptor를 구성하고 적격일 때 flush-deferral을 activate, (2) update_class/update_subclasses가
문 처리 중 발생하는 중간 class flush를 deferral 범위 안에서 미루고, (3) 마지막 publication
시점에 locator_force_bulk로 descriptor를 실어 보낸 뒤 post-force 처리(root class refetch 포함)를
legacy 경로와 동일 helper로 수행(P1-9 parity). 서버가 NULL create LSA를 주면(강등) 이 배선은
전부 우회되고 기존 경로 그대로 흐른다.

## 10. execute_schema.c 변경은 왜 필요한가?

ALTER ... ADD INDEX / CREATE INDEX 계열 문장이 update_class 밖에서도 class flush를 유발하는
지점(통계 갱신 등)이 있어, 문장 단위로 flush-deferral enter/leave/abort를 괄호치는 코드다.
+92줄 전부가 그 bracketing과 에러 경로에서의 abort 복원이다. 이게 없으면 중간 flush가 marker
없는 publication을 만들어 서버 가드(P1-10/pending 검증)에 걸려 문장이 실패한다. 즉 9번 배선의
문장 레벨 안전망이다.

## 11. vacuum_notify_dropped_file_during_recovery의 용도는?

미디어 복구의 bulk cleanup이 인덱스 파일을 destroy한 직후, 그 VFID를 vacuum의 dropped-file
목록에 등록한다(vacuum.c). 등록하지 않으면 복구 후 기동한 vacuum이 로그에 남은 그 b-tree 대상
엔트리를 처리하려고 이미 해제된 페이지를 만지게 된다. 기존 vacuum_rv_notify_dropped_file에
위임해 mvcc 경계 의미론을 그대로 따른다 — 신규 메커니즘이 아니라 기존 DROP 경로가 하는 등록을
복구 문맥에서도 수행하는 것.

## 12. btree.c 변경사항들은? 왜 btree.c에?

네 묶음이다: (1) marker payload의 pack/unpack 코덱(+create_token 계약), (2) 트랜잭션 스코프
pending-build 등록부(register/validate/consume/requires_marker/discard), (3) 복구 전용 undo
purpose 2종과 unique 다중갱신 undo의 부재-객체 repair(P1-1의 pgbuf_set_dirty 포함), (4)
btree_create_file의 create LSA 캡처. btree.c에 있는 이유: 이들이 전부 b-tree 도메인 객체(BTID,
root, 파일 descriptor, b-tree undo purpose)를 다루고, 특히 (3)은 기존 b-tree undo 계열
(BTREE_OP_DELETE_UNDO_INSERT_*)의 형제 케이스라 다른 파일에 둘 수 없다. (1)·(2)는 이론상
별도 파일로 뺄 수 있으나 marker의 내용이 BTID/create LSA/클래스 집합이라 응집도는 btree가
맞고, 분리하면 파일만 늘어난다.

## 13. file_manager.c 변경은 왜 필요한가?

두 가지다. (1) 서버 발급 create LSA를 btree 파일 descriptor(FILE_BTREE_DES 유니온 내부, 디스크
포맷 불변)에 기록/판독하는 접근자 — identity의 저장소다. (2) 복구의 파일 단위 정리를 위한
sector 수집/해제 보조(+7059 블록): cleanup이 파일이 점유한 페이지·볼륨 범위를 알아야 durability
관문 범위 한정과 destroy를 파일 단위로 수행할 수 있다. 리뷰 P2-13(temp retire rc 전파)의 수정
지점도 이 파일 경로에 있다.

## 14. page_buffer.c 변경, PR 7487과 중복 아닌가?

**중복 맞다.** 현재 브랜치의 page_buffer.c 4개 hunk 중 3개(pgbuf_latch_bcb_upon_fix ~6319,
pgbuf_block_bcb ~7124, pgbuf_wake_flush_waiters ~10993)는 PR 7487(CBRD-27084, waiter_exists
미정리 livelock 픽스) 그 자체다 — 그 버그가 이 브랜치의 병렬 CREATE INDEX 워크로드에서 발견돼
브랜치에 먼저 실려 있었고, 이후 별도 PR로 분리됐다. 7487이 develop에 먼저 머지되면 이 3개
hunk는 diff에서 자연 소멸한다(내용 동일 여부는 머지 시점에 rebase로 확인 필요). 이 브랜치
고유의 변경은 hunk 1개뿐이다: `pgbuf_flush_page_if_exists_and_dirty` — scoped durability
barrier가 쓰는 "버퍼에 있고 dirty일 때만 flush" probe 프리미티브 추가.

## 15. log_2pc.c — 2PC와의 호환은 안 되는 건가?

호환된다. 정상 순서에서는 CREATE INDEX 문이 끝나는 시점(publication FORCE)에 marker가 발행되고
pending 등록이 소비되므로, 그 뒤의 2PC prepare/commit은 아무 제약 없이 통과한다. log_2pc.c의
추가 3곳(prepare, commit 1단계, commit 2단계)은 "pending 빌드가 marker 없이 남아 있는" 비정상
순서에서만 커밋을 abort로 전환하는 가드다 — 이 상태로 커밋되면 no-redo 페이지의 내구성 계약이
깨지기 때문에 fail-safe로 막는 것이고, 결함 주입 검증(g003-pending-prepare/commit)으로 두 경로
모두 확인했다. 추가로 informing-participants 상태를 irreversible로 분류한 것은 리뷰 P1-3의
수정이다.

## 조치 결과 (커밋 d0151ca8f, push 완료)

- 1번: `bulk_build_worker_flush`/`bulk_build_scoped_barrier` 파라미터 완전 제거(정의·테이블·enum,
  마지막 항목들이라 재번호 불요). 워커 flush와 scoped barrier는 무조건 수행으로 고정. 전역 flush
  폴백은 bulk 트리 미구축/장벽 런타임 실패 시의 안전망으로만 잔존.
- 7번: wire 협상 전면 제거 — BTREE_LOADINDEX는 단일 확장 layout(요청에 eligible, 응답에 create
  LSA), 서버의 엄격한 요청 형태 검사 유지. `net_server_supports_bulk_no_redo`·
  `client_supports_bulk_marker`·`bulk_wire_extension` 삭제. capability 비트는 log 소비자
  신호(ADR-0004 게이트의 판독 값) 용도로만 남기고 역할에 맞게
  `NET_CAP_BULK_MARKER_CONSUMER`로 개명 — 삭제 시 HA 혼합버전 marker 게이트가 무력화되기
  때문. `CSS_CONN_ENTRY.client_capabilities`는 기존 비트들(INTERRUPT_ENABLED 등)이 쓰므로 유지.
  구버전 클라이언트 상호운용 레인은 설계상 비지원으로 전환(검증 레인의 logged 재생성은
  WITH ONLINE으로 대체).
- 8번: `sm_bulk_index_provenance_is_eligible`는 유지(디버깅용 아님 — 8번 답변 참조).
- 검증(제거 반영 빌드, release+debug green): marker 오라클 PASS, 매트릭스 4레인 PASS, OV3 9/9,
  R4(WITH ONLINE 재생성) PASS, R7/R10 PASS, churn 복원 레인 PASS, 결함 주입 diag 9케이스
  FAILURES=0, 20G 새니티 175.9s(범위 내).

## 16. client_capabilities가 뜻하는 것과 존재 이유

capability 핸드셰이크 자체는 upstream 기존 메커니즘이다(접속 시 클라이언트가 능력 비트마스크를
보내고 check_client_capabilities가 검사 — NET_CAP_INTERRUPT_ENABLED 등). upstream은 접속 검사
순간에만 쓰고 버렸고, 브랜치는 (1) 그 워드를 CSS_CONN_ENTRY.client_capabilities(connection_defs.h:468)에
보관하고 (2) "record 130(bulk marker)을 파싱할 수 있다"는 선언 비트 NET_CAP_BULK_MARKER_CONSUMER를
추가했다.

wire 협상 제거 후 유일한 소비자는 marker 발행 직전의 log 소비자 게이트
(logwr_all_consumers_support_bulk_marker_locked, log_writer.c:2130)다. WAL을 퍼가는 접속
(standby copylogdb)별로 이 비트를 확인해, 구버전 소비자(비트 광고 불가)가 있으면 전체-로깅으로
강등 + NOTIFICATION한다. cas/서버는 동일 버전 정책이지만 HA rolling upgrade 중의 log 소비자는
합법적으로 버전이 어긋나는 유일한 창구라 접속별 신호가 필요하다. 없으면 무조건 발행(구 standby
복제 붕괴) 또는 무조건 미발행(기능 사장)뿐이다. version_string 비교로 대체하지 않는 이유:
게이트는 비트 AND rel_is_log_compatible 둘 다 보며, 버전 문자열은 특정 레코드 타입 지원 여부를
표현할 수 없다(초기의 version-string 접미사 핵을 리뷰에서 이 정식 필드로 교체).

## 조치 결과 2 (커밋 7d0a58740, push 완료) — HA 게이트 전면 삭제

"ha에 이걸 넘겨야 해?"의 답: 넘겨도 아무 일도 일어나지 않는다는 것이 구버전 코드로 증명됐다
(applylogdb la_log_record_process는 rectype 분기뿐이고 REDO_DATA 케이스가 없어 default 통과,
레코드 스킵은 forw_lsa 기반; copylogdb는 페이지 복사만; standby는 WAL 물리 재생 없음). 게이트의
전제("비호환 소비자가 깨진다")가 거짓이므로 장치 전체를 삭제했다: capability 비트+광고 2줄,
CSS_CONN_ENTRY.client_capabilities 필드, log_writer의 소비자 검사/발행 재검증 3함수, 요청 시점
강등+NOTIFICATION. marker는 일반 redo 레코드로 append된다(-111줄). ADR-0004는 superseded 표기.
검증(재빌드 release+debug green): 오라클/매트릭스4/OV3 9/9/R4/R7/R10/churn 전부 PASS, diag
8케이스(emission 케이스는 장치 삭제로 폐기) FAILURES=0, 20G 새니티 174.1s. JIRA 본문·분석서·
검증 시나리오 갱신.

## 17. marker가 왜 클라이언트를 "통해서" 발급되나? xbtree_load_index에서 발급하면 안 되나?

오해 정정부터: marker 발급 주체는 서버다. 발급 지점은 xlocator_force 내부(locator_sr.c:7563),
발행 topop 안이며, parent_lsa도 그 sysop에서 캡처한다(:7558). 클라이언트는 marker를 발급하지
않고 "이번 flush가 그 인덱스의 발행"이라는 신호+identity 힌트(descriptor)만 보태며, 서버는
pending 등록부(빌드 시 등록, btree_load.c:1641)와 파일 descriptor의 create LSA 대조를 통과한
경우에만 발급한다.

xbtree_load_index에서 발급할 수 없는 이유(의도된 설계):
1. marker는 발행 구간의 끝이어야 한다 — restore 청소는 marker_prev_lsa→parent_lsa 구간을
   역재생하는데, parent_lsa는 발행 topop의 부모다. 빌드 시점엔 발행이 없어 한정할 구간이 없다.
2. 빌드~커밋 사이는 클라이언트 주도 다중 요청 구간이라(계층 flush, 통계 등) "발행 완결" 순간을
   아는 서버측 유일 지점이 BTID를 클래스 레코드에 묶는 그 FORCE다.
3. 빌드 시점 발급은 "문장 실패+savepoint rollback 후 marker만 잔존" 창을 만들어 fail-safe
   불변식(발행과 marker는 같은 sysop, marker 없는 pending은 커밋 불가)을 깨뜨린다.

복잡도의 실체는 발급이 아니라 "어느 flush가 발행인지"의 배선(descriptor 코덱 + flush-deferral +
P1-10 가드)이고, 근원은 클라이언트 주도 DDL이라는 기존 아키텍처 비용이다. commit 시점 발급은
sysop 경계 추적을 옮길 뿐이고, 꼬리 없는 서버 자동 감지(모든 FORCE에서 property list 파싱)는
deferral이 그대로 필요해 순감이 아니다. 실질 슬림화 여지 하나: descriptor의 constraint/owner
이름 2필드는 서버가 FORCE 시점 클래스 레코드에서 자체 해석 가능 — 꼬리를 (BTID, create LSA,
클래스 집합)으로 줄일 수 있다.

## 18. "클라는 아무것도 모르고, 서버가 정렬 시점에 no-redo 결정 후 결과만 보고" 설계의 위험성 검토

절반은 이미 그 설계다. "정렬 병렬도 산정 후 병렬이면 no-redo"는 현재 구현 그대로다(병렬-한정
강등: 직렬 확정 시점에 서버가 스스로 logged로 내려감). 클라이언트의 요청 플래그는 실행 모드
결정이 아니라 부류 울타리다 — btree_load_index의 클라이언트측 사용자는 두 부류로,
allocate_index(CREATE/ALTER INDEX, 적격)와 sm_load_online_index(WITH ONLINE 로드 단계,
schema_manager.c:16878/16888, 부적격)가 같은 서버 opcode를 쓴다. 플래그를 없애고 서버가 자동
opt-in하면 온라인 인덱스의 로드 단계가 no-redo+pending이 되는데, 온라인 인덱스는 발행이 별도
상태기계(BUILDING→NORMAL, 복수 flush)라 "marker 없는 pending 커밋 차단" 가드가 정상 경로를
abort시키거나 marker가 엉뚱한 창에 박힌다. 위험 1.

진짜 함정은 "결과 보고"가 아니라 발행 감지의 서버화다. 클라이언트가 아무것도 모르면
descriptor/deferral도 없어야 하고, 그러면 서버가 모든 xlocator_force에서 "이 flush가 이
트랜잭션 pending 인덱스의 발행이며, 지금이 발행의 완결인가"를 판정해야 한다. 서버는 레코드
쓰기 스트림만 보므로 중간 템플릿 flush와 최종 발행을 구분할 수 없다(문장 구조는 클라이언트만
안다). 조기 발급이면 발행 후반부 카탈로그 기록이 walk 창(marker→parent_lsa) 밖에 남아, 오염
창 엣지로 밀어놨던 "복원 시 반쪽 청소" 위험이 정상 경로에서 상시화된다. 위험 2. 반대로 커밋
시점 발급이면 발행 sysop과 marker가 분리되어 parent_lsa 창 정의가 무너지고, "발행은 됐는데
marker가 없는" 크래시 창이 부활한다. 위험 3.

create LSA 회신은 정보용이 아니라 identity 왕복 검증용(서버가 발행 시 descriptor의 LSA를 파일
descriptor와 대조)이라, 위 감지 문제를 풀지 못하는 한 회신만 없앨 수도 없다.

결론: 빌드 모드 결정의 서버화는 이미 완료됐고, 발행 신호의 서버화는 클라이언트 주도 DDL
아키텍처를 유지하는 한 안전하게 불가하다(위험 1·2·3 모두 정상 경로 손상). 안전한 추가 슬림화는
(a) descriptor에서 constraint/owner 이름 2필드 제거(서버가 FORCE 시점 클래스 레코드에서 해석),
(b) 요청 플래그를 "스키마 매니저 DDL 경로" 표식 1비트로 유지·문서화, 두 가지다. 근본 단순화는
DDL 카탈로그 갱신 자체의 서버화가 선행조건이며 이 브랜치 범위를 넘는다.

## 19. marker 필요 여부는 어디서 무슨 근거로 판단하나

결정(4단) -> 기록(1곳) -> 소비(5곳) 구조이고 단일 진실원천은 서버의 pending 등록부다.

빌드 모드 결정: (1) 클라 부류 필터 sm_bulk_index_provenance_is_eligible(schema_manager.c:10699,
새 BTID+heap 로드+인스턴스 존재+비온라인+서버모드) -> 요청 eligible 표시, (2) sbtree_load_index
unpack, (3) btree_load.c:1244 load_args->no_redo = eligible_no_redo, (4) 정렬 계층 강등 2곳
(sort_listfile 단일 프로세스 분기, sort_px_construct_index_leaf n_shards<2 ->
bt_load_demote_to_logged): 병렬 실제 관여 빌드만 no_redo 생존.

필요의 탄생: btree_load.c:1634 `if (load_args->no_redo && built_bulk_tree)` — no-redo로 실제
완주한 경우에만, 파일 descriptor의 create LSA/class_oid/attr_id 재대조 후
btree_bulk_pending_register(:1641)가 (tran_index, trid) 키로 등록. 이 등록이 "커밋 전 marker
필수" 선언이다.

강제 지점(btree_bulk_pending_requires_marker 조회 5곳): locator_sr.c:7299(pending 있는데
descriptor 없는 FORCE 거부), locator_sr.c:7563/7568(정확 일치 검증 후 marker 발급+pending 소비),
log_manager.c:5232(로컬 커밋 차단), log_2pc.c:631/785/1321(2PC prepare/commit 차단). 풀 abort는
btree_bulk_pending_discard로 등록부 소거.

복구 쪽은 등록부와 무관하게 "로그에 marker가 실제 존재하는가"만이 근거다(수집 -> (VFID, create
LSA) 정확 일치 -> 재기동은 트랜잭션 완료 여부, restoredb는 발행 창 오염 여부로 분기).
