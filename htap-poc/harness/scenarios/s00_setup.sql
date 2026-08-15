-- s00: schema setup. Runs with autocommit ON so the dump also captures DDL
-- events (CREATE TABLE stmt + classoid), which doubles as the
-- classoid -> table-name mapping for every later scenario dump.

-- representative types: INT / VARCHAR / DECIMAL / DATETIME (map #30 P0 scope)
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

CREATE TABLE t_audit (
  id   INT PRIMARY KEY,
  note VARCHAR(64)
);

CREATE TABLE big_txn (
  id      INT PRIMARY KEY,
  payload VARCHAR(64)
);

-- digit helper for the large-transaction scenario (no generate_series in CUBRID)
CREATE TABLE digits (n INT PRIMARY KEY);
INSERT INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

-- trigger-driven DML: every t_order insert writes one t_audit row
CREATE TRIGGER trg_order_audit
  AFTER INSERT ON t_order
  EXECUTE INSERT INTO t_audit (id, note) VALUES (obj.id, 'via-trigger');
