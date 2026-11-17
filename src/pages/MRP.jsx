import { useMemo, useState } from 'react';
import { ShoppingBag, Factory, AlertTriangle, ChevronDown, ChevronRight } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { runMRP } from '../lib/mrp';
import { Page, Card, Btn, Spinner, Badge, Stat, Table, cx } from '../components/ui';
import { money, fmt, d, dShort } from '../lib/format';

export default function MRP() {
  const L = useLookups();
  const [netParents, setNetParents] = useState(true);
  const [expanded, setExpanded] = useState({});
  const [run, busy] = useAction();
  const { data: input } = useData(() => api.rpc('get_mrp_inputs'));
  const plan = useMemo(() => (input ? runMRP(input, { netParents, weeks: 4 }) : null), [input, netParents]);
  if (!plan || !L.ready) return <Spinner />;
  const buys = plan.suggestions.filter((s) => s.action === 'Buy');
  const makes = plan.suggestions.filter((s) => s.action === 'Make');
  const late = plan.suggestions.filter((s) => s.late).length;
  const createPOs = () => run(() => api.rpc('create_pos_from_suggestions', { p: { source: 'MRP', send: false, lines: buys.map((b) => ({ item_id: b.item_id, qty: b.qty })) } }), (r) => `${r.length} draft purchase orders created — review them under Purchase Orders`);
  const createWOs = async () => {
    for (const m of makes) await api.rpc('wo_create', { p: { item_id: m.item_id, location_id: L.locations.find((l) => l.code === 'STORE')?.id, qty: m.qty, due_date: m.need_date, notes: 'Planned by MRP' } });
  };
  const toggle = (id) => setExpanded((e) => ({ ...e, [id]: !e[id] }));
  return (
    <Page title="MRP Planner" subtitle="Time-phased material requirements for the next 4 weeks, driven by confirmed sales orders and the bills of material."
      concept={<>
        <ol className="list-decimal space-y-1 pl-5">
          <li><b>Gross requirements</b> — kit quantities on open (<i>Order Placed</i>) sales orders, bucketed by the week they’re needed. Past-due orders land in week 1.</li>
          <li><b>Net the parent</b> — subtract kits already on hand and open production orders (toggle below). Remaining kits become <b>planned production orders</b>, released 1 day before need (assembly lead time).</li>
          <li><b>Explode through the BOM</b> — each planned kit × qty-per gives the component’s <b>dependent demand</b> on the kit’s release date.</li>
          <li><b>Net the component</b> — subtract on-hand stock and <b>scheduled receipts</b> (open purchase orders by expected date). What’s left is the <b>net requirement</b> → a planned purchase (lot-for-lot).</li>
          <li><b>Lead-time offset</b> — order-by date = need date − the supplier’s lead time. A past order-by date means <b>expedite</b>.</li>
        </ol>
        <p>Change anything upstream — place a sales order, receive a PO, finish a production order — and this plan recalculates instantly.</p></>}
      actions={<label className="flex cursor-pointer items-center gap-2 rounded-lg bg-white px-3 py-2 text-sm font-bold ring-1 ring-slate-300">
        <input type="checkbox" checked={netParents} onChange={(e) => setNetParents(e.target.checked)} />Net parent kits on hand first</label>}>
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Open order demand lines" value={input.demand.length} sub={`${new Set(input.demand.map((x) => x.so_number)).size} sales orders`} />
        <Stat label="Planned kit builds" value={makes.length} sub={`${fmt(makes.reduce((a, b) => a + b.qty, 0))} kits`} tone="brand" />
        <Stat label="Planned purchases" value={buys.length} sub={money(buys.reduce((a, b) => a + b.est_cost, 0))} tone="brand" />
        <Stat label="Already late (expedite)" value={late} tone={late ? 'bad' : 'good'} sub="order-by date has passed" />
      </div>

      <Card title="Suggested orders" className="mb-4" pad={false} actions={<>
        <Btn size="sm" variant="secondary" icon={Factory} disabled={!makes.length} busy={busy} onClick={() => run(createWOs, `${makes.length} production orders created`)}>Create production orders</Btn>
        <Btn size="sm" icon={ShoppingBag} disabled={!buys.length} busy={busy} onClick={createPOs}>Create draft POs</Btn></>}>
        <Table rows={plan.suggestions.map((s, i) => ({ ...s, id: i }))} search={false} csv="mrp-suggestions.csv" initialSort={{ key: 'order_by', dir: 'asc' }} columns={[
          { key: 'action', label: 'Action', render: (r) => <Badge color={r.action === 'Make' ? 'brand' : 'blue'}>{r.action}</Badge> },
          { key: 'name', label: 'Item', render: (r) => <b>{r.name}</b> },
          { key: 'qty', label: 'Suggested qty', align: 'right', render: (r) => <b>{fmt(r.qty)}</b> },
          { key: 'need_date', label: 'Needed by', render: (r) => d(r.need_date) },
          { key: 'lead_time_days', label: 'Lead time', align: 'right', render: (r) => `${r.lead_time_days} d` },
          { key: 'order_by', label: 'Order by', render: (r) => <span className={r.late ? 'font-bold text-red-700' : ''}>{d(r.order_by)}{r.late && ' · LATE'}</span> },
          { key: 'supplier_name', label: 'Source', render: (r) => r.supplier_name || 'In-house assembly' },
          { key: 'est_cost', label: 'Est. cost', align: 'right', render: (r) => money(r.est_cost) },
        ]} />
      </Card>

      <Card title="Time-phased MRP records" pad={false}>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-xs font-bold uppercase text-slate-600"><tr>
              <th className="px-3 py-2 text-left">Item</th><th className="px-3 py-2 text-left">Row</th>
              {plan.weeks.map((w, i) => <th key={w} className="px-3 py-2 text-right">Wk {i + 1}<div className="font-normal normal-case text-slate-500">{dShort(w)}</div></th>)}
            </tr></thead>
            <tbody>
              {plan.rows.map((r) => {
                const rowsDef = [['Gross requirements', r.gross], ['Scheduled receipts', r.scheduled], ['Projected on hand', r.projected], ['Net requirements', r.net], ['Planned order receipt', r.planned_receipt], ['Planned order release', r.planned_release]];
                const open = expanded[r.id] ?? r.planned.length > 0;
                return [
                  <tr key={r.id} className={cx('cursor-pointer border-t-2 border-slate-200', r.level === 0 ? 'bg-brand-50/60' : 'bg-white')} onClick={() => toggle(r.id)}>
                    <td className="px-3 py-2" colSpan={2}><span className="flex items-center gap-1.5 font-bold">{open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                      {r.level === 1 && <span className="text-slate-400">└</span>}{r.name}
                      <Badge color={r.level === 0 ? 'brand' : 'gray'}>{r.level === 0 ? 'Level 0 · kit' : 'Level 1'}</Badge>
                      {r.past_due && <Badge color="red"><AlertTriangle size={11} />past-due demand</Badge>}</span>
                      <span className="ml-6 text-xs text-slate-500">On hand {fmt(r.on_hand)} · lead time {r.lead_time_days} d{r.supplier_name ? ` · ${r.supplier_name}` : ''}</span></td>
                    {r.planned_release.map((v, i) => <td key={i} className="px-3 py-2 text-right text-xs">{v > 0 && <Badge color={r.level === 0 ? 'brand' : 'blue'}>release {fmt(v)}</Badge>}</td>)}
                  </tr>,
                  ...(open ? rowsDef.map(([label, vals]) => (
                    <tr key={r.id + label} className="text-slate-700">
                      <td /><td className={cx('px-3 py-1 text-xs', label.startsWith('Planned order release') && 'font-bold text-brand-700', label.startsWith('Net') && 'font-bold')}>{label}</td>
                      {vals.map((v, i) => <td key={i} className={cx('px-3 py-1 text-right tabular-nums', v === 0 && 'text-slate-300', label.startsWith('Net') && v > 0 && 'font-bold text-red-700', label.startsWith('Planned order release') && v > 0 && 'font-black text-brand-700')}>{fmt(v)}</td>)}
                    </tr>)) : []),
                  ...(open && r.sources.length ? [<tr key={r.id + 'src'}><td /><td colSpan={5} className="px-3 pb-2 text-[11px] text-slate-500">Demand from: {r.sources.map((s) => `${dShort(s.date)} ${fmt(s.qty)} (${s.source})`).join(' · ')}</td></tr>] : []),
                ];
              })}
            </tbody>
          </table>
        </div>
      </Card>
    </Page>
  );
}
