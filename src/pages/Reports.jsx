import { useMemo, useState } from 'react';
import { Printer } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups } from '../lib/hooks';
import { Page, Card, Btn, Tabs, Spinner, Stat, DateRange, Table, Badge, StatusBadge } from '../components/ui';
import { TimeLines, Bars, RankBars, SERIES } from '../components/charts';
import { money, fmt, num, pct, d, todayISO, addDaysISO } from '../lib/format';

export default function Reports() {
  const [tab, setTab] = useState('sales');
  const [range, setRange] = useState([addDaysISO(todayISO(), -29), todayISO()]);
  return (
    <Page title="Management Reports" subtitle="Sales trends, best sellers, low stock with order suggestions, stock by location and supplier performance."
      actions={<><DateRange from={range[0]} to={range[1]} onChange={(a, b) => setRange([a, b])} /><Btn variant="secondary" icon={Printer} onClick={() => window.print()}>Print</Btn></>}>
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'sales', label: 'Sales by day / week' }, { value: 'items', label: 'Top sellers & categories' }, { value: 'low', label: 'Low stock & order suggestions' }, { value: 'loc', label: 'Inventory by location' }, { value: 'sup', label: 'Supplier performance' }]} />
      {(tab === 'sales' || tab === 'items') && <Sales range={range} tab={tab} />}
      {tab === 'low' && <LowStock />}
      {tab === 'loc' && <ByLocation />}
      {tab === 'sup' && <SupplierPerf />}
    </Page>
  );
}

function Sales({ range, tab }) {
  const { data: r } = useData(() => api.rpc('get_sales_report', { p_from: range[0], p_to: range[1] }), [range[0], range[1]]);
  if (!r) return <Spinner />;
  const t = r.totals;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <Stat label="Revenue" value={money(t.revenue)} tone="brand" /><Stat label="Gross margin" value={pct(num(t.revenue) ? (100 * (num(t.revenue) - num(t.cost))) / num(t.revenue) : null)} />
        <Stat label="Transactions" value={fmt(t.transactions)} /><Stat label="Average ticket" value={money(t.avg_ticket)} /><Stat label="Units sold" value={fmt(t.units)} />
      </div>
      {tab === 'sales' ? <>
        <Card title="Sales by day"><TimeLines data={r.daily.map((x) => ({ ...x, revenue: num(x.revenue), cost: num(x.cost) }))} series={[{ key: 'revenue', label: 'Revenue' }, { key: 'cost', label: 'Cost of goods' }]} /></Card>
        <div className="grid gap-4 lg:grid-cols-2">
          <Card title="Sales by week"><Bars data={r.weekly.map((x) => ({ ...x, revenue: num(x.revenue) }))} x="week" series={[{ key: 'revenue', label: 'Revenue' }]} xFmt={(v) => d(v).slice(0, 6)} /></Card>
          <Card title="By channel, payment method and location" pad={false}>
            <Table search={false} rows={[...r.by_channel.map((x) => ({ k: 'Channel', name: x.channel, ...x })), ...r.by_payment.map((x) => ({ k: 'Payment', name: x.method, ...x })), ...r.by_location.map((x) => ({ k: 'Location', name: x.location, ...x }))].map((x, i) => ({ ...x, id: i }))}
              columns={[{ key: 'k', label: 'Dimension' }, { key: 'name', label: 'Value' }, { key: 'n', label: 'Transactions', align: 'right' }, { key: 'revenue', label: 'Revenue', align: 'right', render: (x) => money(x.revenue) }]} />
          </Card>
        </div>
        <Card title="Daily detail" pad={false}><Table rows={r.daily.map((x, i) => ({ ...x, id: i }))} csv="sales-by-day.csv" dense search={false} initialSort={{ key: 'date', dir: 'desc' }} columns={[
          { key: 'date', label: 'Date', render: (x) => d(x.date) }, { key: 'transactions', label: 'Transactions', align: 'right' },
          { key: 'revenue', label: 'Revenue', align: 'right', render: (x) => money(x.revenue) }, { key: 'cost', label: 'COGS', align: 'right', render: (x) => money(x.cost) },
          { key: 'margin', label: 'Margin', align: 'right', render: (x) => (num(x.revenue) ? pct((100 * (num(x.revenue) - num(x.cost))) / num(x.revenue)) : '—') }]} /></Card>
      </> : <>
        <div className="grid gap-4 lg:grid-cols-2">
          <Card title="Top-selling items by revenue"><RankBars data={r.top_items.slice(0, 10).map((x) => ({ ...x, revenue: num(x.revenue) }))} /></Card>
          <Card title="Revenue by category"><RankBars data={r.by_category.map((x) => ({ name: x.category, revenue: num(x.revenue) }))} color={SERIES[2]} /></Card>
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <Card title="Top items" pad={false}><Table rows={r.top_items} search={false} csv="top-items.csv" columns={[{ key: 'name', label: 'Item' }, { key: 'qty', label: 'Units', align: 'right', render: (x) => fmt(x.qty) }, { key: 'revenue', label: 'Revenue', align: 'right', render: (x) => money(x.revenue) }, { key: 'margin_pct', label: 'Margin', align: 'right', render: (x) => pct(x.margin_pct) }]} /></Card>
          <Card title="Top customers" pad={false}><Table rows={r.top_customers} search={false} columns={[{ key: 'customer', label: 'Customer' }, { key: 'type', label: 'Type' }, { key: 'n', label: 'Purchases', align: 'right' }, { key: 'revenue', label: 'Revenue', align: 'right', render: (x) => money(x.revenue) }]} /></Card>
        </div>
      </>}
    </div>
  );
}

function LowStock() {
  const { data } = useData(() => api.rpc('get_replenishment'));
  if (!data) return <Spinner />;
  const rows = data.items.filter((i) => num(i.position) <= num(i.reorder_point));
  return (
    <Card title={`${rows.length} items at or below reorder point`} pad={false}>
      <Table rows={rows} csv="low-stock.csv" initialSort={{ key: 'order_by_date', dir: 'asc' }} columns={[
        { key: 'name', label: 'Item', render: (r) => <b>{r.name}</b> }, { key: 'supplier_name', label: 'Supplier', render: (r) => r.supplier_name || 'Made in-house' },
        { key: 'on_hand', label: 'On hand', align: 'right', render: (r) => fmt(r.on_hand) }, { key: 'on_order', label: 'On order', align: 'right', render: (r) => fmt(r.on_order) },
        { key: 'allocated', label: 'Allocated', align: 'right', render: (r) => fmt(r.allocated) }, { key: 'reorder_point', label: 'ROP', align: 'right', render: (r) => fmt(r.reorder_point) },
        { key: 'suggested_qty', label: 'Suggested order qty', align: 'right', render: (r) => <b>{fmt(r.suggested_qty)}</b> },
        { key: 'order_by_date', label: 'Order by', render: (r) => <Badge color="red">{d(r.order_by_date)}</Badge> },
        { key: 'cost', label: 'Est. cost', align: 'right', render: (r) => money(num(r.suggested_qty) * num(r.avg_cost)) }]} />
    </Card>
  );
}

function ByLocation() {
  const L = useLookups();
  const { data } = useData(() => api.rpc('get_inventory_status'));
  const rows = useMemo(() => (data || []).map((r) => ({ ...r, ...Object.fromEntries(L.locations.map((l) => ['l' + l.id, num(r.by_location?.[l.id])])), ...Object.fromEntries(L.locations.map((l) => ['v' + l.id, num(r.by_location?.[l.id]) * num(r.avg_cost)])) })), [data, L.locations]);
  if (!data) return <Spinner />;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-3 md:grid-cols-3">{L.locations.map((l) => <Stat key={l.id} label={l.name} value={money(rows.reduce((a, r) => a + r['v' + l.id], 0))} sub={`${fmt(rows.reduce((a, r) => a + r['l' + l.id], 0))} units · ${rows.filter((r) => r['l' + l.id] > 0).length} items stocked`} />)}</div>
      <Card pad={false}><Table rows={rows} csv="inventory-by-location.csv" dense columns={[{ key: 'name', label: 'Item', render: (r) => <b>{r.name}</b> }, { key: 'category', label: 'Category' },
        ...L.locations.flatMap((l) => [{ key: 'l' + l.id, label: l.code + ' qty', align: 'right', render: (r) => fmt(r['l' + l.id]) }, { key: 'v' + l.id, label: l.code + ' value', align: 'right', render: (r) => fmt(r['v' + l.id]) }]),
        { key: 'value', label: 'Total value', align: 'right', render: (r) => money(r.value) }]} /></Card>
    </div>
  );
}

function SupplierPerf() {
  const { data } = useData(() => api.rpc('get_supplier_scorecards'));
  if (!data) return <Spinner />;
  const chart = data.filter((s) => s.avg_actual_lead !== null).map((s) => ({ name: s.name.split(' ').slice(0, 2).join(' '), quoted: num(s.lead_time_days), actual: num(s.avg_actual_lead) }));
  return (
    <div className="space-y-4">
      <Card title="Average actual lead time vs quoted lead time (days)"><Bars data={chart} x="name" money={false} series={[{ key: 'quoted', label: 'Quoted' }, { key: 'actual', label: 'Actual' }]} /></Card>
      <Card pad={false}><Table rows={data} search={false} csv="supplier-performance.csv" columns={[{ key: 'name', label: 'Supplier' }, { key: 'lead_time_days', label: 'Quoted LT', align: 'right' },
        { key: 'avg_actual_lead', label: 'Actual LT', align: 'right', render: (r) => fmt(r.avg_actual_lead, 1) }, { key: 'on_time_pct', label: 'On-time', align: 'right', render: (r) => pct(r.on_time_pct, 0) },
        { key: 'fill_rate_pct', label: 'Fill rate', align: 'right', render: (r) => pct(r.fill_rate_pct, 1) }, { key: 'owed', label: 'Owed', align: 'right', render: (r) => money(r.owed) },
        { key: 'score', label: 'Score', align: 'right' }, { key: 'rating', label: 'Rating', render: (r) => <StatusBadge status={r.rating} /> }]} /></Card>
    </div>
  );
}
