-- =====================================================================
-- ROSBREN ERP  —  02 BUSINESS LOGIC (every transaction is one atomic DB call)
-- =====================================================================

-- ---------- core inventory movement ----------------------------------
create or replace function _inv_move(p_item int, p_loc int, p_qty numeric, p_type text, p_cost numeric,
  p_ref_type text, p_ref_id bigint, p_ref_no text, p_reason text default null, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_new numeric; v_item record; v_loc text;
begin
  select * into v_item from items where id = p_item;
  if v_item.item_type = 'service' or p_qty = 0 then return; end if;
  insert into inventory(item_id, location_id, qty_on_hand) values (p_item, p_loc, p_qty)
  on conflict (item_id, location_id) do update set qty_on_hand = inventory.qty_on_hand + excluded.qty_on_hand
  returning qty_on_hand into v_new;
  if v_new < 0 then
    select name into v_loc from locations where id = p_loc;
    raise exception 'Insufficient stock: % at % (short by %)', v_item.name, v_loc, -v_new;
  end if;
  insert into inventory_transactions(item_id, location_id, qty_change, txn_type, unit_cost, ref_type, ref_id, ref_no, reason_code, note, user_id)
  values (p_item, p_loc, p_qty, p_type, coalesce(p_cost, v_item.avg_cost), p_ref_type, p_ref_id, p_ref_no, p_reason, p_note, auth.uid());
end $$;

-- weighted-average cost update — call BEFORE adding the received qty
create or replace function _receive_cost(p_item int, p_qty numeric, p_unit_cost numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_on numeric; v_avg numeric;
begin
  select greatest(coalesce(sum(qty_on_hand),0),0) into v_on from inventory where item_id = p_item;
  select avg_cost into v_avg from items where id = p_item;
  if v_on + p_qty > 0 then
    update items set avg_cost = round((v_on * v_avg + p_qty * p_unit_cost) / (v_on + p_qty), 4) where id = p_item;
  end if;
end $$;

-- assemble kits on the spot from components (assemble-to-order backflush)
create or replace function _assemble_kit(p_item int, p_loc int, p_qty numeric, p_ref_type text, p_ref_id bigint, p_ref_no text)
returns void language plpgsql security definer set search_path = public as $$
declare b record; v_cost numeric := 0;
begin
  if not exists (select 1 from bom_lines where parent_item_id = p_item) then
    raise exception 'Item % has no bill of materials', p_item;
  end if;
  for b in select bl.*, i.avg_cost from bom_lines bl join items i on i.id = bl.component_item_id where parent_item_id = p_item loop
    perform _inv_move(b.component_item_id, p_loc, -(b.qty_per * p_qty), 'production_issue', b.avg_cost, p_ref_type, p_ref_id, p_ref_no, null, 'Auto-assembled for sale');
    v_cost := v_cost + b.qty_per * p_qty * b.avg_cost;
  end loop;
  perform _receive_cost(p_item, p_qty, v_cost / p_qty);
  perform _inv_move(p_item, p_loc, p_qty, 'production_receipt', v_cost / p_qty, p_ref_type, p_ref_id, p_ref_no, null, 'Auto-assembled for sale');
end $$;

-- ---------- sale creation (POS, sales-order fulfilment, exchanges) -----
create or replace function _create_sale(p jsonb, p_channel text, p_so_id int)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_sale_id bigint; v_no text; l jsonb; v_item record;
  v_loc int := (p->>'location_id')::int;
  v_odisc numeric := coalesce((p->>'order_discount_pct')::numeric, 0);
  v_tax_rate numeric := setting_num('tax_rate', 0.18);
  v_qty numeric; v_price numeric; v_gross numeric; v_ldisc numeric; v_net numeric; v_tax numeric; v_onhand numeric;
  t_sub numeric := 0; t_disc numeric := 0; t_tax numeric := 0; t_cost numeric := 0;
begin
  if jsonb_array_length(coalesce(p->'lines','[]'::jsonb)) = 0 then raise exception 'Sale has no lines'; end if;
  if v_odisc < 0 or v_odisc > 100 then raise exception 'Discount must be between 0 and 100%%'; end if;
  insert into sales(customer_id, location_id, channel, sales_order_id, payment_method, amount_tendered, cashier_id, cashier_name)
  values ((p->>'customer_id')::int, v_loc, p_channel, p_so_id, coalesce(p->>'payment_method','Cash'),
          (p->>'amount_tendered')::numeric, auth.uid(), current_user_name())
  returning id, sale_number into v_sale_id, v_no;

  for l in select * from jsonb_array_elements(p->'lines') loop
    select * into v_item from items where id = (l->>'item_id')::int;
    if v_item.id is null then raise exception 'Unknown item %', l->>'item_id'; end if;
    v_qty := (l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be positive for %', v_item.name; end if;
    v_price := coalesce((l->>'unit_price')::numeric, v_item.price);
    v_gross := round(v_qty * v_price, 2);
    v_ldisc := round(v_gross * coalesce((l->>'discount_pct')::numeric, 0) / 100, 2);
    v_ldisc := v_ldisc + round((v_gross - v_ldisc) * v_odisc / 100, 2);
    v_net := v_gross - v_ldisc;
    v_tax := case when v_item.taxable then round(v_net * v_tax_rate, 2) else 0 end;

    -- kits: build any shortfall from components right now
    if v_item.item_type = 'kit' then
      select coalesce(qty_on_hand,0) into v_onhand from inventory where item_id = v_item.id and location_id = v_loc;
      v_onhand := coalesce(v_onhand, 0);
      if v_onhand < v_qty then
        perform _assemble_kit(v_item.id, v_loc, v_qty - greatest(v_onhand,0), 'sale', v_sale_id, v_no);
        select * into v_item from items where id = v_item.id;
      end if;
    end if;

    perform _inv_move(v_item.id, v_loc, -v_qty, 'sale', v_item.avg_cost, 'sale', v_sale_id, v_no);
    insert into sale_lines(sale_id, item_id, qty, unit_price, discount_amount, line_total, tax_amount, unit_cost, line_cost)
    values (v_sale_id, v_item.id, v_qty, v_price, v_ldisc, v_net, v_tax, v_item.avg_cost, round(v_qty * v_item.avg_cost, 2));
    t_sub := t_sub + v_gross; t_disc := t_disc + v_ldisc; t_tax := t_tax + v_tax; t_cost := t_cost + round(v_qty * v_item.avg_cost, 2);
  end loop;

  update sales set subtotal = t_sub, discount_total = t_disc, tax_total = t_tax,
                   total = t_sub - t_disc + t_tax, cost_total = t_cost
  where id = v_sale_id;
  return v_sale_id;
end $$;

create or replace function get_sale(p_sale_id bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when is_staff() then (
    select jsonb_build_object(
      'sale', to_jsonb(s) || jsonb_build_object('customer_name', c.name, 'location_name', l.name),
      'lines', coalesce((select jsonb_agg(to_jsonb(sl) || jsonb_build_object('name', i.name, 'sku', i.sku, 'barcode', i.barcode,
                    'returned_qty', coalesce((select sum(rl.qty) from return_lines rl where rl.sale_line_id = sl.id and rl.direction='in'),0))
                    order by sl.id)
                 from sale_lines sl join items i on i.id = sl.item_id where sl.sale_id = s.id), '[]'::jsonb),
      'returns', coalesce((select jsonb_agg(jsonb_build_object('return_number', r.return_number, 'return_type', r.return_type,
                    'return_date', r.return_date, 'net_amount', r.net_amount)) from returns r where r.sale_id = s.id), '[]'::jsonb),
      'company', (select jsonb_object_agg(key, value) from settings where key in ('company_name','company_address','company_phone','currency','receipt_footer')))
    from sales s left join customers c on c.id = s.customer_id join locations l on l.id = s.location_id
    where s.id = p_sale_id or s.sale_number = p_sale_id::text)
  end
$$;

create or replace function find_sale(p_number text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_id bigint;
begin
  perform require_staff();
  select id into v_id from sales where upper(sale_number) = upper(trim(p_number))
     or upper(sale_number) = 'S-' || upper(trim(p_number));
  if v_id is null then raise exception 'Receipt % not found', p_number; end if;
  return get_sale(v_id);
end $$;

-- POS checkout
create or replace function pos_checkout(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_s record;
begin
  perform require_staff();
  v_id := _create_sale(p, 'POS', null);
  select * into v_s from sales where id = v_id;
  perform _log('POS sale', v_s.sale_number || ' · ' || (select count(*) from sale_lines where sale_id = v_id) || ' lines · ' ||
               to_char(v_s.total, 'FM999,999,999') , 'sale', v_s.sale_number);
  return get_sale(v_id);
end $$;

-- ---------- sales orders ----------------------------------------------
create or replace function _insert_so(p jsonb, p_customer int, p_channel text) returns int
language plpgsql security definer set search_path = public as $$
declare v_id int; l jsonb; v_item record; v_disc numeric;
begin
  if jsonb_array_length(coalesce(p->'lines','[]'::jsonb)) = 0 then raise exception 'Order has no lines'; end if;
  select discount_pct into v_disc from customers where id = p_customer;
  insert into sales_orders(customer_id, location_id, requested_date, channel, notes, created_by)
  values (p_customer, (p->>'location_id')::int, coalesce((p->>'requested_date')::date, current_date), p_channel, p->>'notes', auth.uid())
  returning id into v_id;
  for l in select * from jsonb_array_elements(p->'lines') loop
    select * into v_item from items where id = (l->>'item_id')::int and sellable and active;
    if v_item.id is null then raise exception 'Item % cannot be ordered', l->>'item_id'; end if;
    if coalesce((l->>'qty')::numeric,0) <= 0 then raise exception 'Quantity must be positive'; end if;
    insert into sales_order_lines(so_id, item_id, qty, unit_price, discount_pct)
    values (v_id, v_item.id, (l->>'qty')::numeric, v_item.price, coalesce((l->>'discount_pct')::numeric, v_disc, 0));
  end loop;
  return v_id;
end $$;

create or replace function so_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; v_no text;
begin
  perform require_staff();
  v_id := _insert_so(p, (p->>'customer_id')::int, 'Staff');
  select so_number into v_no from sales_orders where id = v_id;
  perform _log('Sales order placed', v_no || ' for ' || (select name from customers where id = (p->>'customer_id')::int), 'sales_order', v_no);
  return jsonb_build_object('id', v_id, 'so_number', v_no);
end $$;

create or replace function so_fulfill(p_so_id int, p_payment_method text default 'Invoice') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_so record; v_sale bigint; v_sale_no text;
begin
  perform require_staff();
  select * into v_so from sales_orders where id = p_so_id for update;
  if v_so.status <> 'Order Placed' then raise exception 'Only orders in "Order Placed" status can be fulfilled (currently %)', v_so.status; end if;
  v_sale := _create_sale(jsonb_build_object(
      'customer_id', v_so.customer_id, 'location_id', v_so.location_id, 'payment_method', p_payment_method,
      'lines', (select jsonb_agg(jsonb_build_object('item_id', item_id, 'qty', qty, 'unit_price', unit_price, 'discount_pct', discount_pct))
                from sales_order_lines where so_id = p_so_id)),
    case when v_so.channel = 'Portal' then 'Portal' else 'Sales Order' end, p_so_id);
  update sales_orders set status = 'Fulfilled', fulfilled_at = now(), sale_id = v_sale where id = p_so_id;
  select sale_number into v_sale_no from sales where id = v_sale;
  perform _log('Sales order fulfilled', v_so.so_number || ' → invoice ' || v_sale_no, 'sales_order', v_so.so_number);
  return get_sale(v_sale);
end $$;

create or replace function so_set_status(p_so_id int, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare v_so record;
begin
  perform require_staff();
  select * into v_so from sales_orders where id = p_so_id for update;
  if p_status = 'Closed' and v_so.status <> 'Fulfilled' then raise exception 'Only fulfilled orders can be closed'; end if;
  if p_status = 'Cancelled' and v_so.status <> 'Order Placed' then raise exception 'Only open orders can be cancelled'; end if;
  update sales_orders set status = p_status,
    closed_at = case when p_status = 'Closed' then now() else closed_at end,
    cancelled_at = case when p_status = 'Cancelled' then now() else cancelled_at end
  where id = p_so_id;
  perform _log('Sales order ' || lower(p_status), v_so.so_number, 'sales_order', v_so.so_number);
end $$;

-- ---------- returns & exchanges ----------------------------------------
-- p: {sale_id, location_id, return_type, reason_code, notes,
--     lines:[{sale_line_id, qty, disposition:'restock'|'write_off'}], replacements:[{item_id, qty}]}
create or replace function process_return(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ret int; v_no text; v_sale record; l jsonb; v_sl record; v_item record;
  v_loc int := (p->>'location_id')::int; v_qty numeric; v_already numeric;
  v_net numeric; v_tax numeric; v_cost numeric; v_refund numeric := 0; v_repl numeric := 0;
  v_reason text := p->>'reason_code'; v_tax_rate numeric := setting_num('tax_rate', 0.18);
  v_disp text;
begin
  perform require_staff();
  select * into v_sale from sales where id = (p->>'sale_id')::bigint;
  if v_sale.id is null then raise exception 'Original sale not found'; end if;
  if v_reason is null then raise exception 'A reason code is required'; end if;
  if jsonb_array_length(coalesce(p->'lines','[]'::jsonb)) = 0 then raise exception 'Select at least one item to return'; end if;
  if p->>'return_type' = 'Exchange' and jsonb_array_length(coalesce(p->'replacements','[]'::jsonb)) = 0 then
    raise exception 'An exchange needs at least one replacement item';
  end if;

  insert into returns(return_type, sale_id, customer_id, location_id, reason_code, notes, user_id, user_name)
  values (coalesce(p->>'return_type','Return'), v_sale.id, v_sale.customer_id, v_loc, v_reason, p->>'notes', auth.uid(), current_user_name())
  returning id, return_number into v_ret, v_no;

  for l in select * from jsonb_array_elements(p->'lines') loop
    select * into v_sl from sale_lines where id = (l->>'sale_line_id')::bigint and sale_id = v_sale.id;
    if v_sl.id is null then raise exception 'Line does not belong to this sale'; end if;
    v_qty := (l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then continue; end if;
    select coalesce(sum(qty),0) into v_already from return_lines where sale_line_id = v_sl.id and direction = 'in';
    if v_qty > v_sl.qty - v_already then
      raise exception 'Cannot return % — only % left returnable on this line', v_qty, v_sl.qty - v_already;
    end if;
    v_net := round(v_sl.line_total / v_sl.qty * v_qty, 2);
    v_tax := round(v_sl.tax_amount / v_sl.qty * v_qty, 2);
    v_cost := round(v_sl.unit_cost * v_qty, 2);
    v_disp := coalesce(l->>'disposition', 'restock');
    insert into return_lines(return_id, direction, sale_line_id, item_id, qty, unit_price, line_total, tax_amount, unit_cost, line_cost, disposition, reason_code)
    values (v_ret, 'in', v_sl.id, v_sl.item_id, v_qty, v_sl.unit_price, v_net, v_tax, v_sl.unit_cost, v_cost, v_disp, v_reason);
    -- goods come back into inventory at their original cost
    perform _receive_cost(v_sl.item_id, v_qty, v_sl.unit_cost);
    perform _inv_move(v_sl.item_id, v_loc, v_qty, 'return', v_sl.unit_cost, 'return', v_ret, v_no, v_reason, 'Returned from ' || v_sale.sale_number);
    -- quality failures are pulled out of sellable stock immediately
    if v_disp = 'write_off' then
      perform _inv_move(v_sl.item_id, v_loc, -v_qty, 'write_off', v_sl.unit_cost, 'return', v_ret, v_no, v_reason, 'Quality failure – quarantined & written off');
    end if;
    v_refund := v_refund + v_net + v_tax;
  end loop;

  for l in select * from jsonb_array_elements(coalesce(p->'replacements','[]'::jsonb)) loop
    select * into v_item from items where id = (l->>'item_id')::int;
    v_qty := (l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then continue; end if;
    if v_item.item_type = 'kit' and coalesce((select qty_on_hand from inventory where item_id = v_item.id and location_id = v_loc),0) < v_qty then
      perform _assemble_kit(v_item.id, v_loc, v_qty - greatest(coalesce((select qty_on_hand from inventory where item_id = v_item.id and location_id = v_loc),0),0), 'return', v_ret, v_no);
      select * into v_item from items where id = v_item.id;
    end if;
    v_net := round(v_qty * v_item.price, 2);
    v_tax := case when v_item.taxable then round(v_net * v_tax_rate, 2) else 0 end;
    insert into return_lines(return_id, direction, item_id, qty, unit_price, line_total, tax_amount, unit_cost, line_cost)
    values (v_ret, 'out', v_item.id, v_qty, v_item.price, v_net, v_tax, v_item.avg_cost, round(v_qty * v_item.avg_cost, 2));
    perform _inv_move(v_item.id, v_loc, -v_qty, 'exchange_out', v_item.avg_cost, 'return', v_ret, v_no, null, 'Exchange replacement');
    v_repl := v_repl + v_net + v_tax;
  end loop;

  update returns set refund_total = v_refund, replacement_total = v_repl, net_amount = v_repl - v_refund where id = v_ret;
  perform _log(coalesce(p->>'return_type','Return') || ' processed',
    v_no || ' on ' || v_sale.sale_number || ' · reason ' || v_reason || ' · net ' || to_char(v_repl - v_refund, 'FM999,999,990'), 'return', v_no);
  return jsonb_build_object('id', v_ret, 'return_number', v_no, 'refund_total', v_refund, 'replacement_total', v_repl, 'net_amount', v_repl - v_refund);
end $$;

-- ---------- transfers & adjustments ----------------------------------
create or replace function inv_transfer(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; v_no text; v_item int := (p->>'item_id')::int; v_from int := (p->>'from_location_id')::int;
        v_to int := (p->>'to_location_id')::int; v_qty numeric := (p->>'qty')::numeric; v_cost numeric;
begin
  perform require_staff();
  if v_from = v_to then raise exception 'Choose two different locations'; end if;
  if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be positive'; end if;
  insert into transfers(item_id, from_location_id, to_location_id, qty, note, user_id, user_name)
  values (v_item, v_from, v_to, v_qty, p->>'note', auth.uid(), current_user_name()) returning id, transfer_number into v_id, v_no;
  select avg_cost into v_cost from items where id = v_item;
  perform _inv_move(v_item, v_from, -v_qty, 'transfer_out', v_cost, 'transfer', v_id, v_no, null, p->>'note');
  perform _inv_move(v_item, v_to, v_qty, 'transfer_in', v_cost, 'transfer', v_id, v_no, null, p->>'note');
  perform _log('Stock transfer', v_no || ' · ' || v_qty || ' × ' || (select name from items where id = v_item) || ' · ' ||
    (select code from locations where id = v_from) || ' → ' || (select code from locations where id = v_to), 'transfer', v_no);
  return jsonb_build_object('transfer_number', v_no);
end $$;

-- p: {item_id, location_id, mode:'count'|'delta', qty, reason_code, note}
create or replace function inv_adjust(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_item int := (p->>'item_id')::int; v_loc int := (p->>'location_id')::int; v_cur numeric; v_delta numeric; v_cost numeric;
begin
  perform require_staff();
  if p->>'reason_code' is null then raise exception 'A reason code is required for adjustments'; end if;
  select coalesce((select qty_on_hand from inventory where item_id = v_item and location_id = v_loc), 0) into v_cur;
  if p->>'mode' = 'count' then
    if (p->>'qty')::numeric < 0 then raise exception 'Counted quantity cannot be negative'; end if;
    v_delta := (p->>'qty')::numeric - v_cur;
  else
    v_delta := (p->>'qty')::numeric;
  end if;
  if v_delta = 0 then return jsonb_build_object('delta', 0, 'message', 'Count matches system — no adjustment needed'); end if;
  select avg_cost into v_cost from items where id = v_item;
  perform _inv_move(v_item, v_loc, v_delta, 'adjustment', v_cost, 'adjustment', null, null, p->>'reason_code', p->>'note');
  perform _log('Inventory adjustment', (select name from items where id = v_item) || ' @ ' || (select code from locations where id = v_loc) ||
     ' · ' || case when v_delta > 0 then '+' else '' end || v_delta || ' · ' || (p->>'reason_code'), 'adjustment', null);
  return jsonb_build_object('delta', v_delta, 'value', round(v_delta * v_cost, 2));
end $$;

-- ---------- production orders (kit assembly work orders) --------------
create or replace function wo_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; v_no text;
begin
  perform require_staff();
  if not exists (select 1 from bom_lines where parent_item_id = (p->>'item_id')::int) then
    raise exception 'This item has no bill of materials';
  end if;
  insert into production_orders(item_id, location_id, qty_planned, due_date, notes, created_by)
  values ((p->>'item_id')::int, (p->>'location_id')::int, (p->>'qty')::numeric, coalesce((p->>'due_date')::date, current_date + 2), p->>'notes', auth.uid())
  returning id, wo_number into v_id, v_no;
  perform _log('Production order created', v_no || ' · ' || (p->>'qty') || ' × ' || (select name from items where id = (p->>'item_id')::int), 'production', v_no);
  return jsonb_build_object('id', v_id, 'wo_number', v_no);
end $$;

-- issue components & start
create or replace function wo_start(p_wo_id int) returns void
language plpgsql security definer set search_path = public as $$
declare v_wo record; b record; v_total numeric := 0; v_short text := '';
begin
  perform require_staff();
  select * into v_wo from production_orders where id = p_wo_id for update;
  if v_wo.status <> 'Planned' then raise exception 'Only planned orders can be started'; end if;
  -- check every component first so the user sees all shortages at once
  for b in select bl.*, i.name, coalesce(inv.qty_on_hand,0) as onhand from bom_lines bl join items i on i.id = bl.component_item_id
           left join inventory inv on inv.item_id = bl.component_item_id and inv.location_id = v_wo.location_id
           where bl.parent_item_id = v_wo.item_id loop
    if b.onhand < b.qty_per * v_wo.qty_planned then
      v_short := v_short || b.name || ' (need ' || (b.qty_per * v_wo.qty_planned) || ', have ' || b.onhand || '); ';
    end if;
  end loop;
  if v_short <> '' then raise exception 'Not enough components at this location: %', v_short; end if;

  for b in select bl.*, i.avg_cost from bom_lines bl join items i on i.id = bl.component_item_id where bl.parent_item_id = v_wo.item_id loop
    perform _inv_move(b.component_item_id, v_wo.location_id, -(b.qty_per * v_wo.qty_planned), 'production_issue', b.avg_cost, 'production', p_wo_id, v_wo.wo_number);
    insert into production_order_components(wo_id, item_id, qty_per, qty_issued, unit_cost, total_cost)
    values (p_wo_id, b.component_item_id, b.qty_per, b.qty_per * v_wo.qty_planned, b.avg_cost, round(b.qty_per * v_wo.qty_planned * b.avg_cost, 2));
    v_total := v_total + round(b.qty_per * v_wo.qty_planned * b.avg_cost, 2);
  end loop;
  update production_orders set status = 'In Progress', started_at = now(), qty_started = qty_planned, material_cost = v_total where id = p_wo_id;
  perform _log('Production started', v_wo.wo_number || ' · components issued, material cost ' || to_char(v_total, 'FM999,999,990'), 'production', v_wo.wo_number);
end $$;

-- p: {qty_good, qty_scrapped, qty_reworked, scrap_reason_code, notes}
create or replace function wo_complete(p_wo_id int, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wo record; v_good numeric := coalesce((p->>'qty_good')::numeric,0); v_scrap numeric := coalesce((p->>'qty_scrapped')::numeric,0);
        v_rework numeric := coalesce((p->>'qty_reworked')::numeric,0); v_unit numeric;
begin
  perform require_staff();
  select * into v_wo from production_orders where id = p_wo_id for update;
  if v_wo.status <> 'In Progress' then raise exception 'Only in-progress orders can be completed'; end if;
  if v_good < 0 or v_scrap < 0 or v_rework < 0 then raise exception 'Quantities cannot be negative'; end if;
  if v_good + v_scrap <> v_wo.qty_started then
    raise exception 'Good (%) + scrapped (%) must equal quantity started (%)', v_good, v_scrap, v_wo.qty_started;
  end if;
  if v_rework > v_good then raise exception 'Reworked units must be counted within the good units'; end if;
  if (v_scrap > 0 or v_rework > 0) and coalesce(p->>'scrap_reason_code','') = '' then
    raise exception 'A quality reason code is required when units are scrapped or reworked';
  end if;
  v_unit := case when v_good > 0 then round(v_wo.material_cost / v_good, 4) end;  -- scrap cost absorbed by good units
  if v_good > 0 then
    perform _receive_cost(v_wo.item_id, v_good, v_unit);
    perform _inv_move(v_wo.item_id, v_wo.location_id, v_good, 'production_receipt', v_unit, 'production', p_wo_id, v_wo.wo_number);
  end if;
  update production_orders set status = 'Completed', finished_at = now(), qty_good = v_good, qty_scrapped = v_scrap,
    qty_reworked = v_rework, scrap_reason_code = nullif(p->>'scrap_reason_code',''), unit_cost = v_unit,
    notes = coalesce(nullif(p->>'notes',''), notes)
  where id = p_wo_id;
  perform _log('Production completed', v_wo.wo_number || ' · ' || v_good || ' good, ' || v_scrap || ' scrapped · unit cost ' ||
     coalesce(to_char(v_unit, 'FM999,999,990'),'n/a'), 'production', v_wo.wo_number);
  return jsonb_build_object('unit_cost', v_unit);
end $$;

create or replace function wo_cancel(p_wo_id int) returns void
language plpgsql security definer set search_path = public as $$
declare v_wo record;
begin
  perform require_staff();
  select * into v_wo from production_orders where id = p_wo_id for update;
  if v_wo.status <> 'Planned' then raise exception 'Only planned (not yet started) orders can be cancelled'; end if;
  update production_orders set status = 'Cancelled' where id = p_wo_id;
  perform _log('Production order cancelled', v_wo.wo_number, 'production', v_wo.wo_number);
end $$;

-- ---------- purchasing --------------------------------------------------
-- p: {supplier_id, location_id, notes, source, send:boolean, lines:[{item_id, qty, unit_cost}]}
create or replace function po_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; v_no text; l jsonb; v_lt int;
begin
  perform require_staff();
  if jsonb_array_length(coalesce(p->'lines','[]'::jsonb)) = 0 then raise exception 'Purchase order has no lines'; end if;
  select lead_time_days into v_lt from suppliers where id = (p->>'supplier_id')::int;
  insert into purchase_orders(supplier_id, location_id, notes, source, created_by, expected_date)
  values ((p->>'supplier_id')::int, (p->>'location_id')::int, p->>'notes', coalesce(p->>'source','Manual'), auth.uid(), current_date + v_lt)
  returning id, po_number into v_id, v_no;
  for l in select * from jsonb_array_elements(p->'lines') loop
    if coalesce((l->>'qty')::numeric,0) <= 0 then raise exception 'Quantities must be positive'; end if;
    insert into purchase_order_lines(po_id, item_id, qty_ordered, unit_cost)
    values (v_id, (l->>'item_id')::int, (l->>'qty')::numeric,
            coalesce((l->>'unit_cost')::numeric, (select avg_cost from items where id = (l->>'item_id')::int)));
  end loop;
  perform _log('Purchase order created', v_no || ' · ' || (select name from suppliers where id = (p->>'supplier_id')::int) ||
               ' · source: ' || coalesce(p->>'source','Manual'), 'purchase_order', v_no);
  if coalesce((p->>'send')::boolean, false) then perform po_send(v_id); end if;
  return jsonb_build_object('id', v_id, 'po_number', v_no);
end $$;

create or replace function po_send(p_po_id int) returns void
language plpgsql security definer set search_path = public as $$
declare v_po record; v_lt int;
begin
  perform require_staff();
  select * into v_po from purchase_orders where id = p_po_id for update;
  if v_po.status <> 'Draft' then raise exception 'Only draft POs can be sent'; end if;
  select lead_time_days into v_lt from suppliers where id = v_po.supplier_id;
  update purchase_orders set status = 'Order Sent', order_date = current_date, expected_date = current_date + v_lt where id = p_po_id;
  perform _log('Purchase order sent', v_po.po_number || ' · expected ' || to_char(current_date + v_lt, 'DD Mon YYYY'), 'purchase_order', v_po.po_number);
end $$;

-- p: {po_id, location_id, receipt_date, notes, lines:[{po_line_id, qty}]}
create or replace function po_receive(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_po record; v_rid int; l jsonb; v_pl record; v_qty numeric; v_amt numeric := 0; v_terms int;
        v_date date := coalesce((p->>'receipt_date')::date, current_date); v_loc int; v_open numeric;
begin
  perform require_staff();
  select * into v_po from purchase_orders where id = (p->>'po_id')::int for update;
  if v_po.status not in ('Order Sent','Partially Received') then raise exception 'PO must be sent before receiving (status %)', v_po.status; end if;
  v_loc := coalesce((p->>'location_id')::int, v_po.location_id);
  select payment_terms_days into v_terms from suppliers where id = v_po.supplier_id;
  insert into po_receipts(po_id, receipt_date, location_id, due_date, notes, received_by, received_by_name)
  values (v_po.id, v_date, v_loc, v_date + v_terms, p->>'notes', auth.uid(), current_user_name()) returning id into v_rid;
  for l in select * from jsonb_array_elements(p->'lines') loop
    v_qty := coalesce((l->>'qty')::numeric, 0);
    if v_qty = 0 then continue; end if;
    select * into v_pl from purchase_order_lines where id = (l->>'po_line_id')::int and po_id = v_po.id for update;
    if v_pl.id is null then raise exception 'Line not on this PO'; end if;
    if v_qty < 0 or v_qty > v_pl.qty_ordered - v_pl.qty_received then
      raise exception 'Receive qty for % must be between 0 and % (remaining)', (select name from items where id = v_pl.item_id), v_pl.qty_ordered - v_pl.qty_received;
    end if;
    perform _receive_cost(v_pl.item_id, v_qty, v_pl.unit_cost);
    perform _inv_move(v_pl.item_id, v_loc, v_qty, 'receipt', v_pl.unit_cost, 'purchase_order', v_po.id, v_po.po_number);
    update purchase_order_lines set qty_received = qty_received + v_qty where id = v_pl.id;
    insert into po_receipt_lines(receipt_id, po_line_id, item_id, qty) values (v_rid, v_pl.id, v_pl.item_id, v_qty);
    v_amt := v_amt + round(v_qty * v_pl.unit_cost, 2);
  end loop;
  if v_amt = 0 then raise exception 'Enter at least one quantity to receive'; end if;
  update po_receipts set amount = v_amt where id = v_rid;
  select coalesce(sum(qty_ordered - qty_received),0) into v_open from purchase_order_lines where po_id = v_po.id;
  update purchase_orders set status = case when v_open = 0 then 'Received' else 'Partially Received' end where id = v_po.id;
  perform _log('PO received', v_po.po_number || ' · ' || to_char(v_amt,'FM999,999,990') || ' · ' ||
     case when v_date <= v_po.expected_date then 'on time' else (v_date - v_po.expected_date) || ' days late' end, 'purchase_order', v_po.po_number);
  return jsonb_build_object('receipt_id', v_rid, 'amount', v_amt, 'days_late', v_date - v_po.expected_date, 'status',
     case when v_open = 0 then 'Received' else 'Partially Received' end);
end $$;

create or replace function po_set_status(p_po_id int, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare v_po record;
begin
  perform require_staff();
  select * into v_po from purchase_orders where id = p_po_id for update;
  if p_status = 'Closed' and v_po.status not in ('Received','Partially Received') then raise exception 'Only received POs can be closed'; end if;
  if p_status = 'Cancelled' and v_po.status not in ('Draft','Order Sent') then raise exception 'Only draft or sent POs (nothing received) can be cancelled'; end if;
  update purchase_orders set status = p_status, closed_at = now() where id = p_po_id;
  perform _log('Purchase order ' || lower(p_status), v_po.po_number, 'purchase_order', v_po.po_number);
end $$;

create or replace function pay_bill(p_receipt_id int, p_amount numeric default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_r record;
begin
  perform require_manager();
  select * into v_r from po_receipts where id = p_receipt_id for update;
  update po_receipts set paid_amount = least(amount, paid_amount + coalesce(p_amount, amount - paid_amount)), paid_date = current_date
  where id = p_receipt_id;
  perform _log('Supplier bill paid', (select po_number from purchase_orders where id = v_r.po_id) || ' · ' ||
     to_char(coalesce(p_amount, v_r.amount - v_r.paid_amount), 'FM999,999,990'), 'purchase_order', null);
end $$;

-- one click: turn suggestion list into draft/sent POs grouped by supplier
-- p: {location_id, source, send, lines:[{item_id, qty}]}
create or replace function create_pos_from_suggestions(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s record; v_res jsonb := '[]'::jsonb; v_po jsonb;
begin
  perform require_staff();
  for s in
    select i.preferred_supplier_id as sid,
           jsonb_agg(jsonb_build_object('item_id', i.id, 'qty', ceil((l->>'qty')::numeric), 'unit_cost', round(i.avg_cost))) as lines
    from jsonb_array_elements(p->'lines') l join items i on i.id = (l->>'item_id')::int
    where i.preferred_supplier_id is not null and (l->>'qty')::numeric > 0
    group by i.preferred_supplier_id
  loop
    v_po := po_create(jsonb_build_object('supplier_id', s.sid, 'location_id', coalesce((p->>'location_id')::int, (select id from locations where code='STORE')),
                       'source', coalesce(p->>'source','ROP'), 'send', coalesce((p->>'send')::boolean,false), 'lines', s.lines));
    v_res := v_res || jsonb_build_array(v_po);
  end loop;
  return v_res;
end $$;

-- ---------- periodic review -------------------------------------------
create or replace function mark_reviewed(p_item_ids int[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_staff();
  update items set last_reviewed_at = current_date where id = any(p_item_ids);
  perform _log('Periodic review', array_length(p_item_ids,1) || ' items reviewed', 'review', null);
end $$;

create or replace function apply_reorder_points(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare l jsonb;
begin
  perform require_staff();
  for l in select * from jsonb_array_elements(p) loop
    update items set reorder_point = (l->>'reorder_point')::numeric where id = (l->>'item_id')::int;
  end loop;
  perform _log('Reorder points updated', jsonb_array_length(p) || ' items recalculated from sales history', 'review', null);
end $$;

-- ---------- master data saves (with audit) -----------------------------
create or replace function save_record(p_table text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; v_row jsonb;
begin
  if p_table in ('expenses','settings') then perform require_manager(); else perform require_staff(); end if;
  if p_table not in ('items','suppliers','customers','locations','bom_lines','expenses','outreach_events','reason_codes') then
    raise exception 'Not allowed';
  end if;
  if (p->>'id') is null then
    execute format('insert into %I (%s) select %s from jsonb_populate_record(null::%I, $1) r returning to_jsonb(%I.*)',
      p_table,
      (select string_agg(quote_ident(k), ',') from jsonb_object_keys(p - 'id') k),
      (select string_agg('r.' || quote_ident(k), ',') from jsonb_object_keys(p - 'id') k), p_table, p_table)
      using p into v_row;
  else
    execute format('update %I t set (%s) = (select %s from jsonb_populate_record(t, $1) r) where id = ($1->>''id'')::int returning to_jsonb(t.*)',
      p_table,
      (select string_agg(quote_ident(k), ',') from jsonb_object_keys(p - 'id') k),
      (select string_agg('r.' || quote_ident(k), ',') from jsonb_object_keys(p - 'id') k))
      using p into v_row;
  end if;
  -- a supplier's quoted lead time is the lead time of the items it supplies (drives ROP, MRP, PO dates)
  if p_table = 'suppliers' and p ? 'lead_time_days' then
    update items set lead_time_days = (v_row->>'lead_time_days')::int where preferred_supplier_id = (v_row->>'id')::int;
  end if;
  perform _log('Saved ' || replace(p_table,'_',' '), coalesce(v_row->>'name', v_row->>'description', v_row->>'id'), p_table, v_row->>'id');
  return v_row;
end $$;

create or replace function save_settings(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  perform require_manager();
  for k in select jsonb_object_keys(p) loop
    update settings set value = p->>k where key = k;
  end loop;
  perform _log('Settings changed', (select string_agg(k2 || '=' || (p->>k2), ', ') from jsonb_object_keys(p) k2), 'settings', null, 'security');
end $$;

create or replace function save_bom(p_parent int, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_staff();
  delete from bom_lines where parent_item_id = p_parent;
  insert into bom_lines(parent_item_id, component_item_id, qty_per)
  select p_parent, (l->>'component_item_id')::int, (l->>'qty_per')::numeric from jsonb_array_elements(p_lines) l
  where (l->>'qty_per')::numeric > 0;
  update items set item_type = 'kit' where id = p_parent and exists (select 1 from bom_lines where parent_item_id = p_parent);
  perform _log('Bill of materials saved', (select name from items where id = p_parent) || ' · ' || jsonb_array_length(p_lines) || ' components', 'bom', null);
end $$;

-- ---------- users & security ------------------------------------------
create or replace function set_user_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_service_context() or (app_role() = 'admin' and mfa_ok())) then raise exception 'Only an admin can change roles'; end if;
  if p_user = auth.uid() and p_role <> 'admin' then raise exception 'You cannot remove your own admin role'; end if;
  update profiles set role = p_role,
    customer_id = case when p_role = 'customer' then customer_id else null end
  where id = p_user;
  perform _log('Role changed', (select email from profiles where id = p_user) || ' → ' || p_role, 'user', null, 'security');
end $$;

create or replace function list_users() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when is_manager() then coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('customer_name', c.name) order by p.created_at), '[]') end
  from profiles p left join customers c on c.id = p.customer_id
$$;

create or replace function log_security_event(p_action text, p_details text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  if p_action = 'Signed in' then update profiles set last_login_at = now() where id = auth.uid(); end if;
  perform _log(p_action, p_details, 'auth', null, 'security');
end $$;

-- my profile (any logged-in user)
create or replace function my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(p) || jsonb_build_object('customer', to_jsonb(c), 'mfa_required',
     coalesce((select value from settings where key='require_staff_mfa'),'true') = 'true',
     'aal', coalesce(auth.jwt() ->> 'aal','aal1'),
     'company_name', (select value from settings where key='company_name'),
     'idle_timeout_minutes', (select value from settings where key='idle_timeout_minutes'))
  from profiles p left join customers c on c.id = p.customer_id where p.id = auth.uid()
$$;

-- ---------- customer portal -------------------------------------------
create or replace function portal_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'category', x->>'name'), '[]')
  from (
    select jsonb_build_object('id', i.id, 'name', i.name, 'category', i.category, 'uom', i.uom, 'price', i.price,
      'description', i.description, 'shelf', i.shelf, 'item_type', i.item_type, 'taxable', i.taxable,
      'locations', (select jsonb_agg(jsonb_build_object('location_id', l.id, 'location', l.name,
            'available', greatest(coalesce(inv.qty_on_hand,0) - coalesce((select sum(sol.qty) from sales_order_lines sol
                 join sales_orders so on so.id = sol.so_id where so.status = 'Order Placed' and sol.item_id = i.id and so.location_id = l.id),0),0))
            order by l.id)
          from locations l left join inventory inv on inv.item_id = i.id and inv.location_id = l.id
          where l.location_type <> 'Internal')) as x
    from items i where i.active and i.sellable and i.item_type <> 'service'
  ) t
  where auth.uid() is not null
$$;

create or replace function portal_place_order(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cust int; v_id int; v_no text;
begin
  select customer_id into v_cust from profiles where id = auth.uid();
  if v_cust is null then raise exception 'Your account is not linked to a customer record'; end if;
  if (p->>'requested_date')::date < current_date then raise exception 'Pickup date cannot be in the past'; end if;
  v_id := _insert_so(p, v_cust, 'Portal');
  select so_number into v_no from sales_orders where id = v_id;
  perform _log('Online pickup order', v_no || ' placed by customer ' || (select name from customers where id = v_cust), 'sales_order', v_no);
  return jsonb_build_object('id', v_id, 'so_number', v_no);
end $$;

create or replace function portal_my_orders() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', so.id, 'so_number', so.so_number, 'status', so.status, 'order_date', so.order_date,
     'requested_date', so.requested_date, 'location', l.name,
     'lines', (select jsonb_agg(jsonb_build_object('name', i.name, 'qty', sol.qty, 'unit_price', sol.unit_price, 'discount_pct', sol.discount_pct))
               from sales_order_lines sol join items i on i.id = sol.item_id where sol.so_id = so.id),
     'total', (select sum(sol.qty * sol.unit_price * (1 - sol.discount_pct/100)) from sales_order_lines sol where sol.so_id = so.id))
     order by so.order_date desc), '[]')
  from sales_orders so join locations l on l.id = so.location_id
  where so.customer_id = (select customer_id from profiles where id = auth.uid())
$$;

create or replace function portal_cancel_order(p_so_id int) returns void
language plpgsql security definer set search_path = public as $$
declare v_so record;
begin
  select * into v_so from sales_orders where id = p_so_id and customer_id = (select customer_id from profiles where id = auth.uid());
  if v_so.id is null then raise exception 'Order not found'; end if;
  if v_so.status <> 'Order Placed' then raise exception 'This order can no longer be cancelled'; end if;
  update sales_orders set status = 'Cancelled', cancelled_at = now() where id = p_so_id;
  perform _log('Online order cancelled by customer', v_so.so_number, 'sales_order', v_so.so_number);
end $$;
