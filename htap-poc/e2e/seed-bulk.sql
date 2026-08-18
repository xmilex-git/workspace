;autocommit off
-- #64 online-snapshot fault suite: bulk rows that stretch the snapshot scan so
-- faults can be injected mid-scan. ids 100000..165535 — disjoint from the seed
-- rows (1..), the writer-loop ids (500000..) and the SN2 marker ids (910001+).
INSERT INTO t_order VALUES (100000, 'bulk', 1.0000, DATETIME'2026-08-16 12:00:00.000');
COMMIT;
INSERT INTO t_order SELECT id + 1,     customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 2,     customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 4,     customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 8,     customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 16,    customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 32,    customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 64,    customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 128,   customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 256,   customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 512,   customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 1024,  customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 2048,  customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 4096,  customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 8192,  customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 16384, customer, amount, created_at FROM t_order WHERE id >= 100000;
INSERT INTO t_order SELECT id + 32768, customer, amount, created_at FROM t_order WHERE id >= 100000;
COMMIT;
