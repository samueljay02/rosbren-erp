import { useAuth, AccountSecurity } from '../auth/Auth';
import { Page, Card } from '../components/ui';

export default function Account() {
  const auth = useAuth();
  return (
    <Page title="My Account" subtitle={`${auth.profile?.full_name} · ${auth.profile?.email} · ${auth.role}`}>
      <Card className="max-w-2xl"><AccountSecurity /></Card>
    </Page>
  );
}
