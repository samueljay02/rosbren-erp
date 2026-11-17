import { useState, useEffect } from 'react';
import { Plus, Rocket, MapPin, CalendarDays, Users, Baby, Bug, Bandage, CheckCircle2 } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, StatusBadge, Spinner, Badge, Empty, cx } from '../components/ui';
import RecordForm from '../components/RecordForm';
import { fmt, d, daysBetween, todayISO, addDaysISO } from '../lib/format';

const FIELDS = [
  { key: 'name', label: 'Event name', wide: true }, { key: 'village', label: 'Village' }, { key: 'event_date', label: 'Date', type: 'date' },
  { key: 'expected_mothers', label: 'Expected expectant mothers', type: 'number', default: 0 }, { key: 'expected_children', label: 'Expected children under 5', type: 'number', default: 0 },
  { key: 'expected_malaria_tests', label: 'Expected malaria tests', type: 'number', default: 0 }, { key: 'expected_wounds', label: 'Expected wound dressings', type: 'number', default: 0 },
  { key: 'notes', label: 'Notes', type: 'textarea', wide: true },
];

export default function Outreach() {
  const [sel, setSel] = useState(null);
  const [edit, setEdit] = useState(null);
  const { data: events } = useData(() => api.select('outreach_events', { order: 'event_date' }));
  useEffect(() => { if (events && !sel) setSel(events.find((e) => e.status === 'Planned')?.id || events[0]?.id); }, [events, sel]);
  if (!events) return <Spinner />;
  return (
    <Page title="Outreach Readiness Planner" subtitle="Turn an upcoming village clinic into a ready-to-go stock plan: kits, transfers, kit builds and component purchases."
      actions={<Btn icon={Plus} onClick={() => setEdit({ event_date: addDaysISO(todayISO(), 14) })}>Plan outreach</Btn>}
      concept={<><p>Rosbren’s mobile clinics serve villages where a missing kit means a mother delivers without a clean birth kit. This planner converts expected attendance into <b>kit requirements</b> using clinic ratios (e.g. 35% malaria positivity, 30% of mothers near term — editable in Settings).</p>
        <p>It then checks the <b>Mobile Outreach Unit</b> stock, plans <b>transfers</b> from the store/pharmacy, creates <b>production orders</b> for kits that must be built (due 2 days before the event), and lists <b>component shortages with order-by dates</b> from supplier lead times — the whole ERP chain (inventory → production → MRP → purchasing) in one click.</p></>}>
      <div className="grid gap-4 lg:grid-cols-[320px_1fr]">
        <div className="space-y-2">
          {events.map((e) => (
            <button key={e.id} onClick={() => setSel(e.id)} className={cx('w-full rounded-xl border bg-white p-3 text-left shadow-sm', sel === e.id ? 'border-brand-500 ring-2 ring-brand-200' : 'border-slate-200 hover:border-brand-300')}>
              <div className="flex items-start justify-between gap-2"><b className="text-slate-900">{e.name}</b><StatusBadge status={e.status} /></div>
              <div className="mt-1 flex items-center gap-3 text-xs text-slate-500"><span className="flex items-center gap-1"><MapPin size={12} />{e.village}</span><span className="flex items-center gap-1"><CalendarDays size={12} />{d(e.event_date)}</span></div>
              {e.status === 'Planned' && <div className="mt-1 text-xs font-bold text-brand-700">in {daysBetween(todayISO(), e.event_date)} days</div>}
            </button>))}
        </div>
        {sel ? <Plan key={sel} id={sel} onEdit={(e) => setEdit(e)} /> : <Card><Empty>Plan your first outreach event.</Empty></Card>}
      </div>
      {edit && <RecordForm table="outreach_events" record={edit.id ? edit : null} fields={FIELDS.map((f) => (!edit.id && edit[f.key] ? { ...f, default: edit[f.key] } : f))} title={edit.id ? edit.name : 'New outreach event'} onClose={() => setEdit(null)} />}
    </Page>
  );
}

function Plan({ id, onEdit }) {
  const L = useLookups();
  const [run, busy] = useAction();
  const { data } = useData(() => api.rpc('outreach_plan', { p_event: id }), [id]);
  if (!data) return <Spinner />;
  const e = data.event;
  const shortComps = data.components.filter((c) => c.short > 0);
  const ready = data.kits.every((k) => k.transfer_qty === 0 && k.build_qty === 0);
  return (
    <div className="space-y-4">
      <Card title={e.name} actions={<>
        <Btn size="sm" variant="ghost" onClick={() => onEdit(e)}>Edit</Btn>
        {e.status === 'Prepared' && <Btn size="sm" variant="secondary" icon={CheckCircle2} busy={busy} onClick={() => run(() => api.rpc('save_record', { p_table: 'outreach_events', p: { id: e.id, status: 'Completed' } }), 'Event marked completed')}>Mark completed</Btn>}
        {e.status === 'Planned' && <Btn size="sm" icon={Rocket} busy={busy} onClick={() => run(() => api.rpc('outreach_prepare', { p_event: id }), (r) => `Prepared: ${r.transfers} transfers posted, ${r.production_orders} kit build orders created`)}>Prepare event</Btn>}</>}>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <K icon={Users} k="Expectant mothers" v={e.expected_mothers} /><K icon={Baby} k="Children under 5" v={e.expected_children} />
          <K icon={Bug} k="Malaria tests" v={e.expected_malaria_tests} /><K icon={Bandage} k="Wound dressings" v={e.expected_wounds} />
        </div>
        <p className="mt-3 text-sm text-slate-600">{e.village} · {d(e.event_date)} · {e.notes}</p>
        {e.status === 'Planned' && <p className={cx('mt-2 rounded-lg p-2 text-sm font-bold', ready ? 'bg-emerald-50 text-emerald-800' : 'bg-amber-50 text-amber-900')}>
          {ready ? 'The Mobile Outreach Unit already holds everything needed.' : 'Not ready yet — “Prepare event” will post the transfers and create the kit builds below.'}</p>}
      </Card>
      <Card title="Kit plan" pad={false}>
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-left text-xs font-bold uppercase text-slate-500"><tr><th className="px-3 py-2">Kit</th><th className="px-3 py-2">Basis</th><th className="px-3 py-2 text-right">Required</th><th className="px-3 py-2 text-right">In mobile unit</th><th className="px-3 py-2 text-right">Elsewhere</th><th className="px-3 py-2 text-right">Transfer</th><th className="px-3 py-2 text-right">Build</th></tr></thead>
          <tbody className="divide-y divide-slate-100">{data.kits.map((k) => (
            <tr key={k.id}><td className="px-3 py-2 font-bold">{k.name}</td><td className="px-3 py-2 text-xs text-slate-500">{k.basis}</td><td className="px-3 py-2 text-right font-bold">{fmt(k.required)}</td>
              <td className="px-3 py-2 text-right">{fmt(k.at_mobile)}</td><td className="px-3 py-2 text-right">{fmt(k.elsewhere)}</td>
              <td className="px-3 py-2 text-right">{k.transfer_qty > 0 ? <Badge color="blue">{fmt(k.transfer_qty)}</Badge> : '—'}</td>
              <td className="px-3 py-2 text-right">{k.build_qty > 0 ? <Badge color="brand">{fmt(k.build_qty)}</Badge> : '—'}</td></tr>))}</tbody>
        </table>
      </Card>
      {data.components.length > 0 && <Card title="Components needed for kit builds (at Clinic Store Room)" pad={false}>
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-left text-xs font-bold uppercase text-slate-500"><tr><th className="px-3 py-2">Component</th><th className="px-3 py-2 text-right">Needed</th><th className="px-3 py-2 text-right">In store</th><th className="px-3 py-2 text-right">Short</th><th className="px-3 py-2">Supplier</th><th className="px-3 py-2">Order by</th></tr></thead>
          <tbody className="divide-y divide-slate-100">{data.components.map((c) => (
            <tr key={c.item_id}><td className="px-3 py-2">{c.name}</td><td className="px-3 py-2 text-right">{fmt(c.needed)}</td><td className="px-3 py-2 text-right">{fmt(c.at_store)}</td>
              <td className={cx('px-3 py-2 text-right', c.short > 0 && 'font-bold text-red-700')}>{c.short > 0 ? fmt(c.short) : '—'}</td><td className="px-3 py-2">{c.supplier} ({c.lead_time_days} d)</td>
              <td className={cx('px-3 py-2', c.short > 0 && c.order_by < todayISO() && 'font-bold text-red-700')}>{c.short > 0 ? d(c.order_by) + (c.order_by < todayISO() ? ' · expedite' : '') : ''}</td></tr>))}</tbody>
        </table>
        {shortComps.length > 0 && <div className="flex justify-end p-3"><Btn size="sm" busy={busy} onClick={() => run(() => api.rpc('create_pos_from_suggestions', { p: { source: 'Outreach', lines: shortComps.map((c) => ({ item_id: c.item_id, qty: c.short })) } }), (r) => `${r.length} draft POs created`)}>Create draft POs for shortages</Btn></div>}
      </Card>}
    </div>
  );
}
const K = ({ icon: I, k, v }) => <div className="rounded-lg bg-slate-50 p-3"><div className="flex items-center gap-1 text-xs font-bold uppercase text-slate-500"><I size={13} />{k}</div><div className="text-2xl font-black text-brand-800">{fmt(v)}</div></div>;
