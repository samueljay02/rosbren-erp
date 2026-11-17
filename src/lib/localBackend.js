// DEVELOPER OFFLINE MODE — runs the exact same SQL inside the browser (PGlite / WebAssembly Postgres).
// Used for building & testing without a Supabase project. It is NOT included in production builds
// (VITE_LOCAL_MODE=false removes this file from the bundle) and it has no real authentication.
import { PGlite } from '@electric-sql/pglite';
import stub from '../../supabase/local_stub.sql?raw';
import setup from '../../supabase/setup.sql?raw';

export const DEMO_USERS = [
  { id: '00000000-0000-0000-0000-00000000000a', email: 'admin@rosbren.local', full_name: 'Clinic Administrator', role: 'admin' },
  { id: '00000000-0000-0000-0000-00000000000b', email: 'pharmacist@rosbren.local', full_name: 'Pharmacist on Duty', role: 'pharmacist' },
  { id: '00000000-0000-0000-0000-00000000000c', email: 'store@rosbren.local', full_name: 'Store Keeper', role: 'storekeeper' },
  { id: '00000000-0000-0000-0000-00000000000d', email: 'grace@example.com', full_name: 'Grace Namutebi', role: 'customer' },
];

export async function createLocalBackend(emit) {
  const db = new PGlite('idb://rosbren-erp-v1');
  const ready = (await db.query(`select to_regclass('public.items') is not null as ok`)).rows[0].ok;
  if (!ready) {
    await db.exec(stub);
    await db.exec(setup);
    for (const u of DEMO_USERS) {
      await db.query(`insert into auth.users(id, email, raw_user_meta_data) values ($1, $2, $3)`, [u.id, u.email, { full_name: u.full_name }]);
      if (u.role !== 'customer' && u.role !== 'admin') await db.query(`update profiles set role = $2, customer_id = null where id = $1`, [u.id, u.role]);
    }
  }
  let session = JSON.parse(sessionStorage.getItem('local-session') || 'null');
  const authListeners = new Set();
  const applyClaims = async () => {
    await db.query(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.jwt.claims', $2, false)`,
      [session?.user.id || '', session ? JSON.stringify({ sub: session.user.id, aal: 'aal2' }) : '']);
  };
  await applyClaims();
  let chain = Promise.resolve();
  const serial = (fn) => (chain = chain.then(fn, fn));

  return {
    async rpc(name, args = {}) {
      return serial(async () => {
        const keys = Object.keys(args);
        const sql = `select ${name}(${keys.map((k, i) => `${k} => $${i + 1}`).join(', ')}) as r`;
        const vals = keys.map((k) => (args[k] !== null && typeof args[k] === 'object' ? JSON.stringify(args[k]) : args[k]));
        try { return (await db.query(sql, vals)).rows[0]?.r ?? null; }
        catch (e) { throw new Error(e.message); }
      });
    },
    async select(table, { eq, order, limit, gte, lte, inList } = {}) {
      return serial(async () => {
        const where = []; const vals = [];
        for (const [k, v] of Object.entries(eq || {})) { vals.push(v); where.push(`${k} = $${vals.length}`); }
        for (const [k, v] of Object.entries(gte || {})) { vals.push(v); where.push(`${k} >= $${vals.length}`); }
        for (const [k, v] of Object.entries(lte || {})) { vals.push(v); where.push(`${k} <= $${vals.length}`); }
        for (const [k, v] of Object.entries(inList || {})) { vals.push(v); where.push(`${k} = any($${vals.length})`); }
        const ord = [].concat(order || []).join(', ');
        const sql = `select * from ${table}${where.length ? ' where ' + where.join(' and ') : ''}${ord ? ' order by ' + ord : ''} limit ${limit || 5000}`;
        const res = await db.query(sql, vals);
        const numeric = new Set(res.fields.filter((f) => f.dataTypeID === 1700).map((f) => f.name));
        const dates = new Set(res.fields.filter((f) => f.dataTypeID === 1082).map((f) => f.name));
        // match PostgREST: numerics as numbers, dates as ISO strings
        return res.rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) =>
          [k, v instanceof Date ? (dates.has(k) ? v.toISOString().slice(0, 10) : v.toISOString()) : numeric.has(k) && v !== null ? Number(v) : v])));
      });
    },
    startRealtime() {}, stopRealtime() {},
    auth: {
      async getSession() { return session; },
      onChange(cb) { authListeners.add(cb); return () => authListeners.delete(cb); },
      async signIn(email) {
        const u = DEMO_USERS.find((x) => x.email === email.trim().toLowerCase());
        if (!u) throw new Error('Offline mode: use one of the demo accounts listed below');
        session = { user: { id: u.id, email: u.email } };
        sessionStorage.setItem('local-session', JSON.stringify(session));
        await serial(applyClaims); authListeners.forEach((cb) => cb(session));
      },
      async signUp() { throw new Error('Sign-up is disabled in offline mode'); },
      async signOut() { session = null; sessionStorage.removeItem('local-session'); await serial(applyClaims); authListeners.forEach((cb) => cb(null)); },
      async resetPassword() {}, async updatePassword() {},
      async aal() { return { currentLevel: 'aal2', nextLevel: 'aal2' }; },
      async factors() { return [{ id: 'local', status: 'verified', friendly_name: 'Offline mode (simulated)' }]; },
      async enroll() { throw new Error('MFA enrollment requires Supabase'); },
      async verify() {}, async unenroll() {},
    },
  };
}
