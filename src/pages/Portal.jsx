import { useMemo, useState } from 'react';
import { LogOut, ShoppingBag, MapPin, Search, Trash2, CheckCircle2, Package, UserCircle } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useAction, ToastProvider } from '../lib/hooks';
import { useAuth, AccountSecurity } from '../auth/Auth';
import { Btn, Card, Field, Input, Select, Tabs, Spinner, Badge, StatusBadge, Empty, cx } from '../components/ui';
import Logo from '../components/Logo';
import { money, fmt, d, dt, num, todayISO, addDaysISO } from '../lib/format';

export default function Portal() {
  const auth = useAuth();
  const [tab, setTab] = useState('shop');
  const [cart, setCart] = useState([]);
  const [q, setQ] = useState(''); const [cat, setCat] = useState('');
  const [loc, setLoc] = useState('');
  const [pickup, setPickup] = useState(addDaysISO(todayISO(), 1));
  const [run, busy] = useAction();
  const { data: catalog } = useData(() => api.rpc('portal_catalog'));
  const { data: orders } = useData(() => api.rpc('portal_my_orders'));
  const locations = useMemo(() => (catalog?.[0]?.locations || []).map((l) => ({ id: l.location_id, name: l.location })), [catalog]);
  const pickupLoc = loc || locations[0]?.id;
  const cats = [...new Set((catalog || []).map((c) => c.category))];
  const shown = (catalog || []).filter((i) => (!cat || i.category === cat) && (!q || i.name.toLowerCase().includes(q.toLowerCase())));
  const availAt = (item, lid) => num(item.locations.find((l) => l.location_id === Number(lid))?.available);
  const add = (item) => setCart((c) => (c.some((x) => x.item.id === item.id) ? c.map((x) => (x.item.id === item.id ? { ...x, qty: x.qty + 1 } : x)) : [...c, { item, qty: 1 }]));
  const total = cart.reduce((a, l) => a + l.qty * num(l.item.price) * (l.item.taxable ? 1.18 : 1) * (1 - num(auth.profile?.customer?.discount_pct) / 100), 0);
  const place = async () => {
    const r = await run(() => api.rpc('portal_place_order', { p: { location_id: Number(pickupLoc), requested_date: pickup, lines: cart.map((l) => ({ item_id: l.item.id, qty: l.qty })) } }), (r) => `Order ${r.so_number} placed — we’ll have it ready for pickup`);
    if (r) { setCart([]); setTab('orders'); }
  };
  return (
    <div className="min-h-screen bg-slate-50">
      <header className="bg-brand-700 text-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3">
          <div className="flex items-center gap-3"><Logo size={40} /><div><div className="text-lg font-black tracking-wider">ROSBREN</div><div className="text-xs text-brand-100">Health Clinic · Online pharmacy pickup</div></div></div>
          <div className="flex items-center gap-3 text-sm"><span className="hidden sm:inline">Hello, <b>{auth.profile?.full_name}</b></span>
            <button onClick={auth.signOut} className="flex items-center gap-1 rounded-lg bg-brand-800 px-3 py-1.5 font-bold hover:bg-brand-900"><LogOut size={15} />Sign out</button></div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">
        <Tabs value={tab} onChange={setTab} tabs={[{ value: 'shop', label: 'Shop & check availability' }, { value: 'cart', label: 'Pickup cart', count: cart.length }, { value: 'orders', label: 'My orders', count: orders?.length }, { value: 'account', label: 'Account security' }]} />
        {tab === 'shop' && (!catalog ? <Spinner /> : <>
          <div className="mb-4 flex flex-wrap gap-2">
            <div className="relative min-w-[220px] flex-1"><Search size={16} className="absolute left-3 top-2.5 text-slate-400" /><Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search medicines and kits…" className="pl-9" /></div>
            <Select value={cat} onChange={(e) => setCat(e.target.value)} placeholder="All categories" options={cats.map((c) => ({ value: c, label: c }))} className="w-56" />
          </div>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {shown.map((i) => { const tot = i.locations.reduce((a, l) => a + num(l.available), 0); return (
              <div key={i.id} className="flex flex-col rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between gap-2"><div><div className="font-black text-slate-900">{i.name}</div><div className="text-xs text-slate-500">{i.category} · per {i.uom}</div></div>
                  <div className="whitespace-nowrap text-lg font-black text-brand-700">{money(i.price)}</div></div>
                {i.description && <p className="mt-1 text-xs text-slate-600">{i.description}</p>}
                <ul className="mt-2 space-y-0.5 text-xs">{i.locations.map((l) => (
                  <li key={l.location_id} className="flex items-center justify-between"><span className="flex items-center gap-1 text-slate-600"><MapPin size={11} />{l.location}{l.location_id === locations[0]?.id && i.shelf ? ` · shelf ${i.shelf}` : ''}</span>
                    {num(l.available) > 5 ? <Badge color="green">In stock</Badge> : num(l.available) > 0 ? <Badge color="amber">Only {fmt(l.available)} left</Badge> : <Badge color="gray">Out</Badge>}</li>))}</ul>
                <Btn className="mt-3" size="sm" icon={ShoppingBag} disabled={tot <= 0 && i.item_type !== 'kit'} onClick={() => add(i)}>{tot <= 0 && i.item_type !== 'kit' ? 'Out of stock' : 'Add to pickup order'}</Btn>
              </div>); })}
          </div></>)}
        {tab === 'cart' && <div className="grid gap-4 lg:grid-cols-[1fr_340px]">
          <Card title="Items" pad={false}>{!cart.length ? <Empty>Your cart is empty.</Empty> : <table className="min-w-full text-sm"><tbody className="divide-y divide-slate-100">
            {cart.map((l, idx) => { const a = availAt(l.item, pickupLoc); return (
              <tr key={l.item.id}><td className="px-4 py-2"><b>{l.item.name}</b><div className="text-xs">{a >= l.qty ? <span className="text-emerald-700">Available at this pickup location</span> : <span className="text-amber-700">{l.item.item_type === 'kit' ? 'Will be assembled for you' : `Only ${fmt(a)} here — we will restock before pickup if possible`}</span>}</div></td>
                <td className="w-24 px-2"><Input type="number" min="1" value={l.qty} onChange={(e) => setCart(cart.map((x, j) => (j === idx ? { ...x, qty: Math.max(1, Number(e.target.value)) } : x)))} /></td>
                <td className="px-4 text-right">{money(l.qty * num(l.item.price))}</td>
                <td className="pr-3"><button onClick={() => setCart(cart.filter((_, j) => j !== idx))} aria-label="Remove"><Trash2 size={15} className="text-slate-400" /></button></td></tr>); })}
          </tbody></table>}</Card>
          <Card title="Pickup details"><div className="space-y-3">
            <Field label="Pickup location"><Select value={pickupLoc || ''} onChange={(e) => setLoc(e.target.value)} options={locations.map((l) => ({ value: l.id, label: l.name }))} /></Field>
            <Field label="Pickup date"><Input type="date" min={todayISO()} value={pickup} onChange={(e) => setPickup(e.target.value)} /></Field>
            <div className="flex justify-between text-lg font-black text-brand-800"><span>Estimated total</span><span>{money(total)}</span></div>
            <p className="text-xs text-slate-500">Pay at pickup by cash or mobile money. Prescription medicines are dispensed after a pharmacist check.</p>
            <Btn className="w-full" size="lg" icon={CheckCircle2} busy={busy} disabled={!cart.length} onClick={place}>Place pickup order</Btn>
          </div></Card></div>}
        {tab === 'orders' && (!orders ? <Spinner /> : !orders.length ? <Card><Empty>No orders yet.</Empty></Card> :
          <div className="space-y-3">{orders.map((o) => (
            <Card key={o.id} title={<span className="flex items-center gap-2"><Package size={16} />{o.so_number} · pickup {d(o.requested_date)} at {o.location}</span>}
              actions={<><StatusBadge status={o.status === 'Fulfilled' ? 'Fulfilled' : o.status} />{o.status === 'Order Placed' && <Btn size="sm" variant="ghost" onClick={() => run(() => api.rpc('portal_cancel_order', { p_so_id: o.id }), 'Order cancelled')}>Cancel</Btn>}</>}>
              <ul className="text-sm">{o.lines.map((l, i) => <li key={i} className="flex justify-between"><span>{fmt(l.qty)} × {l.name}</span><span>{money(num(l.qty) * num(l.unit_price) * (1 - num(l.discount_pct) / 100))}</span></li>)}</ul>
              <div className="mt-2 flex justify-between text-xs text-slate-500"><span>Placed {dt(o.order_date)}</span><b className="text-slate-800">{money(o.total)}</b></div>
              <Steps status={o.status} />
            </Card>))}</div>)}
        {tab === 'account' && <Card className="max-w-2xl"><div className="mb-4 flex items-center gap-2 text-sm text-slate-600"><UserCircle size={18} />{auth.profile?.email}</div><AccountSecurity /></Card>}
      </main>
    </div>
  );
}
function Steps({ status }) {
  const steps = ['Order Placed', 'Fulfilled', 'Closed']; const idx = status === 'Cancelled' ? -1 : steps.indexOf(status);
  const label = { 'Order Placed': 'Received', Fulfilled: 'Ready / picked up', Closed: 'Complete' };
  if (idx < 0) return <p className="mt-2 text-sm font-bold text-red-700">Cancelled</p>;
  return <div className="mt-3 flex gap-1">{steps.map((s, i) => <div key={s} className="flex-1"><div className={cx('h-1.5 rounded', i <= idx ? 'bg-brand-500' : 'bg-slate-200')} /><div className={cx('mt-1 text-[11px]', i <= idx ? 'font-bold text-brand-700' : 'text-slate-400')}>{label[s]}</div></div>)}</div>;
}
