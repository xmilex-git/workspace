---
status: accepted
date: 2026-10-19
issue: CBRD-27664
---

# GROUP BY 정렬 생략은 스캔 중에 키 레코드 경계로 집계하고, 병렬은 부분 집계 런을 키 순서로 병합한다

develop 의 GROUP BY 정렬 생략은 스캔이 행을 임시 리스트(`xasl->list_id`, 커버링이면 그 앞의 covering list 까지)에 쓰고, 스캔이 끝난 뒤 `qexec_groupby_index` 가 다시 읽으며 행마다 그룹 키를 `tp_value_compare` 로 비교·`pr_clone_value` 로 복제해 집계했다. 정렬과 해시만 없을 뿐 임시 쓰기 두 번과 행당 비교·복제가 남았고, 병렬 스캔은 막혀 있었다(`px_scan_checker.cpp` 의 `groupby_skip`). 2026-10-19 그릴링(Q1~Q14)에서 직렬·병렬 모두 임시 리스트 없이 스캔 중에 집계하고, 그룹 경계는 B-tree 가 이미 아는 키 레코드 경계에서만 확인하기로 정했다.

- **스캔 중 그룹 집계.** 행을 리스트에 쓰지 않는다. 그룹 시작·행 집계·부분 상태 결합·그룹 종료(HAVING, groupby_num, 출력 리스트)를 하는 집계 코어 하나를 직렬·병렬·리더 병합이 함께 쓰고, 그룹 종료의 행선지(최종 출력 / 워커 런)만 스캔마다 한 번 정한다. `qexec_groupby_index` 의 리스트 재독 경로는 지운다. 집계 종류에 관계없이(DISTINCT·GROUP_CONCAT·MEDIAN 포함) 직렬은 모두 이 경로다.
- **그룹 경계는 키 레코드.** 키 레코드(키 하나와 그 OID 전부: leaf 와 overflow)가 바뀔 때만 그룹 키 값을 한 번 비교한다. 같은 키 레코드의 행은 비교 없이 집계한다. 그룹 키가 인덱스 키의 일부(동등 조건으로 묶인 앞 컬럼 뒤의 접두, 상수 동등 컬럼 건너뜀)여도 같은 규칙이다.
- **경계를 알리는 자리는 넷이다.**
  - S1, 직렬 커버링: B-tree 의 OID 처리 모드(count-only·MRO·covered dump 옆)에 그룹 집계 모드를 더해 방문 지점에서 집계한다. covering list 와 xasl list 가 없고 스캔은 행을 내지 않는다. leaf 래치를 잡은 채로 부질의를 돌리지 않도록 dptr·if_pred·after_join_pred·부질의가 든 집계 인자·HAVING 상관 부질의가 있으면 쓰지 않는다. groupby_num 이 차면 `end_scan`, 키 레코드마다 인터럽트 확인.
  - K, 그 밖의 직렬(비커버링, S1 조건에 걸린 커버링, DESC, ISS): B-tree 가 배치(OID 버퍼 / covering list)를 채우며 새 키 레코드 시작 위치(`is_key_partially_processed` 가 꺼진 채 들어간 키)를 적고, scan_manager 가 그 행에 표시를 켜고, executor 행 루프의 집계 코어가 표시된 행에서만 그룹 키를 비교한다.
  - P, 병렬 워커: 행별 작업(dptr·조건) 뒤의 `write()` 자리. walker 가 새 slot 과 늦은 합류 도움 체인의 시작을 표시한다.
  - M, 리더: 워커의 부분 집계 런을 키 순서로 k-way 병합해 같은 키의 상태를 공용 결합 함수(`qdata_aggregate_accumulator_to_accumulator`)로 합친다.
- **병렬은 부분 집계 런.** 늦은 합류 overflow 도움 때문에 워커 하나의 출력이 키 순서가 아니므로, 워커는 키가 직전보다 작아질 때 새 런을 시작한다. 병렬 허용 집계는 공용 결합 함수가 합칠 수 있는 종류 전부(DISTINCT 제외)다. ASC 만, groupby_num 이 있으면 직렬(앞쪽 그룹만 읽고 멈춤), #39 같은 집계 뒤 정렬 LIMIT 은 병렬.
- **읽는 순서 의존 값은 직렬과 달라도 된다.** 비집계 비키 컬럼, JSON 원소 순서, 실수 합 끝자리. 그룹 키·순서 무관 집계값·출력 순서는 같다.

## Considered Options

- **워커별 리스트를 그대로 k-way 병합**(티켓 원안): 기각. 늦은 합류 overflow 도움이 지나간 키를 다시 내므로 같은 키가 두 그룹으로 나온다.
- **groupby skip 스캔에서 overflow 도움 끄기**: 기각. leaf 가 몇 장뿐이고 OID 대부분이 overflow 에 있는 대표 질의에서 꼬리 시간이 길어진다.
- **리더가 부분 집계를 정렬(해시 partial 경로)**: 기각. 그룹 수가 많으면 리더가 외부 정렬을 해 직렬보다 느려질 수 있다.
- **해시 그룹바이처럼 행마다 키 값을 꺼내 비교**: 기각(사용자). 인덱스 키가 그룹 관리 역할을 하는 것이 정렬 생략의 이점이다. 행마다 값 비교로 처리하던 일반 경로(G)도 K 로 대체해 없앴다.
- **직렬에서도 px walker 를 리더 안에서 하나로 실행**: 기각. 실행마다 px 준비 비용이 들어 바깥 행마다 수만 번 도는 작은 상관 부질의에서 손해이고, px 에 무워커 모드가 새로 필요하다.
- **플래너가 groupby skip 대신 병렬 해시 집계를 비용으로 고르기**(qo_plan_cmp): 기각(티켓). 이 유형 질의의 플랜이 넓게 바뀐다.

## Consequences

- btree.c 의 범위 스캔 핫패스를 바꾸므로, 게이트 측정에 hot-symbol 배치 확인(cpp-perf-rules CC-08/MEAS-08)을 넣는다.
- trace 숫자는 같은 뜻으로 센다: S1 에서는 covering list 를 읽을 때 세던 qualified rows 를 방문 지점에서 센다. GROUPBY 줄 형식(hash: false, sort: false, readrows, rows)은 그대로다.
- JIRA CBRD-27664 의 범위·AC 가 바뀐다(직렬 스트리밍 포함, 결과 동일의 정의, 허용 집계 확대).
