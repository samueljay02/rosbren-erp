import { useMemo, useState } from 'react';
import { Plus, Play, CheckCircle2, XCircle } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, Field, Input, Select, Modal, Table, Tabs, StatusBadge, Badge, Spinner, Stat, DateRange, Textarea } from '../components/ui';
import { Bars, RankBars, SERIES } from '../components/charts';
import { money, fmt, d, dt, num, pct, todayISO, addDaysISO } from '../lib/format';

export default function Production() {
  const L = useLookups();
  const [tab, setTab] = useState('open');
  const [create, setCreate] = useState(false);
  const [open, setOpen] = useState(null);
  const { data } = useData(async () => {
    const [wos, comps] = await Promise.all([api.select('production_orders', { order: 'created_at desc' }), api.select('production_order_components', { order: 'id' })]);
    return { wos, comps };
  });
  if (!data || !L.ready) return <Spinner />;
  const rows = data.wos.map((w) => ({ ...w, item: L.itemById[w.item_id]?.name, loc: L.locById[w.location_id]?.code, late: w.status !== 'Completed' && w.status !== 'Cancelled' && w.due_date < todayISO() }));
  const shown = tab === 'open' ? rows.filter((r) => r.status === 'Planned' || r.status === 'In Progress') : tab === 'done' ? rows.filter((r) => r.status === 'Completed') : rows;
  return (
    <Page title="Production Orders" subtitle="Kit assembly work orders — issue components per the bill of materials and receive finished kits at rolled-up cost."
      actions={<Btn icon={Plus} onClick={() => setCreate(true)}>New production order</Btn>}
      concept={<><p><b>Planned</b> → <b>Start</b>: components are issued from the location’s stock per the BOM (quantity × qty-per) at their current weighted-average cost; the material cost is captured on the order. → <b>Complete</b>: record good, scrapped and reworked units with a quality reason code; good kits are received into stock.</p>
        <p><b>Rolled-up cost</b> = total component cost ÷ good units, so scrap is absorbed into the cost of good kits (and reported separately as cost of poor quality).</p></>}>
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'open', label: 'Open', count: rows.filter((r) => ['Planned', 'In Progress'].includes(r.status)).length }, { value: 'done', label: 'Completed' }, { value: 'all', label: 'All' }, { value: 'report', label: 'Production & quality report' }]} />
      {tab !== 'report' ? (
        <Card pad={false}>
          <Table rows={shown} onRowClick={(r) => setOpen(r)} csv="production-orders.csv" rowClass={(r) => (r.late ? 'bg-red-50/40' : '')} columns={[
            { key: 'wo_number', label: 'Order', render: (r) => <b className="text-brand-700">{r.wo_number}</b> },
            { key: 'item', label: 'Kit' }, { key: 'loc', label: 'Loc' },
            { key: 'qty_planned', label: 'Qty', align: 'right', render: (r) => fmt(r.qty_planned) },
            { key: 'qty_good', label: 'Good', align: 'right', render: (r) => (r.status === 'Completed' ? fmt(r.qty_good) : '') },
            { key: 'qty_scrapped', label: 'Scrap', align: 'right', render: (r) => (num(r.qty_scrapped) ? <span className="text-red-700">{fmt(r.qty_scrapped)}</span> : '') },
            { key: 'due_date', label: 'Due', render: (r) => <span className={r.late ? 'font-bold text-red-700' : ''}>{d(r.due_date)}</span> },
            { key: 'started_at', label: 'Started', render: (r) => dt(r.started_at) }, { key: 'finished_at', label: 'Finished', render: (r) => dt(r.finished_at) },
            { key: 'unit_cost', label: 'Unit cost', align: 'right', render: (r) => (r.unit_cost ? fmt(r.unit_cost) : '') },
            { key: 'status', label: 'Status', render: (r) => <StatusBadge status={r.status} /> },
          ]} />
        </Card>
      ) : <Report />}
      {create && <CreateWO onClose={() => setCreate(false)} />}
      {open && <WODetail wo={open} comps={data.comps.filter((c) => c.wo_id === open.id)} onClose={() => setOpen(null)} />}
    </Page>
  );
}

function useBomCheck(itemId, locId, qty) {
  const { data } = useData(async () => {
    if (!itemId) return null;
    const [bom, inv] = await Promise.all([api.select('bom_lines', { eq: { parent_item_id: itemId } }), api.select('inventory', { eq: { location_id: locId } })]);
    return { bom, inv };
  }, [itemId, locId]);
  const L = useLookups();
  return useMemo(() => (data ? data.bom.map((b) => {
    const have = num(data.inv.find((i) => i.item_id === b.component_item_id)?.qty_on_hand); const need = num(b.qty_per) * num(qty);
    const it = L.itemById[b.component_item_id];
    return { ...b, name: it?.name, need, have, cost: need * num(it?.avg_cost), ok: have >= need };
  }) : []), [data, qty, L]);
}

function CreateWO({ onClose }) {
  const L = useLookups();
  const kits = L.items.filter((i) => i.item_type === 'kit' && i.active);
  const [f, setF] = useState({ item_id: kits[0]?.id, location_id: L.locations.find((l) => l.code === 'STORE')?.id, qty: 20, due_date: addDaysISO(todayISO(), 2), notes: '' });
  const check = useBomCheck(f.item_id, f.location_id, f.qty);
  const [run, busy] = useAction();
  return (
    <Modal open onClose={onClose} title="New production order" wide footer={<><Btn variant="secondary" onClick={onClose}>Cancel</Btn>
      <Btn busy={busy} onClick={async () => (await run(() => api.rpc('wo_create', { p: { ...f, item_id: Number(f.item_id), location_id: Number(f.location_id), qty: num(f.qty) } }), (r) => `${r.wo_number} created`)) && onClose()}>Create order</Btn></>}>
      <div className="grid gap-3 sm:grid-cols-4">
        <Field label="Kit to build" className="sm:col-span-2"><Select value={f.item_id} onChange={(e) => setF({ ...f, item_id: Number(e.target.value) })} options={kits.map((k) => ({ value: k.id, label: k.name }))} /></Field>
        <Field label="Quantity"><Input type="number" min="1" value={f.qty} onChange={(e) => setF({ ...f, qty: e.target.value })} /></Field>
        <Field label="Due"><Input type="date" value={f.due_date} onChange={(e) => setF({ ...f, due_date: e.target.value })} /></Field>
        <Field label="Location (components & output)" className="sm:col-span-2"><Select value={f.location_id} onChange={(e) => setF({ ...f, location_id: Number(e.target.value) })} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
        <Field label="Notes" className="sm:col-span-2"><Input value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} /></Field>
      </div>
      <BomTable rows={check} />
    </Modal>
  );
}

function BomTable({ rows, issued }) {
  const total = rows.reduce((a, r) => a + num(r.cost ?? r.total_cost), 0);
  return (
    <div className="mt-4">
      <div className="mb-1 text-xs font-bold uppercase text-slate-500">{issued ? 'Components issued' : 'Bill of materials check'}</div>
      <table className="min-w-full text-sm"><thead className="bg-slate-50 text-left text-xs uppercase text-slate-500"><tr><th className="px-3 py-1.5">Component</th><th className="px-3 py-1.5 text-right">Qty per</th>
        <th className="px-3 py-1.5 text-right">{issued ? 'Issued' : 'Required'}</th>{!issued && <th className="px-3 py-1.5 text-right">On hand</th>}<th className="px-3 py-1.5 text-right">{issued ? 'Unit cost' : ''}</th><th className="px-3 py-1.5 text-right">Cost</th></tr></thead>
        <tbody className="divide-y divide-slate-100">{rows.map((r) => <tr key={r.id}><td className="px-3 py-1.5">{r.name}</td><td className="px-3 py-1.5 text-right">{fmt(r.qty_per, 2)}</td>
          <td className="px-3 py-1.5 text-right">{fmt(issued ? r.qty_issued : r.need)}</td>
          {!issued && <td className={`px-3 py-1.5 text-right ${r.ok ? '' : 'font-bold text-red-700'}`}>{fmt(r.have)}{!r.ok && ' ✗'}</td>}
          <td className="px-3 py-1.5 text-right">{issued ? fmt(r.unit_cost) : ''}</td><td className="px-3 py-1.5 text-right">{fmt(r.cost ?? r.total_cost)}</td></tr>)}</tbody>
        <tfoot><tr className="font-black"><td className="px-3 py-1.5" colSpan={issued ? 4 : 5}>Material cost</td><td className="px-3 py-1.5 text-right">{money(total)}</td></tr></tfoot>
      </table>
      {!issued && rows.some((r) => !r.ok) && <p className="mt-2 text-sm text-red-700">Some components are short at this location — transfer stock or raise a purchase order before starting.</p>}
    </div>
  );
}

function WODetail({ wo, comps, onClose }) {
  const L = useLookups();
  const [run, busy] = useAction();
  const check = useBomCheck(wo.status === 'Planned' ? wo.item_id : null, wo.location_id, wo.qty_planned);
  const [c, setC] = useState({ qty_good: num(wo.qty_started || wo.qty_planned), qty_scrapped: 0, qty_reworked: 0, scrap_reason_code: '', notes: '' });
  const scrapCodes = L.reasons.filter((r) => r.category === 'scrap');
  const act = async (fn, msg) => (await run(fn, msg)) && onClose();
  return (
    <Modal open onClose={onClose} title={`${wo.wo_number} · ${wo.item}`} wide footer={<>
      {wo.status === 'Planned' && <Btn variant="secondary" icon={XCircle} busy={busy} onClick={() => act(() => api.rpc('wo_cancel', { p_wo_id: wo.id }), 'Cancelled')}>Cancel</Btn>}
      {wo.status === 'Planned' && <Btn icon={Play} busy={busy} onClick={() => act(() => api.rpc('wo_start', { p_wo_id: wo.id }), 'Started — components issued')}>Start &amp; issue components</Btn>}
      {wo.status === 'In Progress' && <Btn icon={CheckCircle2} busy={busy} onClick={() => act(() => api.rpc('wo_complete', { p_wo_id: wo.id, p: { ...c, qty_good: num(c.qty_good), qty_scrapped: num(c.qty_scrapped), qty_reworked: num(c.qty_reworked) } }), (r) => `Completed — unit cost UGX ${fmt(r.unit_cost)}`)}>Complete order</Btn>}
    </>}>
      <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <Info k="Status" v={<StatusBadge status={wo.status} />} /><Info k="Location" v={L.locById[wo.location_id]?.name} />
        <Info k="Planned qty" v={fmt(wo.qty_planned)} /><Info k="Due" v={d(wo.due_date)} />
        <Info k="Started" v={dt(wo.started_at)} /><Info k="Finished" v={dt(wo.finished_at)} />
        <Info k="Material cost" v={money(wo.material_cost)} /><Info k="Unit cost" v={wo.unit_cost ? money(wo.unit_cost) : '—'} />
        {wo.status === 'Completed' && <><Info k="Good" v={fmt(wo.qty_good)} /><Info k="Scrapped" v={fmt(wo.qty_scrapped)} /><Info k="Reworked" v={fmt(wo.qty_reworked)} /><Info k="Reason" v={L.reasons.find((r) => r.code === wo.scrap_reason_code)?.description || '—'} /></>}
      </div>
      {wo.notes && <p className="mt-3 text-sm text-slate-600">Notes: {wo.notes}</p>}
      {wo.status === 'In Progress' && (
        <div className="mt-4 rounded-lg border border-brand-200 bg-brand-50/50 p-3">
          <div className="mb-2 text-sm font-black text-brand-800">Record completion — good + scrapped must equal {fmt(wo.qty_started)} started</div>
          <div className="grid gap-3 sm:grid-cols-4">
            <Field label="Good units"><Input type="number" value={c.qty_good} onChange={(e) => setC({ ...c, qty_good: e.target.value, qty_scrapped: Math.max(0, num(wo.qty_started) - num(e.target.value)) })} /></Field>
            <Field label="Scrapped"><Input type="number" value={c.qty_scrapped} onChange={(e) => setC({ ...c, qty_scrapped: e.target.value, qty_good: Math.max(0, num(wo.qty_started) - num(e.target.value)) })} /></Field>
            <Field label="Reworked (within good)"><Input type="number" value={c.qty_reworked} onChange={(e) => setC({ ...c, qty_reworked: e.target.value })} /></Field>
            <Field label="Quality reason"><Select value={c.scrap_reason_code} onChange={(e) => setC({ ...c, scrap_reason_code: e.target.value })} placeholder="— none" options={scrapCodes.map((r) => ({ value: r.code, label: r.description }))} /></Field>
          </div>
          <Field label="Notes" className="mt-2"><Textarea value={c.notes} onChange={(e) => setC({ ...c, notes: e.target.value })} /></Field>
          {num(c.qty_good) > 0 && <p className="mt-2 text-sm">Rolled-up unit cost will be <b>{money(num(wo.material_cost) / num(c.qty_good))}</b> ({money(wo.material_cost)} ÷ {fmt(c.qty_good)} good).</p>}
        </div>
      )}
      {wo.status === 'Planned' ? <BomTable rows={check} /> : comps.length > 0 && <BomTable issued rows={comps.map((x) => ({ ...x, name: L.itemById[x.item_id]?.name }))} />}
    </Modal>
  );
}
const Info = ({ k, v }) => <div><div className="text-xs font-bold uppercase text-slate-500">{k}</div><div className="mt-0.5">{v}</div></div>;

function Report() {
  const [range, setRange] = useState([addDaysISO(todayISO(), -89), todayISO()]);
  const { data } = useData(() => api.rpc('get_production_report', { p_from: range[0], p_to: range[1] }), [range[0], range[1]]);
  if (!data) return <Spinner />;
  const m = data.metrics;
  return (
    <div className="space-y-4">
      <Card><div className="flex flex-wrap items-center justify-between gap-2"><b className="text-sm text-slate-700">Orders started in range</b><DateRange from={range[0]} to={range[1]} onChange={(a, b) => setRange([a, b])} /></div></Card>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Yield (good ÷ started)" value={pct(m.yield_pct)} sub={`${fmt(m.units_good)} good of ${fmt(m.units_started)} started`} tone="good" />
        <Stat label="First-pass yield" value={pct(m.first_pass_yield_pct)} sub={`${fmt(m.units_reworked)} units needed rework`} />
        <Stat label="Scrap rate" value={pct(m.scrap_rate_pct)} sub={`Cost of scrap ${money(m.scrap_cost)}`} tone={num(m.scrap_rate_pct) > 3 ? 'warn' : 'default'} />
        <Stat label="On-time completion" value={pct(m.on_time_pct)} sub={`${m.orders_completed} orders completed`} />
        <Stat label="Avg cycle time" value={`${fmt(m.avg_cycle_hours, 1)} h`} sub="start → finish" />
        <Stat label="Throughput" value={`${fmt(m.throughput_per_day, 1)} / day`} sub="good kits per calendar day" />
        <Stat label="Avg cost per good kit" value={money(m.avg_unit_cost)} sub="incl. absorbed scrap" />
        <Stat label="Units scrapped" value={fmt(m.units_scrapped)} tone="bad" />
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Weekly output — good vs scrapped units"><Bars data={data.weekly} x="week" money={false} stacked xFmt={(v) => v?.slice(5)} series={[{ key: 'good', label: 'Good' }, { key: 'scrapped', label: 'Scrapped', color: SERIES[1] }]} /></Card>
        <Card title="Quality issues by reason (Pareto, units scrapped)"><RankBars money={false} label="description" value="scrapped" data={data.by_reason.map((r) => ({ ...r, scrapped: num(r.scrapped) }))} color={SERIES[1]} /></Card>
      </div>
      <Card title="By kit" pad={false}><Table search={false} rows={data.by_item} columns={[{ key: 'item', label: 'Kit' }, { key: 'orders', label: 'Orders', align: 'right' }, { key: 'good', label: 'Good', align: 'right', render: (r) => fmt(r.good) },
        { key: 'scrapped', label: 'Scrapped', align: 'right', render: (r) => fmt(r.scrapped) }, { key: 'yield_pct', label: 'Yield', align: 'right', render: (r) => pct(r.yield_pct) }, { key: 'avg_unit_cost', label: 'Avg unit cost', align: 'right', render: (r) => money(r.avg_unit_cost) }]} /></Card>
      <Card title="Orders in range" pad={false}><Table rows={data.orders} csv="production-report.csv" dense columns={[
        { key: 'wo_number', label: 'Order' }, { key: 'item_name', label: 'Kit' }, { key: 'status', label: 'Status', render: (r) => <StatusBadge status={r.status} /> },
        { key: 'qty_started', label: 'Started', align: 'right', render: (r) => fmt(r.qty_started) }, { key: 'qty_good', label: 'Good', align: 'right', render: (r) => fmt(r.qty_good) },
        { key: 'qty_scrapped', label: 'Scrap', align: 'right', render: (r) => fmt(r.qty_scrapped) }, { key: 'qty_reworked', label: 'Rework', align: 'right', render: (r) => fmt(r.qty_reworked) },
        { key: 'scrap_reason_code', label: 'Reason' }, { key: 'started_at', label: 'Start', render: (r) => dt(r.started_at) }, { key: 'finished_at', label: 'Finish', render: (r) => dt(r.finished_at) },
        { key: 'cycle_hours', label: 'Hours', align: 'right', render: (r) => fmt(r.cycle_hours, 1) }, { key: 'unit_cost', label: 'Unit cost', align: 'right', render: (r) => fmt(r.unit_cost) }]} /></Card>
    </div>
  );
}
