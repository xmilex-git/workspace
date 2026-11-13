# CUBRID/cubrid-admin 소비자 관점 리뷰 보고서

**저장소:** [CUBRID/cubrid-admin](https://github.com/CUBRID/cubrid-admin) (develop `e33ad38`, 2026-11-03, 표시 버전 v0.1.0-alpha.1)
**검증 대상:** 패키징 실행파일 `cubrid-web-manager-linux`(README 방법 B) + Electron 35.7.5 데스크톱
**CMS 대상:** 11.4.6 공식 빌드(CMS 8222274b) / 엔진 develop `be0a9ab1f` + 고정 CMS `5a30b8c` / 같은 엔진 + CMS develop `d58cc10`
**리뷰 일시:** 2026-11-05
**리뷰 결정:** (grill 후 기입)

> **TL;DR** (Blocking): 11.4.6에서는 백업, 복구, HA 페일오버, 생성, 이름 변경, 복사, 언로드가 실제로 동작한다. develop은 엔진이 고정한 CMS로는 DB 로그인부터 실패하고, CMS develop 최신을 넣어야 동작한다. 소비자 화면에서는 폐쇄망 아이콘 깨짐, 1366px 이하에서 로그아웃 버튼 밖으로 밀림, 설정 편집기 줄 번호 고장, HA 상태 오표시가 막는 항목이다.

## Summary

- **버전 지원**: 코드는 11.0-11.4와 11.5(develop)를 모두 겨냥한다(`param-schema` 의 `minVersion`, 비동기 작업 폴백). 11.4.6은 동작, develop은 CMS 최신 필요.
- **주요 이슈**: 외부 CDN 폰트 의존(웹, 데스크톱 모두), 최소 폭 약 1660px 레이아웃, 편집기 줄 번호, HA 상태 표시, 가짜 버전 표시.
- **확인 필요 사항**: 11.4.x CMS의 계정당 단일 세션 제약을 제품에서 어떻게 안내할지, 엔진 develop의 cubridmanager 서브모듈 갱신 주체.

---

## Version Support

| 대상 | DB 로그인 | 대시보드 | 백업/복구 | 비동기 작업 | 판정 |
|---|---|---|---|---|---|
| 11.4.6 (CMS 8222274b) | 성공 | 정상 | 백업 L0 -> 중지 -> 복구 -> 시작, 백업 후 만든 테이블 사라짐 확인 | 미지원, 동기 폴백(polls=0) | 지원 |
| develop + CMS `5a30b8c` | 실패 | 정상 | DB 로그인이 막혀 진행 불가 | - | 미지원 |
| develop + CMS `d58cc10` | 성공 | 정상 | 백업, checkdb 성공 | `gettaskstatus` 폴링 동작(polls=1-2) | 지원 |

- develop 실패 원인: CMS `5a30b8c` 의 `dbmtuserlogin` 이 `SET{t.g.name} ... TABLE(groups)` 를 실행하고, develop 엔진은 `t.g is a varchar type, not an object type` 로 거부한다. CMS develop은 버전별 쿼리로 고쳤다(`cm_job_task.cpp:10964`). 웹 매니저 결함이 아니라 엔진 develop의 서브모듈 고정이 낡은 것이다.
- 11.4.x CMS 세션 제약: 같은 CMS 계정으로 두 번째 로그인하면 첫 토큰이 무효가 된다(`allow_user_multi_connection=YES` 에서도). curl 재현: 28101/28102 `Request is rejected due to invalid token`, 28103(CMS 최신)은 둘 다 유효. 웹 매니저 사용자 둘이 `admin` CMS 계정을 공유하면 서로 "Connection Lost" 로 끊는다.

## Findings

### Blocking (must fix)

1. **폐쇄망에서 아이콘이 글자로 깨짐** (`apps/web-manager/index.html`): Material Symbols, Inter, JetBrains Mono를 `fonts.googleapis.com` 에서 받는다. 차단하면 `expand_more`, `dark_mode`, `logout` 같은 글자가 버튼 자리에 찍히고 HOST LIST 툴바 버튼끼리 겹친다(shots `02-home-offline`). 데스크톱 앱도 첫 화면에서 `fonts.gstatic.com` 을 요청한다. 폰트를 번들에 포함해야 한다.
2. **1366x768, 데스크톱 기본 창에서 로그아웃이 화면 밖** : 사이드바 440px 고정에 본문 최소 폭 1221px라 `main` 이 가로 스크롤된다(1366: scrollWidth 1221 / clientWidth 926). 상단 메뉴바도 함께 스크롤되어 사용자 메뉴와 Logout이 잘린다. Electron 기본 창(1280x772)에서도 같다(shots `18-dashboard-1366x768`, `el-02-dashboard-default`). 가로 스크롤바 자체는 창 맨 아래에 보이며 세로 스크롤 끝까지 내려야 나타나는 구조는 아니다. 390px 폭에서는 본문이 아예 보이지 않는다.
3. **설정 편집기 줄 번호가 본문과 따로 논다** : 줄 번호 칸이 본문과 함께 스크롤되지 않는다. `sort_buffer_size` (51행)가 보이는 위치에서 거터는 1-32를 그대로 보여준다(shot `17-gutter-drift-line51`). 스크롤 전에도 거터 행 높이 25.19px, 본문 24.375px라 30행에서 한 줄 어긋난다. 저장 실패 메시지가 "Line 51" 로 위치를 알려줘도 화면에서 찾을 수 없다. 긴 줄은 `pre-wrap` 으로 접혀 번호가 더 어긋난다.
4. **HA 슬레이브 DB 중지가 복제를 조용히 끊음** : 슬레이브(ha1) hadb 메뉴의 Stop Database 는 일반 확인창만 띄운다. 실행하면 `cub_server`, copylogdb, applylogdb가 모두 내려가 복제가 멈춘다. 대시보드 HA 카드는 계속 "2 nodes active", ha1 SLAVE로 표시한다. Stop Service에는 HA 경고문이 있으나 DB 단위 중지에는 없다.
5. **페일오버 후 호스트 목록 역할 배지가 갱신되지 않음** : ha1 서비스 중지로 ha2가 master가 된 뒤 100초가 지나도 목록은 ha2 "Slave" 로 남았고 수동 Refresh 후에야 "Master" 로 바뀌었다. HA 카드는 ha1 UNKNOWN 상태에서도 "2 nodes active in cluster" 라고 쓴다.
6. **인증 안 된 호스트에 가짜 버전 표시** (`Footer.jsx:11`): `hostEnvs[...]?.CUBRIDVER || '11.2.0.4501'`. 비밀번호가 틀린 호스트를 선택하면 하단에 "Connected to 127.0.0.1:28111 / Version 11.2.0.4501" 이 뜬다. 연결도 버전도 사실이 아니다.

### Non-blocking (should consider)

7. **인스턴스 속성의 "현재 값" 이 실제 값과 다름** (`DatabasePropertyModal.jsx:323`): `[@demodb]` 구간만 읽고 `[common]` 을 무시한다. `[common] log_max_archives=0` 인데 화면은 2147483647(IMPLICIT)을 현재 값이라 쓴다. `cubrid paramdump demodb` 는 0. 화면 안내문 "This table shows the current values" 와 어긋난다.
8. **실행 중 DB의 Optimize가 막혀 있음** (`Sidebar.jsx` optimize `disabled={dbContextMenu.isActive ...}`): CMS는 실행 중 DB에 `UPDATE STATISTICS ON ALL CLASSES` 를 CS 모드로 수행한다(`cm_dep_tasks.c:566`). 통계 갱신을 위해 운영 DB를 내려야 한다.
9. **파라미터 저장 후 되돌리기, 재시작 안내 없음** : 되돌리기 버튼(툴팁 "Undo all changes")은 저장 전 편집 전체를 불러온 시점으로 확인 없이 되돌린다. Ctrl+Z는 단계별로 동작한다. 저장 후에는 되돌리기가 비활성이고 이전 파일 백업도 남지 않는다. `sort_buffer_size=4M` 저장 후에도 실행 중 서버는 2.0M(`paramdump -C`)인데 재시작이 필요하다는 안내가 없다.
10. **폴링 부하** : 대시보드를 열어둔 탭 하나가 분당 API 161회, CMS 227회를 보낸다. 3초마다 `startinfo` 3회, `getallsysparam` 2회, DB마다 `dbspaceinfo`, `getenv` 를 반복한다. 설정과 env는 거의 바뀌지 않는다. 운영자 수만큼 곱해진다.
11. **저장소 e2e가 현재 UI와 어긋남** : HEAD 기준 웹 e2e 90개 중 17 통과, 71 실패. 실패 71개 중 62개가 `#host-section [title="주소:포트"]` 를 기다린다. 2873f84([TOOLS-5037] #168, 10-28)가 title을 `별칭 (주소:포트)` 로 바꿨다. 나머지는 "Authentication Failed" 문구(현재 "Invalid credentials."), "About CUBRID Admin" 메뉴. Electron e2e(develop+CMS최신)는 100개 중 27 통과, 71 실패, 2 건너뜀이고 데스크톱 전용 10개는 모두 통과했다. 실CMS e2e가 수동 실행(`workflow_dispatch`)뿐이라 드리프트가 드러나지 않는다.
12. **완료 알림 중복, 잘못된 제목** : 백업 완료 시 "Backup completed" 와 "Backup Completed" 두 창을 차례로 닫아야 한다(11.4.6, develop 모두). Compact 완료 창 제목이 "Optimization Complete" (`CompactDatabaseModal.jsx` 가 `optimizationComplete` 사용).
13. **오류 메시지** : CMS 비밀번호 오류에 API가 HTTP 500을 돌려준다. develop DB 로그인 실패(CMS 쿼리 오류)에도 "username and password 를 확인하라" 고 안내하고, 상세에는 CMS 구분자 `<end>` 가 그대로 보인다.
14. **엔진 develop의 cubridmanager 고정** (CUBRID/cubrid 대상): 서브모듈이 `5a30b8c` 라 develop 빌드의 CMS로는 DB 로그인이 안 된다. cubrid-admin이 아니라 엔진 저장소에 올릴 항목이다.

### Nice to have

15. DB 메뉴 라벨이 1920 폭에서도 잘린다("Update Database Cr...", "Add Database Vol...", "Edit Instance Propert...").
16. Create Database 가 Database 탭이나 트리 빈 곳 우클릭으로만 열린다.
17. 문구: "result informaton"(언로드 결과), "will automatically create ... automatically"(데스크톱 첫 화면), 생성 요약의 "Charset en_US"(실제 생성은 UTF-8, `db_root.charset=5`), 언로드 "(100%/38%)" 설명 없음, EN 화면의 "Synced 오후 1:09".
18. 자기 동작 직후 갱신 지연: Stop Database 후 대시보드 RUNNING STATUS가 약 25초 ON으로 남는다.
19. HA Peers 창이 방금 추가한 노드 자신(ha1)을 추가 후보로 보여주고, 기본 비밀번호 경고창 위에 겹쳐 뜬다.

## Verified Behavior

| 영역 | 대상 | 결과 |
|---|---|---|
| 가입, 로그인, 해상도 7종(2560-390) 로그인 화면 | 웹 | 정상, 가로 넘침 없음 |
| 호스트 추가, 기본 비밀번호 경고 | 11.4.6, develop 2종 | 정상 |
| 백업 L0 -> 복구(backuptime) -> 시작, 마커 테이블 소멸 | 11.4.6 | 정상, athlete 6677행 유지 |
| compactdb(실행 중, CMS가 `-C` 로 수행), checkdb, unloaddb(행 수 일치) | 11.4.6 / develop+CMS최신 | 정상 |
| createdb(마법사), renamedb(databases.txt, `server=` 갱신), copydb | 11.4.6 | 정상 |
| HA: 피어 자동 발견, Stop Service로 페일오버, Start Service로 슬레이브 복귀, 복제 3행 | 11.4.6 2노드 | 동작, 표시 문제는 4, 5번 |
| 설정 편집기 검증(잘못된 값 저장 거부, 51행 지목) | 11.4.6 | 정상 |
| 모달 높이(1366x768, 1280x720) | 백업, 인스턴스 속성 | 버튼 보임, 내부 스크롤 |
| 한국어 전환, 다크 모드 | 대시보드, 메뉴, 모달 | 번역 누락 없음 |
| Electron 첫 실행 마법사, 가입, 로그인, 호스트 추가, 대시보드 | develop+CMS최신 / 11.4.6 | 정상, 전용 e2e 10개 통과 |

## Not Verified

- 패키징 Windows/macOS 실행파일, `e2e:electron:packaged`, HA의 develop 구성, develop에서 복구.
- 로드(loaddb), 자동 백업 계획, 자동 쿼리, DB 사용자와 CMS 사용자 관리, 호스트 import/export, 브로커 시작/중지, 브로커 SQL 로그(브로커 경유 트래픽 없음).
- 여러 웹 매니저 사용자 동시 사용(세션 제약은 curl로만 재현).

## Overlap with TOOLS JIRA (2026-11-05 조회)

TOOLS-5032 하위 42건, TOOLS 프로젝트 2025-03 이후 376건 중 300건 제목, 첨부 `NCA_DEV1_테스트.xlsx`(통합 테스트/이슈/버그/개선요청 시트)와 대조했다.

| # | 내 발견 | 기존 이슈 | 판정 |
|---|---|---|---|
| 1 | CDN 폰트, 폐쇄망 아이콘 깨짐 | 없음(5048은 업데이트 확인의 폐쇄망 처리만) | 신규 |
| 2 | 1366, 데스크톱 기본 창에서 Logout 밖으로 | TOOLS-5038(헤더+본문 전체 가로 스크롤로 설계), TOOLS-5030(작은 창 UI 깨짐) | 부분: 5038 설계의 결과, 5038/5030에 코멘트 |
| 3 | 편집기 줄 번호 스크롤 안 됨, 어긋남 | 없음 | 신규 |
| 4 | HA 슬레이브 DB 중지 경고 없음, 카드 정상 표시 | TOOLS-5065(HA DB 비활성 안내), 5067(dbname 없는 ha_stop) | 신규(다른 경로) |
| 5 | 페일오버 후 역할 배지 미갱신, "2 nodes active" | 엑셀 통합 테스트 "HA 마스터/슬레이브 변경 후 새로고침" 미수행 | 신규 |
| 6 | 푸터 가짜 버전 11.2.0.4501 | TOOLS-5059는 로그인/정보 창 버전만 | 신규 |
| 7 | 속성 창이 [common] 무시 | TOOLS-5077(Open, 엑셀 버그#29) | 중복 |
| 8 | 실행 중 Optimize 비활성 | TOOLS-5019 항목 11("DB 구동 후 불가") 제기, 하위 작업 없음, HEAD에 남음 | 기존 제기, 5019 코멘트 |
| 9 | cubrid.conf 저장 후 재시작 안내 없음, 이전 파일 백업 없음 | TOOLS-5047(broker.conf만) | 부분: cubrid.conf 미포함 |
| 10 | 정상 상태 폴링 부하(getallsysparam/getenv 3초) | TOOLS-5060, 5061, 5049, 5070, 5075(volume-info) | 부분: 정상 주기 내용 반복은 미포함 |
| 11 | 저장소 e2e 드리프트 | TOOLS-4990(공식 스위트는 CUBRID/cubrid-webmanager-e2e), 4984 | 저장소 내 e2e의 지위 확인 필요 |
| 12 | 백업 완료 창 2회, Compact "최적화" 문구 | TOOLS-5077(엑셀 버그#32, #30) | 중복 |
| 13 | CMS 오류 메시지(500, `<end>`, 비밀번호 안내) | TOOLS-5042, 5029, 5075(오류 코드), 4951(`<end>` 제거는 토큰 오류만) | 대부분 중복 |
| 14 | 엔진 develop cubridmanager 고정 | TOOLS 대상 아님(CBRD) | 신규(엔진) |
| 15 | 메뉴 라벨 잘림 | TOOLS-5077(엑셀 버그#40, 개선#37), 5035, 5037 | 중복 |
| 16 | Create Database 찾기 어려움 | 없음 | 신규(경미) |
| 17 | 문구들 | 언로드 "(100%/38%)"는 TOOLS-5077(개선#28) 중복, 나머지("informaton", 데스크톱 "automatically" 반복, 생성 요약 charset, EN 화면 "오후") 신규 | 일부 중복 |
| 18 | Stop 후 대시보드 25초 지연 | TOOLS-5070(작업 직후 재조회가 기대 결과, HEAD ab00bc5에 포함) | 5070 기대 결과와 불일치, 5070 코멘트 |
| 19 | HA Peers 창 자기 노드 표시, 창 겹침 | 엑셀 버그#49("모달이 여러번 열림", 미착수) | 부분 |
| - | 11.4.x CMS 계정당 단일 세션 | TOOLS-4951(Reconnect 창으로 처리) | 중복(알려진 제약) |
| - | 틀린 비밀번호도 호스트 저장 | TOOLS-5075(Connect & Save 저장 순서) | 중복 |
| - | DB 속성 가로 스크롤바가 맨 아래 | TOOLS-5019 항목 16, TOOLS-5028 | 중복 |
