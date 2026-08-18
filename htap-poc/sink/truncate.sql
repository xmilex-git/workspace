-- ADR 0005: a partial/failed snapshot load can only be cleaned by TRUNCATE
-- (every snapshot row has _version=0, so a re-run cannot overwrite them).
TRUNCATE TABLE htap.t_order_local;
TRUNCATE TABLE htap.t_item_local;
TRUNCATE TABLE htap.t_typecorpus_local;
