import { useState, useEffect } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  LayoutDashboard, ShoppingCart, ClipboardList, Undo2, Users, Boxes, Barcode, Tags, Factory, Network, CalendarRange,
  Truck, Building2, Calculator, HeartPulse, Landmark, BarChart3, History, Settings, ShieldCheck, UserCircle, Info, LogOut, Menu, X, Radio,
} from 'lucide-react';
import { useAuth } from './auth/Auth';
import { onDataChange, LOCAL } from './lib/api';
import Logo from './components/Logo';
import { cx } from './components/ui';

export const NAV = [
  { group: 'Overview', items: [{ to: '/', label: 'Dashboard', icon: LayoutDashboard }] },
  { group: 'Sales', items: [
    { to: '/pos', label: 'Point of Sale', icon: ShoppingCart }, { to: '/sales-orders', label: 'Sales Orders', icon: ClipboardList },
    { to: '/returns', label: 'Returns & Exchanges', icon: Undo2 }, { to: '/customers', label: 'Customers', icon: Users }] },
  { group: 'Inventory', items: [
    { to: '/inventory', label: 'Stock & Locations', icon: Boxes }, { to: '/labels', label: 'Barcode Labels', icon: Barcode },
    { to: '/items', label: 'Items & Pricing', icon: Tags }] },
  { group: 'Production & Planning', items: [
    { to: '/production', label: 'Production Orders', icon: Factory }, { to: '/bom', label: 'Bills of Material', icon: Network },
    { to: '/mrp', label: 'MRP Planner', icon: CalendarRange }] },
  { group: 'Purchasing', items: [
    { to: '/purchasing', label: 'Purchase Orders', icon: Truck }, { to: '/suppliers', label: 'Suppliers & Scorecards', icon: Building2 },
    { to: '/replenishment', label: 'Reorder Points & EOQ', icon: Calculator }] },
  { group: 'Community', items: [{ to: '/outreach', label: 'Outreach Planner', icon: HeartPulse, badge: '★' }] },
  { group: 'Finance & Reports', items: [
    { to: '/financials', label: 'Financial Statements', icon: Landmark, manager: true }, { to: '/reports', label: 'Management Reports', icon: BarChart3 }] },
  { group: 'System', items: [
    { to: '/activity', label: 'Activity Log', icon: History }, { to: '/settings', label: 'Settings', icon: Settings, manager: true },
    { to: '/users', label: 'Users & Security', icon: ShieldCheck, manager: true }, { to: '/account', label: 'My Account', icon: UserCircle },
    { to: '/about', label: 'About & Tech Stack', icon: Info }] },
];

const ROLE_LABEL = { admin: 'Administrator', manager: 'Manager', pharmacist: 'Pharmacist', storekeeper: 'Store keeper' };

function LiveDot() {
  const [pulse, setPulse] = useState(false);
  useEffect(() => onDataChange(() => { setPulse(true); setTimeout(() => setPulse(false), 1200); }), []);
  return (
    <span className="flex items-center gap-1.5 text-xs font-bold text-emerald-700" title="Screens update automatically when any user makes a change">
      <span className="relative flex h-2.5 w-2.5">
        <span className={cx('absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75', pulse ? 'animate-ping' : '')} />
        <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-emerald-500" />
      </span>{LOCAL ? 'Offline dev mode' : 'Live'}
    </span>
  );
}

export default function Layout() {
  const auth = useAuth();
  const [open, setOpen] = useState(false);
  const loc = useLocation();
  useEffect(() => setOpen(false), [loc.pathname]);
  const sidebar = (
    <nav className="flex h-full flex-col bg-brand-800 text-brand-50">
      <div className="flex items-center gap-3 px-5 py-4">
        <Logo size={38} />
        <div><div className="text-lg font-black leading-none tracking-wider">ROSBREN</div><div className="text-[11px] text-brand-200">Health Clinic ERP</div></div>
      </div>
      <div className="flex-1 overflow-y-auto px-3 pb-4">
        {NAV.map((g) => {
          const items = g.items.filter((i) => !i.manager || auth.isManager);
          if (!items.length) return null;
          return (
            <div key={g.group} className="mt-4">
              <div className="px-2 pb-1 text-[10px] font-bold uppercase tracking-[0.15em] text-brand-300">{g.group}</div>
              {items.map((i) => (
                <NavLink key={i.to} to={i.to} end={i.to === '/'}
                  className={({ isActive }) => cx('flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm font-bold transition',
                    isActive ? 'bg-accent-400 text-brand-900' : 'text-brand-100 hover:bg-brand-700 hover:text-white')}>
                  <i.icon size={17} />{i.label}{i.badge && <span className="ml-auto text-accent-400">{i.badge}</span>}
                </NavLink>))}
            </div>);
        })}
      </div>
    </nav>
  );
  return (
    <div className="flex h-screen overflow-hidden bg-slate-50">
      <aside className="hidden w-64 shrink-0 lg:block print:hidden">{sidebar}</aside>
      {open && <div className="fixed inset-0 z-40 flex lg:hidden"><div className="w-64">{sidebar}</div><div className="flex-1 bg-black/40" onClick={() => setOpen(false)} /></div>}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between gap-3 border-b border-slate-200 bg-white px-4 py-2.5 print:hidden">
          <button className="lg:hidden" onClick={() => setOpen(true)} aria-label="Menu">{open ? <X /> : <Menu />}</button>
          <div className="flex items-center gap-3"><LiveDot /><span className="hidden items-center gap-1 text-xs text-slate-500 sm:flex"><Radio size={12} />Multi-user real-time sync</span></div>
          <div className="flex items-center gap-3">
            <div className="text-right leading-tight">
              <div className="text-sm font-bold text-slate-800">{auth.profile?.full_name}</div>
              <div className="flex items-center justify-end gap-1 text-xs text-slate-500">{ROLE_LABEL[auth.role]}{auth.aal?.currentLevel === 'aal2' && <span className="flex items-center gap-0.5 text-emerald-700"><ShieldCheck size={12} />MFA</span>}</div>
            </div>
            <button onClick={auth.signOut} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100" title="Sign out" aria-label="Sign out"><LogOut size={18} /></button>
          </div>
        </header>
        <main className="flex-1 overflow-y-auto"><Outlet /></main>
      </div>
    </div>
  );
}
