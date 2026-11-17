import { useMemo, useState, useEffect } from 'react';
import { Trash2, Minus, Plus, CheckCircle2, Printer, Stethoscope, FlaskConical, ShoppingCart } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, Field, Input, Select, Modal, Badge, cx } from '../components/ui';
import { ScanInput } from '../components/Scanner';
import Receipt, { printReceipt } from '../components/Receipt';
import { money, fmt, num } from '../lib/format';

export default function POS() {
  const L = useLookups();
  const [loc, setLoc] = useState(() => Number(localStorage.getItem('pos-loc')) || null);
  const [cart, setCart] = useState([]);
  const [cust, setCust] = useState('');
  const [odisc, setOdisc] = useState(0);
  const [pay, setPay] = useState('Cash');
  const [tender, setTender] = useState('');
  const [receipt, setReceipt] = useState(null);
  const [run, busy] = useAction();
  useEffect(() => { if (!loc && L.locations?.length) setLoc(L.locations.find((l) => l.code === 'MAIN')?.id || L.locations[0].id); }, [L.locations, loc]);
  useEffect(() => { if (loc) localStorage.setItem('pos-loc', loc); }, [loc]);
  const { data: stock } = useData(() => (loc ? api.select('inventory', { eq: { location_id: loc } }) : Promise.resolve([])), [loc]);
  const onHand = useMemo(() => Object.fromEntries((stock || []).map((s) => [s.item_id, num(s.qty_on_hand)])), [stock]);
  const taxRate = Number(L.setting?.tax_rate || 0.18);

  const add = (it, qty = 1) => setCart((c) => {
    const i = c.findIndex((x) => x.item.id === it.id);
    if (i >= 0) { const n = [...c]; n[i] = { ...n[i], qty: n[i].qty + qty }; return n; }
    return [...c, { item: it, qty, disc: 0 }];
  });
  const upd = (i, patch) => setCart((c) => c.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const selectCustomer = (id) => { setCust(id); const c = L.custById?.[id]; setOdisc(c ? num(c.discount_pct) : 0); };

  const calc = useMemo(() => {
    let sub = 0, disc = 0, tax = 0;
    const lines = cart.map((l) => {
      const gross = l.qty * num(l.item.price);
      let d = (gross * num(l.disc)) / 100; d += ((gross - d) * num(odisc)) / 100;
      const net = gross - d; const t = l.item.taxable ? net * taxRate : 0;
      sub += gross; disc += d; tax += t;
      return { gross, d, net, t };
    });
    return { lines, sub, disc, tax, total: sub - disc + tax };
  }, [cart, odisc, taxRate]);

  const checkout = async () => {
    const r = await run(() => api.rpc('pos_checkout', { p: {
      location_id: loc, customer_id: cust ? Number(cust) : (L.customers.find((c) => c.customer_type === 'Walk-in')?.id ?? null), payment_method: pay,
      order_discount_pct: num(odisc), amount_tendered: tender ? num(tender) : null,
      lines: cart.map((l) => ({ item_id: l.item.id, qty: num(l.qty), discount_pct: num(l.disc) })) } }), (r) => `Sale ${r.sale.sale_number} completed`);
    if (r) { setReceipt(r); setCart([]); setTender(''); selectCustomer(''); }
  };

  const svc = (sku) => L.items?.find((i) => i.sku === sku);
  return (
    <Page title="Point of Sale" subtitle="Scan or search items. Completing a sale reduces stock at this location and records revenue and cost of goods instantly."
      concept={<>
        <p><b>One transaction, many records.</b> When you press <i>Complete sale</i>, a single database transaction creates the sale and its lines, reduces on-hand inventory at the selected location, records cost of goods at the current <b>weighted-average cost</b>, and writes to the inventory ledger and audit log. If any step fails (e.g. not enough stock), nothing is saved.</p>
        <p><b>Kits:</b> if a kit is short on the shelf, the system <b>assembles it on the spot</b> from components (backflush), so selling a parent always consumes its BOM components.</p>
        <p><b>Taxes:</b> VAT applies only to items flagged taxable (most medicines are VAT-exempt in Uganda). <b>Discounts:</b> per-line % plus an order-level % (defaults from the customer’s agreed discount).</p>
      </>}
      actions={<div className="flex items-center gap-2"><span className="text-xs font-bold uppercase text-slate-500">Selling from</span>
        <Select value={loc || ''} onChange={(e) => { setLoc(Number(e.target.value)); setCart([]); }} options={(L.locations || []).map((l) => ({ value: l.id, label: l.name }))} className="w-56" /></div>}>
      <div className="grid gap-4 lg:grid-cols-[1fr_380px]">
        <Card pad={false}>
          <div className="space-y-3 border-b border-slate-100 p-4">
            <ScanInput onItem={(it) => add(it)} filter={(i) => i.sellable} />
            <div className="flex flex-wrap gap-2">
              {svc('SVC-CONSULT') && <Btn size="sm" variant="secondary" icon={Stethoscope} onClick={() => add(svc('SVC-CONSULT'))}>Consultation</Btn>}
              {svc('SVC-LAB') && <Btn size="sm" variant="secondary" icon={FlaskConical} onClick={() => add(svc('SVC-LAB'))}>Lab test</Btn>}
              {['PH-001', 'PH-010', 'KIT-MAL', 'PH-050', 'KIT-ANC'].map((s) => svc(s) && <Btn key={s} size="sm" variant="ghost" onClick={() => add(svc(s))}>+ {svc(s).name.split('(')[0]}</Btn>)}
            </div>
          </div>
          {cart.length === 0 ? (
            <div className="flex flex-col items-center gap-2 p-14 text-slate-400"><ShoppingCart size={40} /><p className="text-sm">Cart is empty — scan a barcode to begin</p></div>
          ) : (
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50 text-left text-xs font-bold uppercase text-slate-500"><tr>
                <th className="px-3 py-2">Item</th><th className="px-3 py-2 text-center">Qty</th><th className="px-3 py-2 text-right">Price</th>
                <th className="px-3 py-2 text-center">Disc %</th><th className="px-3 py-2 text-right">Line total</th><th /></tr></thead>
              <tbody className="divide-y divide-slate-100">
                {cart.map((l, i) => {
                  const avail = onHand[l.item.id] ?? 0; const short = l.item.item_type !== 'service' && l.qty > avail;
                  return (
                    <tr key={l.item.id}>
                      <td className="px-3 py-2"><div className="font-bold">{l.item.name}</div>
                        <div className="flex items-center gap-2 text-xs text-slate-500">{l.item.sku}{l.item.item_type !== 'service' && <span>· {fmt(avail)} on hand</span>}
                          {l.item.taxable && <Badge color="gray">VAT</Badge>}
                          {short && (l.item.item_type === 'kit' ? <Badge color="violet">will auto-assemble {fmt(l.qty - Math.max(avail, 0))}</Badge> : <Badge color="red">insufficient stock</Badge>)}</div></td>
                      <td className="px-3 py-2"><div className="flex items-center justify-center gap-1">
                        <button className="rounded bg-slate-100 p-1" onClick={() => upd(i, { qty: Math.max(1, l.qty - 1) })} aria-label="Decrease"><Minus size={14} /></button>
                        <input value={l.qty} onChange={(e) => upd(i, { qty: Math.max(0, Number(e.target.value) || 0) })} className="w-14 rounded border border-slate-300 py-1 text-center" aria-label="Quantity" />
                        <button className="rounded bg-slate-100 p-1" onClick={() => upd(i, { qty: l.qty + 1 })} aria-label="Increase"><Plus size={14} /></button></div></td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmt(l.item.price)}</td>
                      <td className="px-3 py-2 text-center"><input value={l.disc} onChange={(e) => upd(i, { disc: e.target.value })} className="w-14 rounded border border-slate-300 py-1 text-center" aria-label="Line discount" /></td>
                      <td className="px-3 py-2 text-right font-bold tabular-nums">{fmt(calc.lines[i].net + calc.lines[i].t)}</td>
                      <td className="px-2"><button onClick={() => setCart(cart.filter((_, j) => j !== i))} className="text-slate-400 hover:text-red-600" aria-label="Remove"><Trash2 size={16} /></button></td>
                    </tr>);
                })}
              </tbody>
            </table>
          )}
        </Card>

        <Card title="Checkout">
          <div className="space-y-3">
            <Field label="Customer"><Select value={cust} onChange={(e) => selectCustomer(e.target.value)} placeholder="Walk-in patient"
              options={(L.customers || []).filter((c) => c.customer_type !== 'Walk-in').map((c) => ({ value: c.id, label: `${c.name}${num(c.discount_pct) ? ` (${fmt(c.discount_pct)}% off)` : ''}` }))} /></Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Order discount %"><Input type="number" min="0" max="100" value={odisc} onChange={(e) => setOdisc(e.target.value)} /></Field>
              <Field label="Payment"><Select value={pay} onChange={(e) => setPay(e.target.value)} options={['Cash', 'Mobile Money', 'Card', 'Invoice'].map((v) => ({ value: v, label: v }))} /></Field>
            </div>
            <dl className="space-y-1 rounded-lg bg-slate-50 p-3 text-sm">
              <Row k="Subtotal" v={money(calc.sub)} />
              <Row k="Discounts" v={'− ' + money(calc.disc)} />
              <Row k={`VAT (${(taxRate * 100).toFixed(0)}% on taxable items)`} v={money(calc.tax)} />
              <div className="flex justify-between border-t border-slate-200 pt-2 text-xl font-black text-brand-800"><span>Total</span><span className="tabular-nums">{money(calc.total)}</span></div>
            </dl>
            {pay === 'Cash' && <Field label="Cash tendered"><Input type="number" value={tender} onChange={(e) => setTender(e.target.value)} placeholder="optional" />
              {num(tender) > 0 && <p className={cx('mt-1 text-sm font-bold', num(tender) >= calc.total ? 'text-emerald-700' : 'text-red-700')}>Change: {money(num(tender) - calc.total)}</p>}</Field>}
            <Btn size="lg" className="w-full" icon={CheckCircle2} busy={busy} disabled={!cart.length || !loc || cart.some((l) => !num(l.qty))} onClick={checkout}>Complete sale</Btn>
          </div>
        </Card>
      </div>

      <Modal open={!!receipt} onClose={() => setReceipt(null)} title="Sale complete"
        footer={<><Btn variant="secondary" onClick={() => setReceipt(null)}>New sale</Btn><Btn icon={Printer} onClick={printReceipt}>Print receipt</Btn></>}>
        <div className="max-h-[60vh] overflow-y-auto rounded-lg border border-slate-200"><Receipt data={receipt} /></div>
      </Modal>
    </Page>
  );
}
const Row = ({ k, v }) => <div className="flex justify-between text-slate-600"><span>{k}</span><span className="tabular-nums">{v}</span></div>;
