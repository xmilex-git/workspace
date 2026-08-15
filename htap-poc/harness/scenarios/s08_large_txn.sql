;autocommit off
-- s08: large transaction — 30,000 rows in one txn -> commit.
-- Probes batching across extract() calls and whether the COMMIT arrives
-- once at the end (txn boundary vs streaming interleave).
INSERT INTO big_txn (id, payload)
SELECT a.n * 10000 + b.n * 1000 + c.n * 100 + d.n * 10 + e.n,
       'payload-' || LPAD ((a.n * 10000 + b.n * 1000 + c.n * 100 + d.n * 10 + e.n), 8, '0')
FROM digits a, digits b, digits c, digits d, digits e
WHERE a.n < 3;
COMMIT;
