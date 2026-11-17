import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
const db = new PGlite();
const t0 = Date.now();
await db.exec(fs.readFileSync('supabase/local_stub.sql', 'utf8'));
try { await db.exec(fs.readFileSync("supabase/setup.sql", "utf8")); } catch (e) { console.log("ERR", e.message, e.position, fs.readFileSync("supabase/setup.sql","utf8").slice(Math.max(0,(e.position||0)-300), (e.position||0)+100)); process.exit(1); }
console.log('setup+seed ms', Date.now() - t0);
const q = async (sql, p) => (await db.query(sql, p)).rows;
console.log(await q('select session_user'));

globalThis.db = db; globalThis.q = q;
export { db, q };
