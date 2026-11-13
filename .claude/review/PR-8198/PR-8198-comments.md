# PR #8198 post-ready comments

리뷰 결정(grill 2026-11-10): 엔진 PR Approve, TC #4049 Approve, TC #4756 Approve + 인라인 1 건. 발견 1, 2(TC 회귀 케이스 누락, head 미실행)와 4(TLA+ 산출물 요청)는 게시하지 않는다.

## CUBRID/cubrid#8198 — Approve (commit_id fbaae2592fa5ab4a0c85686f08cede42d83aa792)

본문:

head `fbaae2592` 의 CI 빌드로 확인했습니다. 미커밋 자식 INSERT 뒤 부모의 키가 아닌 컬럼을 UPDATE 하면 develop(`2d928e34b`) 빌드는 3 초 lock timeout 으로 실패하고, 이 PR 빌드는 바로 진행합니다. 자식 INSERT 동안 lockdb 의 부모 행 S 락도 1 개에서 0 개가 됩니다.

HA 에서는 부모 PK UPDATE 와 ON UPDATE SET NULL 자식, 자기 참조 PK UPDATE, 분할 부모의 파티션 이동을 ha_repl 로 돌렸고 master 와 slave 결과가 모두 같았습니다. 되돌린 INSERT 의 슬롯을 다른 트랜잭션의 INSERT 가 다시 쓰는 경우도 재현해 보았는데, 부모 DELETE 가 그 INSERT 를 기다리지 않고 지나가고 그 INSERT 는 외래 키 오류로 끝났습니다.

release 빌드의 cub_server instructions 기준(3 회 중앙값)으로 자식 INSERT 2 만 건은 10.8%, 자식의 키가 아닌 컬럼 UPDATE 2 만 건은 20.8% 줄었고, 자식이 없는 부모 DELETE 는 같았으며, 자식 2 만 건 CASCADE DELETE 는 4.6% 늘었습니다.

## CUBRID/cubrid-testcases#4049 — Approve (commit_id 7c87882853d1753df995d7d847241c3e7b00e636)

본문:

엔진 PR #8198 과 함께 확인했습니다.

## CUBRID/cubrid-testcases-private-ex#4756 — Approve (commit_id 669c39fa48ec93dc2ce5cad4a3bebc953e41b38d)

본문:

엔진 PR #8198 과 함께 확인했습니다. 주석 한 곳만 남깁니다.

인라인 `shell/_40_guava/cbrd_27463/cases/cbrd_27463.sh:10` (RIGHT):

#8198 head 는 외래 키 컬럼을 SET 하지 않는 UPDATE 의 외래 키 검사를 건너뜁니다(`locator_check_foreign_key ()` 의 `locator_index_has_attr ()` 분기). 그래서 `kf_upd_nonkey` 는 검사를 다시 돌리지 않아 락이 0 개입니다. 주석을 "does not run the check, so it holds none" 처럼 바꾸는 건 어떨까요?
