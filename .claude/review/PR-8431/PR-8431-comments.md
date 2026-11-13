# PR #8431 post-ready comments

## CUBRID/cubrid#8431 (engine)

event: APPROVE
commit_id: 6cc3c42d4cc25151cda91c9b660c2cce4f69d127

### top-level

CBRD-27972 를 찾은 TLA+ 모델(`OvfScanResume`)에 객체별 MVCC 상태(미커밋 삽입, 안정, 삭제)와 이 PR 의 leaf 안정 객체 검사를 넣어 다시 돌려 봤습니다. 이 PR 이전 동작은 기존과 같이 멈춘 스캔이 행 하나를 잃는 반례가 나오고, 이 PR 의 동작은 OID 4개, 페이지당 2개 경계에서 통과합니다. 검사에서 DELID 조건, 미커밋 삽입 조건, latch 를 다시 잡을 때마다 하는 재검사, MVCC 가 꺼진 클래스 제외를 하나씩 빼 보면 모두 행을 잃는 반례가 나와서, 넣으신 조건이 각각 필요한 것으로 보입니다.

PR head 에 첨부 evidence 패치와 검사 결과 로그 한 줄을 넣은 optdebug 빌드로 두 실행을 기록해 모델에 대조했습니다. JIRA 재현 그대로에서는 key 1 이 건너뛰어지고 9,974행이 모두 나왔고, leaf 객체를 안정으로 둔 채 스캔이 멈춘 사이 COMPACT 를 돌리고 leaf 행을 지운 실행에서는 그 행의 swap 이 스캔 재개 뒤에야 일어나고 9,975행이 모두 나왔습니다. 두 기록 모두 모델이 받아들였습니다.

### inline: src/storage/btree.c (btree_compact_leaf_has_stable_object 정의부, 함수 시작 줄)

NIT: 위쪽 static 프로토타입 블록에 `btree_compact_fix_leaf` 다음으로 `btree_compact_leaf_has_stable_object` 선언도 추가하는 건 어떨까요? 같은 COMPACT 도우미인 `btree_ovf_compact_pull`, `btree_ovf_compact_chain`, `btree_compact_fix_leaf` 는 정의 순서대로 블록에 선언돼 있습니다.

### inline: src/storage/btree.c (`mvcc_is_mvcc_disabled_class` 분기)

MVCC 가 꺼진 클래스(root, `db_serial`, `_db_collation`, `db_ha_apply_info`)의 기본 인덱스는 모두 PK/unique 라서 여기서 걸러지는 비유니크 인덱스가 실제로 있는지 궁금합니다. 그리고 그런 인덱스가 있다면, 모델에서는 COMPACT 없이도 물리 삭제로 이미 읽은 첫 overflow 페이지가 통째로 빠지고 그 다음 페이지가 첫 페이지가 된 뒤 leaf swap 이 일어나면 재개한 스캔이 행을 놓치는 경로가 나왔습니다. 이 클래스들에서는 키 중간 재개 자체가 일어나지 않는 것으로 보면 될까요?

## CUBRID/cubrid-testcases-private-ex#4770 (TC)

event: APPROVE
commit_id: 3ad598b25586a0ad7c6e3158ebced0dff22f0085

### top-level

스캔이 멈춘 창 자체 대신 그 창을 닫는 규칙(leaf 유일 객체가 미커밋 삭제 상태면 건너뛰고, 커밋과 vacuum 뒤에는 컴팩션)을 tc2 대조군과 함께 확인하고 있습니다. 수정 전 develop 에서 4번만 NOK 가 나는 것도 이 규칙과 맞습니다.
