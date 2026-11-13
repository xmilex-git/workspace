# PR-8424 post-ready comments

## CUBRID/cubrid#8424 (engine)

- review event: APPROVE
- commit_id: 316431fba9f21d3a9a2a14b3f7903f3ab14c189b

### top-level

형제 워커가 temp 파일 공간을 잡느라 잠깐 연 sysop 때문에 병렬 실행이 꺼지던 경우를 확인했습니다. 판정 이유를 기록하는 optdebug 빌드로 02_hash_join_mode 본문(cubrid-testcases #4019 이전)을 반복해 보니, 다른 스레드의 sysop 때문에 직렬로 판정된 경우가 develop 판정에서는 15번 중 7건, 이 PR 에서는 16번 중 0건이었습니다. INSERT 의 문장 sysop 안에서 PL 함수를 부르면 함수의 SQL 을 받은 요청 스레드가 PL 조건으로 직렬 판정을 받는 것도 확인했고, 그 스레드는 호출자의 sysop 에 152번 다시 들어갔습니다. 교착이 없는 것과 sysop 안에서 동시에 도는 스레드가 하나뿐인 것은 TLA+ 모델로도 확인했습니다.

확인 부탁드립니다
- 인라인 코멘트 2건 (JIRA 에서 정한 조건과 다른 부분, owner 가 비었을 때의 판정)

### inline: src/query/parallel/px_parallel.cpp:75 (RIGHT)

JIRA 댓글에서 정한 조건은 sysop 을 연 스레드가 현재 스레드이거나 현재 스레드를 띄우고 기다리는 스레드인 경우였는데, 여기서는 띄운 부모 조건 대신 PL 세션 조건을 씁니다. 부모 조건을 넣으면 부모가 temp 파일용 sysop 을 잠깐 쥔 동안 워커가 다시 직렬로 떨어지고, 부모가 sysop 을 쥔 채 워커를 기다리는 경로는 develop 에도 없어서 지금 구현이 맞다고 봅니다. 이 선택과 이유를 PR 본문과 JIRA 에 한 줄 남겨 두는 것은 어떨까요?

### inline: src/query/parallel/px_parallel.cpp:67 (RIGHT)

첫 읽기에서 sysop 이 열려 있었는데 owner 가 비어 있으면, 클라이언트 트랜잭션에서는 두 읽기 사이에 그 sysop 이 끝난 경우로 이해하고 있습니다. 판정마다 owner 를 기록한 빌드로 같은 본문을 16번 돌렸을 때 이 경우가 1번 나왔고, 그 스캔은 직렬로 실행됐습니다. `lock_topop ()` 이 mutex 를 잡지 않는 시스템 트랜잭션 때문에 `true` 로 두신 건지, `false` 로 해도 되는지 궁금합니다.

## CUBRID/cubrid-testcases#4055, cubrid-testcases-private-ex#4762

리뷰 없음 (변경 없는 draft; 회귀 TC 부재는 코멘트하지 않기로 grill 에서 정함).
