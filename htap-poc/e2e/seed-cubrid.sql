-- E2E #40: pre-snapshot state. Executed under the operator write stop
-- (ADR 0005 checklist step 1) — after this script NOTHING writes to the
-- captured tables until verify-e2e.sh confirms streaming has begun.
-- Recreating the tables gives the run a deterministic classoid->schema state.
DROP TABLE IF EXISTS t_order;
DROP TABLE IF EXISTS t_item;

CREATE TABLE t_order (
  id         INT PRIMARY KEY,
  customer   VARCHAR(64),
  amount     DECIMAL(15,4),
  created_at DATETIME
);

CREATE TABLE t_item (
  sku   VARCHAR(32) PRIMARY KEY,
  qty   INT,
  price DECIMAL(10,2)
);

-- snapshot content; id=2 / SKU-A / SKU-B are also the barrier-boundary rows the
-- streaming workload touches first (gap check: snapshot row + CDC update must
-- converge to the CDC value, _version 0 < any counter)
INSERT INTO t_order VALUES (1, 'alice', 100.0000, DATETIME'2026-08-16 10:00:00.000');
INSERT INTO t_order VALUES (2, 'bob',    20.5000, DATETIME'2026-08-16 10:01:00.000');
INSERT INTO t_item  VALUES ('SKU-A', 10,   19.99);
INSERT INTO t_item  VALUES ('SKU-B',  5, 2500.00);
