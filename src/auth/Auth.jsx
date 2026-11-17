import { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react';
import { ShieldCheck, KeyRound, Smartphone, LogIn, UserPlus, Lock, Eye, EyeOff, AlertTriangle } from 'lucide-react';
import { api, LOCAL } from '../lib/api';
import { Btn, Field, Input, cx } from '../components/ui';
import Logo from '../components/Logo';

const AuthCtx = createContext(null);
export const useAuth = () => useContext(AuthCtx);
export const STAFF_ROLES = ['admin', 'manager', 'pharmacist', 'storekeeper'];
export const isManagerRole = (r) => r === 'admin' || r === 'manager';

export function AuthProvider({ children }) {
  const [state, setState] = useState({ loading: true, session: null, profile: null, aal: null, recovery: false });
  const backendRef = useRef(null);

  const refresh = useCallback(async (session, event) => {
    const b = backendRef.current;
    if (!session) { b.stopRealtime(); setState({ loading: false, session: null, profile: null, aal: null, recovery: false }); return; }
    try {
      const [profile, aal] = await Promise.all([api.rpc('my_profile'), b.auth.aal()]);
      setState({ loading: false, session, profile, aal, recovery: event === 'PASSWORD_RECOVERY' });
      if (profile && (aal.currentLevel === 'aal2' || !(STAFF_ROLES.includes(profile.role) && profile.mfa_required))) b.startRealtime();
    } catch (e) {
      setState({ loading: false, session, profile: null, aal: null, error: e.message });
    }
  }, []);

  useEffect(() => {
    let off;
    (async () => {
      const b = await api.backend(); backendRef.current = b;
      off = b.auth.onChange((s, ev) => { if (ev !== 'TOKEN_REFRESHED') refresh(s, ev); });
      refresh(await b.auth.getSession());
    })();
    return () => off?.();
  }, [refresh]);

  // automatic sign-out after inactivity (configurable in Settings → Security)
  const minutes = Number(state.profile?.idle_timeout_minutes || 15);
  useEffect(() => {
    if (!state.session) return;
    let t;
    const reset = () => { clearTimeout(t); t = setTimeout(async () => {
      try { await api.rpc('log_security_event', { p_action: 'Auto sign-out', p_details: `Idle for ${minutes} minutes` }); } catch { /* ignore */ }
      await backendRef.current.auth.signOut(); sessionStorage.setItem('signout-reason', `You were signed out after ${minutes} minutes of inactivity.`);
    }, minutes * 60000); };
    const evs = ['mousemove', 'keydown', 'click', 'touchstart', 'scroll'];
    evs.forEach((e) => window.addEventListener(e, reset, { passive: true })); reset();
    return () => { clearTimeout(t); evs.forEach((e) => window.removeEventListener(e, reset)); };
  }, [state.session, minutes]);

  const value = {
    ...state,
    role: state.profile?.role,
    isStaff: STAFF_ROLES.includes(state.profile?.role),
    isManager: isManagerRole(state.profile?.role),
    backend: () => backendRef.current,
    reload: async () => refresh(await backendRef.current.auth.getSession()),
    signOut: async () => {
      try { await api.rpc('log_security_event', { p_action: 'Signed out', p_details: 'User signed out' }); } catch { /* ignore */ }
      await backendRef.current.auth.signOut();
    },
  };
  return <AuthCtx.Provider value={value}>{children}</AuthCtx.Provider>;
}

// ---------- password rules ----------
export function passwordProblems(p) {
  const out = [];
  if (p.length < 10) out.push('at least 10 characters');
  if (!/[A-Z]/.test(p)) out.push('an uppercase letter');
  if (!/[a-z]/.test(p)) out.push('a lowercase letter');
  if (!/\d/.test(p)) out.push('a number');
  if (!/[^A-Za-z0-9]/.test(p)) out.push('a symbol');
  return out;
}
function Strength({ password }) {
  const n = 5 - passwordProblems(password).length;
  const colors = ['bg-red-500', 'bg-red-500', 'bg-amber-500', 'bg-amber-400', 'bg-emerald-500', 'bg-emerald-600'];
  return password ? (
    <div className="mt-1.5">
      <div className="flex gap-1">{[0, 1, 2, 3, 4].map((i) => <div key={i} className={cx('h-1.5 flex-1 rounded', i < n ? colors[n] : 'bg-slate-200')} />)}</div>
      {n < 5 && <p className="mt-1 text-xs text-slate-500">Needs {passwordProblems(password).join(', ')}.</p>}
    </div>
  ) : null;
}
function PasswordInput(p) {
  const [show, setShow] = useState(false);
  return (
    <div className="relative">
      <Input {...p} type={show ? 'text' : 'password'} className="pr-10" />
      <button type="button" onClick={() => setShow(!show)} className="absolute right-2 top-2 text-slate-400" aria-label="Show password">{show ? <EyeOff size={18} /> : <Eye size={18} />}</button>
    </div>
  );
}

function Shell({ children }) {
  return (
    <div className="flex min-h-screen bg-slate-50">
      <div className="relative hidden w-[44%] flex-col justify-between overflow-hidden bg-brand-700 p-10 text-white lg:flex">
        <div className="absolute -right-24 -top-24 h-80 w-80 rounded-full bg-accent-400/20" />
        <div className="absolute -bottom-32 -left-20 h-96 w-96 rounded-full bg-brand-500/40" />
        <div className="relative flex items-center gap-3"><Logo size={48} /><div><div className="text-2xl font-black tracking-wide">ROSBREN</div><div className="text-sm text-brand-100">Health Clinic · Operations ERP</div></div></div>
        <div className="relative">
          <h1 className="text-4xl font-black leading-tight">Every medicine, kit and shilling — <span className="text-accent-400">accounted for.</span></h1>
          <p className="mt-4 max-w-md text-brand-100">Pharmacy sales, inventory across the clinic, store room and mobile outreach unit, kit assembly, purchasing and financials in one secure system.</p>
        </div>
        <div className="relative flex items-center gap-2 text-sm text-brand-100"><ShieldCheck size={16} />Protected with passwords, authenticator-app MFA, role-based access and audit logging.</div>
      </div>
      <div className="flex flex-1 items-center justify-center p-6">
        <div className="w-full max-w-md">
          <div className="mb-6 flex items-center gap-3 lg:hidden"><Logo size={40} /><div className="text-xl font-black text-brand-700">ROSBREN ERP</div></div>
          {children}
        </div>
      </div>
    </div>
  );
}

export function LoginScreen() {
  const [mode, setMode] = useState('signin');
  const [f, setF] = useState({ email: '', password: '', confirm: '', full_name: '', phone: '', village: '' });
  const [err, setErr] = useState(''); const [msg, setMsg] = useState(sessionStorage.getItem('signout-reason') || '');
  const [busy, setBusy] = useState(false);
  useEffect(() => { sessionStorage.removeItem('signout-reason'); }, []);
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value });
  const submit = async (e) => {
    e.preventDefault(); setErr(''); setMsg(''); setBusy(true);
    const b = await api.backend();
    try {
      if (mode === 'signin') {
        await b.auth.signIn(f.email, f.password);
      } else if (mode === 'signup') {
        const probs = passwordProblems(f.password);
        if (probs.length) throw new Error('Password needs ' + probs.join(', '));
        if (f.password !== f.confirm) throw new Error('Passwords do not match');
        if (!f.full_name.trim()) throw new Error('Please enter your full name');
        const r = await b.auth.signUp(f.email, f.password, { full_name: f.full_name.trim(), phone: f.phone, village: f.village });
        if (!r.session) setMsg('Account created. Check your email to confirm your address, then sign in.');
      } else {
        await b.auth.resetPassword(f.email);
        setMsg('If that email has an account, a password-reset link is on its way.');
      }
    } catch (e2) {
      setErr(/Invalid login/i.test(e2.message) ? 'Incorrect email or password.' : e2.message);
    } finally { setBusy(false); }
  };
  return (
    <Shell>
      <h2 className="text-2xl font-black text-slate-900">{mode === 'signin' ? 'Sign in' : mode === 'signup' ? 'Create a customer account' : 'Reset password'}</h2>
      <p className="mb-6 mt-1 text-sm text-slate-600">
        {mode === 'signin' ? 'Staff and customers sign in here.' : mode === 'signup' ? 'Order medicines and kits online for pickup. Staff accounts are approved by an administrator.' : 'We’ll email you a secure reset link.'}
      </p>
      {LOCAL && mode === 'signin' && <LocalHint onPick={(email) => setF({ ...f, email, password: 'offline' })} />}
      <form onSubmit={submit} className="space-y-4">
        {mode === 'signup' && <>
          <Field label="Full name"><Input value={f.full_name} onChange={set('full_name')} required autoComplete="name" /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Phone"><Input value={f.phone} onChange={set('phone')} autoComplete="tel" placeholder="+256…" /></Field>
            <Field label="Village / town"><Input value={f.village} onChange={set('village')} /></Field>
          </div>
        </>}
        <Field label="Email"><Input type="email" value={f.email} onChange={set('email')} required autoComplete="email" /></Field>
        {mode !== 'reset' && <Field label="Password">
          <PasswordInput value={f.password} onChange={set('password')} required autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} />
          {mode === 'signup' && <Strength password={f.password} />}
        </Field>}
        {mode === 'signup' && <Field label="Confirm password"><PasswordInput value={f.confirm} onChange={set('confirm')} required autoComplete="new-password" /></Field>}
        {err && <div className="flex items-start gap-2 rounded-lg bg-red-50 p-3 text-sm text-red-800"><AlertTriangle size={16} className="mt-0.5 shrink-0" />{err}</div>}
        {msg && <div className="rounded-lg bg-brand-50 p-3 text-sm text-brand-800">{msg}</div>}
        <Btn type="submit" size="lg" className="w-full" busy={busy} icon={mode === 'signin' ? LogIn : mode === 'signup' ? UserPlus : KeyRound}>
          {mode === 'signin' ? 'Sign in' : mode === 'signup' ? 'Create account' : 'Send reset link'}
        </Btn>
      </form>
      <div className="mt-6 flex justify-between text-sm">
        {mode !== 'signin' ? <button className="font-bold text-brand-700" onClick={() => setMode('signin')}>← Back to sign in</button> :
          <><button className="font-bold text-brand-700" onClick={() => setMode('signup')}>New customer? Create account</button>
            <button className="text-slate-500 hover:text-slate-800" onClick={() => setMode('reset')}>Forgot password?</button></>}
      </div>
    </Shell>
  );
}

function LocalHint({ onPick }) {
  const users = [['admin@rosbren.local', 'Administrator'], ['pharmacist@rosbren.local', 'Pharmacist'], ['store@rosbren.local', 'Store keeper'], ['grace@example.com', 'Customer']];
  return (
    <div className="mb-5 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
      <b>Offline developer mode</b> — no real security. Pick a demo account:
      <div className="mt-2 flex flex-wrap gap-1.5">{users.map(([e, l]) => <button key={e} type="button" onClick={() => onPick(e)} className="rounded bg-white px-2 py-1 font-bold ring-1 ring-amber-300 hover:bg-amber-100">{l}</button>)}</div>
    </div>
  );
}

// ---------- MFA: enroll (first time) or verify (each sign-in) ----------
export function MfaScreen() {
  const auth = useAuth();
  const [factors, setFactors] = useState(null);
  const [enroll, setEnroll] = useState(null);
  const [code, setCode] = useState('');
  const [err, setErr] = useState(''); const [busy, setBusy] = useState(false);
  useEffect(() => { (async () => {
    try { const f = (await auth.backend().auth.factors()).filter((x) => x.status === 'verified'); setFactors(f);
      if (!f.length) setEnroll(await auth.backend().auth.enroll());
    } catch (e) { setErr(e.message); }
  })(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const verify = async (e) => {
    e.preventDefault(); setErr(''); setBusy(true);
    try {
      const id = enroll ? enroll.id : factors[0].id;
      await auth.backend().auth.verify(id, code.replace(/\s/g, ''));
      if (enroll) sessionStorage.setItem('mfa-enrolled', '1');
      await auth.reload();
    } catch (e2) {
      setErr(/invalid|expired/i.test(e2.message) ? 'That code is incorrect or expired. Codes change every 30 seconds.' : e2.message); setCode('');
    } finally { setBusy(false); }
  };
  return (
    <Shell>
      <div className="mb-2 flex items-center gap-2 text-brand-700"><ShieldCheck /> <span className="text-sm font-bold uppercase tracking-wide">Two-step verification</span></div>
      <h2 className="text-2xl font-black text-slate-900">{enroll ? 'Set up your authenticator' : 'Enter your 6-digit code'}</h2>
      <p className="mb-5 mt-1 text-sm text-slate-600">
        {enroll ? 'Staff accounts protect patient-facing and financial data, so a second factor is required. Scan this QR code with Google Authenticator, Microsoft Authenticator or Authy, then enter the code it shows.'
          : 'Open your authenticator app and enter the current code for Rosbren ERP.'}
      </p>
      {factors === null && !err && <p className="text-sm text-slate-500">Loading…</p>}
      {enroll && (
        <div className="mb-5 flex flex-col items-center gap-3 rounded-xl border border-slate-200 bg-white p-4">
          <img src={enroll.qr} alt="Authenticator QR code" className="h-48 w-48" />
          <details className="text-center text-xs text-slate-500"><summary className="cursor-pointer">Can’t scan? Enter this key manually</summary>
            <code className="mt-1 block select-all break-all rounded bg-slate-100 p-2 font-mono text-slate-800">{enroll.secret}</code></details>
        </div>
      )}
      {(enroll || factors?.length > 0) && (
        <form onSubmit={verify} className="space-y-4">
          <Field label="Authenticator code"><Input inputMode="numeric" autoComplete="one-time-code" maxLength={7} value={code} onChange={(e) => setCode(e.target.value)} autoFocus
            className="text-center font-mono text-2xl tracking-[0.5em]" placeholder="000000" /></Field>
          {err && <div className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{err}</div>}
          <Btn type="submit" size="lg" className="w-full" busy={busy} disabled={code.replace(/\s/g, '').length !== 6} icon={Smartphone}>Verify &amp; continue</Btn>
        </form>
      )}
      <button onClick={auth.signOut} className="mt-6 text-sm text-slate-500 hover:text-slate-800">Sign out</button>
    </Shell>
  );
}

export function SetNewPassword() {
  const auth = useAuth();
  const [p, setP] = useState(''); const [c, setC] = useState(''); const [err, setErr] = useState(''); const [busy, setBusy] = useState(false);
  const submit = async (e) => {
    e.preventDefault(); setErr('');
    const probs = passwordProblems(p); if (probs.length) return setErr('Password needs ' + probs.join(', '));
    if (p !== c) return setErr('Passwords do not match');
    setBusy(true);
    try { await auth.backend().auth.updatePassword(p); await api.rpc('log_security_event', { p_action: 'Password changed', p_details: 'Via reset link' }); await auth.reload(); }
    catch (e2) { setErr(e2.message); } finally { setBusy(false); }
  };
  return (
    <Shell>
      <h2 className="mb-4 text-2xl font-black">Choose a new password</h2>
      <form onSubmit={submit} className="space-y-4">
        <Field label="New password"><PasswordInput value={p} onChange={(e) => setP(e.target.value)} autoComplete="new-password" /><Strength password={p} /></Field>
        <Field label="Confirm"><PasswordInput value={c} onChange={(e) => setC(e.target.value)} autoComplete="new-password" /></Field>
        {err && <div className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{err}</div>}
        <Btn type="submit" busy={busy} icon={Lock} className="w-full">Save password</Btn>
      </form>
    </Shell>
  );
}

// Account security panel (used by staff Account page and the customer portal)
export function AccountSecurity() {
  const auth = useAuth();
  const [factors, setFactors] = useState([]);
  const [enroll, setEnroll] = useState(null); const [code, setCode] = useState('');
  const [pw, setPw] = useState(''); const [msg, setMsg] = useState(''); const [err, setErr] = useState('');
  const load = async () => setFactors((await auth.backend().auth.factors()).filter((f) => f.status === 'verified'));
  useEffect(() => { load(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const wrap = (fn) => async (...a) => { setErr(''); setMsg(''); try { await fn(...a); } catch (e) { setErr(e.message); } };
  return (
    <div className="space-y-5">
      <div>
        <h3 className="mb-2 font-black text-brand-800">Authenticator app (MFA)</h3>
        {factors.length ? factors.map((f) => (
          <div key={f.id} className="flex items-center justify-between rounded-lg border border-slate-200 p-3 text-sm">
            <span className="flex items-center gap-2"><ShieldCheck className="text-emerald-600" size={18} />{f.friendly_name || 'Authenticator'} <span className="text-slate-500">· active</span></span>
            {!auth.isStaff && <Btn size="sm" variant="secondary" onClick={wrap(async () => { await auth.backend().auth.unenroll(f.id); await load(); setMsg('Authenticator removed'); })}>Remove</Btn>}
          </div>)) : <p className="text-sm text-slate-600">Not set up. Adding an authenticator protects your account even if your password is stolen.</p>}
        {!factors.length && !enroll && <Btn className="mt-2" size="sm" icon={Smartphone} onClick={wrap(async () => setEnroll(await auth.backend().auth.enroll()))}>Set up authenticator</Btn>}
        {enroll && (
          <div className="mt-3 flex flex-wrap items-end gap-3 rounded-lg border border-slate-200 p-3">
            <img src={enroll.qr} alt="QR" className="h-36 w-36" />
            <div className="space-y-2"><Input placeholder="6-digit code" value={code} onChange={(e) => setCode(e.target.value)} />
              <Btn size="sm" onClick={wrap(async () => { await auth.backend().auth.verify(enroll.id, code); setEnroll(null); setCode(''); await load(); await auth.reload(); setMsg('Authenticator enabled'); })}>Verify</Btn></div>
          </div>
        )}
      </div>
      <div>
        <h3 className="mb-2 font-black text-brand-800">Change password</h3>
        <div className="flex max-w-md gap-2"><PasswordInput value={pw} onChange={(e) => setPw(e.target.value)} placeholder="New password" autoComplete="new-password" />
          <Btn size="sm" onClick={wrap(async () => { const p = passwordProblems(pw); if (p.length) throw new Error('Password needs ' + p.join(', '));
            await auth.backend().auth.updatePassword(pw); await api.rpc('log_security_event', { p_action: 'Password changed', p_details: 'From account page' }); setPw(''); setMsg('Password updated'); })}>Update</Btn></div>
        <div className="max-w-md"><Strength password={pw} /></div>
      </div>
      {msg && <p className="text-sm font-bold text-emerald-700">{msg}</p>}
      {err && <p className="text-sm text-red-700">{err}</p>}
    </div>
  );
}
