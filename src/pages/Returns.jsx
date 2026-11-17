import { useMemo, useState } from 'react';
import { Search, Undo2, Repeat, Trash2, ShieldAlert } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, Field, Input, Select, Table, StatusBadge, Badge, Textarea, Tabs, cx } from '../components/ui';
import { ScanInput, CameraScanner } from '../components/Scanner';
import { money, fmt, dt, num } from '../lib/format';

export default function Returns() {
  const L = useLookups();
  const [tab, setTab] = useState('new');
  const [num_, setNum] = useState('');
  const [sale, setSale] = useState(null);
  const [cam, setCam] = useState(false);
  const [run, busy] = useAction();
  const lookup = async (n) => { const r = await run(() => api.rpc('find_sale', { p_number: n || num_ })); if (r) { setSale(r); setNum(r.sale.sale_number); } };
  const { data: hist } = useData(async () => {
    const [rets, lines, recent] = await Promise.all([api.select('returns', { order: 'return_date desc' }), api.select('return_lines'), api.select('sales', { order: 'sale_date desc', limit: 25 })]);
    return { rets, lines, recent };
  });
  return (
    <Page title="Returns & Exchanges" subtitle="Look up the original receipt, return items to inventory with a reason code, and reverse revenue and cost automatically."
      concept={<><p><b>Return:</b> the customer gets their money back. The system reverses <b>revenue</b> (at the price actually paid, after discounts, plus VAT) and <b>cost of goods</b> (at the original unit cost) and puts the units back into inventory.</p>
        <p><b>Exchange:</b> the returned item comes back and replacement items go out as a new sale inside the same document; the customer pays or is refunded only the <b>difference</b>.</p>
        <p><b>Quality failures</b> (defective, expired, adverse reaction) are returned to inventory and then immediately <b>quarantined & written off</b> with the reason code, so they never get resold — and they show up in quality reporting and inventory losses on the P&amp;L.</p></>}>
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'new', label: 'Process return / exchange' }, { value: 'history', label: 'History', count: hist?.rets.length }]} />
      {tab === 'new' && <>
        <Card className="mb-4">
          <div className="flex flex-wrap items-end gap-3">
            <Field label="Receipt number" className="w-64"><Input value={num_} onChange={(e) => setNum(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && lookup()} placeholder="Scan receipt barcode or type S-10…" autoFocus /></Field>
            <Btn icon={Search} onClick={() => lookup()} busy={busy}>Find sale</Btn>
            <Btn variant="secondary" onClick={() => setCam(true)}>Scan receipt with camera</Btn>
          </div>
          {!sale && hist && <div className="mt-4"><div className="mb-1 text-xs font-bold uppercase text-slate-500">Recent sales</div>
            <div className="flex flex-wrap gap-1.5">{hist.recent.map((s) => <button key={s.id} onClick={() => lookup(s.sale_number)} className="rounded-md bg-slate-100 px-2 py-1 text-xs hover:bg-brand-100"><b>{s.sale_number}</b> · {money(s.total)}</button>)}</div></div>}
        </Card>
        <CameraScanner open={cam} onClose={() => setCam(false)} onScan={(c) => { setCam(false); lookup(c); }} />
        {sale && <ReturnForm key={sale.sale.id} sale={sale} onDone={() => { setSale(null); setNum(''); }} />}
      </>}
      {tab === 'history' && hist && <History hist={hist} />}
    </Page>
  );
}

function ReturnForm({ sale, onDone }) {
  const L = useLookups();
  const [type, setType] = useState('Return');
  const [reason, setReason] = useState('');
  const [loc, setLoc] = useState(sale.sale.location_id);
  const [sel, setSel] = useState({}); // sale_line_id -> {qty, disposition}
  const [repl, setRepl] = useState([]);
  const [notes, setNotes] = useState('');
  const [run, busy] = useAction();
  const reasons = L.reasons.filter((r) => r.category === 'return');
  const isQuality = reasons.find((r) => r.code === reason)?.is_quality;
  const taxRate = Number(L.setting?.tax_rate || 0.18);
  const lines = sale.lines.filter((l) => L.itemById[l.item_id]?.item_type !== 'service');
  const calc = useMemo(() => {
    let refund = 0; for (const l of lines) { const q = num(sel[l.id]?.qty); if (q > 0) refund += ((num(l.line_total) + num(l.tax_amount)) / num(l.qty)) * q; }
    const replacement = repl.reduce((a, r) => a + num(r.qty) * num(r.item.price) * (r.item.taxable ? 1 + taxRate : 1), 0);
    return { refund, replacement, net: replacement - refund };
  }, [sel, repl, lines, taxRate]);
  const submit = async () => {
    const r = await run(() => api.rpc('process_return', { p: {
      sale_id: sale.sale.id, location_id: Number(loc), return_type: type, reason_code: reason, notes,
      lines: Object.entries(sel).filter(([, v]) => num(v.qty) > 0).map(([id, v]) => ({ sale_line_id: Number(id), qty: num(v.qty), disposition: v.disposition || (isQuality ? 'write_off' : 'restock') })),
      replacements: type === 'Exchange' ? repl.map((x) => ({ item_id: x.item.id, qty: num(x.qty) })) : [] } }),
    (r) => `${r.return_number}: ${r.net_amount < 0 ? 'refund ' + money(-r.net_amount) : r.net_amount > 0 ? 'customer pays ' + money(r.net_amount) : 'even exchange'}`);
    if (r) onDone();
  };
  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_360px]">
      <Card title={`Sale ${sale.sale.sale_number} · ${dt(sale.sale.sale_date)} · ${sale.sale.customer_name || 'Walk-in'} · ${money(sale.sale.total)}`} pad={false}>
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-left text-xs font-bold uppercase text-slate-500"><tr><th className="px-3 py-2">Item</th><th className="px-3 py-2 text-right">Sold</th><th className="px-3 py-2 text-right">Paid / unit</th><th className="px-3 py-2 text-right">Returnable</th><th className="px-3 py-2">Return qty</th><th className="px-3 py-2">Disposition</th></tr></thead>
          <tbody className="divide-y divide-slate-100">{lines.map((l) => {
            const left = num(l.qty) - num(l.returned_qty); const s = sel[l.id] || {};
            return <tr key={l.id} className={left <= 0 ? 'opacity-50' : ''}>
              <td className="px-3 py-2 font-bold">{l.name}</td><td className="px-3 py-2 text-right">{fmt(l.qty)}</td>
              <td className="px-3 py-2 text-right">{fmt((num(l.line_total) + num(l.tax_amount)) / num(l.qty))}</td>
              <td className="px-3 py-2 text-right">{fmt(left)}</td>
              <td className="px-3 py-2"><Input type="number" min="0" max={left} disabled={left <= 0} value={s.qty || ''} onChange={(e) => setSel({ ...sel, [l.id]: { ...s, qty: Math.min(left, Math.max(0, Number(e.target.value))) } })} className="w-20" /></td>
              <td className="px-3 py-2"><Select value={s.disposition || (isQuality ? 'write_off' : 'restock')} onChange={(e) => setSel({ ...sel, [l.id]: { ...s, disposition: e.target.value } })}
                options={[{ value: 'restock', label: 'Restock (sellable)' }, { value: 'write_off', label: 'Quarantine & write off' }]} className="w-48" /></td>
            </tr>;
          })}</tbody>
        </table>
        {sale.returns.length > 0 && <p className="p-3 text-xs text-slate-500">Previous returns on this sale: {sale.returns.map((r) => r.return_number).join(', ')}</p>}
      </Card>
      <Card title="Return details">
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            {['Return', 'Exchange'].map((t) => <button key={t} onClick={() => setType(t)} className={cx('flex items-center justify-center gap-1.5 rounded-lg py-2 text-sm font-bold ring-1', type === t ? 'bg-brand-600 text-white ring-brand-600' : 'ring-slate-300')}>{t === 'Return' ? <Undo2 size={15} /> : <Repeat size={15} />}{t}</button>)}
          </div>
          <Field label="Reason code"><Select value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Select reason…" options={reasons.map((r) => ({ value: r.code, label: `${r.description}${r.is_quality ? ' (quality)' : ''}` }))} /></Field>
          {isQuality && <div className="flex gap-2 rounded-lg bg-amber-50 p-2 text-xs text-amber-900"><ShieldAlert size={16} />Quality failure: items default to quarantine & write-off and are tracked in quality reports.</div>}
          <Field label="Return to location"><Select value={loc} onChange={(e) => setLoc(e.target.value)} options={L.locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
          {type === 'Exchange' && <div><div className="mb-1 text-xs font-bold uppercase text-slate-600">Replacement items</div>
            <ScanInput autoFocus={false} onItem={(it) => setRepl((r) => [...r, { item: it, qty: 1 }])} filter={(i) => i.sellable && i.item_type !== 'service'} placeholder="Scan replacement…" />
            {repl.map((r, i) => <div key={i} className="mt-2 flex items-center gap-2 text-sm"><span className="flex-1">{r.item.name}</span>
              <Input type="number" className="w-16" value={r.qty} onChange={(e) => setRepl(repl.map((x, j) => (j === i ? { ...x, qty: e.target.value } : x)))} />
              <button onClick={() => setRepl(repl.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 size={15} className="text-slate-400" /></button></div>)}</div>}
          <Field label="Notes"><Textarea value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
          <dl className="space-y-1 rounded-lg bg-slate-50 p-3 text-sm">
            <div className="flex justify-between"><span>Refund for returned items</span><b>{money(calc.refund)}</b></div>
            {type === 'Exchange' && <div className="flex justify-between"><span>Replacement value</span><b>{money(calc.replacement)}</b></div>}
            <div className="flex justify-between border-t pt-1 text-lg font-black text-brand-800"><span>{calc.net < 0 ? 'Refund to customer' : 'Customer pays'}</span><span>{money(Math.abs(calc.net))}</span></div>
          </dl>
          <Btn className="w-full" size="lg" busy={busy} disabled={!reason || calc.refund <= 0 || (type === 'Exchange' && !repl.length)} onClick={submit}>Process {type.toLowerCase()}</Btn>
          <button className="w-full text-sm text-slate-500" onClick={onDone}>Cancel</button>
        </div>
      </Card>
    </div>
  );
}

function History({ hist }) {
  const L = useLookups();
  const rows = hist.rets.map((r) => {
    const ls = hist.lines.filter((l) => l.return_id === r.id);
    return { ...r, items: ls.map((l) => `${l.direction === 'in' ? '↩' : '→'} ${fmt(l.qty)} ${L.itemById[l.item_id]?.name}${l.disposition === 'write_off' ? ' (written off)' : ''}`).join('; '),
      reason: L.reasons.find((x) => x.code === r.reason_code), customer: L.custById[r.customer_id]?.name };
  });
  return (
    <Card pad={false}>
      <Table rows={rows} csv="returns.csv" initialSort={{ key: 'return_date', dir: 'desc' }} columns={[
        { key: 'return_number', label: 'Return', render: (r) => <b className="text-brand-700">{r.return_number}</b> },
        { key: 'return_date', label: 'Date', render: (r) => dt(r.return_date) },
        { key: 'return_type', label: 'Type', render: (r) => <StatusBadge status={r.return_type} /> },
        { key: 'customer', label: 'Customer' },
        { key: 'reason_code', label: 'Reason', render: (r) => <span>{r.reason?.description} {r.reason?.is_quality && <Badge color="amber">quality</Badge>}</span> },
        { key: 'items', label: 'Items' },
        { key: 'net_amount', label: 'Net', align: 'right', render: (r) => <span className={num(r.net_amount) < 0 ? 'text-red-700' : 'text-emerald-700'}>{money(r.net_amount)}</span> },
        { key: 'user_name', label: 'By' },
      ]} />
    </Card>
  );
}
