import { useMemo, useState, useEffect } from 'react';
import { X, ChevronUp, ChevronDown, Search, Loader2, AlertTriangle, Info, Download } from 'lucide-react';
import { downloadCSV } from '../lib/format';

export const cx = (...a) => a.filter(Boolean).join(' ');

export function Page({ title, subtitle, actions, children, concept }) {
  return (
    <div className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6 lg:px-8">
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-brand-800">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-slate-600">{subtitle}</p>}
        </div>
        {actions && <div className="flex flex-wrap items-center gap-2 print:hidden">{actions}</div>}
      </div>
      {concept && <Concept>{concept}</Concept>}
      {children}
    </div>
  );
}

// "How it works" explainer — helps the team explain ERP/MRP concepts during the demo
export function Concept({ children }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mb-5 rounded-lg border border-brand-100 bg-brand-50/60 text-sm text-brand-900 print:hidden">
      <button onClick={() => setOpen(!open)} className="flex w-full items-center gap-2 px-4 py-2 text-left font-bold">
        <Info size={16} className="text-brand-500" /> How this works {open ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
      </button>
      {open && <div className="space-y-2 px-4 pb-3 leading-relaxed text-brand-900/90">{children}</div>}
    </div>
  );
}

export function Card({ title, actions, children, className, pad = true }) {
  return (
    <section className={cx('rounded-xl border border-slate-200 bg-white shadow-sm', className)}>
      {(title || actions) && (
        <header className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-4 py-3">
          <h2 className="text-sm font-bold uppercase tracking-wide text-slate-700">{title}</h2>
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </header>
      )}
      <div className={pad ? 'p-4' : ''}>{children}</div>
    </section>
  );
}

export function Stat({ label, value, sub, tone = 'default', icon: Icon, onClick }) {
  const tones = { default: 'text-slate-900', good: 'text-emerald-700', warn: 'text-amber-700', bad: 'text-red-700', brand: 'text-brand-700' };
  return (
    <div onClick={onClick} className={cx('rounded-xl border border-slate-200 bg-white p-4 shadow-sm', onClick && 'cursor-pointer hover:border-brand-300')}>
      <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wide text-slate-500">{Icon && <Icon size={14} />}{label}</div>
      <div className={cx('mt-1 text-2xl font-black tabular-nums', tones[tone])}>{value}</div>
      {sub && <div className="mt-0.5 text-xs text-slate-500">{sub}</div>}
    </div>
  );
}

export function Btn({ children, variant = 'primary', size = 'md', className, icon: Icon, busy, ...p }) {
  const v = {
    primary: 'bg-brand-600 text-white hover:bg-brand-700 shadow-sm',
    accent: 'bg-accent-400 text-brand-900 hover:bg-accent-500 shadow-sm',
    secondary: 'bg-white text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50',
    danger: 'bg-red-600 text-white hover:bg-red-700',
    ghost: 'text-slate-600 hover:bg-slate-100',
  }[variant];
  const s = { sm: 'px-2.5 py-1.5 text-xs', md: 'px-3.5 py-2 text-sm', lg: 'px-5 py-3 text-base' }[size];
  return (
    <button {...p} disabled={p.disabled || busy}
      className={cx('inline-flex items-center justify-center gap-1.5 rounded-lg font-bold transition disabled:cursor-not-allowed disabled:opacity-50', v, s, className)}>
      {busy ? <Loader2 size={16} className="animate-spin" /> : Icon && <Icon size={size === 'sm' ? 14 : 16} />}{children}
    </button>
  );
}

export function Field({ label, hint, children, className }) {
  return (
    <label className={cx('block', className)}>
      {label && <span className="mb-1 block text-xs font-bold uppercase tracking-wide text-slate-600">{label}</span>}
      {children}
      {hint && <span className="mt-1 block text-xs text-slate-500">{hint}</span>}
    </label>
  );
}
const inputCls = 'w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-200 disabled:bg-slate-100';
const sized = (c) => (/\bw-/.test(c || '') ? inputCls.replace('w-full ', '') : inputCls);
export const Input = (p) => <input {...p} className={cx(sized(p.className), p.className)} />;
export const Textarea = (p) => <textarea rows={2} {...p} className={cx(inputCls, p.className)} />;
export function Select({ options, placeholder, ...p }) {
  return (
    <select {...p} className={cx(sized(p.className), p.className)}>
      {placeholder !== undefined && <option value="">{placeholder}</option>}
      {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  );
}

const BADGE = {
  green: 'bg-emerald-50 text-emerald-700 ring-emerald-200', red: 'bg-red-50 text-red-700 ring-red-200',
  amber: 'bg-amber-50 text-amber-800 ring-amber-200', blue: 'bg-sky-50 text-sky-700 ring-sky-200',
  gray: 'bg-slate-100 text-slate-700 ring-slate-200', brand: 'bg-brand-50 text-brand-700 ring-brand-200', violet: 'bg-violet-50 text-violet-700 ring-violet-200',
};
export const Badge = ({ color = 'gray', children, className }) =>
  <span className={cx('inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-bold ring-1 ring-inset', BADGE[color], className)}>{children}</span>;
const STATUS = {
  'Order Placed': 'blue', Fulfilled: 'violet', Closed: 'gray', Cancelled: 'red', Draft: 'gray', 'Order Sent': 'blue',
  'Partially Received': 'amber', Received: 'green', Planned: 'gray', 'In Progress': 'amber', Completed: 'green', Prepared: 'green',
  Keep: 'green', Watch: 'amber', Replace: 'red', New: 'gray', Return: 'amber', Exchange: 'violet',
};
export const StatusBadge = ({ status }) => <Badge color={STATUS[status] || 'gray'}>{status}</Badge>;

export function Modal({ open, onClose, title, children, wide, footer }) {
  useEffect(() => {
    if (!open) return;
    const h = (e) => e.key === 'Escape' && onClose?.();
    window.addEventListener('keydown', h); return () => window.removeEventListener('keydown', h);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-slate-900/50 p-4 sm:pt-16 print:static print:bg-white print:p-0" onMouseDown={(e) => e.target === e.currentTarget && onClose?.()}>
      <div className={cx('w-full rounded-xl bg-white shadow-2xl print:shadow-none', wide === 'xl' ? 'max-w-6xl' : wide ? 'max-w-4xl' : 'max-w-lg')} role="dialog" aria-modal="true">
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3 print:hidden">
          <h3 className="text-lg font-black text-brand-800">{title}</h3>
          <button onClick={onClose} className="rounded p-1 text-slate-500 hover:bg-slate-100" aria-label="Close"><X size={18} /></button>
        </div>
        <div className="p-5">{children}</div>
        {footer && <div className="flex justify-end gap-2 border-t border-slate-100 px-5 py-3 print:hidden">{footer}</div>}
      </div>
    </div>
  );
}

export function Tabs({ tabs, value, onChange }) {
  return (
    <div className="mb-4 flex flex-wrap gap-1 border-b border-slate-200 print:hidden">
      {tabs.map((t) => (
        <button key={t.value} onClick={() => onChange(t.value)}
          className={cx('-mb-px border-b-2 px-4 py-2 text-sm font-bold transition',
            value === t.value ? 'border-brand-600 text-brand-700' : 'border-transparent text-slate-500 hover:text-slate-800')}>
          {t.label}{t.count !== undefined && <span className="ml-1.5 rounded-full bg-slate-100 px-1.5 text-xs text-slate-600">{t.count}</span>}
        </button>
      ))}
    </div>
  );
}

export const Spinner = ({ label = 'Loading…' }) => <div className="flex items-center gap-2 p-6 text-sm text-slate-500"><Loader2 className="animate-spin" size={18} />{label}</div>;
export const Empty = ({ children }) => <div className="p-8 text-center text-sm text-slate-500">{children}</div>;
export const ErrorBox = ({ error }) => error ? <div className="mb-4 flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800"><AlertTriangle size={16} className="mt-0.5" />{error}</div> : null;

// Sortable, searchable data table with CSV export
export function Table({ columns, rows, search = true, initialSort, onRowClick, empty = 'No records', csv, maxHeight, rowClass, dense, pageSize = 100 }) {
  const [q, setQ] = useState('');
  const [sort, setSort] = useState(initialSort || null);
  const [limit, setLimit] = useState(pageSize);
  const filtered = useMemo(() => {
    let r = rows || [];
    if (q) {
      const s = q.toLowerCase();
      r = r.filter((row) => columns.some((c) => { const v = c.search ? c.search(row) : row[c.key]; return v !== null && v !== undefined && String(v).toLowerCase().includes(s); }));
    }
    if (sort) {
      const col = columns.find((c) => c.key === sort.key);
      const get = col?.sortValue || ((x) => x[sort.key]);
      r = [...r].sort((a, b) => {
        const va = get(a), vb = get(b);
        if (va === vb) return 0; if (va === null || va === undefined) return 1; if (vb === null || vb === undefined) return -1;
        const n = typeof va === 'number' || (!isNaN(va) && !isNaN(vb) && va !== '' && vb !== '') ? Number(va) - Number(vb) : String(va).localeCompare(String(vb));
        return sort.dir === 'asc' ? n : -n;
      });
    }
    return r;
  }, [rows, q, sort, columns]);
  return (
    <div>
      {(search || csv) && (
        <div className="flex items-center gap-2 border-b border-slate-100 px-3 py-2 print:hidden">
          {search && <div className="relative flex-1"><Search size={15} className="absolute left-2.5 top-2.5 text-slate-400" />
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search…" className="w-full max-w-xs rounded-md border border-slate-200 py-1.5 pl-8 pr-2 text-sm focus:border-brand-400 focus:outline-none" /></div>}
          <span className="text-xs text-slate-500">{filtered.length} rows</span>
          {csv && <button onClick={() => downloadCSV(csv, filtered, columns.filter((c) => !c.noExport).map((c) => ({ key: c.key, label: c.label, csv: c.csv })))}
            className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-bold text-brand-700 hover:bg-brand-50"><Download size={13} />CSV</button>}
        </div>
      )}
      <div className="overflow-auto" style={maxHeight ? { maxHeight } : undefined}>
        <table className="min-w-full text-sm">
          <thead className="sticky top-0 z-10 bg-slate-50 text-left text-xs font-bold uppercase tracking-wide text-slate-600">
            <tr>{columns.map((c) => (
              <th key={c.key} className={cx('whitespace-nowrap px-3 py-2', c.align === 'right' && 'text-right', c.sortable !== false && 'cursor-pointer select-none hover:text-slate-900')}
                onClick={() => c.sortable !== false && setSort((s) => ({ key: c.key, dir: s?.key === c.key && s.dir === 'desc' ? 'asc' : 'desc' }))}>
                {c.label}{sort?.key === c.key && (sort.dir === 'asc' ? ' ▲' : ' ▼')}
              </th>))}</tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {filtered.slice(0, limit).map((r, i) => (
              <tr key={r.id ?? i} onClick={onRowClick ? () => onRowClick(r) : undefined}
                className={cx(onRowClick && 'cursor-pointer hover:bg-brand-50/50', rowClass?.(r))}>
                {columns.map((c) => <td key={c.key} className={cx('px-3', dense ? 'py-1.5' : 'py-2', c.align === 'right' && 'text-right tabular-nums', c.className)}>{c.render ? c.render(r) : r[c.key]}</td>)}
              </tr>))}
          </tbody>
        </table>
        {!filtered.length && <Empty>{empty}</Empty>}
        {filtered.length > limit && <div className="p-2 text-center"><Btn size="sm" variant="ghost" onClick={() => setLimit(limit + pageSize * 3)}>Show more ({filtered.length - limit} remaining)</Btn></div>}
      </div>
    </div>
  );
}

export function DateRange({ from, to, onChange, presets = true }) {
  const set = (days) => {
    const t = new Date(); const f = new Date(); f.setDate(t.getDate() - days + 1);
    const iso = (x) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
    onChange(iso(f), iso(t));
  };
  return (
    <div className="flex flex-wrap items-center gap-2">
      {presets && [['7D', 7], ['30D', 30], ['90D', 90], ['6M', 182]].map(([l, n]) =>
        <button key={l} onClick={() => set(n)} className="rounded-md px-2 py-1 text-xs font-bold text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50">{l}</button>)}
      <input type="date" value={from} onChange={(e) => onChange(e.target.value, to)} className="rounded-md border border-slate-300 px-2 py-1 text-sm" aria-label="From date" />
      <span className="text-slate-400">→</span>
      <input type="date" value={to} onChange={(e) => onChange(from, e.target.value)} className="rounded-md border border-slate-300 px-2 py-1 text-sm" aria-label="To date" />
    </div>
  );
}
