# herdr-integration 설계 인터뷰

상태: 사용자 최종 승인 완료. 네이티브 Herdr 대기로 구현.

## 확정한 결정

- Q1: 조정 대화 S0는 현재 실행 위치에 유지한다. Herdr에는 Claude 작업자를 실행하며, S0의 자동 resume·대화 이동은 하지 않는다.
- Q2: 위임 작업마다 전용 Herdr 작업 세션을 새로 만들고, 작업 종료 후 해당 세션을 닫는다. 생성과 정리를 스킬의 책임으로 둔다.
- 기존 사용자 요구: Claude 작업자는 Sonnet을 사용한다. 빌드·검증·실행·재현·core/gdb 분석 위임을 대상으로 한다.
- 조작 수단은 `herdr agent`이며, 실행에 필요한 pane·session 생성과 정리는 Herdr의 해당 명령을 사용한다.

- Q3: S0는 현재 작업 흐름에서 `agent prompt --wait`로 결과를 기다린다. 대기는 Herdr 네이티브 wait가 처리하며 Python polling은 구현하지 않는다. 별도 알림 서버를 만들지 않는다.
- Q4: 성공·실패가 확정되면 결과를 보존하고 전용 세션을 닫는다. Claude의 승인 요청·질문은 위임한 Codex가 내용을 확인하고 판단해 응답한다. 일괄 자동 승인은 의미하지 않는다.

- Q5: 기존 사용자 권한 안의 작업·구현 판단은 위임한 Codex가 직접 처리한다. 새로운 권한이나 사용자만 아는 정보가 필요할 때만 S0에서 사용자에게 질문한다.
- Q6: 작업 대기는 최대 2시간이다. 이전 제안의 작업별 기한·자동 연장 방식은 채택하지 않는다.

- Q7: 세션 생성 시작부터 승인·질문 대기를 포함한 전체 경과 시간 2시간을 센다. 기한 만료 시 로그·상태를 보존하고 작업 중단을 요청한 뒤 전용 세션을 닫아 timeout 실패로 보고한다. 중단·정리를 위한 짧은 유예만 두며 작업 기한은 연장하지 않는다.

## 확인된 제약

- `agent start`에는 기존 shell pane이 필요하다.
- `agent prompt --wait`는 Herdr가 인식하는 idle/done/blocked 상태까지 기다린다. 상태만으로 작업 성공을 판정할 수 없으므로 최종 결과 확인이 필요하다.
- Herdr 밖에 있는 S0는 `herdr agent prompt`의 입력 대상이 아니다. 작업자의 Herdr 입력 push만으로 외부 S0 대화를 깨울 수 있다고 가정하지 않는다.
- `--handoff`는 Herdr 서버 교체 시 기존 프로세스를 보존하는 기능이며, 이 설계의 작업 위임이나 S0 이동 기능이 아니다.
- 공식 `herdr integration`은 네이티브 세션 식별·복원을 위한 hook 설치 기능이며, 작성할 `herdr-integration` 스킬과 구분한다.

사용자 최종 수정: shell timer·watchdog·추가 대기 스크립트를 만들지 않는다. Herdr 네이티브 wait와 timeout만 사용한다. timeout 반환 또는 S0 재개 시 기한 초과를 확인하면 S0가 기록 보존·중단·세션 정리를 수행한다. S0가 사용자 응답을 기다리는 동안의 자동 세션 종료는 보장하지 않는다.

근거: 설치된 `herdr agent` 도움말, [Herdr integrations](https://herdr.dev/docs/integrations/), [Herdr session state](https://herdr.dev/docs/session-state/).
