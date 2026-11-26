set -euo pipefail
R=xmilex-git/workspace
declare -A T=(
 [S0]="S0 이식 — 클라이언트 절반 SERVER_MODE 편입 + tracer 존치 결정"
 [A1]="A1 이식 — client_session_context와 브래킷 스캐폴드"
 [A2]="A2 이식 — 파서 재진입화 (CSQL_PARSER_TLS, 요청 간 잔존 표)"
 [A3]="A3 이식 — RPC 접기와 SA 단일-클라이언트 가정 9건 재확인"
 [A4]="A4 TLA+ 검증·이식 — 워크스페이스/MOP per-session과 csc 브래킷 소유권"
 [A5]="A5 TLA+ 검증·이식 — sysprm/boot 수명과 세션 간 파라미터 격리"
 [A6]="A6 TLA+ 검증·이식 — REVOKE chn bump와 prepared 재컴파일"
 [A7]="A7 TLA+ 검증·이식 — PL/method in-process 종단과 핸들 수명"
 [A8]="A8 이식 — 에러/크래시 격리 (깊이 가드·sigaltstack·AREA 콜백)"
)
prev=""
: > ids.tsv
for s in S0 A1 A2 A3 A4 A5 A6 A7 A8; do
  url=$(gh issue create -R $R --title "${T[$s]}" --label wayfinder:task --body-file $s.md)
  n=${url##*/}
  id=$(gh api repos/$R/issues/$n --jq .id)
  gh api --method POST repos/$R/issues/618/sub_issues -F sub_issue_id=$id >/dev/null
  if [ -n "$prev" ]; then
    gh api --method POST repos/$R/issues/$n/dependencies/blocked_by -F issue_id=$prev >/dev/null
  fi
  prev=$id
  echo -e "$s\t$n\t$id" | tee -a ids.tsv
done
