---
status: accepted
date: 2026-11-09
---

# 파서 식 중첩 한도는 16384로 고정한다

CAS 폴드(CBRD-27430, PR 7837)는 파서가 만든 식 트리의 중첩 깊이를 `PT_NODE::nesting_depth`로 세고, 16384를 넘으면 문장을 파스 에러("Statement is nested too deeply (the maximum nesting depth is 16384).")로 돌린다([#128](https://github.com/xmilex-git/workspace/issues/128) D5: 고정 상수, 파라미터 없음). 목록을 사슬로 펴는 구문(CASE, DECODE, COALESCE, LEAST/GREATEST, CONCAT)은 목록 길이 + 인자 깊이로 센다. 문법은 CS·SA·서버가 함께 쓰므로 세 모드 모두에 적용된다.

사용자 결정(2026-11-09, [A8 이식](https://github.com/xmilex-git/workspace/issues/629)): 한도 16384를 유지한다.

실측(optdebug, 8MB 스택): `SELECT 1+1+...+1`은 develop SA에서 30000 깊이까지 실행되고 35000에서 core. 폴드는 16384를 넘으면 에러, 서버 스레드에서 16383 깊이는 실행된다(smoke). 회귀 스위트의 최대 형태는 AND 5000항.

이유: 폴드에서 스택 고갈은 서버 전체를 죽인다(CS에서는 CAS 하나). 16384는 develop 크래시 지점의 절반 이하라 프레임이 큰 다른 구문에도 여유가 있다.

## Considered Options

- **16384 유지**: 채택.
- **한도 상향(예: 24576)**: 기각 — 프레임이 큰 구문에서 한도 안 스택 고갈 위험, 추가 측정 필요.

## Consequences

- 스펙 변화(CS·SA·폴드 모두): 중첩 16385 이상 ~ develop 크래시 지점 미만의 식은 develop에서 실행되지만 이제 파스 에러다. 최종 게이트의 QA test.md·매뉴얼에 적는다.
- 중첩 서브쿼리 깊이는 세지 않는다. 그 스택 고갈은 스레드별 대체 시그널 스택 덕에 크래시 콜스택을 남긴다(진단만).
- 서버 스레드 스택은 `ulimit -s`를 따른다: 512KB에서는 16000 깊이도 스택을 넘는다(계측 확인).
