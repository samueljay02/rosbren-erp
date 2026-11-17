
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
