# PR #7900 게시 준비 코멘트

`src/compat/dbi.h:184`

NIT: `dbi_compat.h`가 설치용 `dbi.h`로 배포되는데 새 `db_find_multi_unique_committed`와 `db_find_multi_unique_for_update`는 Windows의 `cubridcs.def`/`cubridsa.def`에 export되지 않았습니다. public API라면 export를 추가하고, 내부 전용이라면 선언을 내부 헤더로 옮기는 것은 어떨까요?
