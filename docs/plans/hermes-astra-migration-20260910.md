# Hermes Astra 전환 및 운영 기록

완료일: 2026-09-10 (Asia/Seoul)

## 합의한 스펙

- 사용자의 순서 수정에 따라 같은 계정의 별도 로그인을 먼저 완료했다.
- gateway 중지 후 공식 최신 안정 릴리스로 업데이트하고 설정·디스크 배치를 변경한 다음 재시작했다.
- SSD 중심 배치와 로그인 후 자동 실행을 우선한다.
- 기본값만 변경하며, 명시적 모델 지정 예약 작업 및 기존 대화 기록을 유지한다.
- 기본 provider `openai-codex`, 모델 `gpt-6-astra`, `agent.reasoning_effort: low`.
- `model.context_length: 1000000`, 기존 `compression.threshold: 0.5` 유지.
- 기존 Hermes OpenAI 인증을 제거하고 현재 Codex와 같은 계정의 독립 OAuth 인증 하나만 유지한다.

## 결정과 근거

- D1: 설치·데이터·앱 로그를 SSD에 둔다. launchd 시작 스크립트와 시작용 로그는 OS 디스크에 둔다. SSD 마운트/접근을 기다리기 전에 launchd가 SSD 경로를 열 필요가 없게 한다.
- D2: Codex 토큰을 복사하지 않고 같은 계정의 별도 OAuth 세션을 사용한다. 일회용 refresh token 회전 충돌을 피한다. 계정 ID 동일성과 refresh token 차이를 값 출력 없이 비교했다.
- D3: 공식 안정 태그 `v2026.9.7` / `2237be355906fbe6065ce1815711eee52b2d646e`로 고정했다. 패키지 버전은 0.21.1이다. 기존 커밋은 `bee2bd8bc2`였다.
- D4: 공식 소스를 수정하지 않고 CLI 래퍼에서 gateway lifecycle을 제어한다. Hermes 내장 `gateway start/install`은 사용자 지정 plist를 재생성하므로 우회한다.

## 배치

- Hermes home 및 설치: `/Volumes/PSSD_T7/dev/hermes/.hermes`
- 앱 로그: `/Volumes/PSSD_T7/dev/hermes/.hermes/logs` (실제 SSD 디렉토리)
- 이전 `~/Library/Logs/Hermes`의 로그를 SSD로 이동했고 logs 심볼릭 링크는 제거했다.
- 시작용 로그: `~/Library/Logs/Hermes-launchd/bootstrap.log`, `bootstrap.error.log`
- 시작 스크립트: `~/.local/libexec/hermes/gateway-launcher.py`
- 서비스 제어: `~/.local/libexec/hermes/gateway-control.py`
- LaunchAgent: `~/Library/LaunchAgents/ai.hermes.gateway.plist`
- Python 본체: OS 디스크의 uv 관리 Python 3.11.15. venv 및 패키지는 SSD.
- 사용자 편의를 위한 `~/.hermes` 및 `~/.local/bin/hermes` 링크는 유지한다.

시작 스크립트는 config 읽기, Python 실행 권한, SSD 로그 쓰기 가능 여부를 확인하며 준비 전에는 10초마다 재시도한다. 시작용 로그에는 대기/준비 메시지만 기록하고, gateway stdout/stderr는 SSD의 `gateway-console.log`로 보낸다. console 로그는 시작 시 2MiB 초과이면 `.1`로 회전한다. 앱 자체 로그 회전은 Hermes가 관리한다. 이 방식은 권한을 우회하지 않으며 macOS가 접근을 거부하면 대기한다.

## 운영 명령

일반 셸의 `hermes gateway start`, `stop`, `restart`, `status`, `install`은 보존용 래퍼를 경유한다. `install`은 기존 사용자 지정 plist를 등록하며 재생성하지 않는다. 이 명령들에는 추가 인자를 받지 않는다.

venv의 CLI를 직접 호출하는 `gateway start/install`은 사용자 지정 설정을 덮어쓸 수 있으므로 사용하지 않는다. 일반 `hermes update`는 기본 브랜치로 이동할 수 있고 내부 서비스 갱신도 수행하므로, 다음 안정판 업데이트 역시 태그 선택 → 중지 → 의존성 설치/설정 마이그레이션 → 사용자 지정 plist 유지 → 시작 순서로 수행한다.

기존 Dario provider와 명시적 Claude 예약 작업은 유지했다. 이전 `dario-hermes-recovery`의 recover 스크립트는 기본 모델을 Claude로 되돌리는 동작이 있으므로 이 새 기본 설정을 복구하는 용도로 실행하지 않는다.

## 검증

- 공식 태그 checkout 및 `uv sync --extra all --locked --inexact --no-dev`로 의존성을 잠금 파일에 맞췄다. 기존 부가 패키지는 보존했다.
- 비대화형 설정 마이그레이션 완료.
- 실제 Hermes credential pool 및 Codex Responses 경로에서 `gpt-6-astra`, `low`로 `OK` 응답 확인.
- 컨텍스트 helper가 1,000,000을 반환하고 압축 비율 0.5 유지 확인.
- gateway launchd 실행, Telegram 연결, SSD 로그 쓰기 확인.
- `hermes gateway restart` 후 plist 해시 유지 확인.
- 전체 1M 입력 요청과 실제 Mac 재부팅은 수행하지 않았다. 서버의 1M 요청 수용이나 재부팅 후 권한 상태를 실증한 것은 아니다.
- gateway의 최초 중지 시 정상 종료 제한 시간을 넘겨 Hermes가 해당 PID를 SIGKILL로 종료했다. 이후 새 서비스는 정상 실행됐다.

## 복구 자료

원래 config, plist, CLI 래퍼는 `/Volumes/PSSD_T7/dev/workspace/.git_ignored_dir/scratch/hermes-migration-20260910-085940`에 보관했다. 기존 인증은 제거 요청에 따라 백업하지 않았다. 코드 복구가 필요하면 gateway를 중지하고 기존 커밋 및 해당 의존성을 복원한다. 로그는 SSD 이동 이후 추가 기록이 있으므로 과거 경로를 복원할 때 새 로그를 보존해야 한다. 단순히 옛 plist만 복사하지 말고 로그 경로도 함께 맞춰야 한다.

## 출처

- https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.7
- https://developers.openai.com/api/docs/models/gpt-6-astra
