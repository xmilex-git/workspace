# PR-4312 post-ready comments

## CUBRID/cubrid-testcases-private-ex#4312

- event: COMMENT
- commit_id: 06dbca9cf9afb3bdd9c43923af6c1209d4d21969

### top-level body

CUBRID/cubrid#8103 의 tc/pr-8103 에 이 커밋을 올려 /run shell 로 확인했습니다. parallel_degree 5/5 와 membuf-only 1-2 는 통과했지만, gha-ci(optdebug)에서는 disk-only 에서 `split_task::execute` 의 assert(CBRD-27557)로 서버가 abort 해서 membuf_config 3-6 이 NOK 이고 코어가 2개 남습니다.
CBRD-27557 이 고쳐지기 전까지는 이 케이스가 CI 에서 계속 크래시하니, 본문의 8/8 OK 가 release 기준이라는 점과 함께 적어주시면 좋겠습니다.

### inline: shell/_40_guava/cbrd_25717/cbrd_25717_membuf_config/cases/cbrd_25717_membuf_config.sh:137 (RIGHT, `set_membuf 0`)

여기서 서버가 죽으면 다음 `set_membuf 20` 의 stop/start 가 적용되지 않아서, membuf+disk 도 0 페이지 서버에서 같은 assert 로 한 번 더 죽는 것 같습니다(CI 에서 코어가 2개 남는 이유로 보입니다). `set_membuf` 에서 재시작 후 `temp_file_memory_size_in_pages` 가 반영됐는지 확인하는 건 어떨까요?
