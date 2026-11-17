import { useState } from 'react';
import { Pencil, Plus, Trash2 } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups, useAction } from '../lib/hooks';
import { Page, Card, Btn, Input, Modal, Spinner, Badge, Select } from '../components/ui';
import { ItemSelect } from '../components/Scanner';
import { money, fmt, num, pct } from '../lib/format';

export default function BOM() {
  const L = useLookups();
  const [edit, setEdit] = useState(null);
  const { data: bom } = useData(() => api.select('bom_lines', { order: 'id' }));
  if (!bom || !L.ready) return <Spinner />;
  const parents = L.items.filter((i) => i.item_type === 'kit' || bom.some((b) => b.parent_item_id === i.id));
  const usedIn = (id) => bom.filter((b) => b.component_item_id === id).map((b) => L.itemById[b.parent_item_id]?.sku);
  return (
    <Page title="Bills of Material" subtitle={`${parents.length} parent items assembled in-house from purchased components.`}
      actions={<Btn icon={Plus} onClick={() => setEdit({ parent: null, lines: [] })}>New BOM</Btn>}
      concept={<><p>A <b>bill of materials</b> lists every component and the quantity needed per one parent. It drives three things: <b>production</b> (components issued per order), <b>assemble-to-order at POS</b>, and <b>MRP</b> (parent demand × qty-per = component <i>dependent demand</i>).</p>
        <p>Shared components such as the kit bag and dispensing envelope appear in several BOMs — MRP adds their requirements together.</p></>}>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {parents.map((p) => {
          const lines = bom.filter((b) => b.parent_item_id === p.id);
          const cost = lines.reduce((a, b) => a + num(b.qty_per) * num(L.itemById[b.component_item_id]?.avg_cost), 0);
          return (
            <Card key={p.id} title={p.name} actions={<Btn size="sm" variant="ghost" icon={Pencil} onClick={() => setEdit({ parent: p.id, lines: lines.map((l) => ({ component_item_id: l.component_item_id, qty_per: l.qty_per })) })}>Edit</Btn>}>
              <table className="w-full text-sm"><tbody className="divide-y divide-slate-100">
                {lines.map((l) => { const c = L.itemById[l.component_item_id]; return (
                  <tr key={l.id}><td className="py-1.5">{c?.name}{usedIn(c?.id).length > 1 && <Badge color="gray" className="ml-1">shared</Badge>}</td><td className="py-1.5 text-right font-bold">× {fmt(l.qty_per, 2)}</td><td className="py-1.5 pl-2 text-right text-slate-500">{fmt(num(l.qty_per) * num(c?.avg_cost))}</td></tr>); })}
              </tbody></table>
              <div className="mt-3 grid grid-cols-3 gap-2 rounded-lg bg-slate-50 p-2 text-center text-xs">
                <div><div className="text-slate-500">Rolled-up cost</div><b>{money(cost)}</b></div>
                <div><div className="text-slate-500">Price</div><b>{money(p.price)}</b></div>
                <div><div className="text-slate-500">Margin</div><b>{num(p.price) ? pct((100 * (num(p.price) - cost)) / num(p.price), 0) : '—'}</b></div>
              </div>
            </Card>);
        })}
      </div>
      {edit && <EditBom init={edit} onClose={() => setEdit(null)} />}
    </Page>
  );
}

function EditBom({ init, onClose }) {
  const L = useLookups();
  const [parent, setParent] = useState(init.parent);
  const [lines, setLines] = useState(init.lines);
  const [run, busy] = useAction();
  const cost = lines.reduce((a, b) => a + num(b.qty_per) * num(L.itemById[b.component_item_id]?.avg_cost), 0);
  return (
    <Modal open onClose={onClose} title={parent ? `BOM — ${L.itemById[parent]?.name}` : 'New bill of materials'} wide footer={<><Btn variant="secondary" onClick={onClose}>Cancel</Btn>
      <Btn busy={busy} disabled={!parent || !lines.length || lines.some((l) => !l.component_item_id)} onClick={async () => (await run(() => api.rpc('save_bom', { p_parent: parent, p_lines: lines.map((l) => ({ ...l, qty_per: num(l.qty_per) })) }), 'Bill of materials saved')) && (L.reload(), onClose())}>Save BOM</Btn></>}>
      {!init.parent && <div className="mb-3"><div className="mb-1 text-xs font-bold uppercase text-slate-600">Parent item</div>
        <Select value={parent || ''} onChange={(e) => setParent(Number(e.target.value))} placeholder="Choose the item to be assembled…" options={L.items.filter((i) => i.item_type !== 'service').map((i) => ({ value: i.id, label: i.name }))} /></div>}
      <table className="w-full text-sm"><thead className="text-left text-xs uppercase text-slate-500"><tr><th className="py-1">Component</th><th className="w-28 py-1">Qty per</th><th className="w-24 py-1 text-right">Cost</th><th /></tr></thead>
        <tbody>{lines.map((l, i) => <tr key={i}><td className="py-1 pr-2"><ItemSelect value={l.component_item_id} onChange={(v) => setLines(lines.map((x, j) => (j === i ? { ...x, component_item_id: v } : x)))} filter={(it) => it.item_type === 'purchased' && it.id !== parent} /></td>
          <td className="py-1"><Input type="number" step="any" value={l.qty_per} onChange={(e) => setLines(lines.map((x, j) => (j === i ? { ...x, qty_per: e.target.value } : x)))} /></td>
          <td className="py-1 text-right">{fmt(num(l.qty_per) * num(L.itemById[l.component_item_id]?.avg_cost))}</td>
          <td className="pl-2"><button onClick={() => setLines(lines.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 size={15} className="text-slate-400" /></button></td></tr>)}</tbody></table>
      <div className="mt-3 flex items-center justify-between"><Btn size="sm" variant="secondary" icon={Plus} onClick={() => setLines([...lines, { component_item_id: null, qty_per: 1 }])}>Add component</Btn><b>Rolled-up cost {money(cost)}</b></div>
    </Modal>
  );
}
