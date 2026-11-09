create table corr (id int primary key, a int, b int);
insert into corr values (1, 1, 7), (2, 1, 7), (3, 1, 100), (4, 1, 101);
create index corr_b on corr (b);
create table mid (m int, g int);
insert into mid values (1, 1), (2, 1);
create table fact (id int, g int);
insert into fact values (1, 1), (2, 1), (3, 1);
commit;
set system parameters 'memoize_memory_limit=0';
SELECT /*+ RECOMPILE PARALLEL(0) ORDERED */ COUNT(*) FROM corr c INNER JOIN mid m ON m.g = c.a INNER JOIN fact f ON f.g = m.g WHERE c.b = 7;
SELECT /*+ RECOMPILE PARALLEL(0) ORDERED USE_NL(m) */ COUNT(*) FROM corr c, mid m WHERE c.b = 7 AND m.g = c.a AND EXISTS (SELECT 1 FROM fact f WHERE f.g = m.g);
;plan simple
SELECT /*+ RECOMPILE PARALLEL(0) ORDERED */ COUNT(*) FROM corr c INNER JOIN mid m ON m.g = c.a INNER JOIN fact f ON f.g = m.g WHERE c.b = 7;
SELECT /*+ RECOMPILE PARALLEL(0) ORDERED USE_NL(m) */ COUNT(*) FROM corr c, mid m WHERE c.b = 7 AND m.g = c.a AND EXISTS (SELECT 1 FROM fact f WHERE f.g = m.g);
