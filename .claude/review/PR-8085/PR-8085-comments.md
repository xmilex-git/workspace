# PR #8085 post-ready review comments (2차)

각 섹션의 event / commit_id는 메타데이터이며 본문에 넣지 않는다. 1차 코멘트는 `PR-8085-comments-20261008.md`.
inline 코멘트는 없다(grill: PR 본문 불일치는 보고서에만, 매뉴얼 항목과 TC 본문 NIT는 게시하지 않음).

---

## CUBRID/cubrid#8085 (engine)

- event: APPROVE
- commit_id: `405422e0ea1487caccd176e3149ee9c0e0e4e44f`

### top-level

NULL을 허용하는 unique 컬럼은 NOT NULL일 때만 행 수로 보도록 바꾼 것(405422e0e)과, 같은 형태의 TC 케이스가 들어간 것을 확인했습니다. develop 동기화 후 CI도 sql, medium 모두 통과했고, shell의 `cbrd_26564` 실패는 다른 PR들에서도 같이 나고 있어서 이 PR과는 무관해 보입니다. TPC-H / JOB 결과도 공유해 주셔서 감사합니다.

---

## CUBRID/cubrid-testcases#3627 (TC)

- event: APPROVE
- commit_id: `89d377226a75394cfd87b3eea585ec070b880e9f`

### top-level

#8051 이후 실행 중 판단 케이스의 답지 갱신과, NULL 허용 unique 키와 상속 계층 outer 케이스 추가를 확인했습니다. 엔진 PR head 기준 CI에서 `cbrd_27543`, `cbrd_24252_5` 모두 통과했습니다.

---

## CUBRID/cubrid-testcases-private-ex#4298

리뷰하지 않음 (파일 변경 없음, 닫기는 TC Merge Gate 봇이 안내).
