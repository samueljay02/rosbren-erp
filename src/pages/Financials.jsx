import { useState } from 'react';
import { Plus, Printer } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups } from '../lib/hooks';
import { Page, Card, Btn, Tabs, Spinner, Stat, DateRange, Table, cx } from '../components/ui';
import { Bars, RankBars } from '../components/charts';
import RecordForm from '../components/RecordForm';
import { money, fmt, num, pct, usd, d, todayISO, addDaysISO } from '../lib/format';

export default function Financials() {
  const L = useLookups();
  const [tab, setTab] = useState('pnl');
  const [range, setRange] = useState([addDaysISO(todayISO(), -181), todayISO()]);
  return (
    <Page title="Financial Statements" subtitle="Profit & loss, inventory valuation and turnover — recalculated live from every sale, return, receipt, adjustment and expense."
      actions={<><DateRange from={range[0]} to={range[1]} onChange={(a, b) => setRange([a, b])} /><Btn variant="secondary" icon={Printer} onClick={() => window.print()}>Print</Btn></>}
      concept={<><p><b>Revenue</b> is recognised when goods leave (POS sale or sales-order fulfilment). <b>Cost of goods sold</b> is the weighted-average cost at that moment. Returns reverse both; exchanges add the replacement as a sale.</p>
        <p><b>Inventory valuation</b> = on-hand units × weighted-average cost, where each receipt re-averages: (old qty × old cost + received qty × PO cost) ÷ new qty. <b>Inventory turnover</b> = annualised COGS ÷ current inventory value; <b>days on hand</b> = inventory value ÷ COGS per day.</p></>}>
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'pnl', label: 'Profit & Loss' }, { value: 'inv', label: 'Inventory valuation & turnover' }, { value: 'exp', label: 'Operating expenses' }]} />
      {tab === 'pnl' && <PnL range={range} rate={Number(L.setting?.usd_rate || 3500)} />}
      {tab === 'inv' && <Valuation range={range} />}
      {tab === 'exp' && <Expenses range={range} />}
    </Page>
  );
}

function PnL({ range, rate }) {
  const { data: p } = useData(() => api.rpc('get_pnl', { p_from: range[0], p_to: range[1] }), [range[0], range[1]]);
  if (!p) return <Spinner />;
  const productNet = num(p.product_sales) - num(p.discounts);
  const services = num(p.clinic_revenue) + num(p.lab_revenue);
  const netRevenue = productNet + services - num(p.returns) + num(p.exchange_sales);
  const cogs = num(p.cogs_sales) + num(p.cogs_exchanges) - num(p.cogs_returns);
  const gross = netRevenue - cogs;
  const opInc = gross - num(p.inventory_losses) - num(p.expense_total);
  const lines = [
    ['Pharmacy & kit sales (gross)', p.product_sales, 1], ['Less: discounts', -num(p.discounts), 1], ['Clinic consultation fees', p.clinic_revenue, 1], ['Laboratory fees', p.lab_revenue, 1],
    ['Less: customer returns', -num(p.returns), 1], ['Add: exchange replacements', p.exchange_sales, 1], ['Net revenue', netRevenue, 0, 'total'],
    ['Cost of goods sold', -num(p.cogs_sales), 1], ['Cost of exchange replacements', -num(p.cogs_exchanges), 1], ['Cost returned to stock', p.cogs_returns, 1], ['Gross profit', gross, 0, 'total'],
    ['Inventory losses (expired, damaged, count variance)', -num(p.inventory_losses), 1],
    ...p.expenses.map((e) => [e.category, -num(e.amount), 1]), ['Total operating expenses', -num(p.expense_total), 0, 'sub'],
    ['Net operating income (before donations)', opInc, 0, 'grand'],
  ];
  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_1.1fr]">
      <Card title={`Profit & loss · ${d(range[0])} – ${d(range[1])}`} pad={false}>
        <table className="min-w-full text-sm">
          <thead className="text-xs uppercase text-slate-500"><tr><th className="px-4 py-2 text-left" /><th className="px-4 py-2 text-right">UGX</th><th className="px-4 py-2 text-right">USD</th><th className="px-4 py-2 text-right">% rev</th></tr></thead>
          <tbody>{lines.map(([k, v, indent, kind]) => (
            <tr key={k} className={cx(kind === 'total' && 'border-t border-slate-300 font-black', kind === 'sub' && 'font-bold', kind === 'grand' && 'border-t-2 border-brand-600 bg-brand-50 text-base font-black')}>
              <td className={cx('px-4 py-1.5', indent && 'pl-8 text-slate-700')}>{k}</td>
              <td className={cx('px-4 py-1.5 text-right tabular-nums', num(v) < 0 && 'text-red-700')}>{num(v) < 0 ? `(${fmt(-num(v))})` : fmt(v)}</td>
              <td className="px-4 py-1.5 text-right tabular-nums text-slate-500">{num(v) < 0 ? `(${usd(-num(v), rate)})` : usd(num(v), rate)}</td>
              <td className="px-4 py-1.5 text-right tabular-nums text-slate-500">{netRevenue ? pct((100 * num(v)) / netRevenue, 1) : ''}</td>
            </tr>))}</tbody>
        </table>
        <p className="px-4 pb-3 text-xs text-slate-500">VAT collected {money(p.tax_collected)} is a liability to URA, not revenue. Scrap absorbed into kit cost: {money(p.scrap_cost_absorbed)}. Donations are recorded outside this operating statement.</p>
      </Card>
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <Stat label="Net revenue" value={money(netRevenue)} tone="brand" /><Stat label="Gross margin" value={pct(netRevenue ? (100 * gross) / netRevenue : null)} sub={money(gross)} />
          <Stat label="Operating expenses" value={money(p.expense_total)} /><Stat label="Net operating income" value={money(opInc)} tone={opInc >= 0 ? 'good' : 'bad'} sub={opInc < 0 ? 'Funding gap covered by donations' : ''} />
        </div>
        <Card title="Monthly revenue, cost of goods and operating expenses">
          <Bars data={p.monthly.map((m) => ({ ...m, revenue: num(m.revenue), cogs: num(m.cogs), expenses: num(m.expenses) }))} x="month"
            series={[{ key: 'revenue', label: 'Revenue' }, { key: 'cogs', label: 'Cost of goods' }, { key: 'expenses', label: 'Operating expenses' }]} xFmt={(v) => v?.slice(2)} height={300} />
        </Card>
      </div>
    </div>
  );
}

function Valuation({ range }) {
  const { data: v } = useData(() => api.rpc('get_inventory_valuation', { p_from: range[0], p_to: range[1] }), [range[0], range[1]]);
  if (!v) return <Spinner />;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Inventory value" value={money(v.total_value)} tone="brand" sub="weighted-average cost" />
        <Stat label="Inventory turnover" value={`${fmt(v.turnover, 2)}×`} sub="annualised COGS ÷ inventory value" />
        <Stat label="Days of inventory on hand" value={fmt(v.days_on_hand, 1)} sub="value ÷ COGS per day" />
        <Stat label="COGS in period" value={money(v.period_cogs)} sub={`${v.period_days} days · annualised ${money(v.annualized_cogs)}`} />
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Value by location"><RankBars data={v.by_location.map((x) => ({ name: x.location, revenue: num(x.value) }))} /></Card>
        <Card title="Value by category"><RankBars data={v.by_category.map((x) => ({ name: x.category, revenue: num(x.value) }))} /></Card>
      </div>
      <Card title="Item valuation & turnover" pad={false}>
        <Table rows={v.items} csv="inventory-valuation.csv" dense initialSort={{ key: 'value', dir: 'desc' }} columns={[
          { key: 'name', label: 'Item', render: (r) => <b>{r.name}</b> }, { key: 'category', label: 'Category' },
          { key: 'qty', label: 'On hand', align: 'right', render: (r) => fmt(r.qty) }, { key: 'avg_cost', label: 'Avg cost', align: 'right', render: (r) => fmt(r.avg_cost, 2) },
          { key: 'value', label: 'Value', align: 'right', render: (r) => money(r.value) }, { key: 'cogs', label: 'COGS (period)', align: 'right', render: (r) => money(r.cogs) },
          { key: 'turnover', label: 'Turnover', align: 'right', render: (r) => (r.turnover === null ? '—' : <span className={num(r.turnover) < 2 ? 'text-amber-700' : ''}>{fmt(r.turnover, 1)}×</span>) },
        ]} />
      </Card>
    </div>
  );
}

function Expenses({ range }) {
  const [edit, setEdit] = useState(null);
  const { data } = useData(() => api.select('expenses', { gte: { expense_date: range[0] }, lte: { expense_date: range[1] }, order: 'expense_date desc' }), [range[0], range[1]]);
  if (!data) return <Spinner />;
  const fields = [{ key: 'expense_date', label: 'Date', type: 'date', default: todayISO() }, { key: 'category', label: 'Category' }, { key: 'amount', label: 'Amount (UGX)', type: 'number' }, { key: 'description', label: 'Description', wide: true }];
  return (
    <Card title="Operating expenses (categories from Rosbren’s financial workbook)" pad={false} actions={<Btn size="sm" icon={Plus} onClick={() => setEdit({})}>Record expense</Btn>}>
      <Table rows={data} csv="expenses.csv" onRowClick={setEdit} columns={[
        { key: 'expense_date', label: 'Date', render: (r) => d(r.expense_date) }, { key: 'category', label: 'Category' }, { key: 'description', label: 'Description' },
        { key: 'amount', label: 'Amount', align: 'right', render: (r) => money(r.amount) }]} />
      {edit && <RecordForm table="expenses" record={edit.id ? edit : null} fields={fields} title="Expense" onClose={() => setEdit(null)} />}
    </Card>
  );
}
