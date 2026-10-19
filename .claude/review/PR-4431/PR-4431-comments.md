# PR-4431 post-ready comments

## CUBRID/cubrid-testcases-private-ex#4431

- event: COMMENT
- commit_id: 8cf9e1e56067ec668d57bea2fa0f8146838aa039

### top-level body

시간 초과 원인 정리와 수정 감사합니다. 최신 develop(3d3e40b6e) optdebug 아카이브로 로컬 컨테이너 CTP 를 돌려보니 19/19 OK 3회, 각 84초 정도였습니다(5개 동시 실행). 같은 조건에서 수정 전 케이스는 check 5 의 checkdb -C 가 700초 가까이 끝나지 않아 로컬 시간 제한(720초)에 두 번 모두 걸렸습니다. gha-ci 에서도 이 케이스를 넣은 브랜치로 /run shell 을 돌려봤는데 19/19 OK, 42초였습니다(이전에는 단독 실행도 907초).


### inline: shell/_40_guava/cbrd_27401/cases/cbrd_27401.sh:417-421 (RIGHT, start_line 417, line 421, check 19)

entries 검사는 check_not_vacuumed 로 vacuum 이 지웠어야 할 인덱스 객체도 ER_INDEX_FOUND_NOT_VACUUMED 로 잡는 것으로 알고 있습니다. 키별 count 는 스냅샷에 보이는 객체만 세서, check 16 경합에서 vacuum 이 객체를 놓쳐도 idx/heap 이 같게 나오고 btree_ovf_dir_check 도 객체는 보지 않는 것 같습니다. JIRA AC 에도 entries 정합이 있으니, 강제 vacuum 뒤 SHOW INDEX CAPACITY 의 Total_value(물리 객체 수)를 보는 건 어떨까요? 로컬에서 경합 직후 34274, 강제 vacuum 뒤 34000 이었고, 아래처럼 바꾼 케이스도 3번 모두 19/19 OK 였습니다. 헤더 76-80행의 "already checked by the per-key counts" 도 함께 고쳐주시면 좋겠습니다.
```suggestion
# ---- 19. structural check of every index and heap; after a full vacuum the index holds ----
#      exactly the 34000 live objects (an object vacuum missed is invisible to the counts)
cubrid server stop $db
cubrid vacuumdb -S $db > vacuum_race.log 2>&1
cubrid server start $db
total_value=`get_capacity Total_value cap_race.log`
cubrid server stop $db
cubrid checkdb -S $checkdb_opts $db > checkdb.log 2>&1
rc=$?
if [ $rc -eq 0 ] && [ `grep -ci "error" checkdb.log` -eq 0 ] && [ "$total_value" = "34000" ]; then
```
