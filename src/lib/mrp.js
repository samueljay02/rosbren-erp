// Material Requirements Planning — weekly time-phased netting & BOM explosion.
//   Gross requirements  = confirmed sales-order demand (parents) / exploded parent plans (components)
//   Net requirement     = gross − on hand − scheduled receipts (open POs / open production orders)
//   Planned order       = lot-for-lot quantity to cover the net requirement
//   Order-by (release)  = requirement date − item lead time ("lead-time offset")

const DAY = 86400000;
export const toDate = (s) => { const d = new Date(typeof s === 'string' && s.length === 10 ? s + 'T00:00:00' : s); d.setHours(0, 0, 0, 0); return d; };
export const addDays = (d, n) => new Date(toDate(d).getTime() + n * DAY);
export const iso = (d) => { const x = toDate(d); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };

export function runMRP(input, { netParents = true, weeks = 4 } = {}) {
  const today = toDate(input.today);
  const horizonEnd = addDays(today, weeks * 7 - 1);
  const items = new Map(input.items.map((i) => [i.id, { ...i, on_hand: +i.on_hand, lead_time_days: +i.lead_time_days }]));
  const bomByParent = new Map();
  for (const b of input.bom) {
    if (!bomByParent.has(b.parent)) bomByParent.set(b.parent, []);
    bomByParent.get(b.parent).push({ component: b.component, qty_per: +b.qty_per });
  }
  const isParent = (id) => bomByParent.has(id);
  const bucketOf = (d) => { const n = Math.floor((toDate(d) - today) / DAY / 7); return Math.max(0, n); };

  // gross requirement events per item
  const gross = new Map(); // id -> [{date, qty, source}]
  const push = (id, date, qty, source) => {
    if (!gross.has(id)) gross.set(id, []);
    gross.get(id).push({ date: toDate(date), qty, source });
  };
  for (const d of input.demand) {
    if (toDate(d.date) > horizonEnd) continue;
    push(d.item_id, toDate(d.date) < today ? today : d.date, +d.qty, `${d.so_number} · ${d.customer}`);
  }
  const pastDue = new Set(input.demand.filter((d) => toDate(d.date) < today).map((d) => d.item_id));

  const receiptsFor = (id, list) => list.filter((r) => r.item_id === id)
    .map((r) => ({ date: toDate(r.date) < today ? today : toDate(r.date), qty: +r.qty, ref: r.ref }))
    .sort((a, b) => a.date - b.date);

  // net one item chronologically; returns planned orders
  const netItem = (id, scheduled) => {
    const it = items.get(id);
    const events = (gross.get(id) || []).slice().sort((a, b) => a.date - b.date);
    let proj = Math.max(0, it.on_hand);
    const sched = scheduled.slice();
    const planned = [];
    for (const e of events) {
      while (sched.length && sched[0].date <= e.date) proj += sched.shift().qty;
      proj -= e.qty;
      if (proj < 0) {
        const qty = Math.ceil(-proj);
        const release = addDays(e.date, -it.lead_time_days);
        planned.push({ need: e.date, qty, release, late: release < today, source: e.source });
        proj = 0;
      }
    }
    return planned;
  };

  const result = new Map(); // id -> {planned, scheduled}
  // 1) parents (level 0)
  for (const id of [...gross.keys()].filter(isParent)) {
    const scheduled = receiptsFor(id, input.production);
    const it = items.get(id);
    let planned;
    if (netParents) planned = netItem(id, scheduled);
    else planned = (gross.get(id) || []).map((e) => ({ need: e.date, qty: e.qty, release: addDays(e.date, -it.lead_time_days), late: addDays(e.date, -it.lead_time_days) < today, source: e.source }));
    result.set(id, { planned, scheduled: netParents ? scheduled : [] });
    // 2) explode planned parent orders through the BOM at the parent's release date
    for (const p of planned) for (const c of bomByParent.get(id)) {
      push(c.component, p.release < today ? today : p.release, p.qty * c.qty_per, `${it.sku} plan ${p.qty} (${p.source})`);
    }
  }
  // 3) components & purchased items (level 1)
  for (const id of gross.keys()) {
    if (isParent(id)) continue;
    const scheduled = receiptsFor(id, input.receipts);
    result.set(id, { planned: netItem(id, scheduled), scheduled });
  }

  // weekly grid
  const weekStarts = Array.from({ length: weeks }, (_, w) => addDays(today, w * 7));
  const rows = [];
  for (const [id, r] of result) {
    const it = items.get(id);
    const g = Array(weeks).fill(0), sr = Array(weeks).fill(0), por = Array(weeks).fill(0), rel = Array(weeks).fill(0), poh = Array(weeks).fill(0), nr = Array(weeks).fill(0);
    for (const e of gross.get(id) || []) g[bucketOf(e.date)] += e.qty;
    for (const s of r.scheduled) if (s.date <= horizonEnd) sr[bucketOf(s.date)] += s.qty;
    for (const p of r.planned) { por[bucketOf(p.need)] += p.qty; rel[bucketOf(p.release)] += p.qty; }
    let proj = Math.max(0, it.on_hand);
    for (let w = 0; w < weeks; w++) {
      const before = proj + sr[w];
      nr[w] = Math.max(0, g[w] - before);
      proj = before - g[w] + por[w];
      poh[w] = Math.round(proj * 100) / 100;
    }
    rows.push({
      id, sku: it.sku, name: it.name, uom: it.uom, level: isParent(id) ? 0 : 1, item_type: it.item_type,
      on_hand: it.on_hand, lead_time_days: it.lead_time_days, supplier_id: it.supplier_id, supplier_name: it.supplier_name,
      avg_cost: +it.avg_cost, past_due: pastDue.has(id),
      gross: g, scheduled: sr, projected: poh, net: nr, planned_receipt: por, planned_release: rel,
      planned: r.planned.map((p) => ({ ...p, need: iso(p.need), release: iso(p.release) })),
      sources: (gross.get(id) || []).map((e) => ({ date: iso(e.date), qty: e.qty, source: e.source })),
    });
  }
  rows.sort((a, b) => a.level - b.level || a.name.localeCompare(b.name));
  const suggestions = rows.flatMap((r) => r.planned.map((p) => ({
    item_id: r.id, sku: r.sku, name: r.name, uom: r.uom, qty: p.qty, need_date: p.need, order_by: p.release, late: p.late,
    action: r.level === 0 ? 'Make' : 'Buy', supplier_name: r.supplier_name, lead_time_days: r.lead_time_days,
    est_cost: Math.round(p.qty * r.avg_cost),
  }))).sort((a, b) => a.order_by.localeCompare(b.order_by));
  return { weeks: weekStarts.map(iso), rows, suggestions };
}
