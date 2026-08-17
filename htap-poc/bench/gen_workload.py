#!/usr/bin/env python3
"""#61 안전 스모크 측정 — 워크로드 SQL 생성기.

결정적(난수 seed 고정) SQL 파일 3종을 scratch에 생성한다. 같은 파일을
supplemental_log off/on 양쪽 측정에 재사용해 워크로드 동일성을 보장한다.

  bench_setup.sql   : t_bench drop/재생성 (매 run 시작 시 실행)
  bench_bulk.sql    : BULK_TXNS 트랜잭션 x (100행 multi-row INSERT + 100행 UPDATE)
                      — 서버/로그 바운드 (문장당 100 row-level 로그 레코드)
  bench_single.sql  : SINGLE_TXNS 트랜잭션 x 단일행 INSERT/UPDATE 교대
                      — 커밋 지연(per-txn latency) 성향
"""
import random, sys, os

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
BULK_TXNS = int(os.environ.get("BULK_TXNS", "200"))      # x100행 insert + x100행 update
SINGLE_TXNS = int(os.environ.get("SINGLE_TXNS", "2000"))
ROWS_PER_GRP = 100

random.seed(61)

def payload(i):
    return f"payload-{i:08d}-" + "x" * 50

with open(f"{OUT}/bench_setup.sql", "w") as f:
    f.write(";autocommit off\n")
    f.write("DROP TABLE IF EXISTS t_bench;\n")
    f.write("CREATE TABLE t_bench (id INT PRIMARY KEY, grp INT, cnt INT, "
            "amount DECIMAL(15,4), payload VARCHAR(100), updated_at DATETIME);\n")
    f.write("CREATE INDEX i_t_bench_grp ON t_bench (grp);\n")
    f.write("COMMIT;\n")

with open(f"{OUT}/bench_bulk.sql", "w") as f:
    f.write(";autocommit off\n")
    rid = 0
    # phase 1: BULK_TXNS txns, each a 100-row multi-row INSERT
    for t in range(BULK_TXNS):
        vals = []
        for _ in range(ROWS_PER_GRP):
            vals.append(f"({rid}, {t}, 0, {random.uniform(1,10000):.4f}, "
                        f"'{payload(rid)}', DATETIME'2026-08-17 10:00:00')")
            rid += 1
        f.write("INSERT INTO t_bench VALUES " + ", ".join(vals) + ";\n")
        f.write("COMMIT;\n")
    # phase 2: BULK_TXNS txns, each one UPDATE touching a 100-row group
    for t in range(BULK_TXNS):
        f.write(f"UPDATE t_bench SET cnt = cnt + 1, amount = amount + 1.5 "
                f"WHERE grp = {t};\n")
        f.write("COMMIT;\n")

with open(f"{OUT}/bench_single.sql", "w") as f:
    f.write(";autocommit off\n")
    base = BULK_TXNS * ROWS_PER_GRP
    for t in range(SINGLE_TXNS):
        if t % 2 == 0:
            f.write(f"INSERT INTO t_bench VALUES ({base + t}, -1, 0, 1.0, "
                    f"'{payload(base + t)}', DATETIME'2026-08-17 11:00:00');\n")
        else:
            f.write(f"UPDATE t_bench SET cnt = cnt + 1 WHERE id = {base + t - 1};\n")
        f.write("COMMIT;\n")

print(f"generated in {OUT}: bulk={BULK_TXNS}x(100-row INS + 100-row UPD) txns, "
      f"single={SINGLE_TXNS} txns")
