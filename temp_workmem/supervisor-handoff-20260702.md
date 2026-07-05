# temp-workmem 캠페인 Supervisor 핸드오프 (v4 — 2026-07-03 저녁, 이전판 전면 대체)

> **용도**: supervisor 세션 재시작/컨텍스트 압축 대비 완전 핸드오프. 이 문서 + SSOT(#75 본문)만 읽으면 즉시 인수 가능해야 한다.
> **역할**: xmilex-git/cubrid 이슈 트래커의 supervisor — dispatch·리뷰·판정·의존성 정리. 구현은 워커, 판단은 supervisor.
> **착지 현황 정본 = SSOT #75 §2.** 이 문서는 델타·판단·운영 상태만.

---

## 0. 좌표·인프라

| 항목 | 값 |
|---|---|
| 이슈 트래커 | `gh ... --repo xmilex-git/cubrid` |
| 엔진 체크아웃 | `~/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, 원격 `xmilex`. **tip @ 이 문서 시점 = `62fc99923`(#127 머지+race fix). develop 47fcc321f 흡수 완료** |
| 툴링 레포 | `~/dev/workspace` — 워커 착수 시 `git -C ~/dev/workspace pull` 필수 |
| SSOT | 이슈 **#75 본문**(append 금지, 본문 편집+로컬 미러 `temp_workmem/issue65_ssot.md` 동기화) |
| Evidence | 이슈 #76 + 로컬 미러 `issue65_evidence.md` (최신 K-11까지) |
| 워커 호스트 | 로컬 tmux `fable` / ssh cubrid@**192.168.6.30**(측정 픽스처) · **.32**(podman rootless) · **.33** |
| 빌드/서버 | cubrid-build 스킬 + `just conf`(빌드마다 리셋 — 재적용 필수), 서버는 cubrid-server-control 래퍼만 |
| 스크래치 | `/tmp` 금지 → `$WORKSPACE/.claude/scratch/` 또는 `~/dev/workspace/.not_git_tracking/scratch/` |
| 골든 | PHJ `<200000`=200360 / `<2000000`=2000495 (tpch_sf10), wmloc DISTINCT=4194304/8796090925056/0/4194303. 중첩HJ md5=d2f407f1 |
| PG 참조 | `~/dev/postgres` (nodeHash.c — #123이 차용 완료) |
| upstream develop 머지 목표 | `47fcc321f6117db77246b6219ca386b169295e31` (#127, .33 진행 중) |

**supervisor 운영 함정**:
- `gh --body`는 반드시 `<<'EOF'` heredoc. 프로세스 치환(`<(...)`)은 이 샌드박스에서 실패 — 임시 파일 사용.
- **원격 claude 기동은 반드시 `cd ~/dev/workspace` 후**(tmux `-c`로 지정) — 아니면 프로젝트 설정/스킬/CLAUDE.md를 못 읽는다.
- **tmux 주입**: C-u → `send-keys -l "<프롬프트>"` → Enter → capture로 소화 확인(ctx 증가/esc to interrupt), 유실 시 재주입. .30은 긴 프롬프트를 scp 파일(`~/task_NNN.md`)로 올리고 "파일 읽고 수행" 단문 주입(`~/rc_claude_launch.sh`로 기동, 토큰 파일 `~/.rc_tok`). .33은 `claude --dangerously-skip-permissions` 직접 기동 가능.
- **401 트러블슈팅(.30)**: stale `~/.claude/.credentials.json`이 env 토큰을 덮음 → `.bak` 치우기 / tmux kill-server 재기동 / 진단은 `claude -p "say ok"`.
- **세션 정책(2026-07-03 사용자 지시로 강화)**: 새 작업 = **세션 kill 후 재기동**(자족 프롬프트) — `/clear` 재사용 금지, tmux kill-session(또는 kill 후 new-session)으로 컨텍스트 완전 격리. 직계 후속만 세션 재사용(#111←#120b, #126←#123, #127잔여검증←#127 선례). supervisor가 워커 컨텍스트 관리를 능동 수행(장기 세션 ctx 비대 감지 시에도 자연 경계에서 kill+핸드오프 재기동). 모델: 명세 실행형=sonnet / 가드·계약·triage=opus / 불변식·R1급=Fable.
- 입력창의 미전송 텍스트는 사용자 것이 아님 — supervisor가 지우고 관리(실사례: .33 "#110 close" 지시문 제거 후 supervisor 직접 처리).
- **로컬 fable 슬롯의 토큰 소진 시 계정 전환은 사용자가 직접 수행**(2026-07-03 사용자 지시) — supervisor는 자동 회전 시도 금지, 소진 감지 시 보고만.

## 1. 캠페인 현 국면 (2026-07-03 저녁)

**Phase3-prep 사실상 완료.** 게이트 3종 기본 ON(`ceb8997e8`) 세계에서 blocker 전부 해소:
- blocker ①(클라이언트 전송 materialize 의존): #120a+#120b(overflow 번역)로 해소, #120 close.
- blocker ②(P2 잔여 3사이트): #117/#118/#119로 해소.
- Class-B 싱크 3종 정리 완료: client fetch(#120 직독)·holdable(#111 zero-copy reparent, ADR 0001 복원)·캐시(#121 Tapeset-source 단일 복사). **`qmgr_materialize_to_pgbuf`는 캐시+overflow/holdable+cacheable/raw-fd 전용 폴백으로 축소.**
- perf 회수: #101(HYBRID 해제, ~557×)+#123(HASH_FILE→PG spill, 4.3×, fhs는 #74 삭제 목록 편입)+#110 close(발동 집합 소멸).

**남은 관문**: #127(develop 머지) → #81 sweep 경량 재실행(머지 후 트리 기준) → **#74 재상신(사람 승인 — 자율 진행 금지)**.

## 2. 남은 일

```
[크리티컬 패스 → #74 재상신]
~~#127 develop 머지~~ ✅ 착지·close(`1dfcef7a7..62fc99923` = M/M2/fix + race-fix). 귀속 정정 = K-12(#123 latent race, merge 무혐의). wm-127-merge-hold 원격 브랜치 삭제 완료.
  ~~#81 sweep 경량 재실행~~ ✅ 완료(.32) — 판정 **조건부 CLEAR**(C1 connect_list 신규 소비처 교체 선행 / C2 raw-fd 순수 삭제 불가·OLD 티어 스필 백킹 대체 결정 / C3 OLD-입력 병렬 정렬 직렬 폴백 / C4 fhs_hash 제외). 정정 3건(first_vpid 보존, materialize 부분 삭제, #113 폴백 존치) + #110 가드 신규 등재. **#74 개정 코멘트로 편입 완료.**
  ~~런타임 검증(62fc99923)~~ ✅ 전 항목 PASS → ~~#74 재상신~~ ✅ **사람 승인 접수(2026-07-03 밤): Phase3 진행, 모델별 dispatch. 단 C2는 (a)(b) 기각 — (c) BufFile 백킹 타당성 분석 지시(사용자 원안)**

[Phase3 실행 트랙 (진행 중)]
~~#128 Phase3-1 C1 소비처 교체~~ ✅ 착지(`39166b84b`, 리뷰 통과·close)
~~#131 Phase3-4 connect_list 본체 삭제~~ ✅ 착지(`9f8e54c80`, -233줄, 리뷰 통과·close)
~~#132 Phase3-5 (c′) 병존 착지~~ ✅ 착지(`ad351c91a`..`a8c68e633` 3커밋, 리뷰 통과·close — RAWFD/NONCE selftest 선재FAIL은 record-only 처분, 캠페인 의존 금지)
~~#133 Phase3-6 채증 캠페인~~ ✅ 통과·close(절체 판정 게이트 4종 충족 — #126 재현 25회 무오차 = 커밋 C 전제 증거 확보)
~~#135 커밋 A~~ ✅ 착지(`dc59b4789`, ±13줄, 리뷰 통과·close — 기본 세계 = page_spill, opt-out escape hatch 실증)
~~#136 soak~~ ✅ 통과·close(gate ON/OFF 대조 FAIL 집합 바이트 동일 — spill 귀속 0, 17,420케이스×2런 코어 0)
~~#137 커밋 B~~ ✅ 착지(`1c1299a6c`, 순감 -3,256줄, 리뷰 통과·close — raw-fd 기판 소멸, PHJ 전략 개선 18.6s→7.4s 관측=EXIT 긍정 신호)
~~#138 Phase3-10~~ ✅ 착지(`f9f4d2f8e`+`945f1058c`, 리뷰 통과·close — 삭제 집합 전량 완료, 죽은 스위치 실증)
#139 Phase3-EXIT 재측정 ✅ 데이터 수집 완료(.30 — K-11 회수 2.99→2.07×/1.44→1.25×, heavy DISTINCT 1.018× 충족, group_wide 0.953× 충족, **order_wide 1.17×·write 1.94× 미분리** + 하네스 정리 `9146b2dd6`)
~~#140 order_wide 분해~~ ✅ 귀속 (b) 확정·close(K-13 — 스필 기계 무결, cap 64MiB 고정 발견)
**→ 캠페인 종결(2026-07-05): 사람 승인(①②) → #74/#78 close. w5 이관=#141, 성능 종합=#142. 4슬롯 유휴 — 다음 dispatch는 사람 지시 대기(잔여: #141, #33~35/58, #113 upstream, #52~56/59).**
~~#134 Phase3-5fix~~ ✅ 착지(`17d95dbda`, +10줄, 리뷰 통과·close — product 무결함, selftest env-coupling. #133은 TEMPMOVE c-leg만 재실행 + env 위생 경고 전달됨)
~~#129 Phase3-2 fhs 삭제~~ ✅ 착지(`635eec6e2`, -2,586줄, 리뷰 통과·close)
~~#130 Phase3-3 sector 삭제~~ ✅ 착지(`88a9b46f7`, -1,275줄, 리뷰 통과·close — C3 폴백이 #99 가드 대체)
~~(c′) coherence 설계~~ ✅ 리뷰 통과(#74 정본 — 옵션4 강하 불요, 구현 착수 승인). #132 Phase3-5 병존 착지 dispatch(fable).
~~C2-(c) 분석~~ ✅ **(c′) 채택**(#74 처분 코멘트): buffile 클래스 직접 백킹은 하드 블로커 2건(append-only·페이지캐시 부재)으로 불가 → 파일 기판 공유 + random-page 변종 + per-tfile 캐시. 조건 ①병존 게이트 후 절체 ②#126 가드는 재현 PASS 채증 후 제거 ③coherence 설계 리뷰 선행. 옵션4(축소판) = 2순위 보존. `qmgr_list_has_raw_fd_segments` 11사이트는 존속·개명으로 정정.
  → 착지 후: (c′) coherence 설계 리뷰 → (c′) 병존 구현 → 절체·raw-fd 삭제 → EXIT 재측정(K-11 픽스처 3종)

[병행/가드 트랙]
~~#126 raw-fd 동시 스캔 가드~~ ✅ 착지(`1dfcef7a7`, 리뷰 통과·close — 가드 제거는 #74 이관 완료)
~~#125 BufFile fd 위생~~ ✅ 착지(`fcc4aac81`, 리뷰 통과·close 2026-07-03 저녁)

[사람 판단 대기]
#74 Phase3 CONTRACT (sweep 후 재상신)
#113 upstream PR (ready-for-human)

[보류(캠페인 무관)]
#33/34/35/58 (perf 별도 트랙), #52~56/59 (사람 판단), #61 (안 하기로)
```

Phase3 본체(#74 승인 후): #81 sweep 삭제 집합 + membuf 강제OFF(H-4) + external_sort raw-fd 직렬 가드 + **fhs 기계(#123 편입)** + **#99/#110 직렬 안전망 가드(#110 close 시 이관)** + **#126 임시 가드(착지 시 이관 예정)**.

## 3. 착지 이력 (2026-07-03분 — 전부 supervisor 리뷰 통과·close)

`ceb8997e8` #80 게이트 기본 ON → `c447d929b` #117 → `b78578bad` #118 → `9232882ef` #119(+#112) → `c1044fd5c` #120a → `61e65c18e` #122 → `475e0ad6d` #101(HYBRID 해제, pread 0.15~0.76/probe — D2 재론 불요 판정) → `712c7243c` #124(픽스처 3종 — 함정⑩ 해제; develop 대비 관찰 = K-11) → `2fafae2be` **#120b**(overflow 번역, R1 핵 — #120a "overflow 생산 불가" 오판 정정 = K-10, census 카운터 `Num_qfile_client_fetch_serve/materialize` 신설) → `0a4ea9ca9` **#121**(캐시 copy-out Tapeset-source, 이중→단일 복사; **#110 동반 close**) → `6b3d5775a` **#123**(accountant+`hls_spill`, #126 발견 부산물) → `ab3052e2b` **#111**(holdable zero-copy reparent, ADR 0001 개정 `8fb828a`) → `fcc4aac81` **#125**(BufFile fd 위생 — EMFILE/ENFILE 매핑+RLIMIT 부트점검, VFD 계층 기각 D4) → `1dfcef7a7` **#126**(raw-fd 동시 스캔 직렬 강등 가드 — NEW 무접촉, 제거는 #74 이관) → `62fc99923` **#127**(develop 47fcc321f 머지 M/M2/fix + #123 latent race 정공 수정 — 귀속 정정 K-12, per-context HLS_SPILL_CURSOR). 부수: `127abc87c` #113 cherry-pick, `a8bfe6813`/`8e70769b0` #115/#116.

## 4. 재론 금지 판단 기록 (근거는 각 이슈 코멘트)

1. **#120**: (A) 합성 VPID 송출 채택 — materialize는 폴백 존치(#74 sweep 전 삭제 금지). D2 번역 = 상수 base(`base_gp = gp − local_offset`), 헤더-전용.
2. **#111**: zero-copy reparent = 기존 포인터 이동 기계 위 2점 수술 — 신규 기계 불요가 정답이었다(P12 절차의 성공 사례).
3. **#121**: 캐시 copy-out의 overflow 폴백은 정답(PEEK 튜플 스캔은 run 조립 불가) — COPY-모드 확장 금지.
4. **#126**: **가드-우선** — 근본 원인(raw-fd read_cache 동시성) 수정 금지, 기판이 Phase3에서 삭제됨. NEW 경로 오탐 금지.
5. **#127 충돌 생사 원칙 P1~P5** (이슈 코멘트 정본): P1 동일-출처 중복=upstream 채택 / P2 재설계 소유 구역=ours / P3 upstream 수정이 OLD에 오면 살리되 NEW 필요성 판정(무음 분기 금지) / P4 의미 충돌=stop-and-report / P5 merge는 merge만.
6. **fd 검토(2026-07-03, supervisor 직접)**: OLTP fd churn 우려는 구조적으로 해소돼 있음(lazy-create: work_mem 내 질의는 open 0회, 스필 tape당 fd 1개, ADR 0005). 실결함 = NEW 경로 EMFILE 미매핑 + RLIMIT 부트 점검 부재 → #125. VFD 계층 신설은 과설계로 기각.
7. #118 analytic 출력 OLD 유지 판정, E-1(#101=(a)만, use_original 폐기), deep interview 취소 등 — v3 이전 기록은 SSOT §3와 각 이슈 참조.

## 5. 현재 4슬롯 배치 (2026-07-03 저녁)

| 슬롯 | 작업 | 모델 | 유의 |
|---|---|---|---|
| `fable` | **유휴** (#143 설계 완료 — 검수 통과) | Fable | 다음: S2(이동) 후보 |
| — | **#143 진행 상태**: 설계✅ → 결정 확정(R1 rename승인·R2 통일·R5 spill_file 유지·R7 주석 영어화+이슈번호 제거=S5 신설·R8 **PGBUF**) → ~~S1+S1b~~ ✅ 착지(`c58f6d159`+`8b66a43aa`, 게이트 6종 green — A/B 1.003×/1.002×) → ~~S2~~ ✅ 착지(4커밋 `893184160`..`0c6233cf1`, M7 드랍 승인) → ~~S3~~ ✅ 착지(`ab5ce81a9`) → **S4 실행 중(.32 opus)** → S5(주석 정규화) 대기 | — | 게이트 6종/슬라이스, #142가 성능 기준선 |
| `.32` | **#143 S4 핫스팟+죽은분기** (새 세션, `~/task_143_s4.md`) | Opus | 방어 assert 보존, 억지 추출 금지 |
| `.33` | **유휴** | opus | **주의**: `/home/cubrid/dev/cubrid` 워크트리 detach 상태. backup ref `backup/wm-integ-leftover-20260702`는 미커밋 작업물 아님(#105 트리 원복 누락 잔상 — #127 코멘트 판독 기록). 다음 정리 때 ref 삭제+워크트리 재정렬 |
| `.30` | **유휴** (S3 착지 `ab5ce81a9` — 리뷰 통과) | Sonnet 5 | 다음 dispatch 대기 |

*상태 확인*: `tmux capture-pane -t fable -p | tail -30` + `for h in 30 32 33; do ssh cubrid@192.168.6.$h 'tmux capture-pane -t claude -p | tail -25'; done` + `git -C ~/dev/cubrid-workmem fetch --all && git log --oneline -8 xmilex/wm-integ-7173-develop` + `gh issue list --repo xmilex-git/cubrid --state open`

## 6. Supervisor 다음 액션 (보고 도착 순서대로)

1. **리뷰 체크리스트(전 건)**: fail-before-fix / debug+release+cubrid_rel / fetch --all+rebase / 트리 원복·데몬 정리 / evidence(사실 변경 시) / diff 스팟체크 / close 정당성(close는 supervisor 소관 — 워커 close 금지 리마인드).
2. **#127 리뷰(도착 시 최우선)**: 헝크별 판단 기록(P1~P5 부합) + 중복 커밋 대조 목록 + 유닛/selftest/parity 스모크 + 게이트 opt-out 대조. 통과 시 → **#81 sweep 경량 재실행 dispatch**(fable 또는 유휴 슬롯, read-only, 머지된 트리 기준으로 #74 삭제 집합 재확인 + materialize 축소·holdable OLD 의존 소멸·fhs 편입·#110/#126 가드 이관 반영).
3. **#126 리뷰**: 가드 범위가 NEW 무접촉인지, 발동 카운터/로그, 20회 무오차. 착지 시 가드 제거 항목을 #74 체크리스트에 이관 확인.
4. **#125 리뷰**: EMFILE fault-injection fail-before-fix + RLIMIT 부트 경고. 통과 시 close.
5. sweep green → **#74 재상신**(사람 승인 대기 — 자율 진행 금지). 상신 자료에 K-11(develop 대비 픽스처 회귀 관찰) 포함.
6. 착지 이벤트마다 SSOT(#75 본문+미러)·이 문서 갱신. evidence는 K-12부터 이어서.

## 7. 워커 dispatch 정본 규칙 (프롬프트에 항상 포함)

- 런타임 검증 필수: workspace pull → 엔진 fetch --all+rebase → debug+release 빌드+cubrid_rel 기록 → just conf 재적용 → 래퍼 기동. "환경 결함으로 검증 미완 close" 금지. fail-before-fix 필수. **이슈 close 금지(supervisor 소관) + 완료 보고는 반드시 이슈에 게시**(터미널 출력만으로 종결 금지 — #121 실사례).
- 함정(SSOT §5-6 ①~⑩) 핵심: ④게이트 기본 ON(env `=0`이 opt-out) ⑥재빌드가 conf 리셋 ⑦stop이 master 미종료 ⑧kill-9 재기동 env 비상속 ⑨측정 중 just build 병행 금지 ⑩해소됨(#124) — 픽스처 3종 사용 가능(단 connect_by는 병렬 가드 수동 우회).
- 판정: robust 집계 + `;trace` + NEW-engagement 카운터 delta + client-fetch census 카운터(`Num_qfile_client_fetch_serve/materialize`). R1급 검증은 클라이언트-가시.
- 커밋 태그 `[temp-workmem <slice>] ... (#이슈, #78, #73)`. 완료 시 한글 보고 + 트리 원복. 10분+ background, 슬롯 완료마다 1줄 보고.
- 억지 구현 금지: "안 하는 게 정답"도 유효 종결(#118), 범위 초과는 stop-and-report(#120/#126 선례).

## 8. 유지 교훈

오진도 "확정" 기록을 이긴다(#99, #120a 오판 정정=K-10) / 완성품 우선 착지(#95) / 이론적 창은 도달가능성 검증부터(P12 — #111 성공 사례) / stop-and-report가 R1 사고를 막는다(#120, #126) / dispatch는 전달 확인까지 / 사실 변경은 즉시 SSOT 본문 수정(append 금지) / 계측 사고는 카운터로 구조 대체(gdb 코어 2회 → census 카운터).
