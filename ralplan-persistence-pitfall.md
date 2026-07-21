# Ralplan 영속화·서브에이전트 운영 주의사항

> 2026-07-21 기준. 현재 동작은 `packages/coding-agent/src/defaults/gjc/skills/ralplan/SKILL.md`,
> `packages/coding-agent/src/prompts/agents/{planner,architect,critic}.md`,
> `packages/coding-agent/src/gjc-runtime/ralplan-runtime.ts`를 기준으로 확인한다.

## 1. 제한 역할 에이전트의 영속화

Planner, Architect, Critic의 bash는 일반 셸 작업용이 아니다. 허용되는 용도는 GJC workflow CLI 영속화와 상태 명령뿐이다.

Ralplan 산출물은 구조화된 `env` 파라미터의 `GJC_RALPLAN_ARTIFACT`로 전달하고 다음 명령으로 저장한다.

```bash
gjc ralplan --write --stage <stage> --stage_n <N> \
  --artifact-env GJC_RALPLAN_ARTIFACT --json
```

- 큰 Markdown을 command 문자열, heredoc, shell substitution으로 전달하지 않는다.
- 제한 역할 에이전트에서 `--artifact <path>`를 사용하지 않는다. 제한 모드에서는 경로를 읽지 않고 해당 문자열 자체를 산출물 본문으로 취급한다.
- 영속화 후에는 전체 본문을 다시 반환하지 않고 receipt와 짧은 verdict/status만 반환한다.

## 2. 계획 단계 mutation boundary

Ralplan 승인 전 계획 단계에서는 제품 코드와 저장소 문서를 수정하지 않는다. 오케스트레이터가 큰 임시 산출물을 준비해야 하면 `/tmp`, `/var/tmp`, `$TMPDIR` 같은 neutral temp 경로만 사용한다. 제한 역할 에이전트는 산출물을 temp 파일로 쓰지 않고 `GJC_RALPLAN_ARTIFACT`로 전달한다. `.gjc` 파일은 직접 편집하지 않고 반드시 GJC CLI를 거친다.

Mutation guard는 방어적 휴리스틱이므로 shell 우회법을 운영 규칙으로 삼지 않는다. 파일 조회에는 `read`, `find`, `search`를 사용하고 제품 변경은 승인된 실행 단계까지 미룬다.

## 3. Planner와 리뷰 lane

1. Planner를 한 번 실행하고 결과를 먼저 영속화한다.
2. Architect와 Critic이 동일한 Planner artifact만 소비하고 서로의 결과에 의존하지 않으면 병렬 실행한다.
3. Critic이 Architect의 판단을 평가해야 하면 Architect 완료 후 순차 실행한다.
4. 동일한 `path`, `sha256`, `stage_n`에 대한 Architect와 Critic receipt를 모두 확인한 뒤 revision 또는 finalization으로 진행한다.
5. Planner resume이 실제로 실패한 경우에만 fresh Planner를 띄우고 `--fallback-reason`, `--fallback-attempted-id`, `--fallback-stage-n`을 함께 기록한다.

Await timeout만으로 subagent를 취소하지 않는다. 토큰·세션 기록이 정지했는지 확인하고, 실제 실패·이탈·복구 불가 상태일 때만 취소한다.

## 4. 오류 대응

- 동일한 tool-call 오류를 반복하지 않는다. 입력 계약을 다시 확인하고 최대 두 번만 교정한다.
- `Received arguments: {}` 같은 검증 오류가 나면 payload 크기와 구조화된 `env` 사용 여부를 먼저 확인한다.
- 중복 stage write는 기존 receipt와 `stage_n`을 확인한 뒤 문서화된 다음 번호로만 재시도한다.
- 계획 본문보다 receipt를 단계 간 계약으로 사용해 대화 컨텍스트의 중복과 드리프트를 줄인다.
