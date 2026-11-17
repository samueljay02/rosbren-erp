import { useMemo, useState } from 'react';
import { ArrowLeftRight, ClipboardCheck, AlertTriangle } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, Field, Input, Select, Modal, Table, Tabs, Badge, Spinner, Stat, Textarea, cx } from '../components/ui';
import { ScanInput } from '../components/Scanner';
import { money, fmt, d, dt, num } from '../lib/format';

export default function Inventory() {
  const L = useLookups();
  const [tab, setTab] = useState('stock');
  const [filter, setFilter] = useState('all');
  const [detail, setDetail] = useState(null);
  const { data } = useData(() => api.rpc('get_inventory_status'));
  const rows = useMemo(() => (data || []).filter((r) => r.active).filter((r) =>
    filter === 'all' ? true : filter === 'low' ? r.below_rop : filter === 'out' ? num(r.on_hand) <= 0 : filter === 'bo' ? num(r.backordered) > 0 : r.item_type === 'kit'), [data, filter]);
  if (!data || !L.ready) return <Spinner />;
  const total = data.reduce((a, r) => a + num(r.value), 0);
  return (
    <Page title="Stock & Locations" subtitle="On-hand quantity by item and location, allocations, backorders and expected availability."
      concept={<><p><b>On hand</b> is physical stock. <b>Allocated</b> is reserved by open sales orders. <b>Available</b> = on hand − allocated. <b>Backordered</b> = allocated beyond what’s on hand.</p>
        <p><b>Inventory position</b> = on hand + on order (open POs) + in production − allocated. When the position falls to the <b>reorder point</b> the item is flagged to reorder.</p>
        <p><b>Estimated available date</b> for backordered / out-of-stock items comes from the earliest open purchase order’s expected date; if nothing is on order, today + the supplier’s quoted lead time.</p></>}>
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Inventory value" value={money(total)} sub="weighted-average cost" />
        <Stat label="Below reorder point" value={data.filter((r) => r.below_rop).length} tone="warn" onClick={() => { setTab('stock'); setFilter('low'); }} />
        <Stat label="Backordered items" value={data.filter((r) => num(r.backordered) > 0).length} tone="bad" onClick={() => { setTab('stock'); setFilter('bo'); }} />
        <Stat label="Out of stock" value={data.filter((r) => num(r.on_hand) <= 0).length} tone="bad" onClick={() => { setTab('stock'); setFilter('out'); }} />
      </div>
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'stock', label: 'Stock by location' }, { value: 'transfer', label: 'Transfer between locations' }, { value: 'adjust', label: 'Scan to count / adjust' }, { value: 'ledger', label: 'Movement ledger' }]} />
      {tab === 'stock' && <Card pad={false}>
        <div className="flex flex-wrap gap-1.5 border-b border-slate-100 px-3 py-2">
          {[['all', 'All items'], ['low', 'Below ROP'], ['bo', 'Backordered'], ['out', 'Out of stock'], ['kit', 'Kits']].map(([v, l]) =>
            <button key={v} onClick={() => setFilter(v)} className={cx('rounded-full px-3 py-1 text-xs font-bold', filter === v ? 'bg-brand-600 text-white' : 'bg-slate-100 text-slate-600')}>{l}</button>)}
        </div>
        <Table rows={rows} onRowClick={setDetail} csv="inventory.csv" dense initialSort={{ key: 'name', dir: 'asc' }} columns={[
          { key: 'name', label: 'Item', render: (r) => <div><b>{r.name}</b><div className="text-xs text-slate-500">{r.sku} · shelf {r.shelf || '—'}</div></div>, search: (r) => r.name + r.sku + r.barcode },
          ...L.locations.map((l) => ({ key: 'loc' + l.id, label: l.code, align: 'right', render: (r) => fmt(r.by_location?.[l.id]), sortValue: (r) => num(r.by_location?.[l.id]), csv: (r) => r.by_location?.[l.id] })),
          { key: 'on_hand', label: 'On hand', align: 'right', render: (r) => <b>{fmt(r.on_hand)}</b> },
          { key: 'allocated', label: 'Allocated', align: 'right', render: (r) => fmt(r.allocated) },
          { key: 'available', label: 'Available', align: 'right', render: (r) => fmt(r.available) },
          { key: 'on_order', label: 'On order', align: 'right', render: (r) => fmt(num(r.on_order) + num(r.in_production)) },
          { key: 'backordered', label: 'Backordered', align: 'right', render: (r) => num(r.backordered) > 0 ? <b className="text-red-700">{fmt(r.backordered)}</b> : '—' },
          { key: 'est_available_date', label: 'Est. available', render: (r) => r.est_available_date ? <span title={r.eta_basis}>{d(r.est_available_date)}<div className="text-[10px] text-slate-500">{r.eta_basis}</div></span> : '—' },
          { key: 'reorder_point', label: 'ROP', align: 'right', render: (r) => fmt(r.reorder_point) },
          { key: 'status', label: 'Status', sortValue: (r) => (num(r.on_hand) <= 0 ? 0 : r.below_rop ? 1 : 2), render: (r) => num(r.on_hand) <= 0 ? <Badge color="red">Out</Badge> : r.below_rop ? <Badge color="amber">Reorder</Badge> : <Badge color="green">OK</Badge> },
          { key: 'value', label: 'Value', align: 'right', render: (r) => money(r.value) },
        ]} />
      </Card>}
      {tab === 'transfer' && <Transfer />}
      {tab === 'adjust' && <Adjust status={data} />}
      {tab === 'ledger' && <Ledger />}
      {detail && <ItemDetail item={detail} onClose={() => setDetail(null)} />}
    </Page>
  );
}

function Transfer() {
  const L = useLookups();
  const [item, setItem] = useState(null);
  const [f, setF] = useState({ from: L.locations.find((l) => l.code === 'STORE')?.id, to: L.locations.find((l) => l.code === 'MAIN')?.id, qty: 1, note: '' });
  const { data: inv } = useData(() => (item ? api.select('inventory', { eq: { item_id: item.id } }) : Promise.resolve([])), [item?.id]);
  const oh = Object.fromEntries((inv || []).map((i) => [i.location_id, num(i.qty_on_hand)]));
  const [run, busy] = useAction();
  const { data: recent } = useData(() => api.select('transfers', { order: 'created_at desc', limit: 15 }));
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card title="Move stock">
        <div className="space-y-3">
          <ScanInput onItem={setItem} filter={(i) => i.item_type !== 'service'} placeholder="Scan or search the item to move…" />
          {item && <div className="rounded-lg bg-brand-50 p-3 text-sm"><b>{item.name}</b> — {L.locations.map((l) => `${l.code}: ${fmt(oh[l.id] || 0)}`).join(' · ')}</div>}
          <div className="grid grid-cols-3 gap-3">
            <Field label="From"><Select value={f.from} onChange={(e) => setF({ ...f, from: Number(e.target.value) })} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
            <Field label="To"><Select value={f.to} onChange={(e) => setF({ ...f, to: Number(e.target.value) })} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
            <Field label="Quantity"><Input type="number" min="1" value={f.qty} onChange={(e) => setF({ ...f, qty: e.target.value })} /></Field>
          </div>
          <Field label="Note"><Input value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} placeholder="e.g. restock dispensary shelf" /></Field>
          <Btn icon={ArrowLeftRight} busy={busy} disabled={!item || f.from === f.to || num(f.qty) <= 0}
            onClick={async () => { if (await run(() => api.rpc('inv_transfer', { p: { item_id: item.id, from_location_id: f.from, to_location_id: f.to, qty: num(f.qty), note: f.note } }), (r) => `Transfer ${r.transfer_number} posted`)) setF({ ...f, qty: 1, note: '' }); }}>Transfer</Btn>
        </div>
      </Card>
      <Card title="Recent transfers" pad={false}>
        <Table search={false} rows={recent || []} dense columns={[
          { key: 'transfer_number', label: 'No.' }, { key: 'created_at', label: 'When', render: (r) => dt(r.created_at) },
          { key: 'item', label: 'Item', render: (r) => L.itemById[r.item_id]?.name },
          { key: 'route', label: 'Route', render: (r) => `${L.locById[r.from_location_id]?.code} → ${L.locById[r.to_location_id]?.code}` },
          { key: 'qty', label: 'Qty', align: 'right', render: (r) => fmt(r.qty) }, { key: 'user_name', label: 'By' }]} />
      </Card>
    </div>
  );
}

function Adjust({ status }) {
  const L = useLookups();
  const [loc, setLoc] = useState(L.locations[0]?.id);
  const [item, setItem] = useState(null);
  const [mode, setMode] = useState('count');
  const [qty, setQty] = useState('');
  const [reason, setReason] = useState('CYCLE_COUNT');
  const [note, setNote] = useState('');
  const [run, busy] = useAction();
  const current = item ? num(status.find((s) => s.id === item.id)?.by_location?.[loc]) : 0;
  const delta = mode === 'count' ? num(qty) - current : num(qty);
  const reasons = L.reasons.filter((r) => r.category === 'adjustment');
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card title="Cycle count or adjustment">
        <div className="space-y-3">
          <Field label="Location"><Select value={loc} onChange={(e) => setLoc(Number(e.target.value))} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
          <ScanInput onItem={(it) => { setItem(it); setQty(''); }} filter={(i) => i.item_type !== 'service'} placeholder="Scan the shelf item…" />
          {item && <>
            <div className="rounded-lg bg-brand-50 p-3 text-sm"><b>{item.name}</b> · system quantity here: <b>{fmt(current)}</b></div>
            <div className="grid grid-cols-2 gap-2">
              {[['count', 'Counted quantity'], ['delta', 'Add / remove (±)']].map(([v, l]) => <button key={v} onClick={() => setMode(v)} className={cx('rounded-lg py-2 text-sm font-bold ring-1', mode === v ? 'bg-brand-600 text-white ring-brand-600' : 'ring-slate-300')}>{l}</button>)}
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Field label={mode === 'count' ? 'Physical count' : 'Change (e.g. −3)'}><Input type="number" value={qty} onChange={(e) => setQty(e.target.value)} autoFocus /></Field>
              <Field label="Reason code"><Select value={reason} onChange={(e) => setReason(e.target.value)} options={reasons.map((r) => ({ value: r.code, label: r.description }))} /></Field>
            </div>
            <Field label="Note"><Textarea value={note} onChange={(e) => setNote(e.target.value)} /></Field>
            {qty !== '' && <p className={cx('text-sm font-bold', delta < 0 ? 'text-red-700' : delta > 0 ? 'text-emerald-700' : 'text-slate-600')}>
              Adjustment: {delta > 0 ? '+' : ''}{fmt(delta)} units · value {money(delta * num(item.avg_cost))}</p>}
            <Btn icon={ClipboardCheck} busy={busy} disabled={qty === ''} onClick={async () => {
              const r = await run(() => api.rpc('inv_adjust', { p: { item_id: item.id, location_id: loc, mode, qty: num(qty), reason_code: reason, note } }), (r) => r.message || `Adjusted ${r.delta > 0 ? '+' : ''}${r.delta}`);
              if (r) { setItem(null); setQty(''); setNote(''); }
            }}>Post adjustment</Btn>
          </>}
        </div>
      </Card>
      <Card title="Why reason codes matter">
        <ul className="list-disc space-y-1.5 pl-5 text-sm text-slate-700">
          <li>Every change to stock that isn’t a sale, receipt, transfer or production must carry a <b>reason code</b> — this is the audit trail.</li>
          <li><b>Expired</b> and <b>Damaged</b> adjustments flow to <i>Inventory losses</i> on the Profit &amp; Loss.</li>
          <li><b>Cycle counts</b> fix record accuracy without a full shutdown stock-take — count a few shelves each day.</li>
          <li><b>Clinic use</b> captures medicines used during treatment so the pharmacy stock stays accurate.</li>
        </ul>
      </Card>
    </div>
  );
}

function Ledger() {
  const L = useLookups();
  const { data } = useData(() => api.select('inventory_transactions', { order: ['created_at desc', 'id desc'], limit: 400 }));
  if (!data) return <Spinner />;
  return (
    <Card pad={false}>
      <Table rows={data} csv="inventory-ledger.csv" dense columns={[
        { key: 'created_at', label: 'When', render: (r) => dt(r.created_at) },
        { key: 'item', label: 'Item', render: (r) => L.itemById[r.item_id]?.name, search: (r) => L.itemById[r.item_id]?.name },
        { key: 'loc', label: 'Loc', render: (r) => L.locById[r.location_id]?.code },
        { key: 'txn_type', label: 'Type', render: (r) => <Badge color={num(r.qty_change) < 0 ? 'amber' : 'green'}>{r.txn_type.replace('_', ' ')}</Badge> },
        { key: 'qty_change', label: 'Qty', align: 'right', render: (r) => <b className={num(r.qty_change) < 0 ? 'text-red-700' : 'text-emerald-700'}>{num(r.qty_change) > 0 ? '+' : ''}{fmt(r.qty_change)}</b> },
        { key: 'unit_cost', label: 'Unit cost', align: 'right', render: (r) => fmt(r.unit_cost) },
        { key: 'ref_no', label: 'Reference' }, { key: 'reason_code', label: 'Reason' }, { key: 'note', label: 'Note' },
      ]} />
    </Card>
  );
}

function ItemDetail({ item, onClose }) {
  const L = useLookups();
  const { data } = useData(() => api.rpc('get_item_ledger', { p_item: item.id, p_limit: 60 }), [item.id]);
  return (
    <Modal open onClose={onClose} title={item.name} wide>
      <div className="mb-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        {L.locations.map((l) => <div key={l.id} className="rounded-lg bg-slate-50 p-3"><div className="text-xs font-bold uppercase text-slate-500">{l.name}</div><div className="text-xl font-black">{fmt(item.by_location?.[l.id])}</div></div>)}
        <div className="rounded-lg bg-brand-50 p-3"><div className="text-xs font-bold uppercase text-brand-700">Avg cost · Value</div><div className="font-black">{fmt(item.avg_cost)} · {money(item.value)}</div></div>
      </div>
      {num(item.backordered) > 0 && <p className="mb-3 flex items-center gap-2 rounded-lg bg-red-50 p-2 text-sm text-red-800"><AlertTriangle size={16} />{fmt(item.backordered)} backordered — estimated available {d(item.est_available_date)} ({item.eta_basis}).</p>}
      <div className="mb-1 text-xs font-bold uppercase text-slate-500">Recent movements · barcode {item.barcode}</div>
      {!data ? <Spinner /> : <Table search={false} rows={data} dense maxHeight={340} columns={[
        { key: 'created_at', label: 'When', render: (r) => dt(r.created_at) }, { key: 'location', label: 'Loc' },
        { key: 'txn_type', label: 'Type' }, { key: 'qty_change', label: 'Qty', align: 'right', render: (r) => fmt(r.qty_change) },
        { key: 'ref_no', label: 'Ref' }, { key: 'reason_code', label: 'Reason' }]} />}
    </Modal>
  );
}
