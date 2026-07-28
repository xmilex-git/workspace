-- TPC-H Query 15: Top Supplier
-- Note: This query requires 3 separate statements (CREATE VIEW, SELECT, DROP VIEW)
-- They will be executed separately by the run script

-- Statement 1: Create view
create view revenue0 (supplier_no, total_revenue) as
	select
		l_suppkey,
		sum(l_extendedprice * (1 - l_discount))
	from
		lineitem
	where
		l_shipdate >= date '1996-01-01'
		and l_shipdate < date '1996-01-01' + interval '3' month
	group by
		l_suppkey;

-- Statement 2: Main query
select
	s_suppkey,
	s_name,
	s_address,
	s_phone,
	total_revenue
from
	supplier,
	revenue0
where
	s_suppkey = supplier_no
	and total_revenue = (
		select
			max(total_revenue)
		from
			revenue0
	)
order by
	s_suppkey;

-- Statement 3: Drop view
drop view revenue0;
