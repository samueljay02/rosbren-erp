// Data access layer. In production every call goes to Supabase (Postgres + Auth + Realtime).
// All business rules run INSIDE the database (see supabase/*.sql), so every user sees the same truth.
import { createClient } from '@supabase/supabase-js';

export const LOCAL = import.meta.env.VITE_LOCAL_MODE === 'true';
const URL_ = import.meta.env.VITE_SUPABASE_URL;
const KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured = LOCAL || (!!URL_ && !!KEY);

const listeners = new Set();
export function onDataChange(cb) { listeners.add(cb); return () => listeners.delete(cb); }
function emit(src) { listeners.forEach((cb) => cb(src)); }

let backend = null;
async function getBackend() {
  if (backend) return backend;
  if (LOCAL) {
    const mod = await import('./localBackend.js');
    backend = await mod.createLocalBackend(emit);
  } else {
    backend = createSupabaseBackend();
  }
  return backend;
}

function createSupabaseBackend() {
  const supabase = createClient(URL_, KEY, { auth: { persistSession: true, autoRefreshToken: true, storage: window.sessionStorage } });
  let channel = null;
  return {
    supabase,
    async rpc(name, args) {
      const { data, error } = await supabase.rpc(name, args || {});
      if (error) throw new Error(error.message);
      return data;
    },
    async select(table, { eq, order, limit, gte, lte, inList } = {}) {
      let q = supabase.from(table).select('*');
      for (const [k, v] of Object.entries(eq || {})) q = q.eq(k, v);
      for (const [k, v] of Object.entries(gte || {})) q = q.gte(k, v);
      for (const [k, v] of Object.entries(lte || {})) q = q.lte(k, v);
      for (const [k, v] of Object.entries(inList || {})) q = q.in(k, v);
      for (const o of [].concat(order || [])) {
        const [col, dir] = o.split(' ');
        q = q.order(col, { ascending: dir !== 'desc' });
      }
      q = q.limit(limit || 5000);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return data;
    },
    startRealtime() {
      if (channel) return;
      channel = supabase.channel('erp-live')
        .on('postgres_changes', { event: '*', schema: 'public' }, (p) => emit(p.table))
        .subscribe();
    },
    stopRealtime() { if (channel) { supabase.removeChannel(channel); channel = null; } },
    auth: {
      async getSession() { const { data } = await supabase.auth.getSession(); return data.session; },
      onChange(cb) { const { data } = supabase.auth.onAuthStateChange((e, s) => cb(s, e)); return () => data.subscription.unsubscribe(); },
      async signIn(email, password) { const { error } = await supabase.auth.signInWithPassword({ email, password }); if (error) throw error; },
      async signUp(email, password, meta) {
        const { data, error } = await supabase.auth.signUp({ email, password, options: { data: meta, emailRedirectTo: window.location.origin + window.location.pathname } });
        if (error) throw error; return data;
      },
      async signOut() { await supabase.auth.signOut(); },
      async resetPassword(email) {
        const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: window.location.origin + window.location.pathname });
        if (error) throw error;
      },
      async updatePassword(password) { const { error } = await supabase.auth.updateUser({ password }); if (error) throw error; },
      // ---- multi-factor (TOTP authenticator app) ----
      async aal() { const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel(); if (error) throw error; return data; },
      async factors() { const { data, error } = await supabase.auth.mfa.listFactors(); if (error) throw error; return data.totp || []; },
      async enroll() {
        // clean up abandoned, unverified enrolments first
        const { data: all } = await supabase.auth.mfa.listFactors();
        for (const f of (all?.all || []).filter((f) => f.status !== 'verified')) await supabase.auth.mfa.unenroll({ factorId: f.id });
        const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Authenticator ' + new Date().toISOString().slice(0, 16) });
        if (error) throw error; return { id: data.id, qr: data.totp.qr_code, secret: data.totp.secret };
      },
      async verify(factorId, code) {
        const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
        if (error) throw error;
      },
      async unenroll(factorId) { const { error } = await supabase.auth.mfa.unenroll({ factorId }); if (error) throw error; },
    },
  };
}

// ---------- public API used by the screens ----------
const MUTATIONS = /^(pos_|so_|process_|inv_|wo_|po_|pay_|create_|mark_|apply_|save_|set_|portal_place|portal_cancel|outreach_prepare|reset_)/;
export const api = {
  async rpc(name, args) {
    const b = await getBackend();
    const r = await b.rpc(name, args);
    if (LOCAL && MUTATIONS.test(name)) emit(name);
    return r;
  },
  async select(table, opts) { const b = await getBackend(); return b.select(table, opts); },
  async backend() { return getBackend(); },
};
