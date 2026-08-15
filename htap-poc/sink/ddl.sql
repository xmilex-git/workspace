-- htap-poc ticket #39: ClickHouse physical tables + canonical FINAL views.
--
-- Shape follows htap-cubrid.md §9.2/§9.4 simplified for the single-node POC
-- (no Replicated*/Distributed), with the schema bends decided in #31:
--   _version   UInt64 (not UInt128) = epoch[16] | event_counter[48]  (ADR 0004)
--   _is_deleted Bool  (not UInt8)   — JSON true/false parses natively
-- Snapshot rows arrive with _version=0 (ADR 0005), so any CDC event wins.
-- Verified live on clickhouse 24.8: RMT accepts Bool as the is_deleted arg,
-- and FINAL already filters _is_deleted rows (the WHERE in the views is
-- intent documentation / belt-and-braces).
--
-- Idempotent: safe to re-run. Partial snapshot loads are cleaned by
-- TRUNCATE only (ADR 0005) — see truncate.sql.

CREATE DATABASE IF NOT EXISTS htap;

-- source: htapdb.t_order (INT PK, VARCHAR, DECIMAL(15,4), DATETIME)
-- DECIMAL arrives as string (decimal.handling.mode=string, #31);
-- DATETIME arrives as ISO8601 UTC string (ZonedTimestamp, #31) — the sink
-- connector sets date_time_input_format=best_effort.
CREATE TABLE IF NOT EXISTS htap.t_order_local (
    id          Int32,
    customer    Nullable(String),
    amount      Nullable(Decimal(15, 4)),
    created_at  Nullable(DateTime64(3, 'UTC')),
    _op         LowCardinality(String),
    _version    UInt64,
    _is_deleted Bool
) ENGINE = ReplacingMergeTree(_version, _is_deleted)
ORDER BY id;

-- source: htapdb.t_item (VARCHAR PK, INT, DECIMAL(10,2))
CREATE TABLE IF NOT EXISTS htap.t_item_local (
    sku         String,
    qty         Nullable(Int32),
    price       Nullable(Decimal(10, 2)),
    _op         LowCardinality(String),
    _version    UInt64,
    _is_deleted Bool
) ENGINE = ReplacingMergeTree(_version, _is_deleted)
ORDER BY sku;

-- canonical views (§9.4): the only query surface consumers should touch.
CREATE OR REPLACE VIEW htap.t_order AS
SELECT id, customer, amount, created_at
FROM htap.t_order_local FINAL
WHERE _is_deleted = false;

CREATE OR REPLACE VIEW htap.t_item AS
SELECT sku, qty, price
FROM htap.t_item_local FINAL
WHERE _is_deleted = false;
