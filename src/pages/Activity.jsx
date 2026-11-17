import { useState } from 'react';
import { api } from '../lib/api';
import { useData } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Table, Tabs, Spinner, Badge } from '../components/ui';
import { dt } from '../lib/format';

export default function Activity() {
  const auth = useAuth();
  const [tab, setTab] = useState('operations');
  const { data } = useData(() => api.rpc('get_activity', { p_category: tab, p_limit: 500 }), [tab]);
  return (
    <Page title="Activity Log" subtitle="Immutable audit trail of every transaction and security event, with who did it and when.">
      <Tabs value={tab} onChange={setTab} tabs={[{ value: 'operations', label: 'Operations' }, ...(auth.isManager ? [{ value: 'security', label: 'Security events' }] : [])]} />
      {!data ? <Spinner /> : <Card pad={false}><Table rows={data} csv={`activity-${tab}.csv`} columns={[
        { key: 'created_at', label: 'When', render: (r) => dt(r.created_at) }, { key: 'user_name', label: 'User', render: (r) => <b>{r.user_name}</b> },
        { key: 'action', label: 'Action', render: (r) => <Badge color={r.category === 'security' ? 'violet' : 'brand'}>{r.action}</Badge> },
        { key: 'details', label: 'Details' }, { key: 'ref_no', label: 'Reference' }]} /></Card>}
    </Page>
  );
}
