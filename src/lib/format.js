export const num = (v) => (v === null || v === undefined || v === '' ? 0 : Number(v));
const nf0 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 });
const nf2 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });
export const fmt = (v, d = 0) => (v === null || v === undefined || v === '' || Number.isNaN(Number(v)) ? '—' : (d === 0 ? nf0 : d === 1 ? nf1 : nf2).format(Number(v)));
export const money = (v) => (v === null || v === undefined ? '—' : `UGX ${nf0.format(Math.round(Number(v)))}`);
export const usd = (v, rate = 3500) => `$${nf0.format(Number(v) / rate)}`;
export const pct = (v, d = 1) => (v === null || v === undefined ? '—' : `${Number(v).toFixed(d)}%`);
export const compact = (v) => {
  const n = Number(v); const a = Math.abs(n);
  if (a >= 1e6) return (n / 1e6).toFixed(a >= 1e7 ? 1 : 2) + 'M';
  if (a >= 1e3) return (n / 1e3).toFixed(a >= 1e4 ? 0 : 1) + 'k';
  return nf0.format(n);
};
export const d = (v) => (v ? new Date(String(v).length === 10 ? v + 'T00:00:00' : v).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '—');
export const dShort = (v) => (v ? new Date(String(v).length === 10 ? v + 'T00:00:00' : v).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' }) : '—');
export const dt = (v) => (v ? new Date(v).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');
export const todayISO = () => { const x = new Date(); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
export const addDaysISO = (s, n) => { const x = new Date(s + 'T00:00:00'); x.setDate(x.getDate() + n); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
export const daysBetween = (a, b) => Math.round((new Date(b + 'T00:00:00') - new Date(a + 'T00:00:00')) / 86400000);
export function downloadCSV(filename, rows, columns) {
  const cols = columns || Object.keys(rows[0] || {}).map((k) => ({ key: k, label: k }));
  const esc = (v) => { const s = v === null || v === undefined ? '' : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const csv = [cols.map((c) => esc(c.label)).join(','), ...rows.map((r) => cols.map((c) => esc(typeof c.csv === 'function' ? c.csv(r) : r[c.key])).join(','))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
  a.download = filename; a.click();
}
