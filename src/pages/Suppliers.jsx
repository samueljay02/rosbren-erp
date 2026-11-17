import { useState } from 'react';
import { Plus, Pencil, Clock, PackageCheck, Wallet, Timer, Phone, Mail } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Btn, Modal, Table, StatusBadge, Spinner, Badge, cx } from '../components/ui';
import RecordForm from '../components/RecordForm';
import { money, fmt, d, pct, num, todayISO } from '../lib/format';

const FIELDS = [
  { key: 'name', label: 'Supplier name', wide: true }, { key: 'contact_name', label: 'Contact person' }, { key: 'phone', label: 'Phone' },
  { key: 'email', label: 'Email', type: 'email' }, { key: 'address', label: 'Address' },
  { key: 'lead_time_days', label: 'Quoted lead time (days)', type: 'number', default: 7, hint: 'Also updates the lead time of every item this supplier provides' },
  { key: 'payment_terms', label: 'Payment terms (label)', default: 'Net 30', hint: 'e.g. Net 30, Net 15, Cash on delivery' },
  { key: 'payment_terms_days', label: 'Payment terms (days until due)', type: 'number', default: 30 },
  { key: 'active', label: 'Active', type: 'checkbox', default: true }, { key: 'notes', label: 'Notes', type: 'textarea', wide: true },
];
const ratingColor = { Keep: 'green', Watch: 'amber', Replace: 'red', New: 'gray' };

export default function Suppliers() {
  const L = useLookups();
  const [edit, setEdit] = useState(null);
  const [open, setOpen] = useState(null);
  const { data } = useData(() => api.rpc('get_supplier_scorecards'));
  if (!data || !L.ready) return <Spinner />;
  return (
    <Page title="Suppliers & Scorecards" subtitle="Every measure is computed from purchase-order and receipt history — none of it is typed in."
      actions={<Btn icon={Plus} onClick={() => setEdit({})}>New supplier</Btn>}
      concept={<><p><b>On-time delivery</b> = % of POs whose first receipt arrived on or before the expected date (send date + quoted lead time). <b>Actual lead time</b> = average days from sending to first receipt, compared with the quoted lead time. <b>Fill rate</b> = units received ÷ units ordered on completed POs. <b>Payments</b>: open bills, amounts overdue and the next due date from payment terms.</p>
        <p><b>Overall score</b> = 40% on-time + 35% fill rate + 25% lead-time accuracy (quoted ÷ actual, capped at 100%). <b>≥85 Keep · 70–85 Watch · &lt;70 Replace.</b></p></>}>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {data.map((s) => (
          <button key={s.id} onClick={() => setOpen(s)} className="rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm transition hover:border-brand-300 hover:shadow">
            <div className="flex items-start justify-between gap-2">
              <div><div className="font-black text-slate-900">{s.name}</div><div className="text-xs text-slate-500">{s.po_count} POs · {s.payment_terms}{!s.active && ' · inactive'}</div></div>
              <div className="text-right"><div className={cx('text-3xl font-black tabular-nums', s.rating === 'Keep' ? 'text-emerald-700' : s.rating === 'Watch' ? 'text-amber-600' : s.rating === 'Replace' ? 'text-red-700' : 'text-slate-400')}>{s.score ?? '—'}</div>
                <Badge color={ratingColor[s.rating]}>{s.rating}</Badge></div>
            </div>
            <div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-100"><div className={cx('h-full rounded-full', s.rating === 'Keep' ? 'bg-emerald-500' : s.rating === 'Watch' ? 'bg-amber-400' : 'bg-red-500')} style={{ width: `${num(s.score)}%` }} /></div>
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <M icon={Clock} k="On-time delivery" v={pct(s.on_time_pct, 0)} bad={num(s.on_time_pct) < 70} />
              <M icon={PackageCheck} k="Fill rate" v={pct(s.fill_rate_pct, 0)} bad={num(s.fill_rate_pct) < 95} />
              <M icon={Timer} k="Lead time actual / quoted" v={`${fmt(s.avg_actual_lead, 1)} / ${s.lead_time_days} d`} bad={num(s.avg_actual_lead) > num(s.lead_time_days) + 1} />
              <M icon={Wallet} k="Owed · overdue" v={<>{money(s.owed)}{num(s.overdue) > 0 && <span className="block text-xs text-red-700">{money(s.overdue)} overdue</span>}</>} bad={num(s.overdue) > 0} />
            </dl>
            {s.next_due && <div className="mt-2 text-xs text-slate-500">Next payment due {d(s.next_due)}{s.paid_on_time_pct !== null && ` · ${pct(s.paid_on_time_pct, 0)} of bills paid on time`}</div>}
          </button>
        ))}
      </div>
      <Card title="Comparison" className="mt-4" pad={false}>
        <Table rows={data} search={false} csv="supplier-scorecards.csv" initialSort={{ key: 'score', dir: 'desc' }} onRowClick={setOpen} columns={[
          { key: 'name', label: 'Supplier', render: (r) => <b>{r.name}</b> }, { key: 'po_count', label: 'POs', align: 'right' }, { key: 'open_pos', label: 'Open', align: 'right' },
          { key: 'on_time_pct', label: 'On-time', align: 'right', render: (r) => pct(r.on_time_pct, 0) },
          { key: 'avg_days_late', label: 'Avg days late', align: 'right', render: (r) => fmt(r.avg_days_late, 1) },
          { key: 'lead_time_days', label: 'Quoted LT', align: 'right' }, { key: 'avg_actual_lead', label: 'Actual LT', align: 'right', render: (r) => fmt(r.avg_actual_lead, 1) },
          { key: 'fill_rate_pct', label: 'Fill rate', align: 'right', render: (r) => pct(r.fill_rate_pct, 1) },
          { key: 'owed', label: 'Owed', align: 'right', render: (r) => money(r.owed) }, { key: 'overdue', label: 'Overdue', align: 'right', render: (r) => (num(r.overdue) ? <span className="text-red-700">{money(r.overdue)}</span> : '—') },
          { key: 'score', label: 'Score', align: 'right', render: (r) => <b>{r.score ?? '—'}</b> }, { key: 'rating', label: 'Rating', render: (r) => <StatusBadge status={r.rating} /> },
        ]} />
      </Card>
      {open && <Detail s={open} onClose={() => setOpen(null)} onEdit={() => { setEdit(L.supById[open.id]); setOpen(null); }} />}
      {edit && <RecordForm table="suppliers" record={edit.id ? edit : null} fields={FIELDS} title={edit.id ? edit.name : 'New supplier'} onClose={() => setEdit(null)} />}
    </Page>
  );
}
const M = ({ icon: I, k, v, bad }) => <div><dt className="flex items-center gap-1 text-[11px] font-bold uppercase text-slate-500"><I size={12} />{k}</dt><dd className={cx('font-black tabular-nums', bad ? 'text-red-700' : 'text-slate-800')}>{v}</dd></div>;

function Detail({ s, onClose, onEdit }) {
  const auth = useAuth();
  const [run, busy] = useAction();
  return (
    <Modal open onClose={onClose} title={s.name} wide="xl" footer={<Btn variant="secondary" icon={Pencil} onClick={onEdit}>Edit supplier</Btn>}>
      <div className="mb-4 flex flex-wrap gap-4 text-sm text-slate-600">
        <span>{s.contact_name}</span>{s.phone && <span className="flex items-center gap-1"><Phone size={14} />{s.phone}</span>}{s.email && <a className="flex items-center gap-1 text-brand-700" href={`mailto:${s.email}`}><Mail size={14} />{s.email}</a>}
        <span>{s.address}</span><span>Quoted lead time <b>{s.lead_time_days} days</b> · <b>{s.payment_terms}</b></span>
      </div>
      <div className="grid gap-4 lg:grid-cols-[1fr_380px]">
        <div><div className="mb-1 text-xs font-bold uppercase text-slate-500">Purchase order history</div>
          <Table rows={s.history} search={false} dense maxHeight={380} columns={[
            { key: 'po_number', label: 'PO' }, { key: 'status', label: 'Status', render: (r) => <StatusBadge status={r.status} /> },
            { key: 'order_date', label: 'Sent', render: (r) => d(r.order_date) }, { key: 'expected_date', label: 'Expected', render: (r) => d(r.expected_date) },
            { key: 'first_receipt', label: 'Received', render: (r) => (r.first_receipt ? <span className={r.first_receipt > r.expected_date ? 'font-bold text-red-700' : 'text-emerald-700'}>{d(r.first_receipt)}</span> : '') },
            { key: 'fill', label: 'Fill', align: 'right', render: (r) => (r.first_receipt ? pct((100 * num(r.received)) / num(r.ordered), 0) : '') },
            { key: 'amount', label: 'Value', align: 'right', render: (r) => money(r.amount) }]} /></div>
        <div><div className="mb-1 text-xs font-bold uppercase text-slate-500">Open bills (payment tracking)</div>
          {!s.open_bills.length && <p className="text-sm text-slate-500">Nothing owed.</p>}
          <ul className="divide-y divide-slate-100 text-sm">{s.open_bills.map((b) => (
            <li key={b.receipt_id} className="flex items-center justify-between gap-2 py-2"><div><b>{b.po_number}</b> · received {d(b.receipt_date)}
              <div className={b.due_date < todayISO() ? 'text-xs font-bold text-red-700' : 'text-xs text-slate-500'}>due {d(b.due_date)}{b.due_date < todayISO() && ' · OVERDUE'}</div></div>
              <div className="text-right"><b>{money(num(b.amount) - num(b.paid))}</b>{auth.isManager && <div><Btn size="sm" variant="ghost" busy={busy} onClick={async () => (await run(() => api.rpc('pay_bill', { p_receipt_id: b.receipt_id }), 'Paid')) && onClose()}>Mark paid</Btn></div>}</div></li>))}</ul>
        </div>
      </div>
    </Modal>
  );
}
