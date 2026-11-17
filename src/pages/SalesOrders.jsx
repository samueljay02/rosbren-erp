import { useMemo, useState } from 'react';
import { Plus, PackageCheck, Lock, XCircle, Printer, Trash2, Globe } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, Field, Input, Select, Modal, Table, Tabs, StatusBadge, Badge, Spinner, Textarea } from '../components/ui';
import { ScanInput } from '../components/Scanner';
import Receipt, { printReceipt } from '../components/Receipt';
import { money, fmt, d, dt, num, todayISO, addDaysISO } from '../lib/format';

const STATUSES = ['Order Placed', 'Fulfilled', 'Closed', 'Cancelled'];

export default function SalesOrders() {
  const L = useLookups();
  const [tab, setTab] = useState('Order Placed');
  const [creating, setCreating] = useState(false);
  const [openId, setOpenId] = useState(null);
  const { data } = useData(async () => {
    const [sos, lines, inv] = await Promise.all([
      api.select('sales_orders', { order: 'order_date desc' }), api.select('sales_order_lines'), api.select('inventory')]);
    return { sos, lines, inv };
  });
  const rows = useMemo(() => {
    if (!data || !L.ready) return [];
    const byso = {}; data.lines.forEach((l) => (byso[l.so_id] ||= []).push(l));
    const oh = {}; data.inv.forEach((i) => { oh[i.item_id + ':' + i.location_id] = num(i.qty_on_hand); });
    return data.sos.map((s) => {
      const ls = byso[s.id] || [];
      const total = ls.reduce((a, l) => a + num(l.qty) * num(l.unit_price) * (1 - num(l.discount_pct) / 100), 0);
      const short = ls.filter((l) => L.itemById[l.item_id]?.item_type !== 'kit' && num(l.qty) > (oh[l.item_id + ':' + s.location_id] || 0));
      const kitShort = ls.filter((l) => L.itemById[l.item_id]?.item_type === 'kit' && num(l.qty) > (oh[l.item_id + ':' + s.location_id] || 0));
      return { ...s, lines: ls, total, short, kitShort, customer: L.custById[s.customer_id]?.name, location: L.locById[s.location_id]?.name, overdue: s.status === 'Order Placed' && s.requested_date < todayISO() };
    });
  }, [data, L]);
  if (!data || !L.ready) return <Spinner />;
  const counts = Object.fromEntries(STATUSES.map((s) => [s, rows.filter((r) => r.status === s).length]));
  const shown = tab === 'All' ? rows : rows.filter((r) => r.status === tab);
  const open = rows.find((r) => r.id === openId);
  return (
    <Page title="Sales Orders" subtitle="Orders from health centres, VHTs, schools, NGOs and online pickup customers."
      actions={<Btn icon={Plus} onClick={() => setCreating(true)}>New sales order</Btn>}
      concept={<><p><b>Order lifecycle:</b> <i>Order Placed</i> → <i>Fulfilled</i> (goods leave stock and an invoice is created, recognising revenue and cost) → <i>Closed</i> (paid / complete). Open orders can be <i>Cancelled</i>.</p>
        <p>Open orders <b>allocate</b> stock: they reduce “available” quantity, show as <b>backorders</b> when stock is short, and are the <b>gross requirements that drive MRP</b>.</p></>}>
      <Tabs value={tab} onChange={setTab} tabs={[...STATUSES.map((s) => ({ value: s, label: s, count: counts[s] })), { value: 'All', label: 'All', count: rows.length }]} />
      <Card pad={false}>
        <Table rows={shown} onRowClick={(r) => setOpenId(r.id)} csv="sales-orders.csv" initialSort={{ key: 'requested_date', dir: tab === 'Order Placed' ? 'asc' : 'desc' }}
          rowClass={(r) => (r.overdue ? 'bg-red-50/40' : '')}
          columns={[
            { key: 'so_number', label: 'Order', render: (r) => <span className="font-bold text-brand-700">{r.so_number}</span> },
            { key: 'customer', label: 'Customer' },
            { key: 'channel', label: 'Channel', render: (r) => r.channel === 'Portal' ? <Badge color="violet"><Globe size={11} />Online pickup</Badge> : 'Staff' },
            { key: 'location', label: 'Location' },
            { key: 'order_date', label: 'Ordered', render: (r) => d(r.order_date) },
            { key: 'requested_date', label: 'Needed by', render: (r) => <span className={r.overdue ? 'font-bold text-red-700' : ''}>{d(r.requested_date)}{r.overdue && ' · overdue'}</span> },
            { key: 'n', label: 'Lines', align: 'right', render: (r) => r.lines.length, sortValue: (r) => r.lines.length },
            { key: 'total', label: 'Value', align: 'right', render: (r) => money(r.total) },
            { key: 'stock', label: 'Stock', sortable: false, noExport: true, render: (r) => r.status !== 'Order Placed' ? '' : r.short.length ? <Badge color="red">Backordered</Badge> : r.kitShort.length ? <Badge color="amber">Needs kit build</Badge> : <Badge color="green">Ready</Badge> },
            { key: 'status', label: 'Status', render: (r) => <StatusBadge status={r.status} /> },
          ]} />
      </Card>
      {creating && <CreateSO onClose={() => setCreating(false)} />}
      {open && <SODetail so={open} onClose={() => setOpenId(null)} />}
    </Page>
  );
}

function SODetail({ so, onClose }) {
  const L = useLookups();
  const [run, busy] = useAction();
  const [invoice, setInvoice] = useState(null);
  const { data: inv } = useData(() => api.select('inventory', { eq: { location_id: so.location_id } }), [so.location_id]);
  const oh = Object.fromEntries((inv || []).map((i) => [i.item_id, num(i.qty_on_hand)]));
  const act = (fn, msg) => run(fn, msg);
  return (
    <Modal open onClose={onClose} title={`${so.so_number} · ${so.customer}`} wide
      footer={<>
        {so.sale_id && <Btn variant="secondary" icon={Printer} onClick={async () => setInvoice(await api.rpc('get_sale', { p_sale_id: so.sale_id }))}>View invoice</Btn>}
        {so.status === 'Order Placed' && <Btn variant="secondary" icon={XCircle} busy={busy} onClick={async () => (await act(() => api.rpc('so_set_status', { p_so_id: so.id, p_status: 'Cancelled' }), 'Order cancelled')) && onClose()}>Cancel order</Btn>}
        {so.status === 'Order Placed' && <Btn icon={PackageCheck} busy={busy} onClick={async () => { const r = await act(() => api.rpc('so_fulfill', { p_so_id: so.id, p_payment_method: so.channel === 'Portal' ? 'Cash' : 'Invoice' }), (r) => `Fulfilled — invoice ${r.sale.sale_number}`); if (r) setInvoice(r); }}>Fulfill order</Btn>}
        {so.status === 'Fulfilled' && <Btn icon={Lock} busy={busy} onClick={async () => (await act(() => api.rpc('so_set_status', { p_so_id: so.id, p_status: 'Closed' }), 'Order closed')) && onClose()}>Close order</Btn>}
      </>}>
      <div className="mb-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <Info k="Status" v={<StatusBadge status={so.status} />} /><Info k="Location" v={so.location} />
        <Info k="Ordered" v={dt(so.order_date)} /><Info k="Needed by" v={d(so.requested_date)} />
        {so.fulfilled_at && <Info k="Fulfilled" v={dt(so.fulfilled_at)} />}{so.closed_at && <Info k="Closed" v={dt(so.closed_at)} />}
        <Info k="Channel" v={so.channel} /><Info k="Customer discount" v={fmt(so.lines[0]?.discount_pct) + '%'} />
      </div>
      <table className="min-w-full text-sm">
        <thead className="bg-slate-50 text-left text-xs font-bold uppercase text-slate-500"><tr><th className="px-3 py-2">Item</th><th className="px-3 py-2 text-right">Qty</th><th className="px-3 py-2 text-right">Unit price</th><th className="px-3 py-2 text-right">On hand here</th><th className="px-3 py-2 text-right">Line value</th></tr></thead>
        <tbody className="divide-y divide-slate-100">{so.lines.map((l) => {
          const it = L.itemById[l.item_id]; const have = oh[l.item_id] ?? 0; const short = num(l.qty) > have;
          return <tr key={l.id}><td className="px-3 py-2">{it?.name}{it?.item_type === 'kit' && <Badge color="brand" className="ml-2">kit</Badge>}</td><td className="px-3 py-2 text-right">{fmt(l.qty)}</td>
            <td className="px-3 py-2 text-right">{fmt(l.unit_price)}</td>
            <td className={`px-3 py-2 text-right ${short && so.status === 'Order Placed' ? 'font-bold text-red-700' : ''}`}>{fmt(have)}{short && so.status === 'Order Placed' && (it?.item_type === 'kit' ? ' (auto-assemble)' : ' (short)')}</td>
            <td className="px-3 py-2 text-right">{money(num(l.qty) * num(l.unit_price) * (1 - num(l.discount_pct) / 100))}</td></tr>;
        })}</tbody>
      </table>
      {so.notes && <p className="mt-3 text-sm text-slate-600">Notes: {so.notes}</p>}
      <Modal open={!!invoice} onClose={() => setInvoice(null)} title="Invoice" footer={<Btn icon={Printer} onClick={printReceipt}>Print</Btn>}><Receipt data={invoice} /></Modal>
    </Modal>
  );
}
const Info = ({ k, v }) => <div><div className="text-xs font-bold uppercase text-slate-500">{k}</div><div className="mt-0.5">{v}</div></div>;

function CreateSO({ onClose }) {
  const L = useLookups();
  const [f, setF] = useState({ customer_id: '', location_id: L.locations.find((l) => l.code === 'STORE')?.id, requested_date: addDaysISO(todayISO(), 7), notes: '' });
  const [lines, setLines] = useState([]);
  const [run, busy] = useAction();
  const add = (it) => setLines((ls) => ls.some((l) => l.item.id === it.id) ? ls : [...ls, { item: it, qty: 1 }]);
  const cust = L.custById[f.customer_id];
  const total = lines.reduce((a, l) => a + num(l.qty) * num(l.item.price) * (1 - num(cust?.discount_pct) / 100), 0);
  const save = async () => {
    const r = await run(() => api.rpc('so_create', { p: { ...f, customer_id: Number(f.customer_id), location_id: Number(f.location_id), lines: lines.map((l) => ({ item_id: l.item.id, qty: num(l.qty) })) } }), (r) => `Sales order ${r.so_number} placed`);
    if (r) onClose();
  };
  return (
    <Modal open onClose={onClose} title="New sales order" wide footer={<><Btn variant="secondary" onClick={onClose}>Cancel</Btn><Btn busy={busy} disabled={!f.customer_id || !lines.length} onClick={save}>Place order</Btn></>}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="Customer"><Select value={f.customer_id} onChange={(e) => setF({ ...f, customer_id: e.target.value })} placeholder="Select customer…" options={L.customers.map((c) => ({ value: c.id, label: `${c.name} · ${c.customer_type}` }))} /></Field>
        <Field label="Fulfil from location"><Select value={f.location_id} onChange={(e) => setF({ ...f, location_id: e.target.value })} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
        <Field label="Needed by"><Input type="date" value={f.requested_date} onChange={(e) => setF({ ...f, requested_date: e.target.value })} /></Field>
      </div>
      {cust && num(cust.discount_pct) > 0 && <p className="mt-2 text-sm text-brand-700">Agreed customer discount of {fmt(cust.discount_pct)}% will be applied.</p>}
      <div className="mt-4"><ScanInput onItem={add} filter={(i) => i.sellable && i.item_type !== 'service'} autoFocus={false} /></div>
      <table className="mt-3 min-w-full text-sm"><tbody className="divide-y divide-slate-100">
        {lines.map((l, i) => <tr key={l.item.id}><td className="py-2">{l.item.name}</td><td className="w-28 py-2"><Input type="number" min="1" value={l.qty} onChange={(e) => setLines(lines.map((x, j) => (j === i ? { ...x, qty: e.target.value } : x)))} /></td>
          <td className="w-32 py-2 text-right">{money(num(l.qty) * num(l.item.price))}</td><td className="w-8 text-right"><button onClick={() => setLines(lines.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 size={16} className="text-slate-400" /></button></td></tr>)}
      </tbody></table>
      {lines.length > 0 && <p className="mt-2 text-right font-black text-brand-800">Order value {money(total)}</p>}
      <Field label="Notes" className="mt-3"><Textarea value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} /></Field>
    </Modal>
  );
}
