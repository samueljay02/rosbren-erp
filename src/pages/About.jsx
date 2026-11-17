import { Page, Card, Badge } from '../components/ui';
import { ArrowRight } from 'lucide-react';

const FLOW = [
  ['Customers & portal', 'Sales orders', 'Allocations, backorders'],
  ['Sales orders', 'MRP', 'Gross requirements'],
  ['Bills of material', 'MRP', 'Dependent demand'],
  ['MRP', 'Production orders', 'Planned kit builds'],
  ['MRP / ROP / EOQ', 'Purchase orders', 'Planned purchases'],
  ['Purchase orders', 'Inventory', 'Receipts + weighted-avg cost'],
  ['Purchase orders', 'Supplier scorecards', 'On-time, lead time, fill rate, bills'],
  ['Production orders', 'Inventory', 'Components out, kits in at rolled-up cost'],
  ['POS / fulfilment', 'Inventory', 'Stock out at location'],
  ['POS / fulfilment', 'Financials', 'Revenue + COGS'],
  ['Returns & exchanges', 'Inventory & Financials', 'Reversals, quality write-offs'],
  ['Sales history', 'Reorder points & EOQ', 'Average usage & variability'],
];

export default function About() {
  return (
    <Page title="About this System" subtitle="How the Rosbren ERP is built, where its data came from, and how the modules connect.">
      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Tools & technology used">
          <dl className="space-y-3 text-sm">
            <Row k="AI coding tool" v={<>Built with <b>Claude</b> (Anthropic), working as an agentic coding assistant: it wrote the database schema, business-logic functions, data generator and React front-end from the assignment requirements and Rosbren’s spreadsheets. Every module was then tested by running real transactions against a live PostgreSQL engine and checking the numbers.</>} />
            <Row k="Database" v={<><b>Supabase</b> (managed <b>PostgreSQL</b>, free tier): tables, PL/pgSQL functions for every transaction, Row-Level Security, Realtime change feeds.</>} />
            <Row k="Authentication" v={<><b>Supabase Auth</b>: email + password (bcrypt), TOTP multi-factor (AAL2), password reset by email.</>} />
            <Row k="Front-end" v={<><b>React 19</b> + <b>Vite</b>, <b>Tailwind CSS</b>, Recharts (charts), lucide-react (icons).</>} />
            <Row k="Barcodes" v={<><b>JsBarcode</b> (printing EAN-13 / Code 128), <b>html5-qrcode</b> (phone/laptop camera scanning); USB scanners work as keyboard input.</>} />
            <Row k="Hosting" v={<>Code on <b>GitHub</b> (private repository), deployed free on <b>Vercel</b> (HTTPS, needed for camera scanning).</>} />
            <Row k="Testing" v={<>PGlite (PostgreSQL compiled to WebAssembly) runs the same SQL offline for automated tests; Playwright browser tests.</>} />
          </dl>
        </Card>
        <Card title="Where the starting data came from">
          <ul className="list-disc space-y-2 pl-5 text-sm text-slate-700">
            <li><b>Item master</b> — Rosbren’s <i>Pharmacy Supplies 2026</i> workbook: real product names, wholesale prices and shelf numbers. Duplicate and misspelled entries were merged; retail price = wholesale × 1.5 (the clinic’s markup in the workbook).</li>
            <li><b>Revenue pattern</b> — <i>Financials 2026</i>: monthly Pharmacy, Clinic and Lab revenue were used as targets, so generated sales add up to the clinic’s real monthly totals.</li>
            <li><b>Daily rhythm</b> — <i>Visits</i> workbook: each day’s sales volume follows Rosbren’s recorded daily patient visits.</li>
            <li><b>Operating expenses</b> — the real expense categories and monthly amounts (rent, payroll, utilities, travel…).</li>
            <li><b>Seasonality</b> — malaria and diarrhoea items rise in Uganda’s rainy seasons (Mar–May, Sep–Nov); coughs and colds in Jun–Aug.</li>
            <li><b>Generated</b> — individual transactions, purchase orders with supplier-specific reliability, production runs with realistic scrap, returns and adjustments. Suppliers and customers are fictional.</li>
          </ul>
        </Card>
      </div>
      <Card title="How the modules connect" className="mt-4">
        <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
          {FLOW.map(([a, b, x], i) => (
            <div key={i} className="flex items-center gap-2 rounded-lg border border-slate-200 p-2 text-sm">
              <Badge color="brand">{a}</Badge><ArrowRight size={14} className="shrink-0 text-slate-400" /><Badge color="blue">{b}</Badge>
              <span className="text-xs text-slate-500">{x}</span>
            </div>))}
        </div>
        <p className="mt-3 text-sm text-slate-600">Every transaction is a single atomic database call: a sale either updates stock, cost, revenue and the ledger together, or nothing changes. Other users’ screens refresh within a second through Supabase Realtime.</p>
      </Card>
    </Page>
  );
}
const Row = ({ k, v }) => <div className="grid grid-cols-[120px_1fr] gap-3"><dt className="font-bold text-slate-500">{k}</dt><dd className="text-slate-800">{v}</dd></div>;
