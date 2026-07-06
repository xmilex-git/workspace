# Supervisor 핸드오프 v5 (2026-07-06 — 이전판 supervisor-handoff-20260702.md 전면 대체)

> **인수 방법**: 이 문서를 읽고 "supervisor mode로 동작하라". 모델 opus 이상이면 충분(업무 = dispatch·리뷰·판정, 구현은 워커).
> **역할**: xmilex-git/cubrid 트래커의 supervisor. 워커가 이슈에 보고 → 리뷰(스팟체크) → close(supervisor만) → 다음 dispatch. 사람(사용자) 결정 사항은 절대 자율 진행 금지.

## 0. 좌표·인프라

| 항목 | 값 |
|---|---|
| 이슈 트래커 | `gh ... --repo xmilex-git/cubrid` |
| 엔진 체크아웃 | `~/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, 원격 `xmilex`. **tip @ 문서 시점 = `855771c8b`** (#144 P3 D2) |
| 툴링 레포 | `~/dev/workspace` (원격 github.com/xmilex-git/workspace). **커밋 후 반드시 `git push origin main`** — 로컬 커밋만 하면 워커 pull에 안 보임(38커밋 미push 실사고, 07-06) |
| develop 대조군 | `47fcc321f` (= 11.5.0.2295). .30/.32에 baseline 설치본 잔존 가능 |
| PG 참조 | `~/dev/postgres` (로컬 전용 — 원격 워커엔 없음) |
| 워커 슬롯 | 로컬 tmux `fable`(Fable 모델) / ssh cubrid@**192.168.6.30**(sonnet, `~/rc_claude_launch.sh`+`~/.rc_tok`, 측정 픽스처 호스트: wmloc/wmwide/t DB 보유) · **.32**(opus, podman/ctp-parallel 가능) · **.33**(opus) |
| SSOT | 이슈 **#75 본문**(append 금지, 본문 편집 + 로컬 미러 `temp_workmem/issue65_ssot.md` 동기·push) |
| Evidence | 이슈 #76 + 미러 `temp_workmem/issue65_evidence.md` (K-13까지) |
| 설계문서 | `temp_workmem/CONTEXT.md`(+#143 신구 용어 부록)·`temp_workmem/docs/tape-model.md`·`docs/adr/0001~0006` — **툴링 레포 소속**(엔진 아님!) |
| 성능 정본 | **#142**(최종 배율표+재현 퀵스타트 — 새 측정 시 여기에 코멘트 누적) |
| 빌드 | cubrid-build 스킬, `WORKSPACE=~/dev/cubrid-workmem just build debug|release` + **`just conf`(재빌드마다 리셋 — 재적용 필수)**. 서버는 **cubrid-server-control 래퍼만**(raw `cubrid server`는 파이프에서 행) |
| 골든 | outer_join md5 `5ff2e5975ce998206119d472b2f7f65e`(+readkeys 5,119,999) / 2-analytic `3cf70016…`(S4 승격판) / DISTINCT `c3435c50…` / CTE `0108e87b…` / UNION `81be5531…` / agg-DISTINCT(wmloc.t) `4194304/8796090925056/0/4194303` / wmmid parity(중형 조인) |

## 1. 완료된 큰 덩어리 (재론 불요 — 상세는 각 이슈)

1. **temp-workmem 재설계 캠페인** (#73/#74/#78, close): 옛 구조 전량 삭제(connect_list·fhs·sector·raw-fd 레지스트리·게이트 3종·가드류, 순감 ~7,300줄), OLD 스필은 (c′) page_spill(per-tfile 캐시, 사용자 아이디어)로 대체. EXIT 측정·사람 승인 완료.
2. **인지복잡도 리팩토링** (#143, close): S1~S5 — OLD/NEW→**PGBUF/TAPESET** 명명(카운터 `Num_qfile_tapeset_create`/`Num_qfile_pgbuf_touch_on_tapeset`, env `CUBRID_WM_*`), selftest TU 분리·회계 `query_workmem.{cpp,hpp}` 분리, 브리지 축소, 핫스팟 추출, 주석 영어화(이슈번호 제거). 전 슬라이스 동작보존 게이트 통과.
3. **성능 회수 로드맵** (#144, close): 착지 = P1-2 리더 per-scan LRU(`6af3965ae`) + P3 D1 cap정책(`936850f83`, `cap=clamp(min(max(work_mem,db/8),db/2),64M,4G)`)+D2 빌드 아레나(`855771c8b`). **중형 해시조인 −40%**(wmmid 픽스처 커밋), outer_join 2.91→2.42×. 반증 종결: P2(런 축소=손해)·P3단독(malloc 폭풍). 드랍: P1-3.

**성능 격차의 확정 인과**(사용자에게 설명 완료): develop은 512M pgbuf 풀을 temp의 **무회계 공짜 캐시**로 씀 / 신판은 동접-안전 예산+직접 파일. outer_join 잔여(2.42×)·order_wide(1.44×)는 이 구조 귀속(#141). 본질 해법 = **#91 탄력 예산(유휴 시 대여·동접 시 회수)** — 미착수 과제.

## 2. 진행 중 (인수 즉시 확인)

- **#141 심화 분석 — fable에서 실행 중** (task = `.not_git_tracking/scratch/task_141_analysis.md`, 분석 전용·무커밋):
  - Part A: PG(~/dev/postgres 원전)의 접근 검토 — per-op 정적 work_mem + OS 페이지캐시 신뢰 + **스필 HJ의 probe측 배치 재파티셔닝**(우리 hls_spill은 probe가 랜덤 탐색 — 이 차이가 outer_join 스필 경로의 정공 후보인지 판정 요구).
  - Part B: 머지 memmove(order_wide 본체) — develop의 `use_original`/`A_sort_key` 기계 규명, E-1("use_original 폐기") 재론 조건(현재는 raw-fd 소멸+리더 LRU 존재) 검토, 대안 비교.
  - **보고가 #141에 오면**: 리뷰 → 사용자에게 요약·권고 제시(구현 착수는 사람 결정 사안일 가능성 높음 — 재설계급 제안 포함 예상).

## 3. 사람 결정 대기 (자율 착수 금지)

| 이슈 | 내용 |
|---|---|
| #141 | w5 구조 회수 — fable 분석 결과 나온 뒤 방향·우선순위 결정 |
| #145 | scan→sort 파이프라인 융합 설계(저우선) — 착수 승인 게이트 |
| #91 재론 | 탄력 예산(escape hatch ③) — 이슈 미개설, 필요 시 설계 이슈로 |
| #113 | 병렬 merge join 무음 행누락 — upstream 보고 후보(ready-for-human) |
| #33~35/58, #52~56/59/61 | 기존 보류 트랙 |
| 후속 선택(기록만) | 문자열 리터럴 내 이슈번호 13건(하네스 마커 동기 필요), #143 M7 대블록 이동 |

## 4. 운영 규칙 (전부 실사고 기반 — 위반 시 재발)

1. **세션**: 새 작업 = tmux **kill 후 재기동**(자족 task 파일 + "너는 이 호스트의 실행 워커다" 서두 필수 — 역할 오해 실사례). 직계 후속만 세션 재사용. `/clear` 금지.
2. **dispatch = 전달 확인까지**: 주입 후 "esc to interrupt" 활성 확인(미확인 방치로 1시간 유실 실사례). 긴 프롬프트는 scp task 파일 + 단문 포인터.
3. **한글 IME**: 입력창 미전송 텍스트는 Enter가 안 먹음 — **C-u로 지우고 `send-keys -l`로 재주입 후 Enter**. 미전송 텍스트는 supervisor가 지우고 관리.
4. **push**: 툴링 레포 커밋 후 즉시 `git push origin main`. 워커 착수 규칙은 `git -C ~/dev/workspace pull`.
5. **워처**: `.not_git_tracking/scratch/sup_watch.sh` — 상단·중단 2곳의 `for n in ...`에 감시 이슈번호 갱신 후 `run_in_background`로 실행(추적형이어야 종료 시 재호출됨). **pkill과 기동을 같은 명령에 섞지 말 것**(자기 래퍼 self-match 자충수 실사례). 자기 코멘트에 오발하면 baseline 갱신 후 재기동.
6. **워커 close 금지**(supervisor 소관), 완료 보고는 반드시 이슈 게시. fail-before-fix / debug+release+cubrid_rel / 트리 원복·데몬 정리 / stop-and-report 관행 유지.
7. **성능 판정 = 동일호스트 A/B 비율**(콜드 3회 중앙값, ≤1.05), 절대치 대조 금지(픽스처 물리 배치 편차 실사례). outer join 판정엔 readkeys 동반(K-12 — LEFT-outer 허위 안전).
8. **대량 rename/이동/주석 변경은 기계 검증기**: `contrib/scripts/rename_wm143_s1.py`(재현 스크립트), comment-only 토큰-diff 검증기(`.claude/scratch/wm143s5/comment_only_diff.py`) 선례.
9. **토큰**: fable 소진 시 계정 전환은 **사용자 직접**(자동 회전 금지, 보고만). .30은 `~/.rc_tok`. 한도 다이얼로그에 걸리면 Escape 후 재개 메시지.
10. **함정(불변)**: 재빌드가 conf 리셋 / `cubrid server stop`이 master 미종료(`cubrid service stop`까지) / kill-9 재기동 env 비상속 / 측정 중 빌드 병행 금지 / **/tmp 금지**(엔진 `.claude/scratch/` 또는 `~/dev/workspace/.not_git_tracking/scratch/`) / 좀비 데몬은 소유 확인 후 개별 SIGTERM / 무한 폴러 금지(완료 감지는 유한 루프).

## 5. 슬롯 현황 (문서 시점)

| 슬롯 | 상태 |
|---|---|
| `fable` | **#141 심화 분석 실행 중** (07-07 주간 리셋 직후라 여유) |
| `.30` | 유휴 (측정 DB 보유: wmloc 5.12M·wmloc.t 4.19M·wmwide 재구성분) |
| `.32` | 유휴 (#144 완주. dev47 baseline·신판 설치본 잔존) |
| `.33` | 유휴. 잔무: backup ref `backup/wm-integ-leftover-20260702` 삭제 + `/home/cubrid/dev/cubrid` 워크트리 재정렬(내용은 #105 잔상 — #127 코멘트에 판독 기록) |

## 6. 인수 직후 체크리스트

1. `gh issue list --repo xmilex-git/cubrid --state open` + `git -C ~/dev/cubrid-workmem fetch --all && git log --oneline -3 xmilex/wm-integ-7173-develop`.
2. `tmux capture-pane -t fable -p | tail -20` — #141 분석 진행/질문 대기/보고 완료 확인. 질문 대기면 규칙 3으로 응답.
3. 워처 재가동(대상 #141): 규칙 5.
4. #141 보고 도착 시: 리뷰(주장마다 file:line 근거 확인) → 사용자에게 요약 + 결정 요청 제시.
