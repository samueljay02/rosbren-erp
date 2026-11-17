-- ROSBREN HEALTH CLINIC ERP — complete database setup
-- Paste this whole file into Supabase → SQL Editor → Run.

-- =====================================================================
-- ROSBREN HEALTH CLINIC ERP  —  01 SCHEMA, SECURITY & HELPERS
-- Database: Supabase (PostgreSQL 15+). Run setup.sql (all parts) once.
-- =====================================================================

-- ---------- Settings ----------------------------------------------------
create table if not exists settings (
  key text primary key,
  value text not null,
  label text,
  description text,
  category text default 'General'
);

-- ---------- Users / profiles -----------------------------------------
create table if not exists customers (
  id serial primary key,
  name text not null,
  customer_type text not null default 'Individual',  -- Individual, Walk-in, Village Health Team, Health Centre, School, NGO
  phone text, email text, village text,
  discount_pct numeric(5,2) not null default 0,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key,
  email text,
  full_name text,
  role text not null default 'customer'
    check (role in ('admin','manager','pharmacist','storekeeper','customer','disabled')),
  customer_id int references customers(id),
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);

-- ---------- Master data -------------------------------------------------
create table if not exists locations (
  id serial primary key,
  code text unique not null,
  name text not null,
  location_type text,
  description text
);

create table if not exists suppliers (
  id serial primary key,
  name text not null,
  contact_name text, phone text, email text, address text,
  lead_time_days int not null default 7,
  payment_terms text not null default 'Net 30',
  payment_terms_days int not null default 30,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists items (
  id serial primary key,
  sku text unique not null,
  barcode text unique not null,
  name text not null,
  category text not null,
  uom text not null default 'pack',
  item_type text not null default 'purchased' check (item_type in ('purchased','kit','service')),
  description text,
  price numeric(14,2) not null default 0,
  avg_cost numeric(14,4) not null default 0,       -- weighted average cost
  reorder_point numeric(12,2) not null default 0,
  lead_time_days int not null default 7,
  preferred_supplier_id int references suppliers(id),
  shelf text,
  taxable boolean not null default false,
  sellable boolean not null default true,
  active boolean not null default true,
  impact_label text,                                 -- e.g. 'mothers equipped for a clean birth'
  last_reviewed_at date,
  created_at timestamptz not null default now()
);

create table if not exists bom_lines (
  id serial primary key,
  parent_item_id int not null references items(id) on delete cascade,
  component_item_id int not null references items(id),
  qty_per numeric(12,3) not null check (qty_per > 0),
  unique (parent_item_id, component_item_id)
);

create table if not exists reason_codes (
  code text primary key,
  category text not null check (category in ('adjustment','return','scrap')),
  description text not null,
  is_quality boolean not null default false
);

-- ---------- Inventory ---------------------------------------------------
create table if not exists inventory (
  item_id int not null references items(id) on delete cascade,
  location_id int not null references locations(id),
  qty_on_hand numeric(14,2) not null default 0,
  primary key (item_id, location_id)
);

create table if not exists inventory_transactions (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  item_id int not null references items(id),
  location_id int not null references locations(id),
  qty_change numeric(14,2) not null,
  txn_type text not null,  -- opening, sale, return, write_off, transfer_in, transfer_out, adjustment, receipt, production_issue, production_receipt, exchange_out
  unit_cost numeric(14,4) not null default 0,
  ref_type text, ref_id bigint, ref_no text,
  reason_code text, note text,
  user_id uuid
);
create index if not exists inv_txn_item_idx on inventory_transactions(item_id, created_at);

-- ---------- Sales -------------------------------------------------------
create sequence if not exists sale_no_seq start 100001;
create sequence if not exists so_no_seq start 5001;
create sequence if not exists po_no_seq start 2001;
create sequence if not exists wo_no_seq start 3001;
create sequence if not exists rt_no_seq start 4001;
create sequence if not exists tr_no_seq start 7001;

create table if not exists sales_orders (
  id serial primary key,
  so_number text unique not null default ('SO-' || nextval('so_no_seq')),
  customer_id int not null references customers(id),
  location_id int not null references locations(id),
  order_date timestamptz not null default now(),
  requested_date date not null default current_date,
  status text not null default 'Order Placed' check (status in ('Order Placed','Fulfilled','Closed','Cancelled')),
  channel text not null default 'Staff' check (channel in ('Staff','Portal')),
  notes text,
  sale_id bigint,
  fulfilled_at timestamptz, closed_at timestamptz, cancelled_at timestamptz,
  created_by uuid
);

create table if not exists sales_order_lines (
  id serial primary key,
  so_id int not null references sales_orders(id) on delete cascade,
  item_id int not null references items(id),
  qty numeric(12,2) not null check (qty > 0),
  unit_price numeric(14,2) not null,
  discount_pct numeric(5,2) not null default 0
);

create table if not exists sales (
  id bigserial primary key,
  sale_number text unique not null default ('S-' || nextval('sale_no_seq')),
  sale_date timestamptz not null default now(),
  customer_id int references customers(id),
  location_id int not null references locations(id),
  channel text not null default 'POS',       -- POS, Sales Order, Portal
  sales_order_id int references sales_orders(id),
  payment_method text not null default 'Cash',
  subtotal numeric(14,2) not null default 0,
  discount_total numeric(14,2) not null default 0,
  tax_total numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  cost_total numeric(14,2) not null default 0,
  amount_tendered numeric(14,2),
  cashier_id uuid,
  cashier_name text
);
create index if not exists sales_date_idx on sales(sale_date);

create table if not exists sale_lines (
  id bigserial primary key,
  sale_id bigint not null references sales(id) on delete cascade,
  item_id int not null references items(id),
  qty numeric(12,2) not null,
  unit_price numeric(14,2) not null,
  discount_amount numeric(14,2) not null default 0,  -- line + share of order discount
  line_total numeric(14,2) not null,                 -- net revenue, excl. tax
  tax_amount numeric(14,2) not null default 0,
  unit_cost numeric(14,4) not null default 0,
  line_cost numeric(14,2) not null default 0
);
create index if not exists sale_lines_sale_idx on sale_lines(sale_id);
create index if not exists sale_lines_item_idx on sale_lines(item_id);

-- ---------- Returns & exchanges ---------------------------------------
create table if not exists returns (
  id serial primary key,
  return_number text unique not null default ('RT-' || nextval('rt_no_seq')),
  return_date timestamptz not null default now(),
  return_type text not null check (return_type in ('Return','Exchange')),
  sale_id bigint not null references sales(id),
  customer_id int references customers(id),
  location_id int not null references locations(id),
  reason_code text references reason_codes(code),
  notes text,
  refund_total numeric(14,2) not null default 0,      -- incl. tax, money back for returned items
  replacement_total numeric(14,2) not null default 0, -- incl. tax, value of items given in exchange
  net_amount numeric(14,2) not null default 0,        -- + customer pays, - customer refunded
  user_id uuid, user_name text
);

create table if not exists return_lines (
  id serial primary key,
  return_id int not null references returns(id) on delete cascade,
  direction text not null check (direction in ('in','out')),  -- in = returned by customer, out = replacement given
  sale_line_id bigint references sale_lines(id),
  item_id int not null references items(id),
  qty numeric(12,2) not null,
  unit_price numeric(14,2) not null,
  line_total numeric(14,2) not null,  -- excl. tax
  tax_amount numeric(14,2) not null default 0,
  unit_cost numeric(14,4) not null,
  line_cost numeric(14,2) not null,
  disposition text,                   -- restock | write_off (for 'in' lines)
  reason_code text
);

-- ---------- Transfers ---------------------------------------------------
create table if not exists transfers (
  id serial primary key,
  transfer_number text unique not null default ('TR-' || nextval('tr_no_seq')),
  created_at timestamptz not null default now(),
  item_id int not null references items(id),
  from_location_id int not null references locations(id),
  to_location_id int not null references locations(id),
  qty numeric(12,2) not null check (qty > 0),
  note text,
  user_id uuid, user_name text
);

-- ---------- Production (kit assembly) ---------------------------------
create table if not exists production_orders (
  id serial primary key,
  wo_number text unique not null default ('WO-' || nextval('wo_no_seq')),
  item_id int not null references items(id),
  location_id int not null references locations(id),
  qty_planned numeric(12,2) not null check (qty_planned > 0),
  qty_started numeric(12,2) not null default 0,
  qty_good numeric(12,2) not null default 0,
  qty_scrapped numeric(12,2) not null default 0,
  qty_reworked numeric(12,2) not null default 0,
  scrap_reason_code text references reason_codes(code),
  status text not null default 'Planned' check (status in ('Planned','In Progress','Completed','Cancelled')),
  due_date date,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  material_cost numeric(14,2) not null default 0,
  unit_cost numeric(14,4),
  notes text,
  created_by uuid
);

create table if not exists production_order_components (
  id serial primary key,
  wo_id int not null references production_orders(id) on delete cascade,
  item_id int not null references items(id),
  qty_per numeric(12,3) not null,
  qty_issued numeric(12,2) not null,
  unit_cost numeric(14,4) not null,
  total_cost numeric(14,2) not null
);

-- ---------- Purchasing --------------------------------------------------
create table if not exists purchase_orders (
  id serial primary key,
  po_number text unique not null default ('PO-' || nextval('po_no_seq')),
  supplier_id int not null references suppliers(id),
  location_id int not null references locations(id),
  created_at timestamptz not null default now(),
  order_date date,                     -- date sent
  expected_date date,                  -- order_date + supplier quoted lead time
  status text not null default 'Draft'
    check (status in ('Draft','Order Sent','Partially Received','Received','Closed','Cancelled')),
  notes text,
  source text,                         -- Manual, ROP, MRP, Periodic Review, Outreach
  created_by uuid,
  closed_at timestamptz
);

create table if not exists purchase_order_lines (
  id serial primary key,
  po_id int not null references purchase_orders(id) on delete cascade,
  item_id int not null references items(id),
  qty_ordered numeric(12,2) not null check (qty_ordered > 0),
  qty_received numeric(12,2) not null default 0,
  unit_cost numeric(14,2) not null
);

create table if not exists po_receipts (
  id serial primary key,
  po_id int not null references purchase_orders(id) on delete cascade,
  receipt_date date not null default current_date,
  location_id int not null references locations(id),
  amount numeric(14,2) not null default 0,     -- bill amount for this receipt
  due_date date not null,                      -- receipt_date + payment terms
  paid_amount numeric(14,2) not null default 0,
  paid_date date,
  notes text,
  received_by uuid, received_by_name text
);

create table if not exists po_receipt_lines (
  id serial primary key,
  receipt_id int not null references po_receipts(id) on delete cascade,
  po_line_id int not null references purchase_order_lines(id),
  item_id int not null references items(id),
  qty numeric(12,2) not null
);

-- ---------- Finance: operating expenses -------------------------------
create table if not exists expenses (
  id serial primary key,
  expense_date date not null,
  category text not null,
  description text,
  amount numeric(14,2) not null,
  created_by uuid
);

-- ---------- Outreach (wow feature) ------------------------------------
create table if not exists outreach_events (
  id serial primary key,
  name text not null,
  village text not null,
  event_date date not null,
  expected_mothers int not null default 0,
  expected_children int not null default 0,
  expected_malaria_tests int not null default 0,
  expected_wounds int not null default 0,
  status text not null default 'Planned' check (status in ('Planned','Prepared','Completed','Cancelled')),
  notes text,
  created_at timestamptz not null default now()
);

-- ---------- Audit / activity log ---------------------------------------
create table if not exists activity_log (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  user_id uuid,
  user_name text,
  action text not null,
  details text,
  ref_type text, ref_no text,
  category text default 'operations'   -- operations | security
);
create index if not exists activity_log_created_idx on activity_log(created_at desc);

-- =====================================================================
-- SECURITY HELPERS
-- =====================================================================
create or replace function setting_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(value,'')::numeric from settings where key = p_key), p_default)
$$;

create or replace function app_role() returns text
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid()
$$;

-- MFA: staff must be at Authenticator Assurance Level 2 (password + TOTP code)
create or replace function mfa_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value from settings where key = 'require_staff_mfa'), 'true') <> 'true'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;

-- direct SQL-editor / service access (no end-user JWT) is treated as admin
create or replace function is_service_context() returns boolean
language sql stable as $$
  select auth.uid() is null and session_user in ('postgres','supabase_admin')
$$;

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select is_service_context()
      or (app_role() in ('admin','manager','pharmacist','storekeeper') and mfa_ok())
$$;

create or replace function is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select is_service_context()
      or (app_role() in ('admin','manager') and mfa_ok())
$$;

create or replace function require_staff() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_staff() then
    raise exception 'Access denied: staff account with MFA verification required';
  end if;
end $$;

create or replace function require_manager() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_manager() then
    raise exception 'Access denied: manager or admin role (with MFA) required';
  end if;
end $$;

create or replace function current_user_name() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(full_name, email) from profiles where id = auth.uid()), 'System')
$$;

create or replace function _log(p_action text, p_details text, p_ref_type text default null,
                                p_ref_no text default null, p_category text default 'operations')
returns void language sql security definer set search_path = public as $$
  insert into activity_log(user_id, user_name, action, details, ref_type, ref_no, category)
  values (auth.uid(), current_user_name(), p_action, p_details, p_ref_type, p_ref_no, p_category);
$$;

-- New sign-ups: first account becomes admin; everyone else starts as a customer
-- (an admin promotes staff in Users & Security). Customers get a linked customer record.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role text; v_cust int; v_name text;
begin
  v_name := coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1));
  if not exists (select 1 from profiles where role = 'admin') then
    v_role := 'admin';
  else
    v_role := 'customer';
    insert into customers(name, customer_type, email, phone, village)
    values (v_name, 'Individual', new.email, new.raw_user_meta_data ->> 'phone', new.raw_user_meta_data ->> 'village')
    returning id into v_cust;
  end if;
  insert into profiles(id, email, full_name, role, customer_id) values (new.id, new.email, v_name, v_role, v_cust);
  insert into activity_log(user_id, user_name, action, details, category)
  values (new.id, v_name, 'Account created', 'New ' || v_role || ' account: ' || new.email, 'security');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- EAN-13 check digit (internal "restricted circulation" prefix 20x)
create or replace function ean13(p12 text) returns text language plpgsql immutable as $$
declare s int := 0; i int;
begin
  for i in 1..12 loop
    s := s + substr(p12, i, 1)::int * (case when i % 2 = 0 then 3 else 1 end);
  end loop;
  return p12 || ((10 - s % 10) % 10)::text;
end $$;

-- =====================================================================
-- ROW LEVEL SECURITY
--   staff (admin/manager/pharmacist/storekeeper) with MFA: operational data
--   managers/admins with MFA: finance, settings, users
--   customers: catalog (via functions), their own orders only
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['customers','locations','suppliers','items','bom_lines','reason_codes','inventory',
    'inventory_transactions','sales_orders','sales_order_lines','sales','sale_lines','returns','return_lines',
    'transfers','production_orders','production_order_components','purchase_orders','purchase_order_lines',
    'po_receipts','po_receipt_lines','outreach_events','activity_log','settings','profiles','expenses']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists staff_all on %I', t);
  end loop;

  -- staff read/write on operational tables
  foreach t in array array['customers','locations','suppliers','items','bom_lines','reason_codes','inventory',
    'inventory_transactions','sales_orders','sales_order_lines','sales','sale_lines','returns','return_lines',
    'transfers','production_orders','production_order_components','purchase_orders','purchase_order_lines',
    'po_receipts','po_receipt_lines','outreach_events']
  loop
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;

-- finance & admin tables: managers only (staff can read settings + activity)
create policy staff_all on expenses for all to authenticated using (is_manager()) with check (is_manager());
create policy staff_all on settings for all to authenticated using (is_manager()) with check (is_manager());
drop policy if exists settings_read on settings;
create policy settings_read on settings for select to authenticated using (is_staff());
create policy staff_all on activity_log for select to authenticated using (is_staff());
create policy staff_all on profiles for select to authenticated using (is_manager());  -- role changes only via set_user_role()
drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles for select to authenticated using (id = auth.uid());

-- customers: see own orders + own customer record
drop policy if exists cust_own_so on sales_orders;
create policy cust_own_so on sales_orders for select to authenticated
  using (customer_id = (select customer_id from profiles where id = auth.uid()));
drop policy if exists cust_own_sol on sales_order_lines;
create policy cust_own_sol on sales_order_lines for select to authenticated
  using (so_id in (select id from sales_orders where customer_id = (select customer_id from profiles where id = auth.uid())));
drop policy if exists cust_self on customers;
create policy cust_self on customers for select to authenticated
  using (id = (select customer_id from profiles where id = auth.uid()));

-- no anonymous access at all
revoke all on all tables in schema public from anon;

-- realtime: every logged-in user's screen refreshes when these change
do $$
declare t text;
begin
  foreach t in array array['inventory','sales','sales_orders','purchase_orders','production_orders','returns',
                           'transfers','activity_log','items','po_receipts','outreach_events','expenses','settings']
  loop
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when duplicate_object then null; when undefined_object then null;
    end;
  end loop;
end $$;


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


-- =====================================================================
-- ROSBREN ERP  —  04 DEMO / STARTING DATA GENERATOR
-- Catalog, prices & shelf numbers: Rosbren "Pharmacy Supplies 2026" workbook (cleaned)
-- Monthly revenue targets & operating expenses: Rosbren "Financials" workbook (2026)
-- Day-to-day volume pattern: Rosbren "Visits" workbook (daily patient visits)
-- Transactions are generated on top of these real patterns, relative to TODAY,
-- so the history always ends yesterday. Re-run any time:  select reset_demo_data();
-- =====================================================================

create or replace function _rnorm() returns double precision language sql volatile as $$
  select sqrt(-2 * ln(greatest(random(), 1e-9))) * cos(2 * pi() * random())
$$;

create or replace function _visits_doy() returns int[] language sql immutable as $$
  select '{53,78,80,110,95,86,101,82,101,74,109,122,91,117,123,101,98,85,87,94,120,82,109,77,102,110,85,90,108,114,73,100,92,84,125,81,95,81,64,89,92,106,90,61,134,101,82,90,84,93,99,125,85,109,76,112,102,81,91,102,84,81,109,101,88,83,86,71,67,82,85,109,66,92,88,67,85,82,86,69,82,77,85,109,74,127,72,88,91,111,91,109,79,86,65,106,111,76,87,109,73,90,87,70,70,79,81,115,99,114,95,89,103,73,92,115,113,83,103,106,60,69,105,105,81,89,111,79,106,104,96,99,86,101,110,87,106,96,91,102,74,88,104,111,94,112,95,102,121,104,96,135,112,87,133,71,110,99,92,95,129,131,109,123,133,95,133,105,130,72,99,68,71,91,95,101,89,65,88,88,81,96,91,94,76,98,98,77,81,97,121,110,118,84,85,111,102,89,63,98,74,103,86,81,102,78,93,81,100,37,80,82,73,130,89,86,86,86,71,90,69,53,74,81,99,116,84,72,40,65,116,103,76,110,112,66,91,77,141,99,115,91,74,98,139,98,92,76,98,80,68,77,73,79,64,90,90,81,86,70,78,81,92,82,67,92,99,17,27,31,28,36,43,53,28,37,53,56,50,51,57,60,64,66,76,50,73,62,43,43,44,66,66,48,58,59,52,64,61,48,58,76,48,60,56,58,57,42,55,54,51,51,52,39,53,50,50,82,73,74,57,55,66,67,47,52,67,63,39,56,44,60,36,53,75,57,45,51,53,55,56,56,72,67,50,63,55,60,47,50,50,53,49,43,41,48,60,57,79,57,52,53,46,52,62}'::int[]
$$;

create or replace function rnd() returns numeric language sql volatile as $$ select random()::numeric $$;



create or replace function reset_demo_data(p_days int default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_start date := current_date - p_days;
  d date; v_m int; v_doy int; v_vis int[] := _visits_doy(); v_msum numeric; v_cur_month text := '';
  ph numeric[] := array[3053900,3237100,3271600,3678200,3848800,4121500,2685900,2429900,2846800,2914800,3000000,3300000];
  cl numeric[] := array[2042000,2144500,1624600,2219900,2680000,2446578,1514700,1171500,1326500,1410500,1450000,1600000];
  lb numeric[] := array[789000,626000,798000,621500,758000,794500,564000,654000,771450,985000,900000,850000];
  v_tph numeric; v_ncons int; v_nlab int; v_rev numeric; k int; v_sale bigint; v_cust int; v_loc int; v_ts timestamptz;
  v_nlines int; j int; r numeric; v_pick int; v_qty numeric; v_item record; v_net numeric; v_tax numeric;
  v_ids int[]; v_w numeric[]; v_wsum numeric; v_season numeric; v_ci int;
  v_main int; v_store int; v_mobile int; v_walkin int; v_inst int[]; v_indiv int[];
  v_consult int; v_lab int; v_so int; v_tax_rate numeric := 0.18;
  v_sup record; v_po int; v_odate date; v_exp date; v_rdate date; v_rcpt int; v_amt numeric; v_q numeric; v_qr numeric;
  it record; v_wo int; v_started timestamptz; v_scr numeric; v_rw numeric; v_unit numeric; v_reason text;
  v_cnt jsonb; v_kit record; v_ret int; v_sl record; v_rr text; v_total numeric; v_x numeric;
begin
  if not (is_service_context() or (app_role() = 'admin' and mfa_ok())) then
    raise exception 'Only an admin can reset demo data';
  end if;
  perform setseed(0.2026);

  -- ---------- wipe (users/profiles and the customers linked to them are kept) ----------
  delete from return_lines; delete from returns; delete from sale_lines; delete from sales;
  delete from sales_order_lines; delete from sales_orders; delete from transfers;
  delete from production_order_components; delete from production_orders;
  delete from po_receipt_lines; delete from po_receipts; delete from purchase_order_lines; delete from purchase_orders;
  delete from inventory_transactions; delete from inventory; delete from bom_lines; delete from expenses;
  delete from outreach_events; delete from activity_log where category = 'operations';
  delete from items; delete from suppliers; delete from locations; delete from reason_codes;
  delete from customers where id not in (select customer_id from profiles where customer_id is not null);
  perform setval('sale_no_seq', 100001, false); perform setval('so_no_seq', 5001, false);
  perform setval('po_no_seq', 2001, false); perform setval('wo_no_seq', 3001, false);
  perform setval('rt_no_seq', 4001, false); perform setval('tr_no_seq', 7001, false);

  -- ---------- settings (existing values are kept) ----------
  insert into settings(key, value, label, description, category) values
    ('company_name','Rosbren Health Clinic','Organization name',null,'General'),
    ('company_address','Rural Uganda','Address',null,'General'),
    ('company_phone','+256','Phone',null,'General'),
    ('currency','UGX','Currency code','Ugandan shilling','General'),
    ('usd_rate','3500','UGX per US dollar','Used to show USD equivalents (rate used in Rosbren financial workbook)','General'),
    ('receipt_footer','Thank you! Every purchase supports care for our community.','Receipt footer',null,'General'),
    ('tax_rate','0.18','VAT rate','Applied to items flagged taxable (most medicines are VAT-exempt in Uganda)','Sales'),
    ('ordering_cost','25000','Ordering cost per order (S)','Cost to place & receive one order: transport to Kampala, airtime, staff time','Inventory Policy'),
    ('holding_cost_pct','0.25','Annual holding cost % (H)','Storage, capital, expiry & loss risk as a share of unit cost per year','Inventory Policy'),
    ('service_level_z','1.65','Safety stock z-score','1.65 ≈ 95% cycle service level','Inventory Policy'),
    ('review_period_days','14','Periodic review interval (days)','How often each item is manually reviewed','Inventory Policy'),
    ('demand_lookback_days','180','Demand history window (days)','Sales history used for average usage, ROP and EOQ','Inventory Policy'),
    ('malaria_positivity_rate','0.35','Malaria test positivity','Share of outreach malaria tests expected positive','Outreach'),
    ('outreach_delivery_ratio','0.3','Mothers needing a birth kit','Share of expectant mothers near term at outreach','Outreach'),
    ('outreach_diarrhoea_ratio','0.15','Children with diarrhoea','Share of children expected to need ORS + zinc','Outreach'),
    ('require_staff_mfa','true','Require MFA for staff','Staff must verify an authenticator code (AAL2) before any data is returned','Security'),
    ('idle_timeout_minutes','15','Auto sign-out after inactivity (minutes)',null,'Security')
  on conflict (key) do nothing;

  -- ---------- locations ----------
  insert into locations(code, name, location_type, description) values
    ('MAIN','Main Pharmacy','Pharmacy','Dispensary counter at the clinic (POS)'),
    ('STORE','Clinic Store Room','Warehouse','Bulk stock and kit assembly bench'),
    ('MOBILE','Mobile Outreach Unit','Mobile','Stock carried to village outreach clinics');
  select id into v_main from locations where code = 'MAIN';
  select id into v_store from locations where code = 'STORE';
  select id into v_mobile from locations where code = 'MOBILE';

  insert into reason_codes(code, category, description, is_quality) values
    ('CYCLE_COUNT','adjustment','Cycle count correction',false),
    ('DAMAGED','adjustment','Damaged in storage',true),
    ('EXPIRED','adjustment','Expired – removed from shelf',true),
    ('CLINIC_USE','adjustment','Used in clinic treatment',false),
    ('LOST','adjustment','Lost / unaccounted',false),
    ('FOUND','adjustment','Found stock',false),
    ('RT_DEFECTIVE','return','Defective / broken seal',true),
    ('RT_EXPIRED','return','Sold expired or near expiry',true),
    ('RT_PACKAGING','return','Damaged packaging',true),
    ('RT_REACTION','return','Adverse reaction reported',true),
    ('RT_WRONG','return','Wrong item dispensed',false),
    ('RT_NOT_NEEDED','return','Prescription changed / not needed',false),
    ('SC_MISSING','scrap','Missing component at packing',true),
    ('SC_DAMAGED','scrap','Component damaged during assembly',true),
    ('SC_SEAL','scrap','Bag seal / label failure',true),
    ('SC_CONTAM','scrap','Sterility compromised',true),
    ('SC_LABEL','scrap','Mislabelled – reworked',true);

  -- ---------- suppliers (fictional Ugandan wholesalers) ----------
  insert into suppliers(name, contact_name, phone, email, address, lead_time_days, payment_terms, payment_terms_days, notes) values
    ('Kampala Pharmaceutical Wholesalers','Ivan Mutebi','+256 772 410 221','orders@kpw.example.ug','Plot 14 Nakivubo Rd, Kampala',5,'Net 30',30,'Main medicines supplier'),
    ('Nile Medical Supplies','Agnes Atim','+256 701 330 915','sales@nilemed.example.ug','Main St, Jinja',7,'Net 15',15,'Haematinics, eye care, lotions'),
    ('East Africa Diagnostics Ltd','Brian Wekesa','+256 752 118 640','ug@eadiag.example.com','Industrial Area, Kampala',14,'Net 45',45,'Malaria RDTs – imported'),
    ('Mukwano Hygiene & Textiles','Lydia Nambi','+256 782 905 412','orders@mukwanoht.example.ug','Mukono',10,'Net 30',30,'Soap, pads, blankets, delivery sheets'),
    ('Pearl Packaging Works','Henry Ouma','+256 703 552 190','pearlpack@example.ug','Wakiso',4,'Cash on delivery',0,'Kit bags and envelopes'),
    ('Lakeside Surgical & Dressings','Rose Kyomuhendo','+256 774 663 018','lakeside@example.ug','Entebbe Rd, Kampala',12,'Net 30',30,'Gauze, gloves, clamps – frequently late'),
    ('Equator Pharma Distributors','Samuel Opio','+256 757 201 334','orders@equatorpharma.example.ug','Mbarara',6,'Net 30',30,'Antibiotics and branded medicines');

  -- ---------- items ----------
  create temp table _cat(sku text, name text, category text, uom text, cost numeric, shelf text, supp text,
    taxable boolean, w numeric, season text, sellable boolean default true, descr text) on commit drop;
  insert into _cat values
   ('PH-001','Paracetamol 500mg Tablets','Analgesics','pack',1400,'12','Kampala',false,5.0,'fever',true,'Pain & fever relief'),
   ('PH-002','Paracetamol Syrup 100ml','Analgesics','bottle',1300,'5','Kampala',false,1.6,'fever',true,'Children''s fever syrup'),
   ('PH-003','Ibuprofen 200mg Tablets','Analgesics','pack',2600,'15','Kampala',false,1.2,'none',true,null),
   ('PH-004','Diclofenac 50mg Tablets','Analgesics','pack',1400,'15','Kampala',false,1.2,'none',true,null),
   ('PH-005','Diclofenac Gel 20g','Analgesics','tube',1300,'26','Equator',false,0.6,'none',true,null),
   ('PH-010','Coartem (Artemether-Lumefantrine) 20/120','Antimalarials','pack',2400,'20','Kampala',false,2.6,'malaria',true,'First-line malaria treatment'),
   ('PH-011','Lonart (Artemether-Lumefantrine)','Antimalarials','pack',2600,'20','Equator',false,0.8,'malaria',true,null),
   ('PH-012','P-Alaxin (DHA-Piperaquine)','Antimalarials','pack',7500,'20','Equator',false,0.5,'malaria',true,null),
   ('PH-013','Fansidar (Sulfadoxine-Pyrimethamine)','Antimalarials','pack',1600,'20','Kampala',false,0.8,'none',true,'IPTp for pregnant mothers'),
   ('PH-020','Amoxicillin 250mg Capsules','Antibiotics','pack',2400,'20','Equator',false,1.6,'resp',true,null),
   ('PH-021','Amoxicillin Paediatric Suspension','Antibiotics','bottle',5500,'30','Equator',false,0.8,'resp',true,null),
   ('PH-022','Ampiclox Capsules','Antibiotics','pack',8000,'20','Equator',false,0.5,'resp',true,null),
   ('PH-023','Cotrimoxazole 480mg Tablets','Antibiotics','pack',2400,'20','Equator',false,1.0,'none',true,null),
   ('PH-024','Metronidazole 200mg Tablets','Antibiotics','pack',2600,'21','Kampala',false,1.2,'none',true,null),
   ('PH-025','Ciprofloxacin 500mg Tablets','Antibiotics','pack',12000,'21','Equator',false,0.35,'none',true,null),
   ('PH-026','Doxycycline 100mg Capsules','Antibiotics','pack',5500,'21','Equator',false,0.6,'none',true,null),
   ('PH-027','Azithromycin 250mg Tablets','Antibiotics','pack',2400,'25','Equator',false,0.7,'resp',true,null),
   ('PH-028','Tetracycline Eye Ointment 1%','Eye Care','tube',1500,'25','Nile',false,0.5,'none',true,'Also used in newborn eye care'),
   ('PH-030','Albendazole 400mg Tablet','Antihelminths','tablet',450,'3','Kampala',false,2.0,'none',true,'Deworming'),
   ('PH-031','Mebendazole 100mg Tablets','Antihelminths','pack',3000,'3','Kampala',false,0.5,'none',true,null),
   ('PH-040','Ferrous Sulphate + Folic Acid (FeFo)','Haematinics','pack',4300,'22','Nile',false,1.0,'none',true,'Iron for expectant mothers'),
   ('PH-041','Folic Acid 5mg Tablets','Haematinics','pack',2400,'22','Nile',false,0.8,'none',true,null),
   ('PH-042','Vitamin A 200,000 IU Capsule','Supplements','capsule',600,'22','Nile',false,0.4,'none',true,'Child supplementation'),
   ('PH-043','Vitamin C 100mg Tablets','Supplements','pack',2000,'14','Kampala',false,1.0,'resp',true,null),
   ('PH-044','Multivitamin Syrup 100ml','Supplements','bottle',4500,'4','Kampala',false,0.5,'none',true,null),
   ('PH-050','ORS Sachet (Oral Rehydration Salts)','Gastrointestinal','sachet',600,'3','Kampala',false,1.5,'rain',true,null),
   ('PH-051','Zinc Sulphate 20mg Tablets (x10)','Gastrointestinal','strip',1200,'22','Nile',false,0.8,'rain',true,null),
   ('PH-052','Magnesium Trisilicate Tablets','Gastrointestinal','pack',1600,'2','Kampala',false,1.0,'none',true,null),
   ('PH-053','Omeprazole 20mg Capsules','Gastrointestinal','pack',4500,'12','Equator',false,0.7,'none',true,null),
   ('PH-060','Salbutamol 4mg Tablets','Respiratory','pack',1800,'14','Kampala',false,0.6,'resp',true,null),
   ('PH-061','Cetirizine 10mg Tablets','Respiratory','pack',1300,'14','Kampala',false,1.0,'resp',true,null),
   ('PH-062','Cough Linctus 100ml','Respiratory','bottle',2200,'4','Kampala',false,0.9,'resp',true,null),
   ('PH-070','Fluconazole 150mg Capsule','Antifungals','pack',3000,'22','Equator',false,0.6,'none',true,null),
   ('PH-071','Calamine Lotion 100ml','Skin Care','bottle',1800,'26','Nile',true,0.6,'none',true,null),
   ('PH-072','Nystatin Oral Suspension','Antifungals','bottle',1800,'5','Nile',false,0.5,'none',true,null),
   ('SU-001','Povidone-Iodine Solution 100ml','Dressings & Supplies','bottle',2000,'4','Lakeside',false,0.5,'none',true,null),
   ('SU-002','Crepe Bandage 7.5cm','Dressings & Supplies','roll',600,'4','Lakeside',false,0.5,'none',true,null),
   ('SU-003','Gauze Swabs (pack of 10)','Dressings & Supplies','pack',1500,'27','Lakeside',false,0.4,'none',true,null),
   ('SU-004','Cotton Wool 100g','Dressings & Supplies','roll',2500,'27','Lakeside',false,0.3,'none',true,null),
   ('SU-005','Sterile Gloves (pair)','Dressings & Supplies','pair',800,'27','Lakeside',false,0.4,'none',true,null),
   ('SU-006','Umbilical Cord Clamp','Dressings & Supplies','each',500,'27','Lakeside',false,0,'none',false,null),
   ('SU-007','Sterile Surgical Blade','Dressings & Supplies','each',400,'27','Lakeside',false,0,'none',false,null),
   ('SU-008','Plastic Delivery Sheet (Mackintosh)','Dressings & Supplies','each',2500,'27','Mukwano',false,0,'none',false,null),
   ('SU-009','Malaria Rapid Diagnostic Test (mRDT)','Lab Supplies','test',2500,'Lab','East Africa',false,0.3,'malaria',true,null),
   ('SU-010','Adhesive Plaster Roll','Dressings & Supplies','roll',1500,'27','Lakeside',false,0.4,'none',true,null),
   ('HY-001','Bar Soap 150g','Hygiene','bar',1500,'Display','Mukwano',true,0.8,'none',true,null),
   ('HY-002','Sanitary Pads (pack of 8)','Hygiene','pack',3500,'Display','Mukwano',false,0.6,'none',true,null),
   ('HY-003','Baby Receiving Blanket','Hygiene','each',8000,'Display','Mukwano',true,0.1,'none',true,null),
   ('PK-001','Kit Bag (printed drawstring)','Packaging','each',1200,'Store','Pearl',false,0,'none',false,null),
   ('PK-002','Dispensing Envelope','Packaging','each',100,'Store','Pearl',false,0,'none',false,null);

  insert into items(sku, barcode, name, category, uom, item_type, description, price, avg_cost, lead_time_days, preferred_supplier_id, shelf, taxable, sellable)
  select c.sku, ean13('20' || lpad((100000 + row_number() over (order by c.sku))::text, 10, '0')),
    c.name, c.category, c.uom, 'purchased', c.descr,
    greatest(round(c.cost * 1.5 / 100) * 100, c.cost + 100), c.cost, s.lead_time_days, s.id, c.shelf, c.taxable, c.sellable
  from _cat c join suppliers s on s.name like c.supp || '%';

  -- kits assembled in-house (parents with bills of materials)
  insert into items(sku, barcode, name, category, uom, item_type, description, price, lead_time_days, shelf, impact_label) values
   ('KIT-MAMA', ean13('209000000001'),'Clean Delivery Kit (Mama Kit)','Kits (Assembled In-House)','kit','kit','Everything for a clean, safe birth at home or a health post',25000,1,'Kits','mothers equipped for a clean birth'),
   ('KIT-NEWB', ean13('209000000002'),'Newborn Care Kit','Kits (Assembled In-House)','kit','kit','Warm blanket, cord & eye care for the first days',22000,1,'Kits','newborns given a warm, clean start'),
   ('KIT-MAL',  ean13('209000000003'),'Malaria Test & Treat Pack','Kits (Assembled In-House)','pack','kit','mRDT + full ACT course + paracetamol',10000,1,'Kits','malaria cases tested & treated'),
   ('KIT-ANC',  ean13('209000000004'),'Antenatal Care (ANC) Pack','Kits (Assembled In-House)','pack','kit','Iron/folate, IPTp (SP) and deworming for expectant mothers',9500,1,'Kits','antenatal visits supplied'),
   ('KIT-ORS',  ean13('209000000005'),'Diarrhoea Treatment Pack (ORS + Zinc)','Kits (Assembled In-House)','pack','kit','WHO-recommended ORS + zinc for children',4500,1,'Kits','children treated for diarrhoea'),
   ('KIT-WOUND',ean13('209000000006'),'Wound Dressing Kit','Kits (Assembled In-House)','kit','kit','Clean dressing supplies for cuts & ulcers',14000,1,'Kits','wounds cleaned & dressed'),
   ('KIT-CHILD',ean13('209000000007'),'Child Health Pack (Deworm + Vitamin A)','Kits (Assembled In-House)','pack','kit','Albendazole + Vitamin A for children under 5',2500,1,'Kits','children dewormed & supplemented');
  insert into items(sku, barcode, name, category, uom, item_type, description, price, lead_time_days, shelf, sellable) values
   ('SVC-CONSULT', ean13('208000000001'),'Clinic Consultation','Clinic Services','visit','service','Outpatient consultation fee',5000,0,null,true),
   ('SVC-LAB',     ean13('208000000002'),'Laboratory Test','Lab Services','test','service','Laboratory investigation fee',4000,0,null,true);

  insert into bom_lines(parent_item_id, component_item_id, qty_per)
  select p.id, c.id, b.q from (values
    ('KIT-MAMA','SU-008',1),('KIT-MAMA','SU-005',2),('KIT-MAMA','SU-006',2),('KIT-MAMA','SU-007',1),('KIT-MAMA','SU-004',1),
    ('KIT-MAMA','SU-003',1),('KIT-MAMA','HY-001',1),('KIT-MAMA','HY-002',1),('KIT-MAMA','PK-001',1),
    ('KIT-NEWB','HY-003',1),('KIT-NEWB','SU-004',1),('KIT-NEWB','HY-001',1),('KIT-NEWB','PH-028',1),('KIT-NEWB','PK-001',1),
    ('KIT-MAL','SU-009',1),('KIT-MAL','PH-010',1),('KIT-MAL','PH-001',1),('KIT-MAL','PK-002',1),
    ('KIT-ANC','PH-040',1),('KIT-ANC','PH-013',1),('KIT-ANC','PH-030',1),('KIT-ANC','PK-002',1),
    ('KIT-ORS','PH-050',2),('KIT-ORS','PH-051',1),('KIT-ORS','PK-002',1),
    ('KIT-WOUND','SU-003',2),('KIT-WOUND','SU-002',1),('KIT-WOUND','SU-001',1),('KIT-WOUND','SU-005',1),('KIT-WOUND','SU-010',1),('KIT-WOUND','PK-001',1),
    ('KIT-CHILD','PH-030',1),('KIT-CHILD','PH-042',1),('KIT-CHILD','PK-002',1)
  ) b(ps, cs, q) join items p on p.sku = b.ps join items c on c.sku = b.cs;
  -- rolled-up standard cost of each kit
  update items kt set avg_cost = (select sum(b.qty_per * c.avg_cost) from bom_lines b join items c on c.id = b.component_item_id where b.parent_item_id = kt.id)
  where kt.item_type = 'kit';

  -- ---------- customers ----------
  insert into customers(name, customer_type, phone, village, discount_pct) values
    ('Walk-in Patient','Walk-in',null,null,0),
    ('Grace Namutebi','Individual','+256 772 000 101','Kasana',0), ('Joseph Okello','Individual','+256 772 000 102','Ndejje',0),
    ('Sarah Achieng','Individual','+256 772 000 103','Kasana',0), ('Moses Kato','Individual','+256 772 000 104','Bukomero',0),
    ('Esther Nakato','Individual','+256 772 000 105','Ndejje',0), ('Peter Ssempijja','Individual','+256 772 000 106','Kasana',0),
    ('Ruth Nansubuga','Individual','+256 772 000 107','Bukomero',0), ('David Mugisha','Individual','+256 772 000 108','Kasana',0),
    ('Kasana Village Health Team','Village Health Team','+256 772 000 201','Kasana',10),
    ('Kayunga District Health Office','Health Centre','+256 772 000 202','Kayunga',10),
    ('St. Mary''s Primary School','School','+256 772 000 203','Ndejje',5),
    ('Hope for Mothers Foundation','NGO','+256 772 000 204','Kampala',15),
    ('Bukomero Health Centre III','Health Centre','+256 772 000 205','Bukomero',10);
  select id into v_walkin from customers where name = 'Walk-in Patient' order by id desc limit 1;
  select array_agg(id) into v_indiv from customers where customer_type = 'Individual';
  select array_agg(id) into v_inst from customers where customer_type in ('Village Health Team','Health Centre','School','NGO');
  select id into v_consult from items where sku = 'SVC-CONSULT';
  select id into v_lab from items where sku = 'SVC-LAB';

  -- product weights for the weighted random picker
  create temp table _w on commit drop as
    select i.id, i.item_type, i.price, i.avg_cost, i.taxable,
      coalesce(c.w, case i.sku when 'KIT-MAL' then 1.6 when 'KIT-MAMA' then 0.5 when 'KIT-ANC' then 0.6 when 'KIT-ORS' then 0.6
                               when 'KIT-NEWB' then 0.3 when 'KIT-WOUND' then 0.4 when 'KIT-CHILD' then 0.7 end) w,
      coalesce(c.season, case i.sku when 'KIT-MAL' then 'malaria' when 'KIT-ORS' then 'rain' else 'none' end) season
    from items i left join _cat c on c.sku = i.sku where i.item_type <> 'service' and i.sellable;

  -- ---------- 1. SALES HISTORY ----------
  d := v_start;
  while d < current_date loop
    v_m := extract(month from d)::int;
    if to_char(d, 'YYYY-MM') <> v_cur_month then
      v_cur_month := to_char(d, 'YYYY-MM');
      select sum(v_vis[least(extract(doy from g)::int, 365)]) into v_msum
      from generate_series(date_trunc('month', d), date_trunc('month', d) + interval '1 month' - interval '1 day', interval '1 day') g;
      -- month-specific product weights: rainy seasons (Mar–May, Sep–Nov) lift malaria & diarrhoea, Jun–Aug lifts coughs/colds
      select array_agg(id order by id), array_agg(w * case
          when season in ('malaria','fever') and v_m in (3,4,5,9,10,11) then 1.6
          when season in ('malaria','fever') then 0.75
          when season = 'rain' and v_m in (3,4,5,9,10,11) then 1.4
          when season = 'resp' and v_m in (6,7,8) then 1.5 else 1 end order by id)
        into v_ids, v_w from _w where w > 0;
      select sum(x) into v_wsum from unnest(v_w) x;
    end if;
    v_doy := least(extract(doy from d)::int, 365);
    v_tph := ph[v_m] * v_vis[v_doy] / v_msum * (1 + 0.006 * (d - v_start) / 30.0);   -- gentle growth trend
    v_ncons := round(cl[v_m] * v_vis[v_doy] / v_msum / 5000 * (0.9 + 0.2 * rnd()));
    v_nlab := round(lb[v_m] * v_vis[v_doy] / v_msum / 4000 * (0.9 + 0.2 * rnd()));
    v_rev := 0; k := 0;
    while (v_rev < v_tph or k < v_ncons) and k < 200 loop
      r := rnd();
      v_loc := case when extract(dow from d) = 3 and extract(week from d)::int % 2 = 0 and rnd() < 0.6 then v_mobile else v_main end;
      v_cust := case when r < 0.05 and v_rev < v_tph * 0.7 then v_inst[1 + floor(rnd() * array_length(v_inst,1))::int]
                     when r < 0.27 then v_indiv[1 + floor(rnd() * array_length(v_indiv,1))::int]
                     else v_walkin end;
      v_ts := d + time '08:00' + (rnd() * interval '10 hours');
      insert into sales(sale_date, customer_id, location_id, channel, payment_method, cashier_name)
      values (v_ts, v_cust, v_loc, 'POS', case when rnd() < 0.62 then 'Cash' else 'Mobile Money' end,
              (array['Pharmacist on duty','Dispenser','Clinic Nurse'])[1 + floor(rnd()*3)::int])
      returning id into v_sale;
      if k < v_ncons and v_cust <> all(v_inst) then
        insert into sale_lines(sale_id, item_id, qty, unit_price, line_total, unit_cost, line_cost) values (v_sale, v_consult, 1, 5000, 5000, 0, 0);
      end if;
      if k < v_nlab and v_cust <> all(v_inst) then
        insert into sale_lines(sale_id, item_id, qty, unit_price, line_total, unit_cost, line_cost) values (v_sale, v_lab, 1, 4000, 4000, 0, 0);
      end if;
      if v_rev < v_tph then
        v_nlines := 1 + (rnd() < 0.45)::int + (rnd() < 0.15)::int;
        for j in 1..v_nlines loop
          r := rnd() * v_wsum; v_ci := 0; v_x := 0;
          loop v_ci := v_ci + 1; v_x := v_x + v_w[v_ci]; exit when v_x >= r or v_ci >= array_length(v_ids,1); end loop;
          select * into v_item from _w where id = v_ids[v_ci];
          if exists (select 1 from sale_lines where sale_id = v_sale and item_id = v_item.id) then continue; end if;
          if v_cust = any(v_inst) then
            v_qty := case when v_item.item_type = 'kit' then 5 + floor(rnd() * 16) else 3 + floor(rnd() * 8) end;
          else
            v_qty := case when rnd() < 0.72 then 1 when rnd() < 0.85 then 2 else 3 end;
          end if;
          v_net := round(v_qty * v_item.price * (1 - coalesce((select discount_pct from customers where id = v_cust),0) / 100), 2);
          v_tax := case when v_item.taxable then round(v_net * v_tax_rate, 2) else 0 end;
          v_unit := round(v_item.avg_cost * (0.97 + rnd() * 0.06), 2);
          insert into sale_lines(sale_id, item_id, qty, unit_price, discount_amount, line_total, tax_amount, unit_cost, line_cost)
          values (v_sale, v_item.id, v_qty, v_item.price, v_qty * v_item.price - v_net, v_net, v_tax, v_unit, round(v_qty * v_unit, 2));
          v_rev := v_rev + v_net;
        end loop;
      end if;
      if not exists (select 1 from sale_lines where sale_id = v_sale) then
        delete from sales where id = v_sale;
      else
        update sales set subtotal = x.sub, discount_total = x.disc, tax_total = x.tax, total = x.sub - x.disc + x.tax, cost_total = x.cost
        from (select sum(qty * unit_price) sub, sum(discount_amount) disc, sum(tax_amount) tax, sum(line_cost) cost from sale_lines where sale_id = v_sale) x
        where id = v_sale;
        -- institutional orders came in as sales orders (placed → fulfilled → closed)
        if v_cust = any(v_inst) then
          insert into sales_orders(customer_id, location_id, order_date, requested_date, status, channel, sale_id, fulfilled_at, closed_at)
          values (v_cust, v_loc, v_ts - interval '3 days', d, 'Closed', 'Staff', v_sale, v_ts, v_ts + interval '2 days') returning id into v_so;
          insert into sales_order_lines(so_id, item_id, qty, unit_price, discount_pct)
          select v_so, item_id, qty, unit_price, (select discount_pct from customers where id = v_cust) from sale_lines
          where sale_id = v_sale and item_id not in (v_consult, v_lab);
          update sales set channel = 'Sales Order', sales_order_id = v_so, payment_method = 'Invoice' where id = v_sale;
        end if;
      end if;
      k := k + 1;
    end loop;
    d := d + 1;
  end loop;

  -- demand rates from the generated history drive purchasing, production and stock levels
  create temp table _dem on commit drop as select * from _demand_stats(p_days);

  -- ---------- 2. PURCHASE ORDER HISTORY (supplier behaviour profiles) ----------
  for v_sup in select sp.*, x.interval_days, x.delay_mu, x.delay_sd, x.short_p, x.late_pay
           from suppliers sp join (values
             ('Kampala',10,0.0,1.0,0.03,0.05),('Nile',14,1.0,1.5,0.08,0.1),('East Africa',21,4.0,3.0,0.20,0.2),
             ('Mukwano',14,0.0,1.0,0.05,0.05),('Pearl',14,-1.0,0.6,0.0,0.0),('Lakeside',14,4.5,3.0,0.30,0.35),
             ('Equator',12,1.5,2.0,0.12,0.15)) x(nm, interval_days, delay_mu, delay_sd, short_p, late_pay)
           on sp.name like x.nm || '%' loop
    v_odate := v_start - v_sup.lead_time_days + floor(rnd() * 4)::int;
    while v_odate < current_date - 1 loop
      v_exp := v_odate + v_sup.lead_time_days;
      v_rdate := v_exp + round(v_sup.delay_mu + v_sup.delay_sd * _rnorm())::int;
      if v_rdate < v_odate + 1 then v_rdate := v_odate + 1; end if;
      insert into purchase_orders(supplier_id, location_id, created_at, order_date, expected_date, status, source)
      values (v_sup.id, v_store, v_odate, v_odate, v_exp, 'Order Sent', (array['ROP','Periodic Review','Manual'])[1 + floor(rnd()*3)::int])
      returning id into v_po;
      insert into purchase_order_lines(po_id, item_id, qty_ordered, unit_cost)
      select v_po, i.id, greatest(5, ceil(dm.avg_daily * v_sup.interval_days * (1.1 + rnd() * 0.4))), round(i.avg_cost * (0.97 + rnd() * 0.06))
      from items i join _dem dm on dm.item_id = i.id where i.preferred_supplier_id = v_sup.id and i.item_type = 'purchased';
      if v_rdate < current_date then
        insert into po_receipts(po_id, receipt_date, location_id, due_date, received_by_name) values (v_po, v_rdate, v_store, v_rdate + v_sup.payment_terms_days, 'Store keeper')
        returning id into v_rcpt;
        update purchase_order_lines set qty_received = case when rnd() < v_sup.short_p then floor(qty_ordered * (0.55 + rnd() * 0.35)) else qty_ordered end
        where po_id = v_po;
        insert into po_receipt_lines(receipt_id, po_line_id, item_id, qty)
        select v_rcpt, id, item_id, qty_received from purchase_order_lines where po_id = v_po and qty_received > 0;
        select sum(qty_received * unit_cost) into v_amt from purchase_order_lines where po_id = v_po;
        update po_receipts set amount = v_amt where id = v_rcpt;
        update purchase_orders set status = case when v_rdate < current_date - 10 then 'Closed'
          when exists (select 1 from purchase_order_lines where po_id = v_po and qty_received < qty_ordered) then 'Partially Received' else 'Received' end,
          closed_at = case when v_rdate < current_date - 10 then v_rdate + 3 end
        where id = v_po;
        -- pay bills: most on time, some suppliers' bills paid late or still open
        if v_rdate + v_sup.payment_terms_days < current_date - 3 and rnd() > v_sup.late_pay * 0.6 then
          update po_receipts set paid_amount = amount,
            paid_date = least(current_date - 1, due_date - floor(rnd()*4)::int + case when rnd() < v_sup.late_pay then 3 + floor(rnd()*10)::int else 0 end)
          where id = v_rcpt;
        end if;
      end if;
      v_odate := v_odate + v_sup.interval_days + floor(rnd() * 4)::int - 1;
    end loop;
  end loop;

  -- ---------- 3. PRODUCTION HISTORY (kit assembly at the store room) ----------
  for v_kit in select i.*, dm.avg_daily, case i.sku when 'KIT-MAL' then 4 when 'KIT-CHILD' then 10 else 7 end as every
               from items i join _dem dm on dm.item_id = i.id where i.item_type = 'kit' loop
    d := v_start + floor(rnd() * 4)::int;
    while d < current_date - 1 loop
      v_q := greatest(10, ceil(v_kit.avg_daily * v_kit.every * (1.0 + rnd() * 0.3)));
      v_started := d + time '08:30' + rnd() * interval '3 hours';
      v_scr := case when rnd() < 0.35 then ceil(v_q * (0.01 + rnd() * 0.05)) else 0 end;
      v_rw := case when rnd() < 0.25 then ceil(v_q * (0.02 + rnd() * 0.04)) else 0 end;
      v_reason := case when v_scr + v_rw > 0 then (array['SC_MISSING','SC_DAMAGED','SC_SEAL','SC_CONTAM','SC_LABEL','SC_SEAL','SC_MISSING'])[1 + floor(rnd()*7)::int] end;
      select sum(b.qty_per * c.avg_cost) into v_unit from bom_lines b join items c on c.id = b.component_item_id where b.parent_item_id = v_kit.id;
      insert into production_orders(item_id, location_id, qty_planned, qty_started, qty_good, qty_scrapped, qty_reworked, scrap_reason_code,
        status, due_date, created_at, started_at, finished_at, material_cost, unit_cost, notes)
      values (v_kit.id, v_store, v_q, v_q, v_q - v_scr, v_scr, least(v_rw, v_q - v_scr), v_reason, 'Completed', d + 2, d - 1, v_started,
        v_started + (interval '1 hour' * (1.2 + v_q / 25.0 + rnd() * 2)) + case when rnd() < 0.12 then interval '3 days' else interval '0' end,
        round(v_q * v_unit, 2), round(v_q * v_unit / (v_q - v_scr), 4), null)
      returning id into v_wo;
      insert into production_order_components(wo_id, item_id, qty_per, qty_issued, unit_cost, total_cost)
      select v_wo, b.component_item_id, b.qty_per, b.qty_per * v_q, c.avg_cost, round(b.qty_per * v_q * c.avg_cost, 2)
      from bom_lines b join items c on c.id = b.component_item_id where b.parent_item_id = v_kit.id;
      d := d + v_kit.every + floor(rnd() * 3)::int - 1;
    end loop;
  end loop;

  -- ---------- 4. RETURNS & EXCHANGES HISTORY ----------
  for v_sl in select sl.*, s.sale_date, s.customer_id, s.location_id from sale_lines sl join sales s on s.id = sl.sale_id
              join items i on i.id = sl.item_id where i.item_type <> 'service' and s.sale_date < current_date - 2
              order by rnd() limit 22 loop
    v_rr := (array['RT_DEFECTIVE','RT_EXPIRED','RT_PACKAGING','RT_WRONG','RT_NOT_NEEDED','RT_REACTION','RT_PACKAGING','RT_WRONG'])[1 + floor(rnd()*8)::int];
    insert into returns(return_date, return_type, sale_id, customer_id, location_id, reason_code, user_name)
    values (v_sl.sale_date + interval '1 day' * (1 + floor(rnd()*5)), case when rnd() < 0.4 then 'Exchange' else 'Return' end,
            v_sl.sale_id, v_sl.customer_id, v_sl.location_id, v_rr, 'Pharmacist on duty') returning id into v_ret;
    insert into return_lines(return_id, direction, sale_line_id, item_id, qty, unit_price, line_total, tax_amount, unit_cost, line_cost, disposition, reason_code)
    values (v_ret, 'in', v_sl.id, v_sl.item_id, 1, v_sl.unit_price, round(v_sl.line_total / v_sl.qty, 2), round(v_sl.tax_amount / v_sl.qty, 2),
            v_sl.unit_cost, v_sl.unit_cost, case when v_rr in ('RT_DEFECTIVE','RT_EXPIRED','RT_REACTION') then 'write_off' else 'restock' end, v_rr);
    if (select return_type from returns where id = v_ret) = 'Exchange' then
      insert into return_lines(return_id, direction, item_id, qty, unit_price, line_total, tax_amount, unit_cost, line_cost)
      select v_ret, 'out', i.id, 1, i.price, i.price, case when i.taxable then round(i.price * 0.18, 2) else 0 end, i.avg_cost, i.avg_cost
      from items i where i.id = v_sl.item_id;
    end if;
    update returns r set refund_total = x.rin, replacement_total = x.rout, net_amount = x.rout - x.rin
    from (select coalesce(sum(line_total + tax_amount) filter (where direction='in'),0) rin,
                 coalesce(sum(line_total + tax_amount) filter (where direction='out'),0) rout from return_lines where return_id = v_ret) x
    where r.id = v_ret;
    insert into inventory_transactions(created_at, item_id, location_id, qty_change, txn_type, unit_cost, ref_type, ref_id, ref_no, reason_code, note)
    select r.return_date, v_sl.item_id, v_sl.location_id, 1, 'return', v_sl.unit_cost, 'return', r.id, r.return_number, v_rr, 'Historical return' from returns r where r.id = v_ret;
    if v_rr in ('RT_DEFECTIVE','RT_EXPIRED','RT_REACTION') then
      insert into inventory_transactions(created_at, item_id, location_id, qty_change, txn_type, unit_cost, ref_type, ref_id, ref_no, reason_code, note)
      select r.return_date, v_sl.item_id, v_sl.location_id, -1, 'write_off', v_sl.unit_cost, 'return', r.id, r.return_number, v_rr, 'Quality failure – written off'
      from returns r where r.id = v_ret;
    end if;
  end loop;

  -- ---------- 5. ADJUSTMENT HISTORY (cycle counts, expiry, damage, clinic use) ----------
  insert into inventory_transactions(created_at, item_id, location_id, qty_change, txn_type, unit_cost, ref_type, reason_code, note)
  select v_start + (rnd() * p_days)::int + time '17:00', i.id, case when rnd() < 0.6 then v_main else v_store end,
    case rc when 'CYCLE_COUNT' then (array[-2,-1,1,-1,2])[1 + floor(rnd()*5)::int] when 'FOUND' then 1
         when 'CLINIC_USE' then -(2 + floor(rnd()*6)) else -(1 + floor(rnd()*4)) end,
    'adjustment', i.avg_cost, 'adjustment', rc, 'Historical adjustment'
  from (select i.*, (array['CYCLE_COUNT','CYCLE_COUNT','EXPIRED','DAMAGED','CLINIC_USE','CLINIC_USE','LOST','FOUND'])[1 + floor(rnd()*8)::int] rc
        from items i, generate_series(1,1) where i.item_type = 'purchased' order by rnd() limit 30) i;

  -- ---------- 6. CURRENT STOCK (go-live balances) ----------
  for it in select i.*, coalesce(dm.avg_daily, 0) ad from items i left join _dem dm on dm.item_id = i.id where i.item_type <> 'service' loop
    v_x := rnd();
    v_total := ceil(greatest(it.ad, 0.05) * case
        when it.sku in ('PH-010','KIT-MAMA','SU-009','HY-003','SU-006','PH-021') then 2 + rnd() * 4      -- deliberately low / at risk
        when it.item_type = 'kit' then 6 + rnd() * 10
        else 40 + rnd() * 80 end);
    if it.sku in ('SU-006','SU-007','SU-008','PK-001','PK-002') then v_total := ceil(v_total * 1.5) + 10; end if;
    if it.item_type = 'kit' then
      insert into inventory values (it.id, v_main, ceil(v_total * 0.45)), (it.id, v_store, ceil(v_total * 0.40)), (it.id, v_mobile, floor(v_total * 0.15));
    elsif it.category = 'Packaging' or it.sellable = false then
      insert into inventory values (it.id, v_store, ceil(v_total * 0.7)), (it.id, v_main, floor(v_total * 0.3)), (it.id, v_mobile, 0);
    else
      insert into inventory values (it.id, v_main, case when it.sku = 'PH-021' then 0 else ceil(v_total * 0.35) end),
        (it.id, v_store, floor(v_total * 0.58)), (it.id, v_mobile, floor(v_total * 0.07));
    end if;
  end loop;
  insert into inventory_transactions(created_at, item_id, location_id, qty_change, txn_type, unit_cost, ref_type, note)
  select current_date - interval '1 minute', inv.item_id, inv.location_id, inv.qty_on_hand, 'opening', i.avg_cost, 'opening',
         'Go-live balance (migrated from Product Summary sheet)'
  from inventory inv join items i on i.id = inv.item_id where inv.qty_on_hand <> 0;

  -- reorder points: calculated from history, then aged (some stale) so periodic review has work to do
  update items i set reorder_point = greatest(1, round(ceil(dm.avg_daily * i.lead_time_days + 1.65 * dm.sd_daily * sqrt(greatest(i.lead_time_days,1))) * (0.8 + rnd() * 0.45))),
    last_reviewed_at = current_date - floor(rnd() * 25)::int
  from _dem dm where dm.item_id = i.id and i.item_type <> 'service';

  -- ---------- 7. OPEN SALES ORDERS (drive MRP over the next 4 weeks) ----------
  perform _seed_so('Kasana Village Health Team', v_main, current_date + 4, '[["KIT-MAL",30]]');
  perform _seed_so('Kayunga District Health Office', v_store, current_date + 9, '[["KIT-MAMA",40],["KIT-NEWB",20]]');
  perform _seed_so('St. Mary''s Primary School', v_store, current_date + 12, '[["KIT-CHILD",150]]');
  perform _seed_so('Hope for Mothers Foundation', v_store, current_date + 16, '[["KIT-ANC",35],["KIT-MAMA",25]]');
  perform _seed_so('Bukomero Health Centre III', v_store, current_date + 19, '[["KIT-WOUND",20],["KIT-ORS",30],["PH-050",50]]');
  perform _seed_so('Kasana Village Health Team', v_main, current_date + 24, '[["KIT-MAL",40]]');
  perform _seed_so('Bukomero Health Centre III', v_store, current_date - 2, '[["PH-010",60]]');
  perform _seed_so('Esther Nakato', v_main, current_date + 2, '[["KIT-NEWB",1],["PH-040",2]]', 'Portal');

  -- ---------- 8. CURRENT PRODUCTION ----------
  insert into production_orders(item_id, location_id, qty_planned, status, due_date, notes)
  select id, v_store, 40, 'Planned', current_date + 3, 'Weekly ANC pack build' from items where sku = 'KIT-ANC';
  insert into production_orders(item_id, location_id, qty_planned, status, due_date, notes)
  select id, v_store, 30, 'Planned', current_date + 5, 'Restock wound kits' from items where sku = 'KIT-WOUND';

  -- ---------- 9. OPERATING EXPENSES (from Rosbren 2026 financial workbook) ----------
  insert into expenses(expense_date, category, description, amount)
  select least((date_trunc('month', m) + interval '27 days')::date, current_date - 1), e.cat, e.cat || ' – ' || to_char(m, 'Mon YYYY'),
         e.v[extract(month from m)::int]
  from generate_series(date_trunc('month', v_start), date_trunc('month', current_date), interval '1 month') m
  cross join (values
    ('Payroll – clinic staff', array[1862000,1862000,1862000,1862000,1862000,1862000,1862000,1862000,1862000,1862000,1862000,1862000]),
    ('Payroll – pharmacist',   array[1500000,1500000,1500000,1500000,1500000,1500000,1500000,1500000,1500000,1500000,1500000,1500000]),
    ('Rent – facility',        array[560000,560000,560000,560000,560000,560000,560000,560000,560000,560000,560000,560000]),
    ('Rent – staff housing',   array[240000,240000,240000,240000,240000,240000,240000,240000,240000,240000,240000,240000]),
    ('Utilities',              array[485500,464200,478500,465900,455600,432800,453500,405000,422600,425000,425000,425000]),
    ('Electricity',            array[45000,60000,55000,58600,82000,86000,81500,82000,72000,80000,80000,80000]),
    ('Travel',                 array[265000,525000,364000,375500,346000,328000,326500,310500,325500,325000,325000,325000]),
    ('Staff meals',            array[476500,481000,476500,465400,447600,486700,478600,456000,432500,435800,435800,435800]),
    ('Charcoal',               array[75000,75000,75000,72500,80000,84000,82000,80000,78000,82000,82000,82000]),
    ('Airtime & data',         array[70000,67000,60000,63500,65000,72000,68000,48000,40000,42000,42000,42000]),
    ('Vet / farm supplies',    array[125000,217000,167000,167500,205700,120000,115500,96000,85000,90500,90500,90500]),
    ('Immunization mobilization', array[20000,20000,20000,20000,20000,20000,24000,28000,26000,25000,25000,25000]),
    ('Packaging bags',         array[22000,25000,20000,20000,20000,22000,25000,32000,34000,35000,35000,35000]),
    ('Waste management',       array[10000,10000,10000,10000,10000,10000,12000,10000,12000,12000,12000,12000]),
    ('Cleaning (Jik, sanitizer)', array[50000,50000,50000,75000,100000,55000,52500,32000,53000,25000,25000,25000]),
    ('Mobile money charges',   array[103652,476853,248546,46245,48600,0,49149,32645,26455,0,30000,30000])
  ) e(cat, v)
  where (date_trunc('month', m) + interval '27 days')::date >= v_start;

  -- ---------- 10. OUTREACH EVENTS ----------
  insert into outreach_events(name, village, event_date, expected_mothers, expected_children, expected_malaria_tests, expected_wounds, status, notes) values
    ('Kasana Village Mobile Clinic','Kasana', current_date + 10, 25, 60, 80, 10, 'Planned','Monthly outreach with VHT mobilizers'),
    ('Ndejje ANC & Immunization Day','Ndejje', current_date + 24, 40, 120, 60, 5, 'Planned','Joint day with district immunization team'),
    ('Bukomero School Health Day','Bukomero', current_date - 20, 0, 180, 40, 8, 'Completed','Deworming & Vitamin A at 3 schools');

  insert into activity_log(user_name, action, details, category)
  values (current_user_name(), 'Demo data generated', p_days || ' days of history generated from Rosbren patterns', 'operations');

  select jsonb_build_object('sales', (select count(*) from sales), 'sale_lines', (select count(*) from sale_lines),
    'items', (select count(*) from items), 'kits', (select count(*) from items where item_type='kit'),
    'purchase_orders', (select count(*) from purchase_orders), 'production_orders', (select count(*) from production_orders),
    'customers', (select count(*) from customers), 'suppliers', (select count(*) from suppliers),
    'first_sale', (select min(sale_date)::date from sales), 'last_sale', (select max(sale_date)::date from sales)) into v_cnt;
  return v_cnt;
end $$;

create or replace function _seed_so(p_customer text, p_loc int, p_date date, p_lines text, p_channel text default 'Staff') returns void
language plpgsql security definer set search_path = public as $$
declare v_so int; v_c record; l jsonb;
begin
  select * into v_c from customers where name = p_customer order by id desc limit 1;
  insert into sales_orders(customer_id, location_id, order_date, requested_date, status, channel)
  values (v_c.id, p_loc, now() - interval '1 day' * (1 + floor(rnd()*4)), p_date, 'Order Placed', p_channel) returning id into v_so;
  for l in select * from jsonb_array_elements(p_lines::jsonb) loop
    insert into sales_order_lines(so_id, item_id, qty, unit_price, discount_pct)
    select v_so, id, (l->>1)::numeric, price, v_c.discount_pct from items where sku = l->>0;
  end loop;
end $$;

revoke execute on function reset_demo_data(int) from anon;


-- generate starting data (re-run any time to refresh history up to yesterday)
select reset_demo_data();
