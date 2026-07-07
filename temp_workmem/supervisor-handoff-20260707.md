# Supervisor 핸드오프 v6 (2026-07-07 — 이전판 supervisor-handoff-20260706.md 전면 대체)

> **인수 방법**: 이 문서를 읽고 "supervisor mode로 동작하라".
> **세션 종결 스냅샷**: T1/T3 구현 캠페인이 로컬 fable 리드(+sonnet 서브에이전트) 체제로 완주 국면에 들어갔고, 사용자가 리드 측에 마무리 스크립트를 투입 — supervisor 상시 감시는 이 시점부로 종료(워처 중지됨).

## 0. 좌표·인프라 (변경분 중심 — 불변 항목은 v5 참조)

| 항목 | 값 |
|---|---|
| 이슈 트래커 | `gh ... --repo xmilex-git/cubrid` |
| 엔진 체크아웃 | `~/dev/cubrid-workmem`. **캠페인 통합 브랜치 = `wm147-t1-grace`** (T3 `wm146-t3-budget` 완주 tip 위로 rebase 완료, upstream develop `04192d663` 머지 포함). 워크트리 `~/dev/wt-t1`/`~/dev/wt-t3` |
| develop 대조군 | `47fcc321f` (11.5.0.2295) |
| 실행 체제 | **원격 워커(.30/.32/.33) 사용 불가** — 로컬 tmux `fable` 세션이 실행 리드(Fable), 구현·검증은 sonnet 서브에이전트 병렬 위임. task 정본 = `.not_git_tracking/scratch/task_t1t3_impl_lead.md` |
| 워처 | `.not_git_tracking/scratch/sup_watch.sh` (대상 #146/#147로 설정된 상태, **현재 중지**) |

## 1. 캠페인 결과 (2026-07-06~07, 상세는 이슈)

- **#146 (T3, per-op work_mem 예산)**: S0~S4 전 슬라이스 착지·push. 선불 예약 폐지→실사용 charge, per-op 한도(row=work_mem, hash=×multiplier GUC), 소비자 통합(agg/memoize/sq_cache, knob 3종 deprecate), MRO 게이트, 관측 카운터 일신. **잔여 = R(agg 파티션-재귀) — 착수 전 정지 유지, supervisor 권고는 보류(별도 트랙 이월)였으나 사용자 최종 결정 미기록.**
- **#147 (T1, Grace 해시조인)**: S1~S6a·S5-lite·S4·S3(등가성 판정) 완주. **probe 랜덤 read 소멸 실증**(강제 Grace에서 카운터 0, readkeys 5,119,999 유지). 스필 경로 DB volume 고정(D-SP1, `$CUBRID_TMP` 분기 제거)·boot sweep 게이트 포함.
- **성적표(병렬, develop 512M 대비)**: outer_join 4M 0.94×/64M 0.97×(캠페인 전 1.59)/256M 1.29×(2.25), wmmid 1.00~1.18×, heavy_distinct·group_wide 다수 셀 develop 추월, order_wide 무변화(별개 기전). 운영 결론: "기본 64M, heavy 256M" 안전. 정본 기록 = #142.
- **#149 (스트리밍 hjoin, 사용자 승인됨)**: P-트랙 진행 — P2·P3(pull 스트리밍) 착지. 256M 대칭 열세 완전 분해 완료. **order_wide는 develop 동등 도달 비현실적 판정(w5 구조 잔여) — 목표 재조정 필요.** 이후 #142에 D-트랙(raw-fd sort run, sort_run_flush prefetch 등 정렬 회수) 커밋 진행 중 — 마무리 스크립트가 정리 예정.
- **#150 (신규)**: sq_cache hit-ratio 0-나눗셈 SIGFPE — pre-existing, develop에도 존재. `ready-for-human`(upstream 보고/백포트 후보).

## 2. 사람 결정 대기 (자율 착수 금지)

| 항목 | 내용 |
|---|---|
| #148 YCSB | 스펙 완성(≈18M rows ≈ 20GB, 측면당 디스크 ~45GB). load 미수행. 실행 시점 = 사용자 재지시 시 |
| T3 R | agg 파티션-재귀 재설계 — 정지 유지 |
| order_wide 목표 | develop 동등 비현실 판정에 따른 목표 재조정(수용/정렬 트랙 신설) |
| #150 | upstream 보고/백포트 여부 |
| #149 잔여 | P5(px split 스트리밍)+DISTINCT 수정 진행 여부 — 마무리 스크립트 결과 확인 후 |
| 기존 보류 | #113, #145, #33~35/52~56/58/59/61 |

## 3. 운영 규칙 추가분 (v5 §4에 누적 — 전부 실사고)

1. **서브에이전트 유휴 알림 소음**: 리드가 워커를 유휴 상주시키면 idle_notification이 사용자 앱을 도배 — 임무 종료 워커는 즉시 종료, 장대기는 유한 foreground로.
2. **IME Enter 함정 상시 재발**: 사용자 미전송 텍스트 발견 시 C-u→`send-keys -l` 재주입→Enter가 supervisor 표준 절차(본 세션에서 4회 수행). 사용자 안내: 조합 후 Space/Esc→Enter.
3. **워처 재기동은 반드시 추적형**(`run_in_background`) — `&`+disown은 종료 통지가 없어 금지. pkill은 `'sup_watch[.]sh'` 브래킷 패턴으로 self-match 회피.
4. **백그라운드 측정 완료가 리드를 못 깨우는 사례** 1회 — 산출물 파일(mtime/행수)로 완료를 직접 판정하고 리드를 깨울 것.
5. conf 리셋 근본 원인 확정: 소스트리 conf 템플릿 `work_mem=2M`이 install마다 덮어씀.
6. 사용자가 리드 pane을 직접 운전하는 동안 supervisor 주입 금지(미전송 텍스트 보존 — 필요 시 캡처→전달→복원).

## 4. 인수 직후 체크리스트

1. `tmux capture-pane -t fable -p | tail -30` — 마무리 스크립트 결과·질문 대기 확인.
2. `gh issue view 147/149/142 --comments` 최근 코멘트로 P-트랙·D-트랙 최종 상태 파악.
3. 감시 재개 필요 시 sup_watch.sh 대상 갱신 후 추적형 재기동.
4. 사용자 보고는 "진짜 멈춤/사람 판단 지점/최종 성적표"만 — 주기 상태 보고 금지(사용자 지시).
