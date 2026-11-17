-- =====================================================================
-- ROSBREN ERP  —  03 REPORTING, PLANNING & ANALYTICS
-- Every number is computed live from transactions; nothing is typed in.
-- =====================================================================

-- daily demand per item over a look-back window, including DEPENDENT demand
-- (kits sold × bill-of-material quantity flow down to their components)
create or replace function _demand_stats(p_days int)
returns table(item_id int, total numeric, avg_daily numeric, sd_daily numeric)
language sql stable security definer set search_path = public as $$
  with days as (select (current_date - g)::date d from generate_series(0, p_days - 1) g),
  direct as (
    select sl.item_id, s.sale_date::date d, sum(sl.qty) q
    from sale_lines sl join sales s on s.id = sl.sale_id
    where s.sale_date >= current_date - (p_days - 1)
    group by 1, 2),
  dep as (
    select b.component_item_id as item_id, x.d, sum(x.q * b.qty_per) q
    from direct x join bom_lines b on b.parent_item_id = x.item_id group by 1, 2),
  allq as (select u.item_id, u.d, sum(u.q) q from (select * from direct union all select * from dep) u group by 1, 2),
  grid as (
    select i.id as item_id, days.d, coalesce(a.q, 0) q
    from items i cross join days left join allq a on a.item_id = i.id and a.d = days.d
    where i.item_type <> 'service')
  select g.item_id, sum(g.q), avg(g.q), coalesce(stddev_samp(g.q), 0) from grid g group by g.item_id
$$;

-- on-hand, allocated, on-order, in production per item
create or replace function _positions()
returns table(item_id int, on_hand numeric, allocated numeric, on_order numeric, in_production numeric)
language sql stable security definer set search_path = public as $$
  select i.id,
    coalesce((select sum(qty_on_hand) from inventory where item_id = i.id), 0),
    coalesce((select sum(sol.qty) from sales_order_lines sol join sales_orders so on so.id = sol.so_id
              where so.status = 'Order Placed' and sol.item_id = i.id), 0),
    coalesce((select sum(pol.qty_ordered - pol.qty_received) from purchase_order_lines pol join purchase_orders po on po.id = pol.po_id
              where po.status in ('Order Sent','Partially Received') and pol.item_id = i.id), 0),
    coalesce((select sum(case when status = 'Planned' then qty_planned else qty_started end) from production_orders
              where status in ('Planned','In Progress') and item_id = i.id), 0)
  from items i where i.item_type <> 'service'
$$;

-- ---------- inventory status (on hand by location, backorders, ETA) ----
create or replace function get_inventory_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return (
  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.category, t.name), '[]') from (
    select i.id, i.sku, i.barcode, i.name, i.category, i.uom, i.item_type, i.price, i.avg_cost, i.reorder_point,
      i.lead_time_days, i.shelf, i.active, s.name as supplier_name,
      p.on_hand, p.allocated, p.on_order, p.in_production,
      greatest(p.on_hand - p.allocated, 0) as available,
      greatest(p.allocated - p.on_hand, 0) as backordered,
      (p.on_hand + p.on_order + p.in_production - p.allocated) as position,
      (p.on_hand + p.on_order + p.in_production - p.allocated) <= i.reorder_point as below_rop,
      round(p.on_hand * i.avg_cost, 2) as value,
      (select jsonb_object_agg(l.id::text, coalesce(inv.qty_on_hand, 0)) from locations l
         left join inventory inv on inv.item_id = i.id and inv.location_id = l.id) as by_location,
      case when p.allocated > p.on_hand or p.on_hand <= 0 then
        coalesce(
          (select min(po.expected_date) from purchase_order_lines pol join purchase_orders po on po.id = pol.po_id
            where pol.item_id = i.id and po.status in ('Order Sent','Partially Received') and pol.qty_ordered > pol.qty_received),
          (select min(due_date) from production_orders where item_id = i.id and status in ('Planned','In Progress')),
          current_date + i.lead_time_days)
      end as est_available_date,
      case when exists (select 1 from purchase_order_lines pol join purchase_orders po on po.id = pol.po_id
            where pol.item_id = i.id and po.status in ('Order Sent','Partially Received') and pol.qty_ordered > pol.qty_received) then 'Open PO'
           when exists (select 1 from production_orders where item_id = i.id and status in ('Planned','In Progress')) then 'Production order'
           when i.item_type = 'kit' then 'Assembly lead time'
           else 'Supplier lead time' end as eta_basis
    from items i join _positions() p on p.item_id = i.id left join suppliers s on s.id = i.preferred_supplier_id
    where i.item_type <> 'service'
  ) t);
end $$;

create or replace function get_item_ledger(p_item int, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return (select coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]') from (
    select it.created_at, it.txn_type, it.qty_change, it.unit_cost, it.ref_no, it.reason_code, it.note, l.code as location
    from inventory_transactions it join locations l on l.id = it.location_id
    where it.item_id = p_item order by it.created_at desc, it.id desc limit p_limit) t);
end $$;

-- ---------- replenishment: ROP with lead-time demand, EOQ, periodic review --
create or replace function get_replenishment() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_days int := setting_num('demand_lookback_days', 180)::int;
  v_S numeric := setting_num('ordering_cost', 25000);
  v_h numeric := setting_num('holding_cost_pct', 0.25);
  v_z numeric := setting_num('service_level_z', 1.65);
  v_R numeric := setting_num('review_period_days', 14);
begin
  perform require_staff();
  return (
  select jsonb_build_object(
    'settings', jsonb_build_object('lookback_days', v_days, 'ordering_cost', v_S, 'holding_cost_pct', v_h, 'z', v_z, 'review_period_days', v_R),
    'items', coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.order_by_date nulls last, t.name), '[]'))
  from (
    select x.*,
      case when x.position <= x.calc_rop then current_date
           when x.avg_daily > 0 then current_date + floor((x.position - x.calc_rop) / x.avg_daily)::int end as order_by_date,
      case when x.position <= x.reorder_point then
             greatest(coalesce(x.eoq, 0), ceil(x.reorder_point - x.position + x.avg_daily * x.lead_time_days)) end as suggested_qty,
      greatest(0, x.order_up_to - x.position) as periodic_qty
    from (
      select i.id, i.sku, i.name, i.category, i.item_type, i.uom, i.avg_cost, i.reorder_point, i.lead_time_days,
        i.last_reviewed_at, s.name as supplier_name, i.preferred_supplier_id,
        (i.last_reviewed_at is null or i.last_reviewed_at + v_R::int <= current_date) as due_for_review,
        round(d.avg_daily, 3) as avg_daily, round(d.sd_daily, 3) as sd_daily, d.total as usage_lookback,
        round(d.avg_daily * 365) as annual_demand,
        round(d.avg_daily * i.lead_time_days, 1) as lead_time_demand,
        ceil(v_z * d.sd_daily * sqrt(i.lead_time_days)) as safety_stock,
        ceil(d.avg_daily * i.lead_time_days + v_z * d.sd_daily * sqrt(i.lead_time_days)) as calc_rop,
        round(v_h * i.avg_cost, 2) as holding_cost_unit,
        case when i.avg_cost > 0 and d.avg_daily > 0 then ceil(sqrt(2 * d.avg_daily * 365 * v_S / (v_h * i.avg_cost))) end as eoq,
        ceil(d.avg_daily * (v_R + i.lead_time_days) + v_z * d.sd_daily * sqrt(v_R + i.lead_time_days)) as order_up_to,
        p.on_hand, p.on_order, p.allocated, p.in_production,
        (p.on_hand + p.on_order + p.in_production - p.allocated) as position
      from items i join _demand_stats(v_days) d on d.item_id = i.id join _positions() p on p.item_id = i.id
      left join suppliers s on s.id = i.preferred_supplier_id
      where i.active and i.item_type <> 'service'
    ) x
  ) t);
end $$;

-- ---------- MRP inputs (the netting/explosion runs in the browser, see src/lib/mrp.js) --
create or replace function get_mrp_inputs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return jsonb_build_object(
    'today', current_date,
    'items', (select jsonb_agg(jsonb_build_object('id', i.id, 'sku', i.sku, 'name', i.name, 'item_type', i.item_type, 'uom', i.uom,
               'lead_time_days', i.lead_time_days, 'avg_cost', i.avg_cost, 'supplier_id', i.preferred_supplier_id,
               'supplier_name', s.name, 'on_hand', p.on_hand, 'allocated', p.allocated))
              from items i join _positions() p on p.item_id = i.id left join suppliers s on s.id = i.preferred_supplier_id),
    'bom', coalesce((select jsonb_agg(jsonb_build_object('parent', parent_item_id, 'component', component_item_id, 'qty_per', qty_per)) from bom_lines), '[]'),
    'demand', coalesce((select jsonb_agg(jsonb_build_object('item_id', sol.item_id, 'qty', sol.qty, 'date', so.requested_date,
               'so_number', so.so_number, 'customer', c.name))
              from sales_order_lines sol join sales_orders so on so.id = sol.so_id join customers c on c.id = so.customer_id
              where so.status = 'Order Placed'), '[]'),
    'receipts', coalesce((select jsonb_agg(jsonb_build_object('item_id', pol.item_id, 'qty', pol.qty_ordered - pol.qty_received,
               'date', po.expected_date, 'ref', po.po_number))
              from purchase_order_lines pol join purchase_orders po on po.id = pol.po_id
              where po.status in ('Order Sent','Partially Received') and pol.qty_ordered > pol.qty_received), '[]'),
    'production', coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'qty', case when status='Planned' then qty_planned else qty_started end,
               'date', due_date, 'ref', wo_number, 'status', status))
              from production_orders where status in ('Planned','In Progress')), '[]')
  );
end $$;

-- ---------- financial statements --------------------------------------
create or replace function get_pnl(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform require_manager();
  with sl as (
    select sl.*, i.item_type, i.category, s.sale_date::date d from sale_lines sl join sales s on s.id = sl.sale_id join items i on i.id = sl.item_id
    where s.sale_date::date between p_from and p_to),
  rl as (
    select rl.*, i.item_type, r.return_date::date d from return_lines rl join returns r on r.id = rl.return_id join items i on i.id = rl.item_id
    where r.return_date::date between p_from and p_to),
  adj as (
    select sum(-qty_change * unit_cost) v from inventory_transactions
    where txn_type in ('adjustment','write_off') and created_at::date between p_from and p_to),
  ex as (select category, sum(amount) amt from expenses where expense_date between p_from and p_to group by category),
  months as (
    select to_char(m, 'YYYY-MM') ym from generate_series(date_trunc('month', p_from), date_trunc('month', p_to), interval '1 month') m)
  select jsonb_build_object(
    'from', p_from, 'to', p_to,
    'product_sales', coalesce((select sum(line_total + discount_amount) from sl where item_type <> 'service'), 0),
    'discounts', coalesce((select sum(discount_amount) from sl where item_type <> 'service'), 0),
    'clinic_revenue', coalesce((select sum(line_total) from sl where item_type = 'service' and category <> 'Lab Services'), 0),
    'lab_revenue', coalesce((select sum(line_total) from sl where item_type = 'service' and category = 'Lab Services'), 0),
    'returns', coalesce((select sum(line_total) from rl where direction = 'in'), 0),
    'exchange_sales', coalesce((select sum(line_total) from rl where direction = 'out'), 0),
    'cogs_sales', coalesce((select sum(line_cost) from sl where item_type <> 'service'), 0),
    'cogs_exchanges', coalesce((select sum(line_cost) from rl where direction = 'out'), 0),
    'cogs_returns', coalesce((select sum(line_cost) from rl where direction = 'in'), 0),
    'inventory_losses', coalesce((select v from adj), 0),
    'scrap_cost_absorbed', coalesce((select sum(material_cost * qty_scrapped / nullif(qty_started,0)) from production_orders
                              where status = 'Completed' and finished_at::date between p_from and p_to), 0),
    'tax_collected', coalesce((select sum(tax_amount) from sl), 0) + coalesce((select sum(case when direction='out' then tax_amount else -tax_amount end) from rl), 0),
    'expenses', coalesce((select jsonb_agg(jsonb_build_object('category', category, 'amount', amt) order by amt desc) from ex), '[]'),
    'expense_total', coalesce((select sum(amt) from ex), 0),
    'monthly', (select jsonb_agg(jsonb_build_object('month', ym,
        'revenue', coalesce((select sum(line_total) from sl where to_char(d,'YYYY-MM') = ym), 0)
                 + coalesce((select sum(case when direction='out' then line_total else -line_total end) from rl where to_char(d,'YYYY-MM') = ym), 0),
        'cogs', coalesce((select sum(line_cost) from sl where to_char(d,'YYYY-MM') = ym), 0)
                 + coalesce((select sum(case when direction='out' then line_cost else -line_cost end) from rl where to_char(d,'YYYY-MM') = ym), 0),
        'expenses', coalesce((select sum(amount) from expenses where to_char(expense_date,'YYYY-MM') = ym and expense_date between p_from and p_to), 0)
      ) order by ym) from months)
  ) into r;
  return r;
end $$;

create or replace function get_inventory_valuation(p_from date default current_date - 179, p_to date default current_date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_days numeric := greatest(p_to - p_from + 1, 1); v_cogs numeric; v_value numeric;
begin
  perform require_staff();
  select coalesce(sum(sl.line_cost),0) into v_cogs from sale_lines sl join sales s on s.id = sl.sale_id
    where s.sale_date::date between p_from and p_to;
  select coalesce(sum(rl.line_cost * case when direction='out' then 1 else -1 end),0) + v_cogs into v_cogs
    from return_lines rl join returns r on r.id = rl.return_id where r.return_date::date between p_from and p_to;
  select coalesce(sum(inv.qty_on_hand * i.avg_cost),0) into v_value from inventory inv join items i on i.id = inv.item_id;
  return jsonb_build_object(
    'from', p_from, 'to', p_to, 'period_days', v_days,
    'total_value', round(v_value, 2),
    'period_cogs', round(v_cogs, 2),
    'annualized_cogs', round(v_cogs * 365 / v_days, 2),
    'turnover', case when v_value > 0 then round(v_cogs * 365 / v_days / v_value, 2) end,
    'days_on_hand', case when v_cogs > 0 then round(v_value / (v_cogs / v_days), 1) end,
    'by_location', (select jsonb_agg(jsonb_build_object('location', l.name, 'code', l.code,
          'value', coalesce((select round(sum(inv.qty_on_hand * i.avg_cost),2) from inventory inv join items i on i.id = inv.item_id where inv.location_id = l.id), 0),
          'units', coalesce((select sum(qty_on_hand) from inventory where location_id = l.id), 0)) order by l.id) from locations l),
    'by_category', (select jsonb_agg(x order by (x->>'value')::numeric desc) from (
          select jsonb_build_object('category', i.category, 'value', round(sum(inv.qty_on_hand * i.avg_cost), 2)) x
          from inventory inv join items i on i.id = inv.item_id group by i.category) c),
    'items', (select jsonb_agg(row_to_json(t)::jsonb order by t.value desc) from (
          select i.id, i.sku, i.name, i.category, i.avg_cost,
            coalesce(sum(inv.qty_on_hand),0) as qty, round(coalesce(sum(inv.qty_on_hand),0) * i.avg_cost, 2) as value,
            coalesce((select sum(sl.line_cost) from sale_lines sl join sales s on s.id = sl.sale_id
                      where sl.item_id = i.id and s.sale_date::date between p_from and p_to), 0) as cogs,
            case when coalesce(sum(inv.qty_on_hand),0) * i.avg_cost > 0 then
              round(coalesce((select sum(sl.line_cost) from sale_lines sl join sales s on s.id = sl.sale_id
                      where sl.item_id = i.id and s.sale_date::date between p_from and p_to), 0) * 365 / v_days / (sum(inv.qty_on_hand) * i.avg_cost), 2) end as turnover
          from items i left join inventory inv on inv.item_id = i.id where i.item_type <> 'service'
          group by i.id) t)
  );
end $$;

-- ---------- production report & quality metrics -----------------------
create or replace function get_production_report(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return (
  with o as (
    select po.*, i.name item_name, i.sku, l.code loc,
      extract(epoch from (po.finished_at - po.started_at)) / 3600.0 as cycle_hours
    from production_orders po join items i on i.id = po.item_id join locations l on l.id = po.location_id
    where coalesce(po.started_at, po.created_at)::date between p_from and p_to),
  c as (select * from o where status = 'Completed')
  select jsonb_build_object(
    'orders', coalesce((select jsonb_agg(row_to_json(o)::jsonb order by coalesce(o.started_at, o.created_at) desc) from o), '[]'),
    'metrics', jsonb_build_object(
      'orders_completed', (select count(*) from c),
      'units_started', coalesce((select sum(qty_started) from c), 0),
      'units_good', coalesce((select sum(qty_good) from c), 0),
      'units_scrapped', coalesce((select sum(qty_scrapped) from c), 0),
      'units_reworked', coalesce((select sum(qty_reworked) from c), 0),
      'yield_pct', (select round(100.0 * sum(qty_good) / nullif(sum(qty_started),0), 2) from c),
      'first_pass_yield_pct', (select round(100.0 * sum(qty_good - qty_reworked) / nullif(sum(qty_started),0), 2) from c),
      'scrap_rate_pct', (select round(100.0 * sum(qty_scrapped) / nullif(sum(qty_started),0), 2) from c),
      'avg_cycle_hours', (select round(avg(cycle_hours)::numeric, 2) from c),
      'on_time_pct', (select round(100.0 * count(*) filter (where finished_at::date <= due_date) / nullif(count(*),0), 1) from c),
      'throughput_per_day', (select round(sum(qty_good) / greatest(p_to - p_from + 1, 1)::numeric, 2) from c),
      'scrap_cost', coalesce((select round(sum(material_cost * qty_scrapped / nullif(qty_started,0)), 2) from c), 0),
      'avg_unit_cost', (select round(sum(material_cost) / nullif(sum(qty_good),0), 2) from c)),
    'by_reason', coalesce((select jsonb_agg(jsonb_build_object('code', scrap_reason_code, 'description', rc.description,
          'scrapped', s_scr, 'reworked', s_rw, 'orders', n) order by s_scr desc)
        from (select scrap_reason_code, sum(qty_scrapped) s_scr, sum(qty_reworked) s_rw, count(*) n from c
              where scrap_reason_code is not null group by 1) x left join reason_codes rc on rc.code = x.scrap_reason_code), '[]'),
    'by_item', coalesce((select jsonb_agg(jsonb_build_object('item', item_name, 'orders', n, 'good', g, 'scrapped', s,
          'yield_pct', round(100.0 * g / nullif(g + s, 0), 1), 'avg_unit_cost', round(mc / nullif(g,0), 0)) order by g desc)
        from (select item_name, count(*) n, sum(qty_good) g, sum(qty_scrapped) s, sum(material_cost) mc from c group by 1) y), '[]'),
    'weekly', coalesce((select jsonb_agg(jsonb_build_object('week', wk, 'good', g, 'scrapped', s) order by wk)
        from (select to_char(date_trunc('week', finished_at), 'YYYY-MM-DD') wk, sum(qty_good) g, sum(qty_scrapped) s from c group by 1) z), '[]')
  ));
end $$;

-- ---------- supplier scorecards (computed from PO history) -------------
create or replace function get_supplier_scorecards() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return (
  with first_rcpt as (
    select po.id po_id, po.supplier_id, po.order_date, po.expected_date, min(r.receipt_date) first_date
    from purchase_orders po join po_receipts r on r.po_id = po.id
    where po.order_date is not null group by po.id),
  fill as (
    select po.supplier_id, sum(pol.qty_received) rec, sum(pol.qty_ordered) ord
    from purchase_orders po join purchase_order_lines pol on pol.po_id = po.id
    where po.status in ('Received','Closed','Partially Received') group by po.supplier_id),
  pay as (
    select po.supplier_id,
      sum(r.amount - r.paid_amount) owed,
      sum(case when r.due_date < current_date then r.amount - r.paid_amount else 0 end) overdue,
      min(case when r.amount > r.paid_amount then r.due_date end) next_due,
      count(*) filter (where r.paid_date is not null) paid_n,
      count(*) filter (where r.paid_date is not null and r.paid_date <= r.due_date) paid_on_time_n,
      sum(r.amount) billed
    from purchase_orders po join po_receipts r on r.po_id = po.id group by po.supplier_id),
  base as (
    select s.*,
      (select count(*) from purchase_orders where supplier_id = s.id and status <> 'Cancelled' and status <> 'Draft') po_count,
      (select count(*) from purchase_orders where supplier_id = s.id and status in ('Order Sent','Partially Received')) open_pos,
      (select count(*) from first_rcpt f where f.supplier_id = s.id) received_pos,
      (select round(100.0 * count(*) filter (where f.first_date <= f.expected_date) / nullif(count(*),0), 1) from first_rcpt f where f.supplier_id = s.id) on_time_pct,
      (select round(avg(f.first_date - f.order_date), 1) from first_rcpt f where f.supplier_id = s.id) avg_actual_lead,
      (select round(avg(f.first_date - f.expected_date), 1) from first_rcpt f where f.supplier_id = s.id) avg_days_late,
      (select round(100.0 * rec / nullif(ord,0), 1) from fill where fill.supplier_id = s.id) fill_rate_pct,
      coalesce(pay.owed, 0) owed, coalesce(pay.overdue, 0) overdue, pay.next_due, coalesce(pay.billed,0) billed,
      case when pay.paid_n > 0 then round(100.0 * pay.paid_on_time_n / pay.paid_n, 1) end as paid_on_time_pct
    from suppliers s left join pay on pay.supplier_id = s.id)
  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.score desc nulls last), '[]') from (
    select b.*,
      round(case when b.received_pos = 0 then null else
        0.40 * coalesce(b.on_time_pct, 0)
      + 0.35 * coalesce(b.fill_rate_pct, 0)
      + 0.25 * least(100, 100.0 * b.lead_time_days / nullif(greatest(b.avg_actual_lead, 1), 0)) end, 1) as score,
      case when b.received_pos = 0 then 'New'
           when 0.40 * coalesce(b.on_time_pct,0) + 0.35 * coalesce(b.fill_rate_pct,0)
              + 0.25 * least(100, 100.0 * b.lead_time_days / nullif(greatest(b.avg_actual_lead,1),0)) >= 85 then 'Keep'
           when 0.40 * coalesce(b.on_time_pct,0) + 0.35 * coalesce(b.fill_rate_pct,0)
              + 0.25 * least(100, 100.0 * b.lead_time_days / nullif(greatest(b.avg_actual_lead,1),0)) >= 70 then 'Watch'
           else 'Replace' end as rating,
      (select coalesce(jsonb_agg(jsonb_build_object('po_number', po.po_number, 'status', po.status, 'order_date', po.order_date,
            'expected_date', po.expected_date, 'first_receipt', (select min(receipt_date) from po_receipts where po_id = po.id),
            'ordered', (select sum(qty_ordered) from purchase_order_lines where po_id = po.id),
            'received', (select sum(qty_received) from purchase_order_lines where po_id = po.id),
            'amount', (select sum(qty_ordered * unit_cost) from purchase_order_lines where po_id = po.id)) order by po.order_date desc nulls first), '[]')
        from purchase_orders po where po.supplier_id = b.id and po.status <> 'Draft') as history,
      (select coalesce(jsonb_agg(jsonb_build_object('receipt_id', r.id, 'po_number', po.po_number, 'receipt_date', r.receipt_date,
            'amount', r.amount, 'paid', r.paid_amount, 'due_date', r.due_date) order by r.due_date), '[]')
        from po_receipts r join purchase_orders po on po.id = r.po_id where po.supplier_id = b.id and r.amount > r.paid_amount) as open_bills
    from base b
  ) x);
end $$;

-- ---------- sales analytics --------------------------------------------
create or replace function get_sales_report(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return (
  with s as (select * from sales where sale_date::date between p_from and p_to),
  sl as (select sl.*, i.name, i.category, i.item_type, s.sale_date from sale_lines sl join s on s.id = sl.sale_id join items i on i.id = sl.item_id)
  select jsonb_build_object(
    'totals', jsonb_build_object('revenue', coalesce((select sum(line_total) from sl),0),
       'cost', coalesce((select sum(line_cost) from sl),0), 'transactions', (select count(*) from s),
       'units', coalesce((select sum(qty) from sl where item_type <> 'service'),0),
       'avg_ticket', (select round(avg(total)) from s)),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('date', d, 'revenue', coalesce(rev,0), 'cost', coalesce(cost,0), 'transactions', coalesce(n,0)) order by d)
         from (select g::date d from generate_series(p_from, p_to, interval '1 day') g) days
         left join (select sale_date::date dd, sum(line_total) rev, sum(line_cost) cost from sl group by 1) a on a.dd = days.d
         left join (select sale_date::date dd, count(*) n from s group by 1) b on b.dd = days.d), '[]'),
    'weekly', coalesce((select jsonb_agg(jsonb_build_object('week', wk, 'revenue', rev, 'cost', cost) order by wk)
         from (select to_char(date_trunc('week', sale_date), 'YYYY-MM-DD') wk, sum(line_total) rev, sum(line_cost) cost from sl group by 1) w), '[]'),
    'top_items', coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'name', name, 'category', category, 'qty', q, 'revenue', rev,
             'margin_pct', round(100 * (rev - cost) / nullif(rev,0), 1)) order by rev desc)
         from (select item_id, name, category, sum(qty) q, sum(line_total) rev, sum(line_cost) cost from sl where item_type <> 'service'
               group by 1,2,3 order by sum(line_total) desc limit 15) t), '[]'),
    'by_category', coalesce((select jsonb_agg(jsonb_build_object('category', category, 'revenue', rev) order by rev desc)
         from (select category, sum(line_total) rev from sl group by 1) c), '[]'),
    'by_channel', coalesce((select jsonb_agg(jsonb_build_object('channel', channel, 'revenue', rev, 'n', n) order by rev desc)
         from (select channel, sum(total) rev, count(*) n from s group by 1) c), '[]'),
    'by_payment', coalesce((select jsonb_agg(jsonb_build_object('method', payment_method, 'revenue', rev, 'n', n) order by rev desc)
         from (select payment_method, sum(total) rev, count(*) n from s group by 1) c), '[]'),
    'by_location', coalesce((select jsonb_agg(jsonb_build_object('location', l.name, 'revenue', rev, 'n', n) order by rev desc)
         from (select location_id, sum(total) rev, count(*) n from s group by 1) c join locations l on l.id = c.location_id), '[]'),
    'top_customers', coalesce((select jsonb_agg(jsonb_build_object('customer', c.name, 'type', c.customer_type, 'revenue', rev, 'n', n) order by rev desc)
         from (select customer_id, sum(total) rev, count(*) n from s group by 1 order by 2 desc limit 10) x join customers c on c.id = x.customer_id), '[]')
  ));
end $$;

-- ---------- dashboard ----------------------------------------------------
create or replace function get_dashboard() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform require_staff();
  return (
  with sl as (select sl.*, s.sale_date from sale_lines sl join sales s on s.id = sl.sale_id where s.sale_date >= current_date - 60)
  select jsonb_build_object(
    'today_revenue', coalesce((select sum(total) from sales where sale_date::date = current_date), 0),
    'today_transactions', (select count(*) from sales where sale_date::date = current_date),
    'mtd_revenue', coalesce((select sum(line_total) from sl where sale_date >= date_trunc('month', current_date)), 0),
    'mtd_cost', coalesce((select sum(line_cost) from sl where sale_date >= date_trunc('month', current_date)), 0),
    'last_month_same_period', coalesce((select sum(line_total) from sl where sale_date >= date_trunc('month', current_date) - interval '1 month'
          and sale_date < current_date - interval '1 month' + interval '1 day'), 0),
    'inventory_value', coalesce((select round(sum(inv.qty_on_hand * i.avg_cost)) from inventory inv join items i on i.id = inv.item_id), 0),
    'below_rop', (select count(*) from items i join _positions() p on p.item_id = i.id where i.active and p.on_hand + p.on_order + p.in_production - p.allocated <= i.reorder_point),
    'out_of_stock', (select count(*) from items i join _positions() p on p.item_id = i.id where i.active and p.on_hand <= 0),
    'open_sales_orders', (select count(*) from sales_orders where status = 'Order Placed'),
    'portal_orders_open', (select count(*) from sales_orders where status = 'Order Placed' and channel = 'Portal'),
    'open_pos', (select count(*) from purchase_orders where status in ('Order Sent','Partially Received')),
    'late_pos', (select count(*) from purchase_orders where status in ('Order Sent','Partially Received') and expected_date < current_date),
    'wo_in_progress', (select count(*) from production_orders where status = 'In Progress'),
    'wo_planned', (select count(*) from production_orders where status = 'Planned'),
    'payables_due_7', coalesce((select sum(amount - paid_amount) from po_receipts where amount > paid_amount and due_date <= current_date + 7), 0),
    'payables_overdue', coalesce((select sum(amount - paid_amount) from po_receipts where amount > paid_amount and due_date < current_date), 0),
    'daily', (select jsonb_agg(jsonb_build_object('date', d, 'revenue', coalesce((select sum(line_total) from sl where sale_date::date = d), 0),
                'cost', coalesce((select sum(line_cost) from sl where sale_date::date = d), 0)) order by d)
              from (select (current_date - g)::date d from generate_series(0, 29) g) days),
    'top_items', (select coalesce(jsonb_agg(x), '[]') from (select jsonb_build_object('name', i.name, 'qty', sum(sl.qty), 'revenue', sum(sl.line_total)) x
              from sl join items i on i.id = sl.item_id where sl.sale_date >= current_date - 29 and i.item_type <> 'service'
              group by i.name order by sum(sl.line_total) desc limit 6) t),
    'impact', (select coalesce(jsonb_agg(jsonb_build_object('label', i.impact_label, 'item', i.name, 'qty', coalesce(q,0)) order by i.id), '[]')
              from items i left join (select item_id, sum(qty) q from sale_lines sl join sales s on s.id = sl.sale_id
                where s.sale_date >= date_trunc('year', current_date) group by 1) x on x.item_id = i.id
              where i.impact_label is not null),
    'patients_served_ytd', (select count(*) from sale_lines sl join sales s on s.id = sl.sale_id join items i on i.id = sl.item_id
              where i.sku = 'SVC-CONSULT' and s.sale_date >= date_trunc('year', current_date)),
    'activity', (select coalesce(jsonb_agg(row_to_json(a)::jsonb), '[]') from (
              select created_at, user_name, action, details, ref_no from activity_log where category = 'operations' order by created_at desc, id desc limit 12) a)
  ));
end $$;

create or replace function get_activity(p_category text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if p_category = 'security' then perform require_manager(); else perform require_staff(); end if;
  return (select coalesce(jsonb_agg(row_to_json(a)::jsonb), '[]') from (
    select * from activity_log where p_category is null or category = p_category order by created_at desc, id desc limit p_limit) a);
end $$;

-- ---------- Outreach Readiness Planner (wow feature) --------------------
-- converts expected attendance into kits, checks the Mobile Outreach stock,
-- pulls from other locations, and plans kit builds + component purchases.
create or replace function outreach_plan(p_event int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e record; v_mobile int; v_store int;
begin
  perform require_staff();
  select * into e from outreach_events where id = p_event;
  select id into v_mobile from locations where code = 'MOBILE';
  select id into v_store from locations where code = 'STORE';
  return (
  with req as (
    select i.id, i.sku, i.name, r.basis, ceil(r.qty)::numeric as required
    from (values
      ('KIT-ANC',   e.expected_mothers::numeric, 'ANC pack per expectant mother'),
      ('KIT-MAMA',  e.expected_mothers * setting_num('outreach_delivery_ratio', 0.3), 'Birth kit for mothers near term'),
      ('KIT-CHILD', e.expected_children::numeric, 'Deworming + Vitamin A per child'),
      ('KIT-ORS',   e.expected_children * setting_num('outreach_diarrhoea_ratio', 0.15), 'Children expected with diarrhoea'),
      ('KIT-MAL',   e.expected_malaria_tests * setting_num('malaria_positivity_rate', 0.35), 'Positive malaria tests to treat'),
      ('KIT-WOUND', e.expected_wounds::numeric, 'Wound dressings')
    ) r(sku, qty, basis) join items i on i.sku = r.sku),
  stock as (
    select q.*, coalesce((select qty_on_hand from inventory where item_id = q.id and location_id = v_mobile), 0) at_mobile,
      coalesce((select sum(qty_on_hand) from inventory where item_id = q.id and location_id <> v_mobile), 0) elsewhere,
      coalesce((select qty_on_hand from inventory where item_id = q.id and location_id = v_store), 0) at_store
    from req q),
  plan as (
    select s.*, least(greatest(s.required - s.at_mobile, 0), s.elsewhere) as transfer_qty,
      greatest(s.required - s.at_mobile - s.elsewhere, 0) as build_qty
    from stock s)
  select jsonb_build_object(
    'event', to_jsonb(e),
    'kits', coalesce((select jsonb_agg(to_jsonb(plan) order by plan.id) from plan), '[]'),
    'components', coalesce((select jsonb_agg(jsonb_build_object('item_id', c.id, 'name', c.name, 'needed', c.needed, 'at_store', c.at_store,
          'short', greatest(c.needed - c.at_store, 0), 'supplier', c.supplier, 'lead_time_days', c.lead_time_days,
          'order_by', e.event_date - 2 - c.lead_time_days) order by c.name)
        from (select ci.id, ci.name, ci.lead_time_days, sp.name supplier, sum(p.build_qty * b.qty_per) needed,
                coalesce((select qty_on_hand from inventory where item_id = ci.id and location_id = v_store), 0) at_store
              from plan p join bom_lines b on b.parent_item_id = p.id join items ci on ci.id = b.component_item_id
              left join suppliers sp on sp.id = ci.preferred_supplier_id
              where p.build_qty > 0 group by ci.id, ci.name, ci.lead_time_days, sp.name) c), '[]')
  ));
end $$;

create or replace function outreach_prepare(p_event int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_plan jsonb; k jsonb; v_mobile int; v_need numeric; src record; v_move numeric; v_store int;
        v_transfers int := 0; v_wos int := 0; e record;
begin
  perform require_staff();
  select * into e from outreach_events where id = p_event;
  if e.status <> 'Planned' then raise exception 'Event already %', e.status; end if;
  v_plan := outreach_plan(p_event);
  select id into v_mobile from locations where code = 'MOBILE';
  select id into v_store from locations where code = 'STORE';
  for k in select * from jsonb_array_elements(v_plan->'kits') loop
    v_need := (k->>'transfer_qty')::numeric;
    for src in select location_id, qty_on_hand from inventory where item_id = (k->>'id')::int and location_id <> v_mobile and qty_on_hand > 0
               order by (location_id = v_store) desc, qty_on_hand desc loop
      exit when v_need <= 0;
      v_move := least(v_need, src.qty_on_hand);
      perform inv_transfer(jsonb_build_object('item_id', (k->>'id')::int, 'from_location_id', src.location_id, 'to_location_id', v_mobile,
              'qty', v_move, 'note', 'Outreach: ' || e.name));
      v_need := v_need - v_move; v_transfers := v_transfers + 1;
    end loop;
    if (k->>'build_qty')::numeric > 0 then
      perform wo_create(jsonb_build_object('item_id', (k->>'id')::int, 'location_id', v_store, 'qty', (k->>'build_qty')::numeric,
              'due_date', e.event_date - 2, 'notes', 'Outreach: ' || e.name || ' — transfer to Mobile Outreach when complete'));
      v_wos := v_wos + 1;
    end if;
  end loop;
  update outreach_events set status = 'Prepared' where id = p_event;
  perform _log('Outreach prepared', e.name || ' · ' || v_transfers || ' transfers, ' || v_wos || ' kit build orders', 'outreach', null);
  return jsonb_build_object('transfers', v_transfers, 'production_orders', v_wos);
end $$;
