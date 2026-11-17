import { useNavigate } from 'react-router-dom';
import { TrendingUp, Wallet, Boxes, AlertTriangle, ClipboardList, Truck, Factory, Receipt, HeartHandshake, Activity as ActivityIcon } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Stat, Spinner, ErrorBox, Badge } from '../components/ui';
import { TimeLines, RankBars } from '../components/charts';
import { money, fmt, pct, dt, num, usd } from '../lib/format';

export default function Dashboard() {
  const nav = useNavigate();
  const auth = useAuth();
  const L = useLookups();
  const { data: d, error } = useData(() => api.rpc('get_dashboard'));
  if (error) return <Page title="Dashboard"><ErrorBox error={error} /></Page>;
  if (!d) return <Spinner />;
  const margin = num(d.mtd_revenue) ? (100 * (num(d.mtd_revenue) - num(d.mtd_cost))) / num(d.mtd_revenue) : null;
  const vsLast = num(d.last_month_same_period) ? (100 * (num(d.mtd_revenue) - num(d.last_month_same_period))) / num(d.last_month_same_period) : null;
  const rate = Number(L.setting?.usd_rate || 3500);
  return (
    <Page title={`Good ${new Date().getHours() < 12 ? 'morning' : new Date().getHours() < 17 ? 'afternoon' : 'evening'}, ${auth.profile?.full_name?.split(' ')[0] || ''}`}
      subtitle="Live view of the pharmacy, stock, production, purchasing and money — every number is computed from transactions.">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat icon={Receipt} label="Today’s sales" value={money(d.today_revenue)} sub={`${d.today_transactions} transactions · ≈ ${usd(d.today_revenue, rate)}`} tone="brand" onClick={() => nav('/reports')} />
        <Stat icon={TrendingUp} label="Month to date" value={money(d.mtd_revenue)} sub={vsLast === null ? '' : `${vsLast >= 0 ? '▲' : '▼'} ${pct(Math.abs(vsLast))} vs same days last month`} tone={vsLast >= 0 ? 'good' : 'warn'} />
        <Stat icon={Wallet} label="Gross margin (MTD)" value={pct(margin)} sub={`COGS ${money(d.mtd_cost)}`} />
        <Stat icon={Boxes} label="Inventory value" value={money(d.inventory_value)} sub="at weighted-average cost" onClick={() => nav('/inventory')} />
        <Stat icon={AlertTriangle} label="Below reorder point" value={d.below_rop} sub={`${d.out_of_stock} items out of stock`} tone={d.below_rop ? 'warn' : 'good'} onClick={() => nav('/replenishment')} />
        <Stat icon={ClipboardList} label="Open sales orders" value={d.open_sales_orders} sub={`${d.portal_orders_open} online pickup orders`} onClick={() => nav('/sales-orders')} />
        <Stat icon={Truck} label="Open purchase orders" value={d.open_pos} sub={d.late_pos ? `${d.late_pos} past expected date` : 'none late'} tone={d.late_pos ? 'bad' : 'default'} onClick={() => nav('/purchasing')} />
        <Stat icon={Factory} label="Production" value={`${d.wo_in_progress} in progress`} sub={`${d.wo_planned} planned kit builds`} onClick={() => nav('/production')} />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <Card title="Revenue vs cost of goods — last 30 days" className="lg:col-span-2">
          <TimeLines data={d.daily} series={[{ key: 'revenue', label: 'Revenue' }, { key: 'cost', label: 'Cost of goods sold' }]} />
        </Card>
        <Card title="Needs attention">
          <ul className="space-y-2 text-sm">
            {d.below_rop > 0 && <Alert onClick={() => nav('/replenishment')} color="amber">{d.below_rop} items at or below reorder point</Alert>}
            {d.out_of_stock > 0 && <Alert onClick={() => nav('/inventory')} color="red">{d.out_of_stock} items out of stock</Alert>}
            {d.late_pos > 0 && <Alert onClick={() => nav('/purchasing')} color="red">{d.late_pos} purchase orders are late</Alert>}
            {num(d.payables_overdue) > 0 && <Alert onClick={() => nav('/suppliers')} color="red">{money(d.payables_overdue)} supplier bills overdue</Alert>}
            {num(d.payables_due_7) > 0 && <Alert onClick={() => nav('/suppliers')} color="amber">{money(d.payables_due_7)} due to suppliers within 7 days</Alert>}
            {d.portal_orders_open > 0 && <Alert onClick={() => nav('/sales-orders')} color="blue">{d.portal_orders_open} online orders waiting for pickup</Alert>}
            <Alert onClick={() => nav('/mrp')} color="brand">Review MRP plan for confirmed kit orders</Alert>
          </ul>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <Card title="Top sellers — last 30 days"><RankBars data={d.top_items.map((x) => ({ ...x, revenue: num(x.revenue) }))} /></Card>
        <Card title={<span className="flex items-center gap-2"><HeartHandshake size={16} />Community impact this year</span>}>
          <ul className="space-y-2.5">
            <li className="flex items-baseline justify-between gap-2 border-b border-slate-100 pb-2"><span className="text-sm text-slate-600">patient consultations</span><b className="text-xl text-brand-700 tabular-nums">{fmt(d.patients_served_ytd)}</b></li>
            {d.impact.map((i) => (
              <li key={i.item} className="flex items-baseline justify-between gap-2"><span className="text-sm text-slate-600">{i.label}</span><b className="text-xl text-brand-700 tabular-nums">{fmt(i.qty)}</b></li>
            ))}
          </ul>
          <p className="mt-3 text-xs text-slate-500">Counted from kits dispensed through POS, sales orders and outreach — ready for donor reports.</p>
        </Card>
        <Card title={<span className="flex items-center gap-2"><ActivityIcon size={16} />Live activity</span>} pad={false}>
          <ul className="max-h-80 divide-y divide-slate-100 overflow-y-auto">
            {d.activity.map((a, i) => (
              <li key={i} className="px-4 py-2 text-sm">
                <div className="flex justify-between gap-2"><b className="text-slate-800">{a.action}</b><span className="whitespace-nowrap text-xs text-slate-400">{dt(a.created_at)}</span></div>
                <div className="text-xs text-slate-600">{a.details}</div>
                <div className="text-[11px] text-slate-400">by {a.user_name}</div>
              </li>))}
          </ul>
        </Card>
      </div>
    </Page>
  );
}

function Alert({ children, onClick, color }) {
  return (
    <li><button onClick={onClick} className="flex w-full items-center justify-between rounded-lg border border-slate-100 px-3 py-2 text-left hover:border-brand-200 hover:bg-brand-50/40">
      <span>{children}</span><Badge color={color}>View</Badge></button></li>
  );
}
