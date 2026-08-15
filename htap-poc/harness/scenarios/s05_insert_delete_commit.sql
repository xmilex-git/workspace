;autocommit off
-- s05: insert then delete the same row inside one txn -> commit.
-- Does the stream carry both events, or is the pair elided?
INSERT INTO t_item VALUES ('SKU-EPHEMERAL', 1, 0.01);
DELETE FROM t_item WHERE sku = 'SKU-EPHEMERAL';
COMMIT;
