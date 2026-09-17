CI 155077의 회귀를 수정했습니다. 이전 검사는 `layout_ready`를 기존 값 기록 여부처럼 사용해, ENUM/문자열 + host variable의 정상적인 초기 도메인 확정까지 막았습니다. interpolation에만 예외를 둔 것으로는 부족했습니다.

이제 debug에서 컬럼별 non-NULL 값 기록 이력을 추적하고, 실제 값에 사용된 레이아웃만 `kind/size/alignby/value_format`으로 비교합니다. 빈 리스트와 NULL-only 컬럼은 타입 변경을 허용합니다. 쓰기·복사·연결·해시 집계의 보관용 첫 튜플에서 이력을 유지하고, truncate 시 초기화합니다. 공유 정렬 키 조립기에는 쓰기를 추가하지 않았습니다.

이력 필드와 갱신·검사 코드는 모두 `!NDEBUG`이며, release의 컬럼 레이아웃은 기존 8바이트를 유지합니다. 기존 FIXED/DIRECT 검사도 debug assert로 유지했습니다.

기존 빌드에서 동일 assert를 재현한 뒤 수정 빌드로 검증했습니다. 최종 소스의 optdebug/release 빌드와 포맷 검사를 통과했고, CI와 같은 TC commit `1eea18808fd865f6f77c33950f8f9750bb662eda`의 로컬 컨테이너 CTP SQL **17,459/17,459 통과, 실패 0, core 0**을 확인했습니다. 이전 CI 실패 45개도 모두 포함되어 성공했습니다. 성능 테스트는 수행하지 않았습니다.
