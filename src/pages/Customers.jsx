import { useMemo, useState } from 'react';
import { Plus } from 'lucide-react';
import { api } from '../lib/api';
import { useData, useLookups } from '../lib/hooks';
import { Page, Card, Btn, Table, Badge, Spinner } from '../components/ui';
import RecordForm from '../components/RecordForm';
import { money, fmt, d, num } from '../lib/format';

const TYPES = ['Individual', 'Walk-in', 'Village Health Team', 'Health Centre', 'School', 'NGO'];
export const CUSTOMER_FIELDS = [
  { key: 'name', label: 'Name', wide: true },
  { key: 'customer_type', label: 'Type', type: 'select', options: TYPES.map((t) => ({ value: t, label: t })) },
  { key: 'discount_pct', label: 'Agreed discount %', type: 'number', default: 0 },
  { key: 'phone', label: 'Phone' }, { key: 'email', label: 'Email', type: 'email' },
  { key: 'village', label: 'Village / town' }, { key: 'notes', label: 'Notes', type: 'textarea', wide: true },
];

export default function Customers() {
  const L = useLookups();
  const [edit, setEdit] = useState(null);
  const { data: sales } = useData(() => api.select('sales', { gte: { sale_date: new Date(Date.now() - 365 * 864e5).toISOString() } }));
  const rows = useMemo(() => {
    if (!L.ready || !sales) return [];
    const agg = {}; sales.forEach((s) => { if (!s.customer_id) return; const a = (agg[s.customer_id] ||= { n: 0, rev: 0, last: null }); a.n++; a.rev += num(s.total); if (!a.last || s.sale_date > a.last) a.last = s.sale_date; });
    return L.customers.map((c) => ({ ...c, n: agg[c.id]?.n || 0, rev: agg[c.id]?.rev || 0, last: agg[c.id]?.last }));
  }, [L, sales]);
  if (!L.ready || !sales) return <Spinner />;
  return (
    <Page title="Customers" subtitle="Patients, Village Health Teams, health centres, schools and NGO partners." actions={<Btn icon={Plus} onClick={() => setEdit({})}>New customer</Btn>}>
      <Card pad={false}>
        <Table rows={rows} onRowClick={setEdit} csv="customers.csv" initialSort={{ key: 'rev', dir: 'desc' }} columns={[
          { key: 'name', label: 'Customer', render: (r) => <b>{r.name}</b> },
          { key: 'customer_type', label: 'Type', render: (r) => <Badge color={r.customer_type === 'Individual' || r.customer_type === 'Walk-in' ? 'gray' : 'brand'}>{r.customer_type}</Badge> },
          { key: 'village', label: 'Village' }, { key: 'phone', label: 'Phone' },
          { key: 'discount_pct', label: 'Discount', align: 'right', render: (r) => (num(r.discount_pct) ? fmt(r.discount_pct) + '%' : '—') },
          { key: 'n', label: 'Purchases (12 mo)', align: 'right' },
          { key: 'rev', label: 'Revenue (12 mo)', align: 'right', render: (r) => money(r.rev) },
          { key: 'last', label: 'Last purchase', render: (r) => d(r.last) },
        ]} />
      </Card>
      {edit && <RecordForm table="customers" record={edit.id ? edit : null} fields={CUSTOMER_FIELDS} title={edit.id ? edit.name : 'New customer'} onClose={() => setEdit(null)} />}
    </Page>
  );
}
