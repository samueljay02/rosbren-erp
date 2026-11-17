import { useState } from 'react';
import { api } from '../lib/api';
import { useAction, useLookups } from '../lib/hooks';
import { Modal, Btn, Field, Input, Select, Textarea } from './ui';

// Generic create/edit form for master data. Saves through save_record() (validated + audited in the DB).
export default function RecordForm({ table, record, fields, title, onClose, onSaved }) {
  const [f, setF] = useState(() => ({ ...Object.fromEntries(fields.map((x) => [x.key, x.default ?? ''])), ...(record || {}) }));
  const [run, busy] = useAction();
  const L = useLookups();
  const save = async () => {
    const payload = {};
    for (const x of fields) {
      let v = f[x.key];
      if (x.type === 'number') v = v === '' || v === null ? null : Number(v);
      if (x.type === 'checkbox') v = !!v;
      if (x.type === 'select' && x.numeric) v = v === '' ? null : Number(v);
      if (v === '') v = null;
      if (!x.readOnly) payload[x.key] = v;
    }
    if (record?.id) payload.id = record.id;
    const r = await run(() => api.rpc('save_record', { p_table: table, p: payload }), 'Saved');
    if (r) { L.reload?.(); onSaved?.(r); onClose(); }
  };
  return (
    <Modal open onClose={onClose} title={title || (record?.id ? 'Edit' : 'New')} wide={fields.length > 8}
      footer={<><Btn variant="secondary" onClick={onClose}>Cancel</Btn><Btn busy={busy} onClick={save}>Save</Btn></>}>
      <div className="grid gap-3 sm:grid-cols-2">
        {fields.map((x) => (
          <Field key={x.key} label={x.label} hint={x.hint} className={x.wide ? 'sm:col-span-2' : ''}>
            {x.type === 'select' ? <Select value={f[x.key] ?? ''} disabled={x.readOnly} onChange={(e) => setF({ ...f, [x.key]: e.target.value })} options={x.options} placeholder={x.placeholder} />
              : x.type === 'textarea' ? <Textarea value={f[x.key] ?? ''} onChange={(e) => setF({ ...f, [x.key]: e.target.value })} />
              : x.type === 'checkbox' ? <label className="flex items-center gap-2 py-2 text-sm"><input type="checkbox" checked={!!f[x.key]} onChange={(e) => setF({ ...f, [x.key]: e.target.checked })} />{x.checkLabel || 'Yes'}</label>
              : <Input type={x.type || 'text'} value={f[x.key] ?? ''} readOnly={x.readOnly} step="any" onChange={(e) => setF({ ...f, [x.key]: e.target.value })} />}
          </Field>
        ))}
      </div>
    </Modal>
  );
}
