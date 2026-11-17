import { useMemo, useState } from 'react';
import { Plus, Send, PackageOpen, Lock, XCircle, Trash2, Mail, Printer, Wallet } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction, useToast } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Btn, Field, Input, Select, Modal, Table, Tabs, StatusBadge, Badge, Spinner, Textarea, cx } from '../components/ui';
import { ScanInput } from '../components/Scanner';
import { money, fmt, d, num, todayISO, addDaysISO, daysBetween } from '../lib/format';

const ST = ['Draft', 'Order Sent', 'Partially Received', 'Received', 'Closed', 'Cancelled'];

export default function Purchasing() {
  const L = useLookups();
  const [tab, setTab] = useState('open');
  const [create, setCreate] = useState(false);
  const [openId, setOpenId] = useState(null);
  const { data } = useData(async () => {
    const [pos, lines, rcpts] = await Promise.all([api.select('purchase_orders', { order: 'created_at desc' }), api.select('purchase_order_lines'), api.select('po_receipts', { order: 'receipt_date desc' })]);
    return { pos, lines, rcpts };
  });
  const rows = useMemo(() => {
    if (!data || !L.ready) return [];
    return data.pos.map((p) => {
      const ls = data.lines.filter((l) => l.po_id === p.id); const rc = data.rcpts.filter((r) => r.po_id === p.id);
      const first = rc.map((r) => r.receipt_date).sort()[0];
      return { ...p, lines: ls, receipts: rc, supplier: L.supById[p.supplier_id]?.name, total: ls.reduce((a, l) => a + num(l.qty_ordered) * num(l.unit_cost), 0),
        ordered: ls.reduce((a, l) => a + num(l.qty_ordered), 0), received: ls.reduce((a, l) => a + num(l.qty_received), 0), first_receipt: first,
        days_late: first && p.expected_date ? daysBetween(p.expected_date, first) : null,
        overdue: ['Order Sent', 'Partially Received'].includes(p.status) && p.expected_date < todayISO() };
    });
  }, [data, L]);
  if (!data || !L.ready) return <Spinner />;
  const shown = tab === 'open' ? rows.filter((r) => ['Draft', 'Order Sent', 'Partially Received'].includes(r.status)) : tab === 'all' ? rows : rows.filter((r) => r.status === tab);
  const open = rows.find((r) => r.id === openId);
  return (
    <Page title="Purchase Orders" subtitle="Create, send and receive purchase orders. Expected dates come from each supplier’s quoted lead time."
      actions={<Btn icon={Plus} onClick={() => setCreate(true)}>New purchase order</Btn>}
      concept={<><p><b>Draft</b> → <b>Order Sent</b> (expected receipt date = send date + supplier’s quoted lead time) → <b>Received</b> / <b>Partially Received</b> → <b>Closed</b>. A short-shipped PO can be closed early; the shortfall lowers the supplier’s <b>fill rate</b>.</p>
        <p>Receiving increases on-hand stock at the chosen location, recalculates <b>weighted-average cost</b>, compares the actual date with the expected date (on-time delivery), and creates a <b>supplier bill</b> due on receipt date + payment terms (e.g. Net 30).</p></>}>
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'open', label: 'Open', count: rows.filter((r) => ['Draft', 'Order Sent', 'Partially Received'].includes(r.status)).length }, ...ST.slice(3).map((s) => ({ value: s, label: s })), { value: 'all', label: 'All', count: rows.length }]} />
      <Card pad={false}>
        <Table rows={shown} onRowClick={(r) => setOpenId(r.id)} csv="purchase-orders.csv" rowClass={(r) => (r.overdue ? 'bg-red-50/40' : '')} initialSort={{ key: 'created_at', dir: 'desc' }} columns={[
          { key: 'po_number', label: 'PO', render: (r) => <b className="text-brand-700">{r.po_number}</b> },
          { key: 'supplier', label: 'Supplier' },
          { key: 'source', label: 'Source', render: (r) => <span className="text-xs text-slate-500">{r.source}</span> },
          { key: 'order_date', label: 'Sent', render: (r) => d(r.order_date) },
          { key: 'expected_date', label: 'Expected', render: (r) => <span className={r.overdue ? 'font-bold text-red-700' : ''}>{d(r.expected_date)}</span> },
          { key: 'first_receipt', label: 'Received', render: (r) => r.first_receipt ? <span>{d(r.first_receipt)} {r.days_late > 0 ? <Badge color="red">{r.days_late}d late</Badge> : <Badge color="green">on time</Badge>}</span> : '' },
          { key: 'fill', label: 'Received / ordered', align: 'right', sortValue: (r) => r.received / (r.ordered || 1), render: (r) => `${fmt(r.received)} / ${fmt(r.ordered)}` },
          { key: 'total', label: 'Value', align: 'right', render: (r) => money(r.total) },
          { key: 'status', label: 'Status', render: (r) => <StatusBadge status={r.status} /> },
        ]} />
      </Card>
      {create && <CreatePO onClose={() => setCreate(false)} />}
      {open && <PODetail po={open} onClose={() => setOpenId(null)} />}
    </Page>
  );
}

function CreatePO({ onClose }) {
  const L = useLookups();
  const [f, setF] = useState({ supplier_id: '', location_id: L.locations.find((l) => l.code === 'STORE')?.id, notes: '' });
  const [lines, setLines] = useState([]);
  const [run, busy] = useAction();
  const sup = L.supById[f.supplier_id];
  const add = (it) => setLines((ls) => (ls.some((l) => l.item.id === it.id) ? ls : [...ls, { item: it, qty: 10, unit_cost: Math.round(num(it.avg_cost)) }]));
  const save = (send) => run(() => api.rpc('po_create', { p: { ...f, supplier_id: Number(f.supplier_id), location_id: Number(f.location_id), send, source: 'Manual', lines: lines.map((l) => ({ item_id: l.item.id, qty: num(l.qty), unit_cost: num(l.unit_cost) })) } }),
    (r) => `${r.po_number} ${send ? 'sent' : 'saved as draft'}`).then((r) => r && onClose());
  return (
    <Modal open onClose={onClose} title="New purchase order" wide footer={<><Btn variant="secondary" onClick={onClose}>Cancel</Btn>
      <Btn variant="secondary" busy={busy} disabled={!f.supplier_id || !lines.length} onClick={() => save(false)}>Save draft</Btn>
      <Btn icon={Send} busy={busy} disabled={!f.supplier_id || !lines.length} onClick={() => save(true)}>Save &amp; send</Btn></>}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="Supplier"><Select value={f.supplier_id} onChange={(e) => setF({ ...f, supplier_id: e.target.value })} placeholder="Select supplier…" options={L.suppliers.filter((s) => s.active).map((s) => ({ value: s.id, label: s.name }))} /></Field>
        <Field label="Deliver to"><Select value={f.location_id} onChange={(e) => setF({ ...f, location_id: e.target.value })} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
        <Field label="Expected receipt"><Input readOnly value={sup ? `${d(addDaysISO(todayISO(), sup.lead_time_days))} (${sup.lead_time_days}-day lead time, ${sup.payment_terms})` : '—'} /></Field>
      </div>
      <div className="mt-4 flex gap-2">
        <ScanInput className="flex-1" autoFocus={false} onItem={add} filter={(i) => i.item_type === 'purchased'} />
        {sup && <Btn variant="secondary" onClick={() => L.items.filter((i) => i.preferred_supplier_id === sup.id && i.active).forEach(add)}>Add all items from this supplier</Btn>}
      </div>
      <table className="mt-3 min-w-full text-sm"><thead className="text-left text-xs uppercase text-slate-500"><tr><th>Item</th><th className="w-24">Qty</th><th className="w-32">Unit cost</th><th className="w-32 text-right">Line</th><th /></tr></thead>
        <tbody className="divide-y divide-slate-100">{lines.map((l, i) => <tr key={l.item.id}><td className="py-1.5">{l.item.name}{sup && l.item.preferred_supplier_id !== sup.id && <Badge color="amber" className="ml-1">not usual supplier</Badge>}</td>
          <td><Input type="number" value={l.qty} onChange={(e) => setLines(lines.map((x, j) => (j === i ? { ...x, qty: e.target.value } : x)))} /></td>
          <td><Input type="number" value={l.unit_cost} onChange={(e) => setLines(lines.map((x, j) => (j === i ? { ...x, unit_cost: e.target.value } : x)))} /></td>
          <td className="text-right">{money(num(l.qty) * num(l.unit_cost))}</td><td className="pl-2"><button onClick={() => setLines(lines.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 size={15} className="text-slate-400" /></button></td></tr>)}</tbody></table>
      {lines.length > 0 && <p className="mt-2 text-right font-black">Total {money(lines.reduce((a, l) => a + num(l.qty) * num(l.unit_cost), 0))}</p>}
      <Field label="Notes" className="mt-2"><Textarea value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} /></Field>
    </Modal>
  );
}

function PODetail({ po, onClose }) {
  const L = useLookups();
  const auth = useAuth();
  const toast = useToast();
  const [run, busy] = useAction();
  const [rcv, setRcv] = useState(null); // {po_line_id: qty}
  const [rf, setRf] = useState({ location_id: po.location_id, receipt_date: todayISO(), notes: '' });
  const sup = L.supById[po.supplier_id];
  const act = async (fn, msg) => (await run(fn, msg)) && onClose();
  const scanReceive = (it) => {
    const line = po.lines.find((l) => l.item_id === it.id);
    if (!line) return toast(`${it.name} is not on this PO`, 'error');
    setRcv((r) => { const cur = num(r?.[line.id]); const max = num(line.qty_ordered) - num(line.qty_received); return { ...r, [line.id]: Math.min(max, cur + 1) }; });
  };
  const emailBody = encodeURIComponent(`Dear ${sup?.contact_name || 'Supplier'},\n\nPlease supply the following for ${po.po_number}:\n\n${po.lines.map((l) => `- ${L.itemById[l.item_id]?.name}: ${fmt(l.qty_ordered)} @ UGX ${fmt(l.unit_cost)}`).join('\n')}\n\nTotal: UGX ${fmt(po.total)}\nRequired by: ${d(po.expected_date)}\nDeliver to: ${L.locById[po.location_id]?.name}, Rosbren Health Clinic\nPayment terms: ${sup?.payment_terms}\n\nThank you,\nRosbren Health Clinic`);
  return (
    <Modal open onClose={onClose} title={`${po.po_number} · ${po.supplier}`} wide="xl" footer={<>
      <Btn variant="ghost" icon={Printer} onClick={() => window.print()}>Print</Btn>
      {sup?.email && <a className="inline-flex items-center gap-1.5 rounded-lg px-3.5 py-2 text-sm font-bold text-slate-600 hover:bg-slate-100" href={`mailto:${sup.email}?subject=${encodeURIComponent('Purchase order ' + po.po_number)}&body=${emailBody}`}><Mail size={16} />Email supplier</a>}
      {['Draft', 'Order Sent'].includes(po.status) && <Btn variant="secondary" icon={XCircle} busy={busy} onClick={() => act(() => api.rpc('po_set_status', { p_po_id: po.id, p_status: 'Cancelled' }), 'PO cancelled')}>Cancel PO</Btn>}
      {po.status === 'Draft' && <Btn icon={Send} busy={busy} onClick={() => act(() => api.rpc('po_send', { p_po_id: po.id }), 'PO sent to supplier')}>Send order</Btn>}
      {['Order Sent', 'Partially Received'].includes(po.status) && !rcv && <Btn icon={PackageOpen} onClick={() => setRcv({})}>Receive items</Btn>}
      {['Received', 'Partially Received'].includes(po.status) && <Btn variant={po.status === 'Received' ? 'primary' : 'secondary'} icon={Lock} busy={busy} onClick={() => act(() => api.rpc('po_set_status', { p_po_id: po.id, p_status: 'Closed' }), 'PO closed')}>Close PO</Btn>}
    </>}>
      <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-6">
        <Info k="Status" v={<StatusBadge status={po.status} />} /><Info k="Deliver to" v={L.locById[po.location_id]?.name} />
        <Info k="Sent" v={d(po.order_date)} /><Info k="Expected" v={d(po.expected_date)} />
        <Info k="Lead time · terms" v={`${sup?.lead_time_days} d · ${sup?.payment_terms}`} /><Info k="Value" v={money(po.total)} />
      </div>
      {rcv && (
        <div className="mt-4 rounded-lg border-2 border-brand-300 bg-brand-50/50 p-3">
          <div className="mb-2 font-black text-brand-800">Receive against {po.po_number} — scan each item or type quantities</div>
          <div className="grid gap-3 sm:grid-cols-3">
            <ScanInput onItem={scanReceive} filter={(i) => po.lines.some((l) => l.item_id === i.id)} placeholder="Scan item to count +1…" />
            <Select value={rf.location_id} onChange={(e) => setRf({ ...rf, location_id: Number(e.target.value) })} options={L.locations.map((l) => ({ value: l.id, label: 'Receive into ' + l.name }))} />
            <Input type="date" value={rf.receipt_date} onChange={(e) => setRf({ ...rf, receipt_date: e.target.value })} />
          </div>
          {po.expected_date && <p className="mt-2 text-sm">{rf.receipt_date <= po.expected_date ? <Badge color="green">On time</Badge> : <Badge color="red">{daysBetween(po.expected_date, rf.receipt_date)} days late</Badge>} vs expected {d(po.expected_date)} · bill due {d(addDaysISO(rf.receipt_date, sup?.payment_terms_days || 0))}</p>}
        </div>
      )}
      <table className="mt-4 min-w-full text-sm">
        <thead className="bg-slate-50 text-left text-xs font-bold uppercase text-slate-500"><tr><th className="px-3 py-2">Item</th><th className="px-3 py-2 text-right">Ordered</th><th className="px-3 py-2 text-right">Received</th><th className="px-3 py-2 text-right">Unit cost</th><th className="px-3 py-2 text-right">Line value</th>{rcv && <th className="px-3 py-2">Receive now</th>}</tr></thead>
        <tbody className="divide-y divide-slate-100">{po.lines.map((l) => { const rem = num(l.qty_ordered) - num(l.qty_received); return (
          <tr key={l.id}><td className="px-3 py-2">{L.itemById[l.item_id]?.name}</td><td className="px-3 py-2 text-right">{fmt(l.qty_ordered)}</td>
            <td className={cx('px-3 py-2 text-right', rem > 0 && num(l.qty_received) > 0 && 'text-amber-700')}>{fmt(l.qty_received)}</td>
            <td className="px-3 py-2 text-right">{fmt(l.unit_cost)}</td><td className="px-3 py-2 text-right">{money(num(l.qty_ordered) * num(l.unit_cost))}</td>
            {rcv && <td className="px-3 py-2"><div className="flex items-center gap-2"><Input type="number" min="0" max={rem} className="w-24" value={rcv[l.id] ?? ''} disabled={rem <= 0} onChange={(e) => setRcv({ ...rcv, [l.id]: e.target.value })} />
              {rem > 0 && <button className="text-xs font-bold text-brand-700" onClick={() => setRcv({ ...rcv, [l.id]: rem })}>all {fmt(rem)}</button>}</div></td>}
          </tr>); })}</tbody>
      </table>
      {rcv && <div className="mt-3 flex justify-end gap-2"><Btn variant="secondary" onClick={() => setRcv(null)}>Cancel</Btn>
        <Btn icon={PackageOpen} busy={busy} disabled={!Object.values(rcv).some((v) => num(v) > 0)} onClick={() => act(() => api.rpc('po_receive', { p: { po_id: po.id, ...rf, lines: Object.entries(rcv).map(([k, v]) => ({ po_line_id: Number(k), qty: num(v) })) } }),
          (r) => `Received ${money(r.amount)} · ${r.days_late > 0 ? r.days_late + ' days late' : 'on time'} · ${r.status}`)}>Post receipt</Btn></div>}
      {po.receipts.length > 0 && <div className="mt-5">
        <div className="mb-1 text-xs font-bold uppercase text-slate-500">Receipts & supplier bills</div>
        <table className="min-w-full text-sm"><thead className="text-left text-xs uppercase text-slate-500"><tr><th className="py-1">Date</th><th>Timeliness</th><th className="text-right">Amount</th><th>Due</th><th className="text-right">Paid</th><th /></tr></thead>
          <tbody className="divide-y divide-slate-100">{po.receipts.map((r) => { const late = daysBetween(po.expected_date, r.receipt_date); const owed = num(r.amount) - num(r.paid_amount); return (
            <tr key={r.id}><td className="py-1.5">{d(r.receipt_date)}</td><td>{late > 0 ? <Badge color="red">{late}d late</Badge> : <Badge color="green">on time</Badge>}</td>
              <td className="text-right">{money(r.amount)}</td><td className={owed > 0 && r.due_date < todayISO() ? 'font-bold text-red-700' : ''}>{d(r.due_date)}</td>
              <td className="text-right">{owed <= 0 ? <Badge color="green">paid {d(r.paid_date)}</Badge> : money(r.paid_amount)}</td>
              <td className="text-right">{owed > 0 && auth.isManager && <Btn size="sm" variant="secondary" icon={Wallet} busy={busy} onClick={() => act(() => api.rpc('pay_bill', { p_receipt_id: r.id }), 'Bill marked paid')}>Pay {money(owed)}</Btn>}</td></tr>); })}</tbody></table>
      </div>}
    </Modal>
  );
}
const Info = ({ k, v }) => <div><div className="text-xs font-bold uppercase text-slate-500">{k}</div><div className="mt-0.5">{v}</div></div>;
