import { useState } from 'react';
import { Plus } from 'lucide-react';
import { useLookups } from '../lib/hooks';
import { Page, Card, Btn, Table, Badge, Spinner } from '../components/ui';
import RecordForm from '../components/RecordForm';
import { fmt, num, pct } from '../lib/format';

export default function Items() {
  const L = useLookups();
  const [edit, setEdit] = useState(null);
  if (!L.ready) return <Spinner />;
  const fields = [
    { key: 'sku', label: 'SKU' }, { key: 'barcode', label: 'Barcode (EAN-13)', hint: 'Scan an existing barcode or keep the generated one' },
    { key: 'name', label: 'Name', wide: true }, { key: 'category', label: 'Category' }, { key: 'uom', label: 'Unit of measure', default: 'pack' },
    { key: 'item_type', label: 'Type', type: 'select', default: 'purchased', options: [{ value: 'purchased', label: 'Purchased' }, { value: 'kit', label: 'Kit (made in-house, needs BOM)' }, { value: 'service', label: 'Service (no stock)' }] },
    { key: 'price', label: 'Selling price (UGX)', type: 'number' },
    { key: 'avg_cost', label: 'Average cost (UGX)', type: 'number', hint: 'Updated automatically by receipts & production', readOnly: !!edit?.id },
    { key: 'reorder_point', label: 'Reorder point', type: 'number', hint: 'Recalculate on Reorder Points & EOQ' },
    { key: 'lead_time_days', label: 'Lead time (days)', type: 'number', default: 7 },
    { key: 'preferred_supplier_id', label: 'Preferred supplier', type: 'select', numeric: true, placeholder: '— none (made in-house)', options: L.suppliers.map((s) => ({ value: s.id, label: s.name })) },
    { key: 'shelf', label: 'Shelf / bin' },
    { key: 'taxable', label: 'VAT', type: 'checkbox', checkLabel: 'Taxable (VAT applies)' },
    { key: 'sellable', label: 'Sellable', type: 'checkbox', checkLabel: 'Can be sold', default: true },
    { key: 'active', label: 'Active', type: 'checkbox', checkLabel: 'Active', default: true },
    { key: 'description', label: 'Description', type: 'textarea', wide: true },
  ];
  const newBarcode = () => { const base = '20' + String(Date.now()).slice(-10); let s = 0; for (let i = 0; i < 12; i++) s += Number(base[i]) * (i % 2 ? 3 : 1); return base + ((10 - (s % 10)) % 10); };
  return (
    <Page title="Items & Pricing" subtitle={`${L.items.length} items: medicines and supplies (from the Rosbren pharmacy workbook, cleaned), in-house kits and clinic services.`}
      actions={<Btn icon={Plus} onClick={() => setEdit({ barcode: newBarcode(), sku: '', active: true, sellable: true })}>New item</Btn>}
      concept={<p>The item master is the single source of truth for SKU, barcode, price, cost, reorder point and lead time. The original spreadsheet had duplicate names (e.g. “Paracetamol” on 9 shelves), misspellings and mixed categories; those were merged into one clean record per product.</p>}>
      <Card pad={false}>
        <Table rows={L.items} onRowClick={setEdit} csv="items.csv" initialSort={{ key: 'category', dir: 'asc' }} columns={[
          { key: 'sku', label: 'SKU', render: (r) => <span className="font-mono text-xs">{r.sku}</span> },
          { key: 'name', label: 'Item', render: (r) => <b>{r.name}</b> },
          { key: 'category', label: 'Category' },
          { key: 'item_type', label: 'Type', render: (r) => <Badge color={r.item_type === 'kit' ? 'brand' : r.item_type === 'service' ? 'violet' : 'gray'}>{r.item_type}</Badge> },
          { key: 'barcode', label: 'Barcode', render: (r) => <span className="font-mono text-xs">{r.barcode}</span> },
          { key: 'price', label: 'Price', align: 'right', render: (r) => fmt(r.price) },
          { key: 'avg_cost', label: 'Avg cost', align: 'right', render: (r) => fmt(r.avg_cost) },
          { key: 'margin', label: 'Margin', align: 'right', sortValue: (r) => (num(r.price) ? (num(r.price) - num(r.avg_cost)) / num(r.price) : 0), render: (r) => (num(r.price) && r.item_type !== 'service' ? pct((100 * (num(r.price) - num(r.avg_cost))) / num(r.price), 0) : '—') },
          { key: 'reorder_point', label: 'ROP', align: 'right', render: (r) => (r.item_type === 'service' ? '—' : fmt(r.reorder_point)) },
          { key: 'lead_time_days', label: 'Lead time', align: 'right', render: (r) => (r.item_type === 'service' ? '—' : `${r.lead_time_days} d`) },
          { key: 'supplier', label: 'Supplier', render: (r) => L.supById[r.preferred_supplier_id]?.name || (r.item_type === 'kit' ? 'Made in-house' : '—') },
          { key: 'active', label: 'Status', render: (r) => (r.active ? '' : <Badge color="red">inactive</Badge>) },
        ]} />
      </Card>
      {edit && <RecordForm table="items" record={edit.id ? edit : null} fields={fields.map((f) => (!edit.id && edit[f.key] !== undefined ? { ...f, default: edit[f.key] } : f))} title={edit.id ? edit.name : 'New item'} onClose={() => setEdit(null)} />}
    </Page>
  );
}
