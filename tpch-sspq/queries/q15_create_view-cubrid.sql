-- TPC-H Query 15: Create revenue view
create view revenue0 (supplier_no, total_revenue) as
	select
		l_suppkey,
		sum(l_extendedprice * (1 - l_discount))
	from
		lineitem
	where
		l_shipdate >= date '1996-01-01'
		and l_shipdate < DATE_ADD(DATE '1996-01-01', INTERVAL 3 MONTH)
	group by
		l_suppkey;
