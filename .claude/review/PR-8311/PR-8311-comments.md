# PR #8311 post-ready comments (2차)

## CUBRID/cubrid#8311 — Approve (commit 8f644ec56)

재측정과 방식 변경 확인했습니다. 병합이 읽은 run 페이지를 LRU 맨 아래로 보내는 쪽이 직렬·병렬 모두에 맞는 방향으로 보입니다. `pgbuf_copy_page_to_area_lru_bottom` 의 잠금 순서도 기존 unfix 경로와 같아 문제없어 보입니다. CI sql 실패 11건은 `cbrd_27381` TC 가 엔진 PR #8209 보다 먼저 develop 에 들어가서 생긴 것이라 이 PR 과는 무관합니다.

## CUBRID/cubrid-testcases#3918 — Approve (commit e84f553fc)

top-level:
DISTINCT ORDER BY LIMIT 질의와 trace 섹션 추가 확인했습니다.

inline `sql/_36_guava/cbrd_27787/cases/cbrd_27787.sql:7`:
NIT: 엔진 PR 의 8f644ec56 에서 private LRU 빌리기가 빠졌으니, 헤더의 "the workers keep the input pages in the main thread's private LRU list" 부분도 run 페이지를 LRU 맨 아래로 보내는 설명으로 바꾸면 어떨까요?
