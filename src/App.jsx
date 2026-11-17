import { lazy, Suspense, useEffect } from 'react';
import { HashRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth, LoginScreen, MfaScreen, SetNewPassword, STAFF_ROLES } from './auth/Auth';
import { LookupsProvider, ToastProvider } from './lib/hooks';
import { api, configured } from './lib/api';
import Layout from './Layout';
import { Spinner } from './components/ui';
import Logo from './components/Logo';

const P = (f) => lazy(f);
const Dashboard = P(() => import('./pages/Dashboard'));
const POS = P(() => import('./pages/POS'));
const SalesOrders = P(() => import('./pages/SalesOrders'));
const Returns = P(() => import('./pages/Returns'));
const Customers = P(() => import('./pages/Customers'));
const Inventory = P(() => import('./pages/Inventory'));
const Labels = P(() => import('./pages/Labels'));
const Items = P(() => import('./pages/Items'));
const Production = P(() => import('./pages/Production'));
const BOM = P(() => import('./pages/BOM'));
const MRP = P(() => import('./pages/MRP'));
const Purchasing = P(() => import('./pages/Purchasing'));
const Suppliers = P(() => import('./pages/Suppliers'));
const Replenishment = P(() => import('./pages/Replenishment'));
const Outreach = P(() => import('./pages/Outreach'));
const Financials = P(() => import('./pages/Financials'));
const Reports = P(() => import('./pages/Reports'));
const Activity = P(() => import('./pages/Activity'));
const SettingsPage = P(() => import('./pages/Settings'));
const UsersPage = P(() => import('./pages/Users'));
const Account = P(() => import('./pages/Account'));
const About = P(() => import('./pages/About'));
const Portal = P(() => import('./pages/Portal'));

function Splash({ text = 'Loading Rosbren ERP…' }) {
  return <div className="flex h-screen flex-col items-center justify-center gap-3 bg-slate-50"><Logo size={56} /><Spinner label={text} /></div>;
}

function NotConfigured() {
  return (
    <div className="mx-auto max-w-xl p-10">
      <Logo size={56} />
      <h1 className="mt-4 text-2xl font-black text-brand-800">Connect your Supabase project</h1>
      <p className="mt-2 text-slate-700">Set <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code> (see README → Setup) and rebuild.</p>
    </div>
  );
}

function Gate() {
  const auth = useAuth();
  useEffect(() => {
    if (!auth.profile || !auth.session) return;
    const key = 'logged-' + auth.session.user.id + (auth.aal?.currentLevel || '');
    const passed = !STAFF_ROLES.includes(auth.role) || !auth.profile.mfa_required || auth.aal?.currentLevel === 'aal2';
    if (passed && !sessionStorage.getItem(key)) {
      sessionStorage.setItem(key, '1');
      const enrolled = sessionStorage.getItem('mfa-enrolled'); sessionStorage.removeItem('mfa-enrolled');
      api.rpc('log_security_event', { p_action: 'Signed in', p_details: auth.aal?.currentLevel === 'aal2' ? (enrolled ? 'Password + new authenticator enrolled (MFA)' : 'Password + authenticator code (MFA)') : 'Password' }).catch(() => {});
    }
  }, [auth.profile, auth.session, auth.aal, auth.role]);

  if (auth.loading) return <Splash />;
  if (!auth.session) return <LoginScreen />;
  if (auth.recovery) return <SetNewPassword />;
  if (!auth.profile) return <Splash text={auth.error || 'Preparing your account…'} />;
  if (auth.role === 'disabled') return <div className="p-10 text-center"><h1 className="text-xl font-black">This account has been disabled.</h1><button className="mt-4 underline" onClick={auth.signOut}>Sign out</button></div>;
  if (STAFF_ROLES.includes(auth.role) && auth.profile.mfa_required && auth.aal?.currentLevel !== 'aal2') return <MfaScreen />;
  if (auth.role === 'customer') return <Suspense fallback={<Splash />}><Portal /></Suspense>;
  const M = (el) => (auth.isManager ? el : <Navigate to="/" />);
  return (
    <LookupsProvider>
      <HashRouter>
        <Suspense fallback={<Spinner />}>
          <Routes>
            <Route element={<Layout />}>
              <Route index element={<Dashboard />} />
              <Route path="pos" element={<POS />} />
              <Route path="sales-orders" element={<SalesOrders />} />
              <Route path="returns" element={<Returns />} />
              <Route path="customers" element={<Customers />} />
              <Route path="inventory" element={<Inventory />} />
              <Route path="labels" element={<Labels />} />
              <Route path="items" element={<Items />} />
              <Route path="production" element={<Production />} />
              <Route path="bom" element={<BOM />} />
              <Route path="mrp" element={<MRP />} />
              <Route path="purchasing" element={<Purchasing />} />
              <Route path="suppliers" element={<Suppliers />} />
              <Route path="replenishment" element={<Replenishment />} />
              <Route path="outreach" element={<Outreach />} />
              <Route path="financials" element={M(<Financials />)} />
              <Route path="reports" element={<Reports />} />
              <Route path="activity" element={<Activity />} />
              <Route path="settings" element={M(<SettingsPage />)} />
              <Route path="users" element={M(<UsersPage />)} />
              <Route path="account" element={<Account />} />
              <Route path="about" element={<About />} />
              <Route path="*" element={<Navigate to="/" />} />
            </Route>
          </Routes>
        </Suspense>
      </HashRouter>
    </LookupsProvider>
  );
}

export default function App() {
  if (!configured) return <NotConfigured />;
  return <ToastProvider><AuthProvider><Gate /></AuthProvider></ToastProvider>;
}
