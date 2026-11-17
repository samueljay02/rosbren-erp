import { useState } from 'react';
import { Printer, Trash2 } from 'lucide-react';
import { useLookups } from '../lib/hooks';
import { Page, Card, Btn, Input, Select } from '../components/ui';
import { ScanInput } from '../components/Scanner';
import { BarcodeSvg } from '../components/Receipt';
import { fmt } from '../lib/format';

export default function Labels() {
  const L = useLookups();
  const [list, setList] = useState([]);
  const [cat, setCat] = useState('');
  const add = (it, n = 1) => setList((l) => (l.some((x) => x.item.id === it.id) ? l : [...l, { item: it, n }]));
  const cats = [...new Set((L.items || []).filter((i) => i.item_type !== 'service').map((i) => i.category))].sort();
  const labels = list.flatMap((x) => Array.from({ length: Number(x.n) || 0 }, () => x.item));
  return (
    <Page title="Barcode Labels" subtitle="Print EAN-13 shelf and item labels. They scan with a USB scanner or a phone camera at the POS, receiving and stock counts."
      actions={<Btn icon={Printer} disabled={!labels.length} onClick={() => window.print()}>Print {labels.length} labels</Btn>}
      concept={<p>Every item carries a unique <b>EAN-13</b> barcode in the GS1 “restricted circulation” range (prefix <b>20</b>), meant for in-house labelling. The 13th digit is a check digit calculated by the database, so mis-scans are rejected.</p>}>
      <div className="grid gap-4 print:block lg:grid-cols-[360px_1fr]">
        <Card title="Choose items" className="print:hidden">
          <div className="space-y-3">
            <ScanInput onItem={(it) => add(it)} filter={(i) => i.item_type !== 'service'} autoFocus={false} />
            <div className="flex gap-2"><Select value={cat} onChange={(e) => setCat(e.target.value)} placeholder="Add a whole category…" options={cats.map((c) => ({ value: c, label: c }))} />
              <Btn variant="secondary" disabled={!cat} onClick={() => L.items.filter((i) => i.category === cat && i.active).forEach((i) => add(i))}>Add</Btn></div>
            <Btn variant="ghost" size="sm" onClick={() => ['PH-001', 'PH-010', 'KIT-MAL', 'KIT-MAMA', 'PH-050', 'HY-001', 'SU-009', 'PH-040'].forEach((s) => { const it = L.items.find((i) => i.sku === s); if (it) add(it, 2); })}>Add demo set (8 items × 2)</Btn>
            <ul className="divide-y divide-slate-100 text-sm">
              {list.map((x, i) => <li key={x.item.id} className="flex items-center gap-2 py-1.5"><span className="flex-1">{x.item.name}</span>
                <Input type="number" min="0" className="w-16" value={x.n} onChange={(e) => setList(list.map((y, j) => (j === i ? { ...y, n: e.target.value } : y)))} />
                <button onClick={() => setList(list.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 size={15} className="text-slate-400" /></button></li>)}
            </ul>
          </div>
        </Card>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 print:grid-cols-3 print:gap-1">
          {labels.map((it, i) => (
            <div key={i} className="flex break-inside-avoid flex-col items-center rounded border border-dashed border-slate-300 bg-white p-2 text-center print:border-slate-400">
              <div className="line-clamp-2 text-[11px] font-black leading-tight">{it.name}</div>
              <BarcodeSvg value={it.barcode} format="EAN13" height={38} width={1.5} fontSize={11} />
              <div className="flex w-full justify-between text-[10px] text-slate-600"><span>{it.sku}</span><span>Shelf {it.shelf || '—'}</span><b>UGX {fmt(it.price)}</b></div>
            </div>))}
          {!labels.length && <p className="col-span-3 p-10 text-center text-sm text-slate-500 print:hidden">Add items on the left to preview their labels.</p>}
        </div>
      </div>
    </Page>
  );
}
