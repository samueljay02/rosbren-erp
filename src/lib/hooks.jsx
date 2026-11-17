import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { api, onDataChange } from './api';

// Fetch data and automatically re-fetch whenever ANY user changes data (Supabase Realtime).
export function useData(fetcher, deps = [], { live = true } = {}) {
  const [state, setState] = useState({ data: null, loading: true, error: null });
  const fnRef = useRef(fetcher); fnRef.current = fetcher;
  const seq = useRef(0);
  const load = useCallback(async (quiet) => {
    const my = ++seq.current;
    if (!quiet) setState((s) => ({ ...s, loading: true }));
    try {
      const data = await fnRef.current();
      if (my === seq.current) setState({ data, loading: false, error: null });
    } catch (e) {
      if (my === seq.current) setState((s) => ({ ...s, loading: false, error: e.message }));
    }
  }, []);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, deps);
  useEffect(() => {
    if (!live) return;
    let t;
    const off = onDataChange(() => { clearTimeout(t); t = setTimeout(() => load(true), 350); });
    return () => { off(); clearTimeout(t); };
  }, [live, load]);
  return { ...state, reload: () => load(true) };
}

// Master data shared by every screen (kept live).
const LookupCtx = createContext(null);
export function LookupsProvider({ children }) {
  const { data, reload } = useData(async () => {
    const [items, locations, customers, suppliers, reasons, settings] = await Promise.all([
      api.select('items', { order: 'name' }), api.select('locations', { order: 'id' }), api.select('customers', { order: 'name' }),
      api.select('suppliers', { order: 'name' }), api.select('reason_codes', { order: 'code' }), api.select('settings', { order: 'key' }),
    ]);
    const by = (arr) => Object.fromEntries(arr.map((x) => [x.id, x]));
    return {
      items, locations, customers, suppliers, reasons, settings,
      itemById: by(items), locById: by(locations), custById: by(customers), supById: by(suppliers),
      itemByBarcode: Object.fromEntries(items.map((i) => [String(i.barcode), i])),
      setting: Object.fromEntries(settings.map((s) => [s.key, s.value])),
    };
  }, []);
  return <LookupCtx.Provider value={{ ...(data || {}), ready: !!data, reload }}>{children}</LookupCtx.Provider>;
}
export const useLookups = () => useContext(LookupCtx);

// Toasts
const ToastCtx = createContext(() => {});
export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);
  const push = useCallback((msg, kind = 'success') => {
    const id = Math.random();
    setToasts((t) => [...t, { id, msg, kind }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), kind === 'error' ? 7000 : 4000);
  }, []);
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="fixed bottom-4 right-4 z-[100] flex flex-col gap-2 print:hidden" role="status" aria-live="polite">
        {toasts.map((t) => (
          <div key={t.id} className={`max-w-sm rounded-lg px-4 py-3 text-sm shadow-lg ring-1 ${t.kind === 'error' ? 'bg-red-50 text-red-800 ring-red-200' : 'bg-brand-700 text-white ring-brand-800'}`}>
            <span className="font-bold mr-1">{t.kind === 'error' ? 'Error:' : '✓'}</span>{t.msg}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}
export const useToast = () => useContext(ToastCtx);

// Run an RPC with toast feedback; returns result or undefined on error
export function useAction() {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const run = useCallback(async (fn, okMsg) => {
    setBusy(true);
    try {
      const r = await fn();
      if (okMsg) toast(typeof okMsg === 'function' ? okMsg(r) : okMsg);
      return r ?? true;
    } catch (e) { toast(e.message, 'error'); return undefined; }
    finally { setBusy(false); }
  }, [toast]);
  return [run, busy];
}
