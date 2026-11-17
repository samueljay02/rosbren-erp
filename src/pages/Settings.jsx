import { useEffect, useState } from 'react';
import { Save, RotateCcw } from 'lucide-react';
import { api } from '../lib/api';
import { useLookups, useAction } from '../lib/hooks';
import { useAuth } from '../auth/Auth';
import { Page, Card, Btn, Field, Input, Select, Spinner } from '../components/ui';

export default function SettingsPage() {
  const L = useLookups();
  const auth = useAuth();
  const [vals, setVals] = useState(null);
  const [run, busy] = useAction();
  useEffect(() => { if (L.settings && !vals) setVals(Object.fromEntries(L.settings.map((s) => [s.key, s.value]))); }, [L.settings, vals]);
  if (!vals) return <Spinner />;
  const groups = [...new Set(L.settings.map((s) => s.category))];
  const changed = Object.fromEntries(L.settings.filter((s) => vals[s.key] !== s.value).map((s) => [s.key, vals[s.key]]));
  return (
    <Page title="Settings" subtitle="Stored, editable parameters used by every calculation (EOQ, safety stock, tax, outreach ratios, security)."
      actions={<Btn icon={Save} busy={busy} disabled={!Object.keys(changed).length} onClick={async () => { if (await run(() => api.rpc('save_settings', { p: changed }), 'Settings saved — all screens recalculate')) L.reload(); }}>Save {Object.keys(changed).length || ''} changes</Btn>}>
      <div className="grid gap-4 lg:grid-cols-2">
        {groups.map((g) => (
          <Card key={g} title={g}>
            <div className="space-y-3">{L.settings.filter((s) => s.category === g).map((s) => (
              <Field key={s.key} label={s.label || s.key} hint={s.description}>
                {s.key === 'require_staff_mfa' ? <Select value={vals[s.key]} onChange={(e) => setVals({ ...vals, [s.key]: e.target.value })} options={[{ value: 'true', label: 'Required (recommended)' }, { value: 'false', label: 'Not required' }]} />
                  : <Input value={vals[s.key]} onChange={(e) => setVals({ ...vals, [s.key]: e.target.value })} />}
              </Field>))}</div>
          </Card>))}
        {auth.role === 'admin' && <Card title="Demo data">
          <p className="mb-3 text-sm text-slate-600">Regenerate the 6½-month history so it ends yesterday (run this the morning of a demo). Users, logins and settings are kept; all transactions are replaced.</p>
          <Btn variant="danger" icon={RotateCcw} busy={busy} onClick={async () => { if (window.confirm('Replace ALL transactions with freshly generated history?')) { const r = await run(() => api.rpc('reset_demo_data', { p_days: 200 }), (r) => `Generated ${r.sales} sales, ${r.purchase_orders} POs, ${r.production_orders} production orders`); if (r) L.reload(); } }}>Regenerate demo data</Btn>
        </Card>}
      </div>
    </Page>
  );
}
