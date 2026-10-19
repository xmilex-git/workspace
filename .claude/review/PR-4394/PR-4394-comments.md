# PR-4394 post-ready comments

## CUBRID/cubrid-testcases-private-ex#4394

- event: COMMENT
- commit_id: 757f1901996eb85dded5926952deb2bffeac6f65

### top-level body

ALTER INDEX ... COMPACT 전용 케이스 추가 감사합니다. 로컬 컨테이너 CTP(optdebug, gha-ci 아카이브 빌드)로 세 지점에서 돌려봤습니다.

| 지점 | 커밋 | 결과 |
|---|---|---|
| 직전 | 453da49c8 (0c310e25c^) | NOK, 4-6, 8-11, 13 (Syntax error: unexpected 'compact') |
| 직후 | 0c310e25c | OK x3 (16/16), Total pages 39 -> 23, Num_ovf_page 36 -> 20 매번 동일 |
| 최신 develop | fd540db0c | OK (16/16) |

세 지점 모두 코어는 없었습니다. 경합 단계에서 COMPACT 마다 er_log_debug 를 찍어보니 30회 모두 DML 세션이 살아 있는 동안 시작했고 23회가 1-5 페이지를 반납해서, 본문의 "대부분의 COMPACT는 no-op" 보다는 실제로 경합하고 있는 것 같습니다.

확인 부탁드립니다
- 본문의 "답지는 develop 58b49b39f 빌드에서 CTP로 생성"은 shell 케이스라 답지가 없으니, 위 표처럼 지점별 결과와 빌드 종류로 바꿔주시면 좋겠습니다.
- 개발자 테스트 리포트 6절 시나리오 중 이번 케이스에서 뺀 것(killtran 중단, 잠금 관찰, HA, 성능 비교)과 그 이유도 본문에 남겨주시면 좋겠습니다.

### inline: shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh:170 (RIGHT, check 6 조건)

Num_ovf_page 는 데이터로 정해지는 것 같습니다. 키당 5,000 OID 면 데이터 8 + 디렉터리 1 페이지라 4 x 9 = 36, 컴팩션 뒤 2,000 OID 는 4 + 1 이라 4 x 5 = 20 이고, 네 번 돌려서 모두 36 -> 20 이었습니다. 지금 조건은 키 하나만 컴팩션돼도(36 -> 32) 통과하니 값으로 보는 건 어떨까요? before 쪽 조건이 positive control 역할도 합니다. 헤더 29행의 ~7 overflow pages 도 실측은 8페이지였습니다.
```suggestion
if [ -n "$ovf_before" ] && [ -n "$ovf_after" ] && [ "$ovf_before" -ge 32 ] && [ "$ovf_after" -le 20 ]; then
```

### inline: shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh:247 (RIGHT, 경합 COMPACT 루프)

COMPACT 와 DML 이 교착되면 이 루프와 아래 wait 가 CTP 가 케이스를 끊을 때까지 멈추고, deletedb 정리도 안 될 것 같습니다. 여기서는 run_sql 대신 timeout 300 csql ... 로 부르고 백그라운드 csql 도 timeout 으로 감싸면, wait 도 끝나고 교착이 NOK 한 줄로 남지 않을까요?

### inline: shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh:203 (RIGHT, fill_factor = 49)

테스트 리포트 6절 시나리오 중 결정적으로 넣을 수 있는 것들이 빠져 있는 것 같습니다. 최신 develop 에서 확인해보니 fill_factor = 50 은 허용, = 4294967386 은 같은 범위 오류(이번 PR 에서 고친 int 절단), SELECT 권한만 있는 사용자는 INDEX authorization failure 이고 grant index 뒤에는 성공, COMPACT 직후 kill -9 하면 자동 재기동 뒤 키별 2000건, Num_ovf_page 20, checkdb rc=0 이 그대로였습니다. 모두 몇 줄이라 추가해보는 건 어떨까요? 파티션 테이블(ON t / ON ONLY t)은 따로 확인하지 못했습니다.

### inline: shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh:23 (RIGHT, 동반 변경 설명)

헤더에서 동반 변경(키 중간에서 멈춘 스캔을 OID 기준으로 재개)을 설명하고 있는데, COMPACT 와 동시에 도는 SELECT 가 없어서 이 변경이 막으려는 동시 스캔의 행 누락은 검사되지 않는 것 같습니다. 테스트 리포트 3.1절과 6절에서 1순위로 꼽은 시나리오라, check 13 경합에 같은 키를 읽는 SELECT 세션(리포트 1절의 한 문장 idx/heap 비교)을 넣는 건 어떨까요? 넣기 어렵다면 본문에 제외 이유를 남겨주시면 좋겠습니다.

### inline: shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh:259 (RIGHT, check_counts race 14000)

NIT: check 14 가 결과를 두 줄 쓰는 바람에 .result 는 16줄인데 헤더 번호는 15까지라, 16번이 NOK 이면 헤더에서 찾기 어려울 것 같습니다.
