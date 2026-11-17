import { api } from '../lib/api';
import { useData, useAction } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Table, Select, Spinner, Badge } from '../components/ui';
import { dt } from '../lib/format';
import { ShieldCheck, KeyRound, Timer, Users as UsersIcon, FileLock2, Database } from 'lucide-react';

const ROLES = [['admin', 'Administrator — everything + user roles'], ['manager', 'Manager — finance, settings'], ['pharmacist', 'Pharmacist — sales, returns, stock'], ['storekeeper', 'Store keeper — stock, production, purchasing'], ['customer', 'Customer — online ordering only'], ['disabled', 'Disabled — no access']];

export default function UsersPage() {
  const auth = useAuth();
  const [run] = useAction();
  const { data } = useData(() => api.rpc('list_users'));
  return (
    <Page title="Users & Security" subtitle="Who can access what, and the controls protecting Rosbren’s clinical, inventory and financial data.">
      <div className="mb-4 grid gap-3 md:grid-cols-3">
        {[[KeyRound, 'Strong passwords', '10+ characters with upper/lower case, number and symbol; Supabase Auth stores them as salted bcrypt hashes.'],
          [ShieldCheck, 'Mandatory MFA for staff', 'Authenticator-app (TOTP) codes. The database itself refuses staff data unless the session is AAL2 (password + code).'],
          [UsersIcon, 'Role-based access', 'Row-Level Security policies in Postgres: customers only see their own orders; finance & settings are manager-only.'],
          [Timer, 'Session protection', 'Auto sign-out after inactivity; sessions live only in the browser tab (cleared when it closes).'],
          [FileLock2, 'Audit trail', 'Every transaction, role change, sign-in and settings change is logged with user and time.'],
          [Database, 'Server-side business rules', 'Stock, costs and money only change through validated database functions — never by editing tables directly.']].map(([I, t, x]) => (
          <div key={t} className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm"><div className="flex items-center gap-2 font-black text-brand-800"><I size={18} />{t}</div><p className="mt-1 text-sm text-slate-600">{x}</p></div>))}
      </div>
      <Card title="Accounts" pad={false}>
        {!data ? <Spinner /> : <Table rows={data} columns={[
          { key: 'full_name', label: 'Name', render: (r) => <b>{r.full_name}</b> }, { key: 'email', label: 'Email' },
          { key: 'role', label: 'Role', render: (r) => auth.role === 'admin' && r.id !== auth.session.user.id
            ? <Select value={r.role} onChange={(e) => run(() => api.rpc('set_user_role', { p_user: r.id, p_role: e.target.value }), 'Role updated')} options={ROLES.map(([v, l]) => ({ value: v, label: l }))} className="w-72" />
            : <Badge color={r.role === 'customer' ? 'gray' : r.role === 'disabled' ? 'red' : 'brand'}>{r.role}</Badge> },
          { key: 'customer_name', label: 'Linked customer' }, { key: 'created_at', label: 'Created', render: (r) => dt(r.created_at) }, { key: 'last_login_at', label: 'Last sign-in', render: (r) => dt(r.last_login_at) }]} />}
      </Card>
      <p className="mt-3 text-sm text-slate-500">New staff: ask them to create an account on the sign-in page, then change their role here. They’ll be required to set up an authenticator app at their next sign-in.</p>
    </Page>
  );
}
