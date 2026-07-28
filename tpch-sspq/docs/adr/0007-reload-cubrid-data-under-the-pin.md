# `tpch_sf10_v2`를 은퇴시키고 CUBRID 데이터를 pin 빌드로 다시 적재한다

ADR 0004는 `~/databases/tpch_sf10_v2`(55G, 적재 완료)를 그대로 재사용한다고
정했다. 그 전제가 실측으로 깨졌다. **pin 빌드 `f30f1c260`은 이 데이터베이스를
아예 열지 못한다.**

```
catalog_class.c:4898 ERROR CODE = -64  ... Unknown class "db_root".
boot_sr.c:2751      ERROR CODE = -113 ... Unable to restart/initialize the database server.
```

원인은 설정 실수나 데이터 손상이 아니라 **on-disk CHAR/VARCHAR 저장 포맷 변경**이다.

| 사실 | 근거 |
|---|---|
| DB를 만든 빌드는 `4cfc837` | `~/release/CUBRID-q19-4cfc837/log/cubrid_utility.log:17` — `cubrid createdb -r -F /home/cubrid/databases/tpch_sf10_v2 … tpch_sf10_v2 en_US.utf8`, 26-07-23 18:37:31 |
| `83b29b02c` CBRD-26663 *CHAR/VARCHAR unified variable-length storage* | `4cfc837`과 `f30f1c260` **양쪽 모두의** 조상 |
| `a9fca9002` CBRD-26956 *"Full revert of CBRD-26663; VARCHAR restored to the byte_size header"* | `f30f1c260`에는 있고 `4cfc837`에는 **없다** |
| 실패 지점이 정확히 VARCHAR 카탈로그 디코드 | `catcls_get_server_compat_info()` → `catcls_find_class_oid_by_class_name(…, "db_root", …)`. 조회 키가 `_db_class`의 VARCHAR `class_name`이다. revert가 건드린 파일에 `object_representation.h`, `object_representation_sr.c`, `object_primitive.c`가 포함된다 |
| 볼륨 자체는 정상 | 대조 실험: 같은 볼륨을 생성 빌드 `4cfc837`로 기동 → `++ cubrid server start: success`, `Server tpch_sf10_v2 (rel 11.5.0, pid 4148480)`. 즉시 다시 정지 |

저장 포맷 revert에는 마이그레이션 경로가 없다. 그래서 선택지는 둘뿐이다.
(a) pin을 `a9fca9002` 이전으로 되돌려 기존 DB를 살린다,
(b) pin을 유지하고 데이터를 다시 적재한다.

(a)는 ADR 0002의 "develop 스냅샷을 pin한다"를 뒤집고, 이미 develop에 들어간
저장 포맷을 측정 대상에서 제외하는 결과가 된다. 데이터는 다시 만들 수 있고 pin은
프로젝트의 판정 기준이므로 (b)를 택한다.

## Decision

- **`~/databases/tpch_sf10_v2`는 은퇴한 `4cfc837` 빌드의 자산으로 취급한다.**
  G1 자산이 아니다. 여기서 나온 수치는 pin 빌드 수치와 같은 표에 올리지 않는다.
  파일은 삭제하지 않고 그대로 둔다(사용자 소유물).
- CUBRID 데이터는 **pin 빌드로 새로 적재한다.** `createdb` 기하와 로케일은
  `tpch_sf10_v2`와 동일하게 맞춘다 — `--db-volume-size=256M
  --log-volume-size=512M`, `en_US.utf8`, 16 K 페이지.
- 새 DB는 **전용 `databases.txt`를 쓴다.** `CUBRID_DATABASES` =
  `.git_ignored_dir/tpch-sspq/cubrid-databases`. 공용 `~/databases/databases.txt`는
  수정하지 않는다.
- 적재 원본은 ADR 0004와 같은 `scale10/load_data/*.load`다. 데이터셋 provenance
  한계(kit 부재)는 ADR 0004 그대로 유효하다.
- **G1 선행 조건이 늘어난다**: PG 8개 테이블 적재 + CUBRID 8개 테이블 재적재.
  Q1 파일럿은 `tpch_sf10_q1`(lineitem 단독)로 먼저 통과시켰다.

## Consequences

- ADR 0004의 "데이터: `tpch_sf10_v2`를 그대로 쓴다"는 **이 ADR로 대체된다.**
  같은 ADR의 쿼리·스키마 정본 결정과 provenance 한계 수용은 그대로 유효하다.
- G1 진입 비용이 커진다. lineitem 단독 적재만으로도 loaddb 17:54 + PK 1:36 +
  통계 1:42가 들었다. 8개 테이블 전체는 이보다 크다.
- **두 빌드의 테이블 크기가 다르다.** 저장 포맷이 달라졌으므로 `tpch_sf10_v2`의
  볼륨 크기를 새 DB의 기대값으로 쓸 수 없다. 실제로 pin 빌드에서 lineitem은
  permanent data 12,254 M(25 볼륨), 전체 스캔이 682,937 × 16 K 페이지다.
- **앞으로 develop pin을 옮길 때마다 같은 일이 재발할 수 있다.** pin을 바꾸면
  기존 DB를 열 수 있는지 먼저 확인하고, 열리지 않으면 재적재를 일정에 넣는다.
  pin 이동은 데이터 재적재 비용을 포함한 결정으로 취급한다.
- 대용량 산출물 배치 원칙(README)에 따라 새 DB는 `.git_ignored_dir/` 아래 두므로
  git에 들어가지 않는다.
