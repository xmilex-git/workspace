# 양측 엔진은 exact SHA로 pin하고, 전용 prefix에 격리 설치한다

비교 대상 두 엔진 모두 이 장비에서는 릴리스 바이너리가 아니다. PostgreSQL은 설치본이 아예 없고
`~/dev/postgres`에 소스만 있으며, 그 소스는 `master` = **20devel**(개발 브랜치)이다. CUBRID는 설치본이
여럿 있지만 현재 `~/CUBRID`가 가리키는 것은 `11.5.0.2317-94864ed`, 즉 `codex/jdbc-direct-phase3`
PoC 브랜치 빌드라 실험 코드가 섞여 있다. 이 상태에서 "버전"으로 결과를 식별하면 나중에 어떤 코드가
측정됐는지 복원할 수 없다. 그래서 **버전 문자열이 아니라 commit SHA를 식별자로 삼고**, 설치는 공용
경로를 건드리지 않는 전용 prefix에 한다.

## Decision

- **PostgreSQL**: `~/dev/postgres` master `5713b437abed7085e7d59849c6e9e0f4f469633d`
  (`git describe` = `REL_19_BETA1-472-g5713b437abe`, `configure.ac` = `20devel`, 2026-07-28 10:49 KST).
  이 SHA를 고정하고 다른 커밋으로 옮기지 않는다. 재클론 없이 로컬 체크아웃을 그대로 쓴다.
  설치 prefix는 홈 아래 전용 경로(`$HOME/pg/<sha-prefix>` 형태)로 두며 root 권한이 필요 없다.
- **CUBRID**: 설치 직전 `~/dev/cubrid`에서 `git fetch origin develop`한 시점의 HEAD를 pin한다.
  **`CUBRID_DEVELOP_SHA = f30f1c26003e5aa8e93182648e06cad76fc77064`**
  (2026-07-27 16:23:31 +0900, `[APIS-1087] Update cubrid-jdbc submodule (#7501)`; 2026-07-28 fetch로 확정).
  `~/dev/cubrid` 작업 트리가 dirty하므로 빌드는 그 SHA로 만든 clean 워크트리 `~/dev/wt-tpch-sspq`에서 하고,
  `just build release`에 `INSTALL_PREFIX=$HOME/tpch-sspq-install/cubrid-f30f1c260`을 지정해 전용 경로에 넣는다.
  설치본 채증: `bin/cubrid_rel` → `CUBRID 11.5.0 (11.5.0.2374-f30f1c2) … (Jul 28 2026 13:24:29)`.
- **`~/CUBRID` 심링크는 건드리지 않는다.** 기존 PoC 설치본도 삭제하지 않는다.

## Consequences

- **20devel은 안정 릴리스가 아니다.** 이 프로젝트의 수치는 "PostgreSQL <릴리스 번호>의 성능"으로
  인용할 수 없고, 모든 보고서에 개발 스냅샷임을 명시한다. 릴리스 대비 재측정은 별도 결정 사항이다.
- 두 SHA와 빌드 플래그는 Comparison Snapshot의 필수 항목이다. 둘 중 하나라도 비면 그 측정은 표에
  올리지 않는다. 설치 후 실제 바이너리로 `cubrid_rel` / `pg_config --version`을 채증해
  pin 값과 일치하는지 확인한다(SSOT 환경 함정 #1: stale 바이너리).
- 공용 심링크를 쓰지 않으므로 다른 세션이 `just build`로 `~/CUBRID`를 repoint해도 이 프로젝트의
  측정은 영향을 받지 않는다. 대신 하네스는 `$CUBRID`에 의존하지 말고 **전용 prefix를 명시**해야 한다.
- 재빌드·재설치는 conf를 초기화한다. pin된 빌드로 설치한 뒤 파라미터를 다시 적용하고,
  적용된 값을 실측으로 확인한 다음에야 측정을 시작한다.
