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
