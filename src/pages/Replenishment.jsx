import { useEffect, useMemo, useState } from 'react';
import { RefreshCw, ShoppingBag, CheckSquare, Save } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Btn, Input, Field, Modal, Table, Tabs, Badge, Spinner, Stat } from '../components/ui';
import { money, fmt, d, num } from '../lib/format';

export default function Replenishment() {
  const L = useLookups();
  const auth = useAuth();
  const [tab, setTab] = useState('reorder');
  const [sel, setSel] = useState({});
  const [detail, setDetail] = useState(null);
  const [run, busy] = useAction();
  const { data } = useData(() => api.rpc('get_replenishment'));
  const [s, setS] = useState(null);
  useEffect(() => { if (data && !s) setS(data.settings); }, [data, s]);
  const items = useMemo(() => (data?.items || []).filter((i) => num(i.avg_daily) > 0 || num(i.position) > 0), [data]);
  if (!data || !L.ready || !s) return <Spinner />;
  const reorder = items.filter((i) => num(i.position) <= num(i.reorder_point));
  const review = items.filter((i) => i.due_for_review);
  const changedRop = items.filter((i) => num(i.calc_rop) !== num(i.reorder_point));
  const shown = tab === 'reorder' ? reorder : tab === 'review' ? review : items;
  const qtyFor = (i) => (tab === 'review' ? num(i.periodic_qty) : num(i.suggested_qty) || num(i.eoq));
  const chosen = shown.filter((i) => sel[i.id] && qtyFor(i) > 0);
  const saveSettings = () => run(() => api.rpc('save_settings', { p: { ordering_cost: String(s.ordering_cost), holding_cost_pct: String(s.holding_cost_pct), service_level_z: String(s.z), review_period_days: String(s.review_period_days), demand_lookback_days: String(s.lookback_days) } }), 'Policy saved — EOQ and reorder points recalculated');
  return (
    <Page title="Reorder Points & EOQ" subtitle={`Inventory policy computed from the last ${data.settings.lookback_days} days of sales history (including kit demand exploded to components).`}
      concept={<>
        <p><b>Average daily usage (d)</b> and its <b>standard deviation (σ)</b> come from daily sales history. Components also count <i>dependent</i> demand: every kit sold × its BOM quantity.</p>
        <p><b>Reorder point</b> = lead-time demand + safety stock = <b>d × L + z × σ × √L</b>. Ordering when the inventory position (on hand + on order − allocated) hits this level covers demand during the supplier’s lead time at the chosen service level.</p>
        <p><b>EOQ</b> = √(2 × D × S ÷ H), where D = annual demand (d × 365), S = cost to place one order, H = annual holding cost per unit (holding % × unit cost). It balances ordering cost against holding cost.</p>
        <p><b>Periodic review</b>: every R days a person reviews each item and orders up to <b>d × (R + L) + z × σ × √(R + L)</b> minus the inventory position.</p></>}>
      <Card title="Policy inputs (stored settings — change one and every result recalculates)" className="mb-4">
        <div className="grid grid-cols-2 gap-3 md:grid-cols-6">
          <Field label="Ordering cost S (UGX/order)"><Input type="number" value={s.ordering_cost} onChange={(e) => setS({ ...s, ordering_cost: e.target.value })} disabled={!auth.isManager} /></Field>
          <Field label="Holding cost H (0.25 = 25%/yr)"><Input type="number" step="0.01" value={s.holding_cost_pct} onChange={(e) => setS({ ...s, holding_cost_pct: e.target.value })} disabled={!auth.isManager} /></Field>
          <Field label="Service level z"><Input type="number" step="0.01" value={s.z} onChange={(e) => setS({ ...s, z: e.target.value })} disabled={!auth.isManager} /></Field>
          <Field label="Review period R (days)"><Input type="number" value={s.review_period_days} onChange={(e) => setS({ ...s, review_period_days: e.target.value })} disabled={!auth.isManager} /></Field>
          <Field label="History window (days)"><Input type="number" value={s.lookback_days} onChange={(e) => setS({ ...s, lookback_days: e.target.value })} disabled={!auth.isManager} /></Field>
          <div className="flex items-end">{auth.isManager ? <Btn icon={Save} busy={busy} onClick={saveSettings} className="w-full">Save &amp; recalculate</Btn> : <p className="text-xs text-slate-500">Managers can change policy inputs.</p>}</div>
        </div>
      </Card>
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="At / below reorder point" value={reorder.length} tone="warn" onClick={() => setTab('reorder')} />
        <Stat label="Due for periodic review" value={review.length} onClick={() => setTab('review')} />
        <Stat label="Reorder points out of date" value={changedRop.length} sub="stored ≠ calculated" />
        <Stat label="Suggested order value" value={money(reorder.reduce((a, i) => a + num(i.suggested_qty) * num(i.avg_cost), 0))} />
      </div>
      <Tabs value={tab} onChange={(t) => { setTab(t); setSel({}); }} tabs={[{ value: 'reorder', label: 'Reorder now', count: reorder.length }, { value: 'review', label: 'Periodic review', count: review.length }, { value: 'all', label: 'All items', count: items.length }]} />
      <Card pad={false} actions={<div className="flex flex-wrap gap-2">
        <Btn size="sm" variant="secondary" onClick={() => setSel(Object.fromEntries(shown.map((i) => [i.id, true])))}>Select all</Btn>
        <Btn size="sm" variant="secondary" icon={RefreshCw} busy={busy} disabled={!Object.values(sel).some(Boolean)} onClick={() => run(() => api.rpc('apply_reorder_points', { p: shown.filter((i) => sel[i.id]).map((i) => ({ item_id: i.id, reorder_point: num(i.calc_rop) })) }), 'Reorder points updated from history')}>Apply calculated ROP</Btn>
        {tab === 'review' && <Btn size="sm" variant="secondary" icon={CheckSquare} busy={busy} disabled={!Object.values(sel).some(Boolean)} onClick={() => run(() => api.rpc('mark_reviewed', { p_item_ids: shown.filter((i) => sel[i.id]).map((i) => i.id) }), 'Marked as reviewed')}>Mark reviewed</Btn>}
        <Btn size="sm" icon={ShoppingBag} busy={busy} disabled={!chosen.filter((i) => i.preferred_supplier_id).length}
          onClick={() => run(() => api.rpc('create_pos_from_suggestions', { p: { source: tab === 'review' ? 'Periodic Review' : 'ROP', lines: chosen.filter((i) => i.preferred_supplier_id).map((i) => ({ item_id: i.id, qty: qtyFor(i) })) } }), (r) => `${r.length} draft POs created (grouped by supplier)`)}>Create draft POs</Btn>
      </div>} title={tab === 'review' ? 'Order-up-to quantities' : 'Continuous review (ROP / EOQ)'}>
        <Table rows={shown} csv="replenishment.csv" dense onRowClick={setDetail} initialSort={{ key: 'order_by_date', dir: 'asc' }} columns={[
          { key: 'sel', label: '', sortable: false, noExport: true, render: (r) => <input type="checkbox" checked={!!sel[r.id]} onClick={(e) => e.stopPropagation()} onChange={(e) => setSel({ ...sel, [r.id]: e.target.checked })} aria-label="Select" /> },
          { key: 'name', label: 'Item', render: (r) => <div><b>{r.name}</b><div className="text-xs text-slate-500">{r.supplier_name || 'Made in-house'}</div></div> },
          { key: 'avg_daily', label: 'd /day', align: 'right', render: (r) => fmt(r.avg_daily, 2) },
          { key: 'sd_daily', label: 'σ', align: 'right', render: (r) => fmt(r.sd_daily, 2) },
          { key: 'lead_time_days', label: 'L', align: 'right' },
          { key: 'lead_time_demand', label: 'LT demand', align: 'right', render: (r) => fmt(r.lead_time_demand, 1) },
          { key: 'safety_stock', label: 'Safety', align: 'right' },
          { key: 'calc_rop', label: 'Calc ROP', align: 'right', render: (r) => <b>{fmt(r.calc_rop)}</b> },
          { key: 'reorder_point', label: 'Stored ROP', align: 'right', render: (r) => <span className={num(r.reorder_point) !== num(r.calc_rop) ? 'text-amber-700' : ''}>{fmt(r.reorder_point)}</span> },
          { key: 'eoq', label: 'EOQ', align: 'right', render: (r) => <b>{fmt(r.eoq)}</b> },
          { key: 'position', label: 'Position', align: 'right', render: (r) => <span className={num(r.position) <= num(r.reorder_point) ? 'font-bold text-red-700' : ''}>{fmt(r.position)}</span> },
          tab === 'review' ? { key: 'order_up_to', label: 'Order-up-to', align: 'right' } : { key: 'order_by_date', label: 'Order by', render: (r) => d(r.order_by_date) },
          tab === 'review' ? { key: 'periodic_qty', label: 'Order qty', align: 'right', render: (r) => <b>{fmt(r.periodic_qty)}</b> } : { key: 'suggested_qty', label: 'Suggested', align: 'right', render: (r) => (r.suggested_qty ? <b>{fmt(r.suggested_qty)}</b> : '—') },
          ...(tab === 'review' ? [{ key: 'last_reviewed_at', label: 'Last review', render: (r) => d(r.last_reviewed_at) }] : []),
        ]} />
      </Card>
      {detail && <Explain i={detail} s={data.settings} onClose={() => setDetail(null)} />}
    </Page>
  );
}

function Explain({ i, s, onClose }) {
  const D = num(i.avg_daily) * 365; const H = num(s.holding_cost_pct) * num(i.avg_cost);
  const R = num(s.review_period_days); const L = num(i.lead_time_days);
  return (
    <Modal open onClose={onClose} title={`How the numbers for ${i.name} are calculated`} wide>
      <div className="grid gap-4 md:grid-cols-2">
        <Box t="Demand (from sales history)">
          <Line k="Units used in last window" v={fmt(i.usage_lookback)} /><Line k="Average daily usage d" v={fmt(i.avg_daily, 3)} />
          <Line k="Std. deviation σ (daily)" v={fmt(i.sd_daily, 3)} /><Line k="Annual demand D = d × 365" v={fmt(D)} />
        </Box>
        <Box t="Reorder point">
          <Line k="Lead time L" v={`${L} days`} /><Line k={`Lead-time demand d × L = ${fmt(i.avg_daily, 2)} × ${L}`} v={fmt(i.lead_time_demand, 1)} />
          <Line k={`Safety stock z·σ·√L = ${s.z} × ${fmt(i.sd_daily, 2)} × ${fmt(Math.sqrt(L), 2)}`} v={fmt(i.safety_stock)} />
          <Line k="Reorder point (rounded up)" v={<b>{fmt(i.calc_rop)}</b>} />
        </Box>
        <Box t="Economic order quantity">
          <Line k="Ordering cost S" v={money(s.ordering_cost)} /><Line k={`Holding cost H = ${s.holding_cost_pct} × ${fmt(i.avg_cost)}`} v={money(H)} />
          <Line k={`EOQ = √(2 × ${fmt(D)} × ${fmt(s.ordering_cost)} ÷ ${fmt(H, 1)})`} v={<b>{fmt(i.eoq)}</b>} />
          <Line k="Orders per year ≈ D ÷ EOQ" v={i.eoq ? fmt(D / num(i.eoq), 1) : '—'} />
        </Box>
        <Box t="Position & periodic review">
          <Line k="On hand + on order + in production − allocated" v={`${fmt(i.on_hand)} + ${fmt(i.on_order)} + ${fmt(i.in_production)} − ${fmt(i.allocated)} = ${fmt(i.position)}`} />
          <Line k={`Order-up-to = d(R+L) + zσ√(R+L), R=${R}`} v={fmt(i.order_up_to)} />
          <Line k="Periodic order qty" v={fmt(i.periodic_qty)} />
          <Line k="Status" v={num(i.position) <= num(i.reorder_point) ? <Badge color="red">Reorder now</Badge> : <Badge color="green">OK until {d(i.order_by_date)}</Badge>} />
        </Box>
      </div>
    </Modal>
  );
}
const Box = ({ t, children }) => <div className="rounded-lg border border-slate-200 p-3"><div className="mb-2 text-xs font-bold uppercase text-brand-700">{t}</div><div className="space-y-1">{children}</div></div>;
const Line = ({ k, v }) => <div className="flex justify-between gap-3 text-sm"><span className="text-slate-600">{k}</span><span className="tabular-nums">{v}</span></div>;
